//
//  Builtins.swift
//  MathExpressionEngine
//
//  Constants, function identities (`FnID`), arities, the scalar math
//  implementation, and a typed `evaluateValue` over `EngineValue` (shared by the
//  reference interpreter and the tape). Semantics per DESIGN-FunctionNode-Catalogue.md.
//

import Foundation

/// Monomorphized builtin identity — payload-free, so it lives directly in POD
/// tape instructions.
enum FnID: Sendable {
    case sin, cos, tan, asin, acos, atan
    case sqrt, abs, exp, log, log2
    case floor, ceil, round, sign, fract
    case radians, degrees, saturate
    case atan2, pow, min, max, mod, step
    case clamp, mix, smoothstep
    case length, distance, dot, cross, normalize
    case sum, product, mean, count
    case identity, translate, scale, rotateX, rotateY, rotateZ, compose
    case transformPoint, transformDir, transpose
    case quatAxisAngle, conjugate, mul, rotate
}

enum Builtins {
    static let constants: [String: Float] = [
        "pi":  .pi,
        "tau": 2 * .pi,
        "e":   Float(2.718281828459045235),
    ]

    /// Argument count per function.
    static let arities: [String: Int] = [
        "sin": 1, "cos": 1, "tan": 1,
        "asin": 1, "acos": 1, "atan": 1,
        "sqrt": 1, "abs": 1, "exp": 1, "log": 1, "log2": 1,
        "floor": 1, "ceil": 1, "round": 1, "sign": 1, "fract": 1,
        "radians": 1, "degrees": 1, "saturate": 1,
        "atan2": 2, "pow": 2, "min": 2, "max": 2, "mod": 2, "step": 2,
        "clamp": 3, "mix": 3, "smoothstep": 3,
        "length": 1, "distance": 2, "dot": 2, "cross": 2, "normalize": 1,
        "sum": 1, "product": 1, "mean": 1, "count": 1,
        "identity": 0, "translate": 1, "scale": 1,
        "rotateX": 1, "rotateY": 1, "rotateZ": 1, "compose": 3,
        "transformPoint": 2, "transformDir": 2, "transpose": 1,
        "quatAxisAngle": 2, "conjugate": 1, "mul": 2, "rotate": 2,
    ]

    /// Array reduction functions.
    static let reductions: Set<String> = ["sum", "product", "mean", "count"]

    /// Transform / quaternion functions (handled by dedicated type rules).
    static let transformFns: Set<String> = [
        "identity", "translate", "scale", "rotateX", "rotateY", "rotateZ", "compose",
        "transformPoint", "transformDir", "transpose", "quatAxisAngle", "conjugate",
        "mul", "rotate",
    ]

