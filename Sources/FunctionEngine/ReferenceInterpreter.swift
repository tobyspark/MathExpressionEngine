//
//  ReferenceInterpreter.swift
//  FunctionEngine
//
//  Tree-walking evaluator over the function body, producing typed `EngineValue`s.
//  Uses the shared value-math in Value.swift / Builtins, and stays on as the
//  differential oracle for the tape (validating lowering & sequencing).
//

enum ReferenceInterpreter {

    static func evalBody(_ body: Body, _ inputs: [String: Float]) throws(EvalError) -> [EngineValue] {
        var locals: [String: EngineValue] = [:]
        var outputs: [EngineValue] = []
        for stmt in body.statements {
            switch stmt {
            case .local(let name, let value, _):
                locals[name] = try eval(value, inputs, locals)
            case .output(_, let value, _):
                outputs.append(try eval(value, inputs, locals))
            }
        }
        return outputs
    }

    static func eval(_ e: Expr, _ inputs: [String: Float], _ locals: [String: EngineValue]) throws(EvalError) -> EngineValue {
        switch e {
        case .number(let value, _):
            return .float(value)

        case .variable(let name, _):
            if let local = locals[name] { return local }
            if let constant = Builtins.constants[name] { return .float(constant) }
            guard let value = inputs[name] else { throw EvalError.missingInput(name) }
            return .float(value)

        case .negate(let operand, _):
            return EngineValue.negate(try eval(operand, inputs, locals))

        case .binary(let op, let l, let r, _):
            let a = try eval(l, inputs, locals)
            let b = try eval(r, inputs, locals)
            return EngineValue.binary(op, a, b)

        case .swizzle(let base, let chars, _):
            let v = try eval(base, inputs, locals)
            let idx = swizzleIndices(chars) ?? [0]
            let i0 = idx[0]
            let i1 = idx.count > 1 ? idx[1] : 0
            let i2 = idx.count > 2 ? idx[2] : 0
            let i3 = idx.count > 3 ? idx[3] : 0
            return EngineValue.swizzle(v, i0, i1, i2, i3, count: idx.count)

        case .call(let name, let args, _):
            var vs: [EngineValue] = []
            vs.reserveCapacity(args.count)
            for arg in args { vs.append(try eval(arg, inputs, locals)) }

            if Builtins.isConstructor(name) {
                let width = name == "vec2" ? 2 : (name == "vec3" ? 3 : 4)
                if vs.count == 1 { return EngineValue.splat(width, vs[0].scalar) }
                switch width {
                case 2:  return EngineValue.construct2(vs[0].scalar, vs[1].scalar)
                case 3:  return EngineValue.construct3(vs[0].scalar, vs[1].scalar, vs[2].scalar)
                default: return EngineValue.construct4(vs[0].scalar, vs[1].scalar, vs[2].scalar, vs[3].scalar)
                }
            }

            guard let id = Builtins.id(forName: name) else { return .float(.nan) }
            let a0 = vs[0]
            let a1 = vs.count > 1 ? vs[1] : .float(0)
            let a2 = vs.count > 2 ? vs[2] : .float(0)
            return Builtins.evaluateValue(id, a0, a1, a2)
        }
    }
}
