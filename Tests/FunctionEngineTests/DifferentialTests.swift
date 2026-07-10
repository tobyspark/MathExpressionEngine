import Testing
@testable import FunctionEngine

// Differential testing: the fast POD tape (`compile`) must agree with the
// tree-walking reference interpreter (`compileReferenceInterpreter`) on random
// well-typed scalar expressions. Both compute Float via the *same* underlying
// math (Builtins.evaluate) applied to the *same* AST shape, so results must be
// bit-identical (NaN-aware). Seeded RNG ⇒ reproducible failures.

/// Deterministic SplitMix64 PRNG.
private struct RNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }

    mutating func unit() -> Float {
        Float(next() >> 40 & 0xFFFFFF) / Float(0x1000000)   // [0, 1)
    }

    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}

/// Generates random, syntactically-valid scalar expressions over vars a/b/c.
private struct ExprGen {
    var rng: RNG
    let vars = ["a", "b", "c"]

    let fns1 = ["sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "abs",
                "exp", "log", "log2", "floor", "ceil", "round", "sign",
                "fract", "radians", "degrees", "saturate"]
    let fns2 = ["atan2", "pow", "min", "max", "mod", "step"]
    let fns3 = ["clamp", "mix", "smoothstep"]
    let ops  = ["+", "-", "*", "/", "^", "%"]

    mutating func leaf() -> String {
        switch rng.int(3) {
        case 0:  return vars[rng.int(vars.count)]
        case 1:  return ["pi", "tau", "e"][rng.int(3)]
        default: return "\(rng.int(10)).\(rng.int(10))"
        }
    }

    mutating func generate(depth: Int) -> String {
        if depth <= 0 { return leaf() }
        switch rng.int(5) {
        case 0, 1:
            return "(\(generate(depth: depth - 1)) \(ops[rng.int(ops.count)]) \(generate(depth: depth - 1)))"
        case 2:
            return "(-\(generate(depth: depth - 1)))"
        case 3:
            return "\(fns1[rng.int(fns1.count)])(\(generate(depth: depth - 1)))"
        default:
            if rng.int(2) == 0 {
                return "\(fns2[rng.int(fns2.count)])(\(generate(depth: depth - 1)), \(generate(depth: depth - 1)))"
            } else {
                return "\(fns3[rng.int(fns3.count)])(\(generate(depth: depth - 1)), \(generate(depth: depth - 1)), \(generate(depth: depth - 1)))"
            }
        }
    }
}

private func equalOrBothNaN(_ a: Float, _ b: Float) -> Bool {
    a == b || (a.isNaN && b.isNaN)
}

@Suite struct DifferentialTests {

    @Test func tapeMatchesReferenceInterpreter() throws {
        var gen = ExprGen(rng: RNG(seed: 0xF00D_CAFE_1234_5678))
        var checked = 0

        for _ in 0..<400 {
            let src = gen.generate(depth: 4)

            let tape = compile(src)
            let reference = compileReferenceInterpreter(src)

            // The generator only emits valid scalar expressions.
            #expect(tape.isValid, "generator produced an invalid expression: `\(src)` — \(tape.diagnostics)")
            #expect(reference.isValid)
            guard tape.isValid, reference.isValid else { continue }

            // Both back ends must derive the same interface.
            #expect(tape.interface == reference.interface)

            for _ in 0..<4 {
                let inputs: [String: Float] = [
                    "a": gen.rng.float(in: -6...6),
                    "b": gen.rng.float(in: -6...6),
                    "c": gen.rng.float(in: -6...6),
                ]
                let t = try tape.evaluate(inputs)
                let r = try reference.evaluate(inputs)
                #expect(equalOrBothNaN(t, r),
                        "mismatch for `\(src)` with \(inputs): tape=\(t) reference=\(r)")
                checked += 1
            }
        }

        #expect(checked > 1000, "expected a meaningful number of comparisons, got \(checked)")
    }

    @Test func tapeAndReferenceAgreeOnFixedCases() throws {
        // A few hand-picked expressions, exact agreement.
        for src in ["sin(a) + b ^ 2", "clamp(a * b, -1, 1)", "-(a) + mix(b, c, 0.25)",
                    "sqrt(abs(a)) / (b + 1)", "atan2(a, b) * pi"] {
            let tape = compile(src)
            let reference = compileReferenceInterpreter(src)
            #expect(tape.isValid && reference.isValid)
            let inputs: [String: Float] = ["a": 1.5, "b": -2.25, "c": 0.75]
            #expect(equalOrBothNaN(try tape.evaluate(inputs), try reference.evaluate(inputs)))
        }
    }
}
