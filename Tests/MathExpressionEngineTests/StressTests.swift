import Testing
@testable import MathExpressionEngine

// Stress the eval path: many evaluations across expressions with differing
// register counts, each checked against the reference interpreter — guarding the
// register-machine execution (indexing, missing-input bail) under load.
//
// (Since slice 6 the register file is a heap `[EngineValue]` — Option B, unified
// value type. The earlier stack-scratch/zero-alloc register file can be
// reintroduced as a scalar/vector fast path behind these same tests; see
// DESIGN-FunctionNode-Engine.md §9 / the arrays decision.)

@Suite struct StressTests {

    private func equalOrBothNaN(_ a: Float, _ b: Float) -> Bool {
        a == b || (a.isNaN && b.isNaN)
    }

    @Test func heavyLoadTapeMatchesReference() throws {
        // Expressions chosen to vary register count and cover all instruction kinds.
        let sources = [
            "a + b",                                              // tiny
            "sin(a) * cos(b) + c ^ 2",
            "clamp(mix(a, b, saturate(c)), -1, 1)",
            "sqrt(abs(a * b)) / (c + 1) - atan2(a, b)",
            "((a + b) * (b - c)) ^ 2 / (abs(c) + 0.5)",
            "smoothstep(-1, 1, a) + step(b, c) * mod(a, 3.0)",
        ]

        var accumulator: Float = 0
        var comparisons = 0

        for src in sources {
            let tape = compile(src)
            let reference = compileReferenceInterpreter(src)
            #expect(tape.isValid && reference.isValid, "failed to compile `\(src)`")

            var x: Float = -3
            var i = 0
            while i < 30_000 {
                let inputs: [String: Float] = ["a": x, "b": x * 0.5 - 1, "c": 2 - x]
                let t = try tape.evaluate(inputs)
                let r = try reference.evaluate(inputs)
                #expect(equalOrBothNaN(t, r), "mismatch `\(src)` @ \(inputs): tape=\(t) ref=\(r)")
                if t.isFinite { accumulator += t * 1e-6 }
                x += 0.0004
                i += 1
                comparisons += 1
            }
        }

        #expect(comparisons == sources.count * 30_000)
        #expect(accumulator.isFinite)
    }

    @Test func missingInputStillThrowsOnHeavyPath() throws {
        // The bail-without-throwing-inside-the-closure path must still surface
        // the typed error.
        let r = compile("a + b + c")
        #expect(r.isValid)
        #expect(throws: EvalError.missingInput("b")) {
            try r.evaluate(["a": 1, "c": 3])   // b absent
        }
    }
}
