//
//  Sema.swift
//  FunctionEngine
//
//  Resolution + bottom-up type synthesis over the function body. Variables are
//  `float` (vector *inputs* need annotation syntax, deferred), so every leaf type
//  is known and each node synthesizes its result type from its operands — no
//  unification needed. Reports type errors, derives inputs, and types the outputs.
//

func analyze(_ body: Body) -> (interface: Interface, diagnostics: [Diagnostic]) {
    var diagnostics: [Diagnostic] = []
    var inputs: [String] = []
    var inputSeen = Set<String>()

    var letNames = Set<String>()
    for stmt in body.statements {
        if case .local(let name, _, _) = stmt { letNames.insert(name) }
    }

    var letTypes: [String: ValueType] = [:]   // locals defined so far → type
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
            guard argTypes[0].isVector else { diag(.typeMismatch, "`normalize` expects a vector.", span); return nil }
            return argTypes[0]
        default:
            break
        }

        if Builtins.genNUnary.contains(name) {
            return argTypes[0]   // float→float or vecN→vecN
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

    func synthesize(_ e: Expr) -> ValueType? {
        switch e {
        case .number:
            return .float

        case .variable(let name, let span):
            if let t = letTypes[name] { return t }
            if letNames.contains(name) {
                diag(.useBeforeDefinition, "`\(name)` is used before it is defined.", span)
                return nil
            }
            if Builtins.isConstant(name) { return .float }
            if inputSeen.insert(name).inserted { inputs.append(name) }
            return .float

        case .negate(let x, _):
            return synthesize(x)

        case .binary(let op, let l, let r, let span):
            guard let lt = synthesize(l), let rt = synthesize(r) else { return nil }
            if lt == rt { return lt }
            if lt == .float { return rt }
            if rt == .float { return lt }
            diag(.typeMismatch, "`\(opSymbol(op))` needs matching types — got `\(lt.name)` and `\(rt.name)`.", span)
            return nil

        case .swizzle(let base, let chars, let span):
            guard let bt = synthesize(base) else { return nil }
            guard bt.isVector else {
                diag(.badSwizzle, "`.\(chars)` can't be applied to a `\(bt.name)` — only vectors have components.", span)
                return nil
            }
            guard let indices = swizzleIndices(chars), indices.allSatisfy({ $0 < bt.width }) else {
                diag(.badSwizzle, "`.\(chars)` is not a valid swizzle for a `\(bt.name)`.", span)
                return nil
            }
            return ValueType.ofWidth(indices.count)

        case .call(let name, let args, let span):
            var argTypes: [ValueType] = []
            for a in args {
                guard let t = synthesize(a) else { return nil }
                argTypes.append(t)
            }
            return synthesizeCall(name, argTypes, span)
        }
    }

    for stmt in body.statements {
        switch stmt {
        case .local(let name, let value, let span):
            let t = synthesize(value)
            if !declaredLocals.insert(name).inserted {
                diag(.duplicateBinding, "`\(name)` is already defined.", span)
            }
            letTypes[name] = t ?? .float

        case .output(let name, let value, let span):
            let t = synthesize(value)
            if !outputNamesSeen.insert(name).inserted {
                diag(.duplicateOutput, "Two outputs are both named `\(name)`.", span)
            }
            outputs.append(OutputPort(name: name, type: t ?? .float))
        }
    }

    return (Interface(inputs: inputs, outputs: outputs), diagnostics)
}
