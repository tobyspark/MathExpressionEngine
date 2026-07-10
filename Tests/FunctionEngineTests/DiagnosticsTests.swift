import Testing
@testable import FunctionEngine

@Suite struct DiagnosticsTests {

    private func codes(_ src: String) -> [DiagnosticCode] {
        compile(src).diagnostics.map(\.code)
    }

    @Test func unknownFunctionReported() {
        let r = compile("foo(1)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .unknownName })
    }

    @Test func wrongArgumentCountReported() {
        let r = compile("sin(1, 2)")           // sin takes 1
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .argumentCount })
    }

    @Test func unmatchedParenReported() {
        let r = compile("sin(1")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .unmatchedParen })
    }

    @Test func emptyBodyReported() {
        let r = compile("")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .emptyBody })
    }

    @Test func trailingGarbageIsInvalid() {
        let r = compile("2 + 3 4")
        #expect(!r.isValid)
    }

    @Test func danglingOperatorIsInvalid() {
        let r = compile("2 +")
        #expect(!r.isValid)
    }

    @Test func validExpressionHasNoErrorDiagnostics() {
        let r = compile("sin(x) + 1")
        #expect(r.isValid)
        #expect(!r.diagnostics.contains { $0.severity == .error })
    }

    @Test func diagnosticCarriesASpan() {
        // The unknown name `foo` should be located, not pinned at 0.
        let r = compile("1 + foo(2)")
        let d = r.diagnostics.first { $0.code == .unknownName }
        #expect(d != nil)
        #expect((d?.span.start ?? 0) > 0)
    }

    @Test func evaluatingInvalidThrowsNotCompiled() {
        let r = compile("foo(")
        #expect(throws: EvalError.notCompiled) { try r.evaluate([:]) }
    }

    @Test func missingInputThrows() {
        let r = compile("x + 1")
        #expect(r.isValid)
        #expect(throws: EvalError.missingInput("x")) { try r.evaluate([:]) }
    }
}
