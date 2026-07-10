import Testing
@testable import MathExpressionEngine

/// Metamorphic / algebraic invariants — assert relationships that must hold for
/// any inputs, without hand-computing expected values.
@Suite struct PropertyTests {

    private func eval(_ src: String, _ inputs: [String: Float]) throws -> Float {
        let r = compile(src)
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        return try r.evaluate(inputs)
    }

    private let samples: [Float] = [-100, -3.5, -1, 0, 0.25, 1, 2.5, 42]

    @Test func additiveIdentity() throws {
        for x in samples {
            #expect(try eval("x + 0", ["x": x]) == x)
        }
    }

    @Test func multiplicativeIdentity() throws {
        for x in samples {
            #expect(try eval("x * 1", ["x": x]) == x)
        }
    }

    @Test func mixEndpoints() throws {
        for a in samples {
            for b in samples {
                #expect(try eval("mix(a, b, 0)", ["a": a, "b": b]) == a)
                #expect(try eval("mix(a, b, 1)", ["a": a, "b": b]) == b)
            }
        }
    }

    @Test func clampWithinBounds() throws {
        for x in samples {
            let v = try eval("clamp(x, 0, 1)", ["x": x])
            #expect(v >= 0 && v <= 1)
        }
    }

    @Test func determinismSameInputsSameOutput() throws {
        let r = compile("sin(x) * cos(y) + x ^ 2")
        #expect(r.isValid)
        let a = try r.evaluate(["x": 1.3, "y": 0.7])
        let b = try r.evaluate(["x": 1.3, "y": 0.7])
        #expect(a == b)
    }
}
