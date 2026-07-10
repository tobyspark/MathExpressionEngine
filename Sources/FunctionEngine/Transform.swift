//
//  Transform.swift
//  FunctionEngine
//
//  Portable column-major 4×4 matrix and quaternion, laid out to match Apple's
//  `simd_float4x4` (columns) and `simd_quatf` (x,y,z,w) so the Fabric boundary is
//  a trivial reinterpret. No dependency on the Apple `simd` module — built on
//  stdlib `SIMD` types so the engine stays cross-platform / Linux-CI-testable.
//
//  Scope note: general 4×4 `inverse` and quaternion `slerp` are intentionally
//  deferred to a follow-up slice.
//

import Foundation

@inline(__always) func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y,
          a.z * b.x - a.x * b.z,
          a.x * b.y - a.y * b.x)
}
@inline(__always) func length3(_ v: SIMD3<Float>) -> Float { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
@inline(__always) func normalize3(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let l = length3(v)
    return l > 0 ? v / l : v
}

/// Column-major 4×4 matrix (each stored value is a column).
public struct Mat4: Sendable, Equatable {
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>

    static let identity = Mat4(c0: SIMD4(1, 0, 0, 0),
                               c1: SIMD4(0, 1, 0, 0),
                               c2: SIMD4(0, 0, 1, 0),
                               c3: SIMD4(0, 0, 0, 1))

    /// Matrix · vector (column-major).
    @inline(__always) func mulVec(_ v: SIMD4<Float>) -> SIMD4<Float> {
        c0 * v.x + c1 * v.y + c2 * v.z + c3 * v.w
    }

    /// Matrix · matrix.
    func mul(_ o: Mat4) -> Mat4 {
        Mat4(c0: mulVec(o.c0), c1: mulVec(o.c1), c2: mulVec(o.c2), c3: mulVec(o.c3))
    }

    var transposed: Mat4 {
        Mat4(c0: SIMD4(c0.x, c1.x, c2.x, c3.x),
             c1: SIMD4(c0.y, c1.y, c2.y, c3.y),
             c2: SIMD4(c0.z, c1.z, c2.z, c3.z),
             c3: SIMD4(c0.w, c1.w, c2.w, c3.w))
    }

    func transformPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = mulVec(SIMD4(p.x, p.y, p.z, 1))
        return SIMD3(r.x, r.y, r.z)
    }
    func transformDir(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let r = mulVec(SIMD4(v.x, v.y, v.z, 0))
        return SIMD3(r.x, r.y, r.z)
    }

    // MARK: Builders

    static func translation(_ t: SIMD3<Float>) -> Mat4 {
        Mat4(c0: SIMD4(1, 0, 0, 0), c1: SIMD4(0, 1, 0, 0), c2: SIMD4(0, 0, 1, 0), c3: SIMD4(t.x, t.y, t.z, 1))
    }
    static func scaling(_ s: SIMD3<Float>) -> Mat4 {
        Mat4(c0: SIMD4(s.x, 0, 0, 0), c1: SIMD4(0, s.y, 0, 0), c2: SIMD4(0, 0, s.z, 0), c3: SIMD4(0, 0, 0, 1))
    }
    static func rotationX(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(c0: SIMD4(1, 0, 0, 0), c1: SIMD4(0, c, s, 0), c2: SIMD4(0, -s, c, 0), c3: SIMD4(0, 0, 0, 1))
    }
    static func rotationY(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(c0: SIMD4(c, 0, -s, 0), c1: SIMD4(0, 1, 0, 0), c2: SIMD4(s, 0, c, 0), c3: SIMD4(0, 0, 0, 1))
    }
    static func rotationZ(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(c0: SIMD4(c, s, 0, 0), c1: SIMD4(-s, c, 0, 0), c2: SIMD4(0, 0, 1, 0), c3: SIMD4(0, 0, 0, 1))
    }

    static func compose(position: SIMD3<Float>, rotation: Quat, scale: SIMD3<Float>) -> Mat4 {
        translation(position).mul(rotation.matrix).mul(scaling(scale))
    }
}

/// Quaternion (x, y, z, w).
public struct Quat: Sendable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    var w: Float

    static let identity = Quat(x: 0, y: 0, z: 0, w: 1)

    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
    var length: Float { (x * x + y * y + z * z + w * w).squareRoot() }

    static func axisAngle(_ angle: Float, _ axis: SIMD3<Float>) -> Quat {
        let a = normalize3(axis)
        let half = angle * 0.5
        let s = sin(half)
        return Quat(x: a.x * s, y: a.y * s, z: a.z * s, w: cos(half))
    }

    /// Hamilton product self·other.
    func mul(_ o: Quat) -> Quat {
        Quat(x: w * o.x + x * o.w + y * o.z - z * o.y,
             y: w * o.y - x * o.z + y * o.w + z * o.x,
             z: w * o.z + x * o.y - y * o.x + z * o.w,
             w: w * o.w - x * o.x - y * o.y - z * o.z)
    }

    var conjugate: Quat { Quat(x: -x, y: -y, z: -z, w: w) }

    var normalized: Quat {
        let l = length
        return l > 0 ? Quat(x: x / l, y: y / l, z: z / l, w: w / l) : self
    }

    /// Rotate a vector: v + 2w(u×v) + 2u×(u×v), where u = xyz.
    func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = xyz
        let t = 2 * cross3(u, v)
        return v + w * t + cross3(u, t)
    }

    /// Rotation matrix for this (assumed unit) quaternion.
    var matrix: Mat4 {
        let (x, y, z, w) = (self.x, self.y, self.z, self.w)
        return Mat4(
            c0: SIMD4(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0),
            c1: SIMD4(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0),
            c2: SIMD4(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0),
            c3: SIMD4(0, 0, 0, 1)
        )
    }
}
