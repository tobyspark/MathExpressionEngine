//
//  Transform.swift
//  MathExpressionEngine
//
//  Transform (4×4 matrix) and quaternion types for the engine. These are Apple's
//  `simd_float4x4` and `simd_quatf` directly, so an `EngineValue.transform` /
//  `.quat` payload *is* the Fabric port value — the boundary is a zero-copy
//  reinterpret rather than a field-by-field marshal.
//
//  The engine's algebra (translate / scale / rotate / compose / transformPoint,
//  quaternion axis-angle / rotate / to-matrix) is provided below as extensions,
//  so the rest of the engine keeps calling `Mat4.translation(_:)`, `q.rotate(_:)`
//  &c. unchanged. Matrix composition and matrix·vector delegate to simd's
//  operators; the builders and quaternion formulas keep their explicit,
//  column-major / (x,y,z,w) definitions so behaviour is identical to before.
//
//  Scope note: general 4×4 `inverse` and quaternion `slerp` are available from
//  simd (`.inverse`, `simd_slerp`) but not yet exposed in the language.
//

import Foundation
import simd

/// A 4×4 transform — Apple's column-major `simd_float4x4`.
public typealias Mat4 = simd_float4x4

/// A quaternion (x, y, z, w) — Apple's `simd_quatf`.
public typealias Quat = simd_quatf

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

// MARK: - Mat4 (simd_float4x4)

extension Mat4 {
    static let identity = matrix_identity_float4x4

    // `columns` and `init(columns:)` are native on simd_float4x4.

    /// Matrix · vector (column-major).
    @inline(__always) func mulVec(_ v: SIMD4<Float>) -> SIMD4<Float> { self * v }

    /// Matrix · matrix (standard column-major composition).
    func mul(_ o: Mat4) -> Mat4 { self * o }

    var transposed: Mat4 { self.transpose }

    func transformPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = self * SIMD4(p.x, p.y, p.z, 1)
        return SIMD3(r.x, r.y, r.z)
    }
    func transformDir(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let r = self * SIMD4(v.x, v.y, v.z, 0)
        return SIMD3(r.x, r.y, r.z)
    }

    // MARK: Builders

    static func translation(_ t: SIMD3<Float>) -> Mat4 {
        Mat4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(t.x, t.y, t.z, 1)))
    }
    static func scaling(_ s: SIMD3<Float>) -> Mat4 {
        Mat4(columns: (SIMD4(s.x, 0, 0, 0), SIMD4(0, s.y, 0, 0), SIMD4(0, 0, s.z, 0), SIMD4(0, 0, 0, 1)))
    }
    static func rotationX(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }
    static func rotationY(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }
    static func rotationZ(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    static func compose(position: SIMD3<Float>, rotation: Quat, scale: SIMD3<Float>) -> Mat4 {
        translation(position).mul(rotation.matrix).mul(scaling(scale))
    }
}

// MARK: - Quat (simd_quatf)

extension Quat {
    static let identity = Quat(ix: 0, iy: 0, iz: 0, r: 1)

    /// (x, y, z, w) — the imaginary parts followed by the real part.
    public var components: SIMD4<Float> { self.vector }

    /// Build from an (x, y, z, w) vector. Inverse of `components`.
    public init(components v: SIMD4<Float>) { self.init(vector: v) }

    // `conjugate`, `normalized` and `length` are native on simd_quatf.

    static func axisAngle(_ angle: Float, _ axis: SIMD3<Float>) -> Quat {
        let a = normalize3(axis)
        let half = angle * 0.5
        let s = sin(half)
        return Quat(ix: a.x * s, iy: a.y * s, iz: a.z * s, r: cos(half))
    }

    /// Hamilton product self·other. Explicit to pin the (x,y,z,w) convention.
    func mul(_ o: Quat) -> Quat {
        let (x, y, z, w) = (vector.x, vector.y, vector.z, vector.w)
        let (ox, oy, oz, ow) = (o.vector.x, o.vector.y, o.vector.z, o.vector.w)
        return Quat(ix: w * ox + x * ow + y * oz - z * oy,
                    iy: w * oy - x * oz + y * ow + z * ox,
                    iz: w * oz + x * oy - y * ox + z * ow,
                    r:  w * ow - x * ox - y * oy - z * oz)
    }

    /// Rotate a vector: v + 2w(u×v) + 2u×(u×v), where u = xyz.
    func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = self.imag
        let t = 2 * cross3(u, v)
        return v + self.real * t + cross3(u, t)
    }

    /// Rotation matrix for this (assumed unit) quaternion.
    var matrix: Mat4 {
        let (x, y, z, w) = (vector.x, vector.y, vector.z, vector.w)
        return Mat4(columns: (
            SIMD4(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0),
            SIMD4(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0),
            SIMD4(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}