    /// Componentwise unary math functions (`genN → genN`).
    static let genNUnary: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "abs", "exp",
        "log", "log2", "floor", "ceil", "round", "sign", "fract",
        "radians", "degrees", "saturate",
    ]

    /// Multi-argument math functions that (in this slice) require scalar args.
    static let scalarMulti: Set<String> = [
        "atan2", "pow", "min", "max", "mod", "step", "clamp", "mix", "smoothstep",
    ]

    static func isFunction(_ name: String) -> Bool { arities[name] != nil }
    static func isConstant(_ name: String) -> Bool { constants[name] != nil }
    static func isConstructor(_ name: String) -> Bool { name == "vec2" || name == "vec3" || name == "vec4" }

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
        case "length": return .length
        case "distance": return .distance
        case "dot": return .dot
        case "cross": return .cross
        case "normalize": return .normalize
        case "sum": return .sum
        case "product": return .product
        case "mean": return .mean
        case "count": return .count
        case "identity": return .identity
        case "translate": return .translate
        case "scale": return .scale
        case "rotateX": return .rotateX
        case "rotateY": return .rotateY
        case "rotateZ": return .rotateZ
        case "compose": return .compose
        case "transformPoint": return .transformPoint
        case "transformDir": return .transformDir
        case "transpose": return .transpose
        case "quatAxisAngle": return .quatAxisAngle
        case "conjugate": return .conjugate
        case "mul": return .mul
        case "rotate": return .rotate
        default: return nil
        }
    }

    /// The single scalar math implementation. Unused arguments are ignored.
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
        case .step:     return a1 < a0 ? 0 : 1
        case .clamp:    return Swift.min(Swift.max(a0, a1), a2)
        case .mix:      return a0 + (a1 - a0) * a2
        case .smoothstep:
            let t = Swift.min(Swift.max((a2 - a0) / (a1 - a0), 0), 1)
            return t * t * (3 - 2 * t)
        // Vector-/array-/transform-only ids never reach the scalar path.
        case .length, .distance, .dot, .cross, .normalize,
             .sum, .product, .mean, .count,
             .identity, .translate, .scale, .rotateX, .rotateY, .rotateZ, .compose,
             .transformPoint, .transformDir, .transpose,
             .quatAxisAngle, .conjugate, .mul, .rotate:
            return .nan
        }
    }

    /// Name-based scalar entry point (reference interpreter fallback / tests).
    static func apply(_ name: String, _ a: [Float]) -> Float {
        guard let id = id(forName: name) else { return .nan }
        let a0 = a.count > 0 ? a[0] : 0
        let a1 = a.count > 1 ? a[1] : 0
        let a2 = a.count > 2 ? a[2] : 0
        return evaluate(id, a0, a1, a2)
    }

    /// Typed evaluation over `EngineValue`. Unused args may be `.float(0)`.
    static func evaluateValue(_ id: FnID, _ a0: EngineValue, _ a1: EngineValue, _ a2: EngineValue) -> EngineValue {
        switch id {
        case .length:    return .float(EngineValue.length(a0))
        case .distance:  return .float(EngineValue.length(EngineValue.binary(.sub, a0, a1)))
        case .dot:       return .float(EngineValue.dot(a0, a1))
        case .cross:     return EngineValue.cross(a0, a1)
        case .normalize:
            if case .quat(let q) = a0 { return .quat(q.normalized) }
            return EngineValue.binary(.div, a0, .float(EngineValue.length(a0)))

        case .identity:       return .transform(.identity)
        case .translate:      return .transform(Mat4.translation(a0.asVec3))
        case .scale:
            if case .vec3(let s) = a0 { return .transform(Mat4.scaling(s)) }
            return .transform(Mat4.scaling(SIMD3(repeating: a0.scalar)))   // uniform
        case .rotateX:        return .transform(Mat4.rotationX(a0.scalar))
        case .rotateY:        return .transform(Mat4.rotationY(a0.scalar))
        case .rotateZ:        return .transform(Mat4.rotationZ(a0.scalar))
        case .compose:        return .transform(Mat4.compose(position: a0.asVec3, rotation: a1.asQuat, scale: a2.asVec3))
        case .transformPoint: return .vec3(a0.asMat4.transformPoint(a1.asVec3))
        case .transformDir:   return .vec3(a0.asMat4.transformDir(a1.asVec3))
        case .transpose:      return .transform(a0.asMat4.transposed)
        case .quatAxisAngle:  return .quat(Quat.axisAngle(a0.scalar, a1.asVec3))
        case .conjugate:      return .quat(a0.asQuat.conjugate)
        case .mul:            return EngineValue.binary(.mul, a0, a1)
        case .rotate:         return EngineValue.binary(.mul, a0, a1)   // quat · vec3
        case .count:
            return .float(Float(a0.arrayElements?.count ?? 0))
        case .sum, .product, .mean:
            guard let els = a0.arrayElements, !els.isEmpty else { return .float(0) }
            var acc = els[0]
            let op: BinaryOp = (id == .product) ? .mul : .add
            for k in 1..<els.count { acc = EngineValue.binary(op, acc, els[k]) }
            if id == .mean { acc = EngineValue.binary(.div, acc, .float(Float(els.count))) }
            return acc
        case .atan2, .pow, .min, .max, .mod, .step, .clamp, .mix, .smoothstep:
            // Scalar-only multi-arg (this slice): args are floats.
            return .float(evaluate(id, a0.scalar, a1.scalar, a2.scalar))
        default:
            // Componentwise unary genN.
            let s = a0.wide
            var out = SIMD4<Float>()
            for i in 0..<a0.width { out[i] = evaluate(id, s[i], 0, 0) }
            return EngineValue.make(out, width: a0.width)
        }
    }
}
