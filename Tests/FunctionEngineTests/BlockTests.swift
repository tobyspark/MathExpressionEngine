import Testing
@testable import FunctionEngine

// `let` locals and `out` multiple named outputs.
@Suite struct BlockTests {

    @Test func letBindingIsUsableAsImplicitResult() throws {
        #expect(try compile("let d = 3; d * 2").evaluate([:]) == 6)
    }

    @Test func localsAreNotInputs() {
        #expect(compile("let d = 2; d * x").interface.inputs == ["x"])
    }

    @Test func bareExpressionHasImplicitResultOutput() {
        #expect(compile("a + 1").interface.outputNames == ["result"])
    }

    @Test func multipleNamedOutputs() throws {
        let r = compile("let s = a + b; out sum = s; out diff = a - b")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputNames == ["sum", "diff"])
        #expect(r.interface.inputs == ["a", "b"])
        #expect(try r.evaluateAll(["a": 5, "b": 3]) == [8, 2])
    }

    @Test func evaluateReturnsFirstOutput() throws {
        let r = compile("out a1 = x + 1; out a2 = x - 1")
        #expect(try r.evaluate(["x": 10]) == 11)
        #expect(try r.evaluateAll(["x": 10]) == [11, 9])
    }

    @Test func chainedLocals() throws {
        let r = compile("let a = x + 1; let b = a * 2; out y = b + a")
        #expect(r.isValid, "\(r.diagnostics)")
        // a = 4, b = 8, y = 12
        #expect(try r.evaluate(["x": 3]) == 12)
    }

    // MARK: - Errors

    @Test func bareExprMixedWithOutIsError() {
        let r = compile("out y = a; a + 1")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .mixedOutput })
    }

    @Test func duplicateOutputIsError() {
        let r = compile("out y = a; out y = b")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateOutput })
    }

    @Test func onlyLetsNoOutputIsError() {
        let r = compile("let d = a + b")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .noOutput })
    }

    @Test func useBeforeDefinitionIsError() {
        let r = compile("out y = d; let d = 3")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .useBeforeDefinition })
    }

    @Test func duplicateLocalIsError() {
        let r = compile("let d = 1; let d = 2; out y = d")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding })
    }

    @Test func letWithoutEqualsIsError() {
        let r = compile("let d 3; out y = d")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .expectedEquals })
    }
}
