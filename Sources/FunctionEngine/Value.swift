//
//  Value.swift
//  FunctionEngine
//
//  Operations on `EngineValue` shared by the reference interpreter and the tape
//  (a single, centralized value-math implementation). Elementwise ops broadcast
//  a scalar against a vector; reductions and swizzles are width-aware.
//

import Foundation

extension EngineValue {
    var width: Int { type.width }

    /// Widen to a 4-lane vector (scalars splat across all lanes so broadcasting
    /// falls out of a plain lane-wise op).
    var wide: SIMD4<Float> {
        switch self {
        case .float(let x): return SIMD4(repeating: x)
        case .vec2(let v):  return SIMD4(v.x, v.y, 0, 0)
        case .vec3(let v):  return SIMD4(v.x, v.y, v.z, 0)
        case .vec4(let v):  return v
        }
    }

    static func make(_ s: SIMD4<Float>, width: Int) -> EngineValue {
        switch width {
        case 1:  return .float(s.x)
        case 2:  return .vec2(SIMD2(s.x, s.y))
        case 3:  return .vec3(SIMD3(s.x, s.y, s.z))
        default: return .vec4(s)
        }
    }

    // MARK: - Arithmetic

    static func negate(_ v: EngineValue) -> EngineValue {
        make(-v.wide, width: v.width)
    }

    /// Elementwise binary op with scalar↔vector broadcast. Mismatched vector
    /// widths can't occur (the checker forbids them); if they somehow do, the
    /// wider width wins.
    static func binary(_ op: BinaryOp, _ a: EngineValue, _ b: EngineValue) -> EngineValue {
        let width = Swift.max(a.width, b.width)
        let sa = a.wide, sb = b.wide
        var out = SIMD4<Float>()
        for i in 0..<width { out[i] = scalarBinary(op, sa[i], sb[i]) }
        return make(out, width: width)
    }

    static func scalarBinary(_ op: BinaryOp, _ x: Float, _ y: Float) -> Float {
        switch op {
        case .add: return x + y
        case .sub: return x - y
        case .mul: return x * y
        case .div: return x / y
        case .mod: return x.truncatingRemainder(dividingBy: y)
        case .pow: return Float(pow(Double(x), Double(y)))
        }
    }

    // MARK: - Construction

    static func construct2(_ a: Float, _ b: Float) -> EngineValue { .vec2(SIMD2(a, b)) }
    static func construct3(_ a: Float, _ b: Float, _ c: Float) -> EngineValue { .vec3(SIMD3(a, b, c)) }
    static func construct4(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> EngineValue { .vec4(SIMD4(a, b, c, d)) }

    static func splat(_ width: Int, _ s: Float) -> EngineValue {
        switch width {
        case 2:  return .vec2(SIMD2(repeating: s))
        case 3:  return .vec3(SIMD3(repeating: s))
        default: return .vec4(SIMD4(repeating: s))
        }
    }

    // MARK: - Swizzle

    /// Permute components by lane index (`indices` has 1–4 entries). One index
    /// yields a float; more yield the matching vecN.
    static func swizzle(_ v: EngineValue, _ i0: Int, _ i1: Int, _ i2: Int, _ i3: Int, count: Int) -> EngineValue {
        let s = v.wide
        switch count {
        case 1:  return .float(s[i0])
        case 2:  return .vec2(SIMD2(s[i0], s[i1]))
        case 3:  return .vec3(SIMD3(s[i0], s[i1], s[i2]))
        default: return .vec4(SIMD4(s[i0], s[i1], s[i2], s[i3]))
        }
    }

    // MARK: - Vector reductions

    static func length(_ v: EngineValue) -> Float {
        let s = v.wide
        var sum: Float = 0
        for i in 0..<v.width { sum += s[i] * s[i] }
        return sum.squareRoot()
    }

    static func dot(_ a: EngineValue, _ b: EngineValue) -> Float {
        let sa = a.wide, sb = b.wide
        let w = Swift.min(a.width, b.width)
        var sum: Float = 0
        for i in 0..<w { sum += sa[i] * sb[i] }
        return sum
    }

    static func cross(_ a: EngineValue, _ b: EngineValue) -> EngineValue {
        let x = a.wide, y = b.wide
        return .vec3(SIMD3(
            x.y * y.z - x.z * y.y,
            x.z * y.x - x.x * y.z,
            x.x * y.y - x.y * y.x
        ))
    }
}

// MARK: - Swizzle component mapping

func swizzleLane(_ c: Character) -> Int? {
    switch c {
    case "x", "r": return 0
    case "y", "g": return 1
    case "z", "b": return 2
    case "w", "a": return 3
    default:       return nil
    }
}

/// Map a swizzle string to lane indices, or nil if any character is invalid or
/// the length isn't 1–4.
func swizzleIndices(_ chars: String) -> [Int]? {
    var indices: [Int] = []
    for c in chars {
        guard let lane = swizzleLane(c) else { return nil }
        indices.append(lane)
    }
    return (1...4).contains(indices.count) ? indices : nil
}
