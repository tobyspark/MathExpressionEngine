import Testing
@testable import MathExpressionEngine

@Suite struct TransformTests {

    private func value(_ src: String, _ inputs: [String: Float] = [:]) throws -> EngineValue {
        let r = compile(src)
        #expect(r.isValid, "`\(src)`: \(r.diagnostics)")
        return try r.evaluateValue(inputs)
    }
    private func approx(_ a: Float, _ b: Float, _ eps: Float = 1e-4) -> Bool { abs(a - b) <= eps }
    private func approxVec3(_ v: EngineValue, _ x: Float, _ y: Float, _ z: Float) -> Bool {
        let c = v.components
        return c.count >= 3 && approx(c[0], x) && approx(c[1], y) && approx(c[2], z)
    }
    private func approxComponents(_ v: EngineValue, _ expected: [Float]) -> Bool {
        let c = v.components
        return c.count == expected.count && zip(c, expected).allSatisfy { approx($0, $1) }
    }

    @Test func identityOutputType() {
        #expect(compile("identity()").interface.outputType == .transform)
        #expect(compile("quatAxisAngle(x, vec3(0, 1, 0))").interface.outputType == .quat)
    }

    @Test func identityTransformsPointUnchanged() throws {
        #expect(approxVec3(try value("transformPoint(identity(), vec3(1, 2, 3))"), 1, 2, 3))
    }

    @Test func translate() throws {
        #expect(approxVec3(try value("transformPoint(translate(vec3(10, 20, 30)), vec3(1, 2, 3))"), 11, 22, 33))
        // direction ignores translation
        #expect(approxVec3(try value("transformDir(translate(vec3(10, 20, 30)), vec3(1, 2, 3))"), 1, 2, 3))
    }

    @Test func scale() throws {
        #expect(approxVec3(try value("transformPoint(scale(vec3(2, 3, 4)), vec3(1, 1, 1))"), 2, 3, 4))
        #expect(approxVec3(try value("transformPoint(scale(2), vec3(1, 1, 1))"), 2, 2, 2))   // uniform
    }

    @Test func rotateZ90() throws {
        #expect(approxVec3(try value("transformPoint(rotateZ(pi / 2), vec3(1, 0, 0))"), 0, 1, 0))
    }

    @Test func matrixTimesVec4() throws {
        #expect(approxComponents(try value("translate(vec3(5, 6, 7)) * vec4(0, 0, 0, 1)"), [5, 6, 7, 1]))
    }

    @Test func matrixMultiplyWithIdentity() throws {
        #expect(approxVec3(try value("transformPoint(translate(vec3(5, 0, 0)) * identity(), vec3(0, 0, 0))"), 5, 0, 0))
    }

    @Test func transposeTwiceRoundTrips() throws {
        let original = try value("rotateZ(0.7)").components
        #expect(approxComponents(try value("transpose(transpose(rotateZ(0.7)))"), original))
    }

    @Test func quaternionRotatesVector() throws {
        // 90° about +Y maps (1,0,0) -> (0,0,-1)
        #expect(approxVec3(try value("quatAxisAngle(pi / 2, vec3(0, 1, 0)) * vec3(1, 0, 0)"), 0, 0, -1))
        #expect(approxVec3(try value("rotate(quatAxisAngle(pi / 2, vec3(0, 1, 0)), vec3(1, 0, 0))"), 0, 0, -1))
    }

    @Test func quaternionComposeMatchesRotation() throws {
        // compose(0, 90°-about-z, 1) applied to (1,0,0) == (0,1,0)
        #expect(approxVec3(try value("transformPoint(compose(vec3(0,0,0), quatAxisAngle(pi/2, vec3(0,0,1)), vec3(1,1,1)), vec3(1,0,0))"), 0, 1, 0))
    }

    @Test func quaternionMultiplyComposesRotations() throws {
        // two 45°-about-z rotations == one 90°: (1,0,0) -> (0,1,0)
        let src = "let q = quatAxisAngle(pi / 4, vec3(0, 0, 1)); out r = (q * q) * vec3(1, 0, 0)"
        #expect(approxVec3(try value(src), 0, 1, 0))
    }

    @Test func inverseUndoesTransform() throws {
        // inverse(T) * T == identity, so it round-trips a point back.
        let src = "let t = translate(vec3(3, -4, 5)) * rotateY(0.9); transformPoint(inverse(t) * t, vec3(2, 7, -1))"
        #expect(approxVec3(try value(src), 2, 7, -1))
    }

