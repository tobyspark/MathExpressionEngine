import Testing
@testable import FunctionEngine

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
        #expect(r.interface.inputs.contains("step") && r.interface.inputs.contains("count"))
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
}
