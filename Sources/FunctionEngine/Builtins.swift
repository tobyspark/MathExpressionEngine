//
//  Builtins.swift
//  FunctionEngine
//
//  The scalar builtin table: constants, function arities (for the checker), a
//  payload-free `FnID` (so the compiled tape dispatches without strings), and a
//  single math implementation `evaluate(id:…)` shared by the tape and the
//  reference interpreter. Semantics follow DESIGN-FunctionNode-Catalogue.md:
//  radians throughout, `^`/`pow` exponent, floor/ceil/round are float-valued.
//  Transcendentals compute via Double and narrow to Float (this reference math
//  is the oracle; the SIMD-native fast path comes in a later slice).
//

import Foundation

/// Monomorphized builtin identity — no associated payload, so it is trivially
/// Sendable and lives directly in POD tape instructions (no string dispatch).
enum FnID: Sendable {
    case sin, cos, tan, asin, acos, atan
    case sqrt, abs, exp, log, log2
    case floor, ceil, round, sign, fract
    case radians, degrees, saturate
    case atan2, pow, min, max, mod, step
    case clamp, mix, smoothstep
}

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

    static func id(forName name: String) -> FnID? {
        switch name {
        case "sin": return .sin
        case "cos": return .cos
        case "tan": return .tan
        case "asin": return .asin
        case "acos": return .acos
        case "atan": return .atan
        case "sqrt": return .sqrt
        case "abs": return .abs
        case "exp": return .exp
        case "log": return .log
        case "log2": return .log2
        case "floor": return .floor
        case "ceil": return .ceil
        case "round": return .round
        case "sign": return .sign
        case "fract": return .fract
        case "radians": return .radians
        case "degrees": return .degrees
        case "saturate": return .saturate
        case "atan2": return .atan2
        case "pow": return .pow
        case "min": return .min
        case "max": return .max
        case "mod": return .mod
        case "step": return .step
        case "clamp": return .clamp
        case "mix": return .mix
        case "smoothstep": return .smoothstep
        default: return nil
        }
    }

    /// The single math implementation. Unused arguments (per the function's
    /// arity) are ignored, so callers may pass 0 for absent operands.
    @inline(__always)
    static func evaluate(_ id: FnID, _ a0: Float, _ a1: Float, _ a2: Float) -> Float {
        @inline(__always) func d(_ x: Float) -> Double { Double(x) }

        switch id {
        case .sin:      return Float(sin(d(a0)))
        case .cos:      return Float(cos(d(a0)))
        case .tan:      return Float(tan(d(a0)))
        case .asin:     return Float(asin(d(a0)))
        case .acos:     return Float(acos(d(a0)))
        case .atan:     return Float(atan(d(a0)))
        case .sqrt:     return a0.squareRoot()
        case .abs:      return Swift.abs(a0)
        case .exp:      return Float(exp(d(a0)))
        case .log:      return Float(log(d(a0)))
        case .log2:     return Float(log2(d(a0)))
        case .floor:    return a0.rounded(.down)
        case .ceil:     return a0.rounded(.up)
        case .round:    return a0.rounded(.toNearestOrAwayFromZero)
        case .sign:     return a0 > 0 ? 1 : (a0 < 0 ? -1 : 0)
        case .fract:    return a0 - a0.rounded(.down)
        case .radians:  return a0 * .pi / 180
        case .degrees:  return a0 * 180 / .pi
        case .saturate: return Swift.min(Swift.max(a0, 0), 1)
        case .atan2:    return Float(atan2(d(a0), d(a1)))
        case .pow:      return Float(pow(d(a0), d(a1)))
        case .min:      return Swift.min(a0, a1)
        case .max:      return Swift.max(a0, a1)
        case .mod:      return a0.truncatingRemainder(dividingBy: a1)
        case .step:     return a1 < a0 ? 0 : 1     // step(edge, x)
        case .clamp:    return Swift.min(Swift.max(a0, a1), a2)
        case .mix:      return a0 + (a1 - a0) * a2
        case .smoothstep:
            let t = Swift.min(Swift.max((a2 - a0) / (a1 - a0), 0), 1)
            return t * t * (3 - 2 * t)
        }
    }

    /// Name-based entry point used by the tree-walking reference interpreter.
    static func apply(_ name: String, _ a: [Float]) -> Float {
        guard let id = id(forName: name) else { return .nan }
        let a0 = a.count > 0 ? a[0] : 0
        let a1 = a.count > 1 ? a[1] : 0
        let a2 = a.count > 2 ? a[2] : 0
        return evaluate(id, a0, a1, a2)
    }
}
