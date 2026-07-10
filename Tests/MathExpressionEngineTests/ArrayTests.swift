import Testing
@testable import MathExpressionEngine

@Suite struct ArrayTests {

    private func value(_ src: String, _ inputs: [String: Float] = [:]) throws -> EngineValue {
        let r = compile(src)
        #expect(r.isValid, "`\(src)`: \(r.diagnostics)")
        return try r.evaluateValue(inputs)
    }
    private func approx(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-4 }

    @Test func arrayLiteral() throws {
        #expect(try value("[1, 2, 3]").arrayElements == [.float(1), .float(2), .float(3)])
        #expect(compile("[1, 2, 3]").interface.outputType == .array(.float))
    }

    @Test func comprehensionHalfOpen() throws {
        #expect(try value("[i * 2 for i in 0..<4]").arrayElements == [.float(0), .float(2), .float(4), .float(6)])
    }

    @Test func comprehensionInclusive() throws {
        #expect(try value("[i for i in 1..3]").arrayElements == [.float(1), .float(2), .float(3)])
    }

    @Test func indexing() throws {
        #expect(try value("[10, 20, 30][1]") == .float(20))
        #expect(try compile("let a = [10, 20, 30]; out y = a[k]").evaluate(["k": 2]) == 30)
    }

    @Test func reductions() throws {
        #expect(try value("sum([1, 2, 3, 4])") == .float(10))
        #expect(try value("product([1, 2, 3, 4])") == .float(24))
        #expect(try value("count([5, 6, 7])") == .float(3))
        #expect(approx(try value("mean([2, 4, 6])").scalar, 4))
    }

    @Test func vectorComprehension() throws {
        let v = try value("[vec2(i, i * 2) for i in 0..<3]")
        #expect(v.arrayElements == [.vec2(SIMD2(0, 0)), .vec2(SIMD2(1, 2)), .vec2(SIMD2(2, 4))])
        #expect(compile("[vec3(i, 0, 0) for i in 0..<n]").interface.outputType == .array(.vec3))
    }

    @Test func sumOfVectors() throws {
        #expect(try value("sum([vec2(1, 2), vec2(3, 4)])") == .vec2(SIMD2(4, 6)))
    }

    @Test func comprehensionWithInputs() throws {
        let r = compile("[i * step for i in 0..<count]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.inputNames.contains("step") && r.interface.inputNames.contains("count"))
        #expect(try r.evaluateValue(["step": 10, "count": 3]).arrayElements == [.float(0), .float(10), .float(20)])
    }

    @Test func outputTypesInferred() {
        #expect(compile("[1, 2, 3]").interface.outputType == .array(.float))
        #expect(compile("sum([1, 2, 3])").interface.outputType == .float)
        #expect(compile("[vec2(i, i) for i in 0..<n]").interface.outputType == .array(.vec2))
    }

    // MARK: - Errors

    @Test func heterogeneousArrayIsError() {
        let r = compile("[1, vec2(1, 2)]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .heterogeneousArray })
    }

    @Test func emptyArrayIsError() {
        let r = compile("[]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .emptyArray })
    }

    @Test func indexingNonArrayIsError() {
        let r = compile("x[0]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .notAnArray })
    }

    @Test func reducingNonArrayIsError() {
        let r = compile("sum(x)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .notAnArray })
    }

    @Test func addingArraysIsError() {
        let r = compile("[1, 2] + [3, 4]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }

    @Test func indexOutOfBoundsThrows() {
        let r = compile("[1, 2, 3][k]")
        #expect(r.isValid)
        #expect(throws: EvalError.self) { try r.evaluate(["k": 5]) }
    }

    // min/max reduce a single array argument (largest/smallest element).

    @Test func minMaxReduceScalarArray() throws {
        #expect(try value("min([3, 1, 2])") == .float(1))
        #expect(try value("max([3, 1, 2])") == .float(3))
        #expect(compile("min([3, 1, 2])").interface.outputType == .float)
    }

    @Test func minMaxReduceVectorArrayComponentwise() throws {
        #expect(try value("max([vec3(1, 5, 3), vec3(4, 2, 6)])") == .vec3(SIMD3(4, 5, 6)))
        #expect(try value("min([vec3(1, 5, 3), vec3(4, 2, 6)])") == .vec3(SIMD3(1, 2, 3)))
        #expect(compile("max([vec2(1, 2), vec2(3, 4)])").interface.outputType == .vec2)
    }

    @Test func minMaxReduceArrayInput() throws {
        let r = compile("in xs: float[]; out m = max(xs)")
        #expect(r.isValid, "\(r.diagnostics)")
        let m = try r.evaluateValue(with: ["xs": .array([.float(5), .float(2), .float(8), .float(1)])])
        #expect(m == .float(8))
    }

    @Test func minMaxTwoArgFormStillComponentwise() throws {
        // The reduction form doesn't disturb the existing two-argument form.
        #expect(try value("min(3, 5)") == .float(3))
        #expect(try value("max(vec2(1, 9), vec2(4, 2))") == .vec2(SIMD2(4, 9)))
    }

    @Test func minReducingNonArrayIsError() {
        let r = compile("min(5)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .argumentCount })
    }

    @Test func minReducingNonNumericArrayIsError() {
        let r = compile("min([identity(), identity()])")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .typeMismatch })
    }
}
