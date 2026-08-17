import Testing
@testable import MathExpressionEngine

/// The public host-boundary constructors (`Mat4(columns:)`, `Quat(components:)`)
/// must be exact inverses of the public `columns` / `components` getters, so a
/// host `simd_float4x4` / `simd_quatf` round-trips through the engine unchanged.
@Suite struct HostBoundaryTests {

    @Test func mat4ColumnsRoundTrip() {
        let cols = (SIMD4<Float>(1, 2, 3, 4),
                    SIMD4<Float>(5, 6, 7, 8),
                    SIMD4<Float>(9, 10, 11, 12),
                    SIMD4<Float>(13, 14, 15, 16))
        let m = Mat4(columns: cols)
        #expect(m.columns == cols)
        // And feeding the columns back reproduces the same matrix.
        #expect(Mat4(columns: m.columns) == m)
    }

    @Test func quatComponentsRoundTrip() {
        let v = SIMD4<Float>(0.1, 0.2, 0.3, 0.9)
        let q = Quat(components: v)
        #expect(q.components == v)
        #expect(Quat(components: q.components) == q)
    }

    /// A transform an expression produced can be fed straight back in as a
    /// `transform` input and used, exercising both directions of the boundary.
    @Test func transformInputRoundTripsThroughEvaluation() throws {
        let produced = compile("translate(vec3(1, 2, 3))")
        #expect(produced.isValid, "diagnostics: \(produced.diagnostics)")
        guard case .transform(let m) = try produced.evaluateValue(with: [:]) else {
            Issue.record("expected a transform output"); return
        }

        // Reconstruct via the public constructor and pass it back in.
        let rebuilt = EngineValue.transform(Mat4(columns: m.columns))
        let identity = compile("in t: transform; out o = t")
        #expect(identity.isValid, "diagnostics: \(identity.diagnostics)")
        guard case .transform(let out) = try identity.evaluateValue(with: ["t": rebuilt]) else {
            Issue.record("expected a transform output"); return
        }
        #expect(out == m)
    }

    /// Every `EvalError` case describes itself. Missing this, a host reporting
    /// an evaluation failure gets Foundation's "The operation couldn't be
    /// completed. (…error 0.)" placeholder, which names neither the case nor
    /// its payload.
    @Test(arguments: [EvalError.notCompiled,
                      .missingInput("x"),
                      .indexOutOfBounds(index: 4, count: 3),
                      .limitExceeded("comprehension produced 9000 elements (max 4096)")])
    func evalErrorsDescribeThemselves(_ error: EvalError) {
        let description = error.localizedDescription
        #expect(error.errorDescription != nil)
        #expect(!description.contains("couldn"), "fell back to Foundation's placeholder: \(description)")
        #expect(!description.contains("EvalError"), "fell back to Foundation's placeholder: \(description)")
    }

    /// The payloads are what make a failure actionable, so they have to reach
    /// the text.
    @Test func evalErrorDescriptionsCarryTheirPayload() {
        #expect(EvalError.missingInput("gain").localizedDescription.contains("gain"))

        let bounds = EvalError.indexOutOfBounds(index: 4, count: 3).localizedDescription
        #expect(bounds.contains("4") && bounds.contains("3"))

        #expect(EvalError.limitExceeded("too many elements").localizedDescription.contains("too many elements"))
    }
}
