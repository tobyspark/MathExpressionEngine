//
//  Builtins.swift
//  FunctionEngine
//
//  The scalar builtin table: constants, function arities (for the checker), and
//  their evaluation. Semantics follow DESIGN-FunctionNode-Catalogue.md:
//  radians throughout, `^`/`pow` exponent, floor/ceil/round are float-valued.
//  Transcendentals compute via Double and narrow to Float (this is the
//  reference interpreter / oracle; the fast tape uses simd kernels later).
//

import Foundation

enum Builtins {
    static let constants: [String: Float] = [
        "pi":  .pi,
        "tau": 2 * .pi,
        "e":   Float(2.718281828459045235),
    ]

    /// Argument count per function (drives the arity diagnostic).
    static let arities: [String: Int] = [
        "sin": 1, "cos": 1, "tan": 1,
        "asin": 1, "acos": 1, "atan": 1,
        "sqrt": 1, "abs": 1, "exp": 1, "log": 1, "log2": 1,
        "floor": 1, "ceil": 1, "round": 1, "sign": 1, "fract": 1,
        "radians": 1, "degrees": 1, "saturate": 1,
        "atan2": 2, "pow": 2, "min": 2, "max": 2, "mod": 2, "step": 2,
        "clamp": 3, "mix": 3, "smoothstep": 3,
    ]

    static func isFunction(_ name: String) -> Bool { arities[name] != nil }
    static func isConstant(_ name: String) -> Bool { constants[name] != nil }

    static func apply(_ name: String, _ a: [Float]) -> Float {
        @inline(__always) func d(_ x: Float) -> Double { Double(x) }

        switch name {
        case "sin":      return Float(sin(d(a[0])))
        case "cos":      return Float(cos(d(a[0])))
        case "tan":      return Float(tan(d(a[0])))
        case "asin":     return Float(asin(d(a[0])))
        case "acos":     return Float(acos(d(a[0])))
        case "atan":     return Float(atan(d(a[0])))
        case "sqrt":     return a[0].squareRoot()
        case "abs":      return Swift.abs(a[0])
        case "exp":      return Float(exp(d(a[0])))
        case "log":      return Float(log(d(a[0])))
        case "log2":     return Float(log2(d(a[0])))
        case "floor":    return a[0].rounded(.down)
        case "ceil":     return a[0].rounded(.up)
        case "round":    return a[0].rounded(.toNearestOrAwayFromZero)
        case "sign":     return a[0] > 0 ? 1 : (a[0] < 0 ? -1 : 0)
        case "fract":    return a[0] - a[0].rounded(.down)
        case "radians":  return a[0] * .pi / 180
        case "degrees":  return a[0] * 180 / .pi
        case "saturate": return Swift.min(Swift.max(a[0], 0), 1)
        case "atan2":    return Float(atan2(d(a[0]), d(a[1])))
        case "pow":      return Float(pow(d(a[0]), d(a[1])))
        case "min":      return Swift.min(a[0], a[1])
        case "max":      return Swift.max(a[0], a[1])
        case "mod":      return a[0].truncatingRemainder(dividingBy: a[1])
        case "step":     return a[1] < a[0] ? 0 : 1     // step(edge, x)
        case "clamp":    return Swift.min(Swift.max(a[0], a[1]), a[2])
        case "mix":      return a[0] + (a[1] - a[0]) * a[2]
        case "smoothstep":
            let e0 = a[0], e1 = a[1], x = a[2]
            let t = Swift.min(Swift.max((x - e0) / (e1 - e0), 0), 1)
            return t * t * (3 - 2 * t)
        default:
            return .nan
        }
    }
}
