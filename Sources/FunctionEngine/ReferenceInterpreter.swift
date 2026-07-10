//
//  ReferenceInterpreter.swift
//  FunctionEngine
//
//  Tree-walking evaluator over the function body. Retained as the differential
//  oracle for the fast POD-tape engine (assert tape == reference).
//

import Foundation

enum ReferenceInterpreter {

    /// Evaluate the whole body, returning outputs in source order.
    static func evalBody(_ body: Body, _ inputs: [String: Float]) throws(EvalError) -> [Float] {
        var locals: [String: Float] = [:]
        var outputs: [Float] = []
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

    static func eval(_ e: Expr, _ inputs: [String: Float], _ locals: [String: Float]) throws(EvalError) -> Float {
        switch e {
        case .number(let value, _):
            return value

        case .variable(let name, _):
            if let local = locals[name] { return local }
            if let constant = Builtins.constants[name] { return constant }
            guard let value = inputs[name] else { throw EvalError.missingInput(name) }
            return value

        case .negate(let operand, _):
            let v = try eval(operand, inputs, locals)
            return -v

        case .binary(let op, let l, let r, _):
            let a = try eval(l, inputs, locals)
            let b = try eval(r, inputs, locals)
            switch op {
            case .add: return a + b
            case .sub: return a - b
            case .mul: return a * b
            case .div: return a / b
            case .mod: return a.truncatingRemainder(dividingBy: b)
            case .pow: return Float(pow(Double(a), Double(b)))
            }

        case .call(let name, let args, _):
            var values: [Float] = []
            values.reserveCapacity(args.count)
            for arg in args { values.append(try eval(arg, inputs, locals)) }
            return Builtins.apply(name, values)
        }
    }
}
