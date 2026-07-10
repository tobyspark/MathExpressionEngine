import Testing
@testable import FunctionEngine

@Suite struct VectorTests {

    private func value(_ src: String, _ inputs: [String: Float] = [:]) throws -> EngineValue {
        let r = compile(src)
        #expect(r.isValid, "`\(src)`: \(r.diagnostics)")
        return try r.evaluateValue(inputs)
    }
    private func approx(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-4 }

    @Test func constructVectors() throws {
        #expect(try value("vec2(1, 2)") == .vec2(SIMD2(1, 2)))
        #expect(try value("vec3(1, 2, 3)") == .vec3(SIMD3(1, 2, 3)))
        #expect(try value("vec4(1, 2, 3, 4)") == .vec4(SIMD4(1, 2, 3, 4)))
    }

    @Test func splatConstructor() throws {
        #expect(try value("vec2(5)") == .vec2(SIMD2(5, 5)))
        #expect(try value("vec4(0)") == .vec4(SIMD4(0, 0, 0, 0)))
    }

    @Test func swizzles() throws {
        #expect(try value("vec3(1, 2, 3).x") == .float(1))
        #expect(try value("vec3(1, 2, 3).zyx") == .vec3(SIMD3(3, 2, 1)))
        #expect(try value("vec4(1, 2, 3, 4).xy") == .vec2(SIMD2(1, 2)))
        #expect(try value("vec3(1, 2, 3).xxz") == .vec3(SIMD3(1, 1, 3)))
        #expect(try value("vec4(1, 2, 3, 4).rgb") == .vec3(SIMD3(1, 2, 3)))
        #expect(try value("vec4(1, 2, 3, 4).a") == .float(4))
    }

    @Test func elementwiseAndBroadcast() throws {
        #expect(try value("vec3(1, 2, 3) + vec3(10, 20, 30)") == .vec3(SIMD3(11, 22, 33)))
        #expect(try value("vec3(1, 2, 3) * 2") == .vec3(SIMD3(2, 4, 6)))
        #expect(try value("2 * vec3(1, 2, 3)") == .vec3(SIMD3(2, 4, 6)))
        #expect(try value("vec2(4, 8) / 2") == .vec2(SIMD2(2, 4)))
        #expect(try value("-vec3(1, 2, 3)") == .vec3(SIMD3(-1, -2, -3)))
    }

    @Test func vectorFunctions() throws {
        #expect(approx(try value("length(vec3(3, 4, 0))").scalar, 5))
        #expect(approx(try value("distance(vec2(0, 0), vec2(3, 4))").scalar, 5))
        #expect(approx(try value("dot(vec3(1, 2, 3), vec3(4, 5, 6))").scalar, 32))
        #expect(try value("cross(vec3(1, 0, 0), vec3(0, 1, 0))") == .vec3(SIMD3(0, 0, 1)))
        let n = try value("normalize(vec3(0, 3, 0))")
        #expect(approx(n.components[0], 0) && approx(n.components[1], 1) && approx(n.components[2], 0))
    }

    @Test func genNMathIsComponentwise() throws {
        #expect(try value("abs(vec3(-1, 2, -3))") == .vec3(SIMD3(1, 2, 3)))
        #expect(try value("floor(vec2(1.7, 2.2))") == .vec2(SIMD2(1, 2)))
    }

    @Test func outputTypesAreInferred() {
        #expect(compile("vec3(x, y, z)").interface.outputType == .vec3)
        #expect(compile("normalize(vec3(x, y, z))").interface.outputType == .vec3)
        #expect(compile("length(vec3(x, y, z))").interface.outputType == .float)
        #expect(compile("vec3(x, y, z).xy").interface.outputType == .vec2)
    }

    @Test func vectorLocalsAndTypedOutputs() throws {
        let r = compile("let p = vec3(x, y, 0); out dir = normalize(p); out len = length(p)")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputs == [OutputPort(name: "dir", type: .vec3),
                                        OutputPort(name: "len", type: .float)])
        let outs = try r.evaluateValues(["x": 3, "y": 4])
        #expect(outs.count == 2)
        #expect(approx(outs[1].scalar, 5))   // length
    }

    // MARK: - Errors

    @Test func mismatchedVectorWidthsError() {
        let r = compile("vec2(1, 2) + vec3(1, 2, 3)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func swizzleOnScalarIsError() {
        let r = compile("x.xy")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .badSwizzle })
    }

    @Test func swizzleComponentOutOfRangeIsError() {
        let r = compile("vec2(1, 2).z")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .badSwizzle })
    }

    @Test func crossRequiresVec3() {
        let r = compile("cross(vec2(1, 2), vec2(3, 4))")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func scalarMultiRejectsVectors() {
        let r = compile("min(vec2(1, 2), vec2(3, 4))")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }
}
