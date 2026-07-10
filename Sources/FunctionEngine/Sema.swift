//
//  Sema.swift
//  FunctionEngine
//
//  Resolution + bottom-up type synthesis over the function body. Variables are
//  `float` (vector inputs are deferred), comprehension loop variables are `float`,
//  so every leaf type is known and each node synthesizes its result type from its
//  operands. Reports type errors, derives inputs, and types the outputs.
//

func analyze(_ body: Body) -> (interface: Interface, diagnostics: [Diagnostic]) {
    var diagnostics: [Diagnostic] = []
    var inputs: [String] = []
    var inputSeen = Set<String>()

    var letNames = Set<String>()
    for stmt in body.statements {
        if case .local(let name, _, _) = stmt { letNames.insert(name) }
    }

    var letTypes: [String: ValueType] = [:]
    var declaredLocals = Set<String>()
    var outputs: [OutputPort] = []
    var outputNamesSeen = Set<String>()

    func diag(_ code: DiagnosticCode, _ message: String, _ span: Span) {
        diagnostics.append(Diagnostic(code: code, severity: .error, message: message, span: span))
    }

    func opSymbol(_ op: BinaryOp) -> String {
        switch op {
        case .add: return "+"
        case .sub: return "-"
        case .mul: return "*"
        case .div: return "/"
        case .mod: return "%"
        case .pow: return "^"
        }
    }

    func synthesizeCall(_ name: String, _ argTypes: [ValueType], _ span: Span) -> ValueType? {
        if Builtins.isConstructor(name) {
            let width = name == "vec2" ? 2 : (name == "vec3" ? 3 : 4)
            if argTypes.count == 1 && argTypes[0] == .float { return ValueType.ofWidth(width) }
            if argTypes.count == width && argTypes.allSatisfy({ $0 == .float }) { return ValueType.ofWidth(width) }
            diag(.argumentCount, "`\(name)` takes \(width) floats or one float — got (\(argTypes.map(\.name).joined(separator: ", "))).", span)
            return nil
        }

        guard let arity = Builtins.arities[name] else {
            diag(.unknownName, "Unknown function `\(name)`.", span)
            return nil
        }
        if argTypes.count != arity {
            let plural = arity == 1 ? "argument" : "arguments"
            diag(.argumentCount, "`\(name)` takes \(arity) \(plural), got \(argTypes.count).", span)
            return nil
        }

        if Builtins.reductions.contains(name) {
            guard case .array(let elem) = argTypes[0] else {
                diag(.notAnArray, "`\(name)` expects an array.", span); return nil
            }
            return name == "count" ? .float : elem
        }

        if Builtins.transformFns.contains(name) {
            func require(_ ok: Bool, _ message: String) -> Bool {
                if !ok { diag(.typeMismatch, message, span) }
                return ok
            }
            switch name {
            case "identity":
                return .transform
            case "translate":
                return require(argTypes[0] == .vec3, "`translate` expects a vec3.") ? .transform : nil
            case "scale":
                return require(argTypes[0] == .vec3 || argTypes[0] == .float, "`scale` expects a vec3 or a float.") ? .transform : nil
            case "rotateX", "rotateY", "rotateZ":
                return require(argTypes[0] == .float, "`\(name)` expects a float (radians).") ? .transform : nil
            case "compose":
                return require(argTypes[0] == .vec3 && argTypes[1] == .quat && argTypes[2] == .vec3,
                               "`compose` expects (vec3 position, quat rotation, vec3 scale).") ? .transform : nil
            case "transformPoint", "transformDir":
                return require(argTypes[0] == .transform && argTypes[1] == .vec3,
                               "`\(name)` expects (transform, vec3).") ? .vec3 : nil
            case "transpose":
                return require(argTypes[0] == .transform, "`transpose` expects a transform.") ? .transform : nil
            case "quatAxisAngle":
                return require(argTypes[0] == .float && argTypes[1] == .vec3,
                               "`quatAxisAngle` expects (float angle, vec3 axis).") ? .quat : nil
            case "conjugate":
                return require(argTypes[0] == .quat, "`conjugate` expects a quat.") ? .quat : nil
            case "mul":
                switch (argTypes[0], argTypes[1]) {
                case (.transform, .transform): return .transform
                case (.transform, .vec4):      return .vec4
                case (.quat, .quat):           return .quat
                case (.quat, .vec3):           return .vec3
                default:
                    diag(.typeMismatch, "`mul` isn't defined for `\(argTypes[0].name)` and `\(argTypes[1].name)`.", span)
                    return nil
                }
            case "rotate":
                return require(argTypes[0] == .quat && argTypes[1] == .vec3,
                               "`rotate` expects (quat, vec3).") ? .vec3 : nil
            default:
                return nil
            }
        }

        switch name {
        case "length":
            guard argTypes[0].isVector else { diag(.typeMismatch, "`length` expects a vector.", span); return nil }
            return .float
        case "distance":
            guard argTypes[0].isVector, argTypes[0] == argTypes[1] else {
                diag(.typeMismatch, "`distance` expects two vectors of the same size.", span); return nil
            }
            return .float
        case "dot":
            guard argTypes[0].isVector, argTypes[0] == argTypes[1] else {
                diag(.typeMismatch, "`dot` expects two vectors of the same size.", span); return nil
            }
            return .float
        case "cross":
            guard argTypes[0] == .vec3, argTypes[1] == .vec3 else {
                diag(.typeMismatch, "`cross` expects two vec3.", span); return nil
            }
            return .vec3
        case "normalize":
            if argTypes[0] == .quat { return .quat }
            guard argTypes[0].isVector else { diag(.typeMismatch, "`normalize` expects a vector or quaternion.", span); return nil }
            return argTypes[0]
        default:
            break
        }

        if Builtins.genNUnary.contains(name) {
            return argTypes[0]
        }
        if Builtins.scalarMulti.contains(name) {
            guard argTypes.allSatisfy({ $0 == .float }) else {
                diag(.typeMismatch, "`\(name)` expects scalar arguments in this version.", span); return nil
            }
            return .float
        }

        diag(.unknownName, "Unknown function `\(name)`.", span)
        return nil
    }

    func synthesize(_ e: Expr, _ scope: [String: ValueType]) -> ValueType? {
        switch e {
        case .number:
            return .float

        case .variable(let name, let span):
            if let t = scope[name] { return t }        // comprehension loop variable
            if let t = letTypes[name] { return t }     // local
            if letNames.contains(name) {
                diag(.useBeforeDefinition, "`\(name)` is used before it is defined.", span)
                return nil
            }
            if Builtins.isConstant(name) { return .float }
            if inputSeen.insert(name).inserted { inputs.append(name) }
            return .float

        case .negate(let x, let span):
            guard let t = synthesize(x, scope) else { return nil }
            guard !t.isArray else { diag(.typeMismatch, "`-` doesn't apply to arrays.", span); return nil }
            return t

        case .binary(let op, let l, let r, let span):
            guard let lt = synthesize(l, scope), let rt = synthesize(r, scope) else { return nil }
            guard !lt.isArray, !rt.isArray else {
                diag(.typeMismatch, "`\(opSymbol(op))` doesn't apply to arrays.", span); return nil
            }
            if lt == .transform || lt == .quat || rt == .transform || rt == .quat {
                guard op == .mul else {
                    diag(.typeMismatch, "only `*` applies to transforms and quaternions.", span); return nil
                }
                switch (lt, rt) {
                case (.transform, .transform): return .transform
                case (.transform, .vec4):      return .vec4
                case (.quat, .quat):           return .quat
                case (.quat, .vec3):           return .vec3
                default:
                    diag(.typeMismatch, "`*` isn't defined for `\(lt.name) * \(rt.name)` (for transform·vec3 use transformPoint / transformDir).", span)
                    return nil
                }
            }
            if lt == rt { return lt }
            if lt == .float { return rt }
            if rt == .float { return lt }
            diag(.typeMismatch, "`\(opSymbol(op))` needs matching types — got `\(lt.name)` and `\(rt.name)`.", span)
            return nil

        case .swizzle(let base, let chars, let span):
            guard let bt = synthesize(base, scope) else { return nil }
            guard bt.isVector else {
                diag(.badSwizzle, "`.\(chars)` can't be applied to a `\(bt.name)` — only vectors have components.", span)
                return nil
            }
            guard let indices = swizzleIndices(chars), indices.allSatisfy({ $0 < bt.width }) else {
                diag(.badSwizzle, "`.\(chars)` is not a valid swizzle for a `\(bt.name)`.", span)
                return nil
            }
            return ValueType.ofWidth(indices.count)

        case .arrayLiteral(let elements, let span):
            var elementType: ValueType? = nil
            for el in elements {
                guard let t = synthesize(el, scope) else { return nil }
                if let known = elementType {
                    if known != t {
                        diag(.heterogeneousArray, "Array elements must all be the same type — found `\(known.name)` and `\(t.name)`.", span)
                        return nil
                    }
                } else {
                    elementType = t
                }
            }
            guard let elementType else {
                diag(.emptyArray, "An empty array has no element type.", span); return nil
            }
            return .array(elementType)

        case .index(let base, let idx, let span):
            guard let bt = synthesize(base, scope) else { return nil }
            guard let it = synthesize(idx, scope) else { return nil }
            guard case .array(let elem) = bt else {
                diag(.notAnArray, "`\(bt.name)` isn't an array, so it can't be indexed.", span); return nil
            }
            guard it == .float else {
                diag(.typeMismatch, "An array index must be a number, got `\(it.name)`.", span); return nil
            }
            return elem

        case .comprehension(let bodyExpr, let loopVar, let lo, let hi, _, let span):
            guard let lt = synthesize(lo, scope), let ht = synthesize(hi, scope) else { return nil }
            guard lt == .float, ht == .float else {
                diag(.expectedRange, "A comprehension range must use numbers.", span); return nil
            }
            var inner = scope
            inner[loopVar] = .float
            guard let bt = synthesize(bodyExpr, inner) else { return nil }
            return .array(bt)

        case .call(let name, let args, let span):
            var argTypes: [ValueType] = []
            for a in args {
                guard let t = synthesize(a, scope) else { return nil }
                argTypes.append(t)
            }
            return synthesizeCall(name, argTypes, span)
        }
    }

    for stmt in body.statements {
        switch stmt {
        case .local(let name, let value, let span):
            let t = synthesize(value, [:])
            if !declaredLocals.insert(name).inserted {
                diag(.duplicateBinding, "`\(name)` is already defined.", span)
            }
            letTypes[name] = t ?? .float

        case .output(let name, let value, let span):
            let t = synthesize(value, [:])
            if !outputNamesSeen.insert(name).inserted {
                diag(.duplicateOutput, "Two outputs are both named `\(name)`.", span)
            }
            outputs.append(OutputPort(name: name, type: t ?? .float))
        }
    }

    return (Interface(inputs: inputs, outputs: outputs), diagnostics)
}
