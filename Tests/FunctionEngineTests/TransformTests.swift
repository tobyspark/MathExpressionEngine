import Testing
@testable import FunctionEngine

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

    @Test func transformArrayComprehensionDrivesInstances() throws {
        // The north-star: an array of transforms (feeds InstancedMesh).
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
}