    @Test func inverseOutputType() {
        #expect(compile("inverse(rotateX(0.3))").interface.outputType == .transform)
    }

    @Test func lookAtLooksAlongForward() throws {
        // Camera at origin looking down -Z: a point one unit ahead (at -Z) lands
        // on the camera's -Z axis with the expected depth (view space).
        let src = "transformPoint(lookAt(vec3(0, 0, 0), vec3(0, 0, -1), vec3(0, 1, 0)), vec3(0, 0, -5))"
        #expect(approxVec3(try value(src), 0, 0, -5))
    }

    @Test func lookAtInverseIsCameraPlacement() throws {
        // inverse(view) maps the camera origin back to the eye position.
        let src = "transformPoint(inverse(lookAt(vec3(2, 3, 4), vec3(0, 0, 0), vec3(0, 1, 0))), vec3(0, 0, 0))"
        #expect(approxVec3(try value(src), 2, 3, 4))
    }

    @Test func lookAtOutputType() {
        #expect(compile("lookAt(vec3(0,0,5), vec3(0,0,0), vec3(0,1,0))").interface.outputType == .transform)
    }

    @Test func quatEulerMatchesRotationMatrix() throws {
        // quatEuler(x,y,z) == rotateZ(z)·rotateY(y)·rotateX(x) applied to a vector.
        let euler = "rotate(quatEuler(vec3(0.3, -0.7, 1.1)), vec3(1, 2, 3))"
        let matrix = "transformDir(rotateZ(1.1) * rotateY(-0.7) * rotateX(0.3), vec3(1, 2, 3))"
        let e = try value(euler).components
        #expect(approxComponents(try value(matrix), Array(e)))
    }

    @Test func slerpEndpoints() throws {
        // t=0 and t=1 return the endpoints; midpoint of two 0°/90°-about-Y
        // rotations is 45°, taking (1,0,0) to (cos45°, 0, -sin45°).
        let a = "quatAxisAngle(0, vec3(0, 1, 0))"
        let b = "quatAxisAngle(pi / 2, vec3(0, 1, 0))"
        #expect(approxVec3(try value("slerp(\(a), \(b), 0) * vec3(1, 0, 0)"), 1, 0, 0))
        #expect(approxVec3(try value("slerp(\(a), \(b), 1) * vec3(1, 0, 0)"), 0, 0, -1))
        let mid = Float(2).squareRoot() / 2
        #expect(approxVec3(try value("slerp(\(a), \(b), 0.5) * vec3(1, 0, 0)"), mid, 0, -mid))
    }

    @Test func slerpOutputType() {
        #expect(compile("slerp(quatAxisAngle(0, vec3(0,1,0)), quatAxisAngle(1, vec3(0,1,0)), t)").interface.outputType == .quat)
    }

    @Test func transformArrayComprehensionDrivesInstances() throws {
        // Representative target: an array of transforms (feeds InstancedMesh).
        let r = compile("[translate(vec3(i, 0, 0)) for i in 0..<n]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputType == .array(.transform))
        let v = try r.evaluateValue(["n": 3])
        #expect(v.arrayElements?.count == 3)
    }

    @Test func publicAccessorsForBridging() throws {
        // The Fabric adapter reads these to build simd_float4x4 / simd_quatf.
        guard case .transform(let m) = try value("identity()") else { #expect(Bool(false)); return }
        let (c0, _, _, c3) = m.columns
        #expect(c0 == SIMD4(1, 0, 0, 0))
        #expect(c3 == SIMD4(0, 0, 0, 1))

        guard case .quat(let q) = try value("quatAxisAngle(0, vec3(0, 1, 0))") else { #expect(Bool(false)); return }
        #expect(q.components == SIMD4(0, 0, 0, 1))   // zero-angle → identity quaternion
    }

    // MARK: - Errors

    @Test func transformTimesVec3IsError() {
        let r = compile("translate(vec3(1, 2, 3)) * vec3(1, 0, 0)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func transformPlusTransformIsError() {
        let r = compile("identity() + identity()")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func inverseOfQuatIsError() {
        // inverse is transform-only; a quat should be rejected (use conjugate).
        let r = compile("inverse(quatAxisAngle(1, vec3(0, 1, 0)))")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func slerpWithNonQuatIsError() {
        let r = compile("slerp(vec3(0, 0, 0), quatAxisAngle(1, vec3(0, 1, 0)), 0.5)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }
}
