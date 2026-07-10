//
//  ReferenceInterpreter.swift
//  FunctionEngine
//
//  Tree-walking evaluator. In the TDD build this is the first (green)
//  implementation; it also stays on as the differential oracle for the fast
//  POD-tape engine added in a later slice (assert tape == reference).
//

import Foundation

enum ReferenceInterpreter {
    static func eval(_ e: Expr, _ inputs: [String: Float]) throws(EvalError) -> Float {
        switch e {
        case .number(let value, _):
            return value

        case .variable(let name, _):
            if let constant = Builtins.constants[name] { return constant }
            guard let value = inputs[name] else { throw EvalError.missingInput(name) }
            return value

        case .negate(let operand, _):
            let v = try eval(operand, inputs)
            return -v

        case .binary(let op, let l, let r, _):
            let a = try eval(l, inputs)
            let b = try eval(r, inputs)
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
            for arg in args { values.append(try eval(arg, inputs)) }
            return Builtins.apply(name, values)
        }
    }
}
