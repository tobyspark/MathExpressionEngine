import Testing
@testable import MathExpressionEngine

// Diagnostics & guardrail hardening.
@Suite struct HardeningTests {

    @Test func didYouMeanSuggestion() {
        let r = compile("sine(x)")   // typo of `sin`
        #expect(!r.isValid)
        let d = r.diagnostics.first { $0.code == .unknownName }
        #expect(d != nil)
        #expect(d?.message.contains("sin") == true)
        #expect(d?.message.contains("Did you mean") == true)
    }

    @Test func unknownFunctionWithNoCloseMatchStillErrors() {
        let r = compile("qwertyuiop(x)")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .unknownName })
    }

    @Test func literalDivideByZeroIsAdvisoryWarning() {
        let r = compile("x / 0")
        #expect(r.isValid)   // warnings don't block
        #expect(r.diagnostics.contains { $0.code == .divisionByZero && $0.severity == .warning })
    }

    @Test func nonLiteralDivisionIsNotWarned() {
        let r = compile("x / y")
        #expect(r.isValid)
        #expect(!r.diagnostics.contains { $0.code == .divisionByZero })
    }

    @Test func unusedLetIsAdvisoryWarning() {
        let r = compile("let unused = 1; out y = x + 1")
        #expect(r.isValid)
        #expect(r.diagnostics.contains { $0.code == .unusedBinding && $0.severity == .warning })
    }

    @Test func usedLetIsNotWarned() {
        let r = compile("let d = x + 1; out y = d * 2")
        #expect(r.isValid)
        #expect(!r.diagnostics.contains { $0.code == .unusedBinding })
    }

    @Test func warningsNeverBlock() {
        let r = compile("let unused = 9; x / 0")
        #expect(r.isValid)
        #expect(r.diagnostics.allSatisfy { $0.severity != .error })
    }

    @Test func deeplyNestedExpressionIsRejectedNotCrashed() {
        let src = String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)
        let r = compile(src)
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .expressionTooDeep })
    }

    @Test func comprehensionSizeCapThrowsNotHangs() {
        let r = compile("[i for i in 0..<n]")
        #expect(r.isValid)
        #expect(throws: EvalError.self) { try r.evaluateValue(["n": 5_000_000]) }
    }

    @Test func indexOutOfBoundsThrows() {
        let r = compile("[1, 2, 3][k]")
        #expect(r.isValid)
        #expect(throws: EvalError.self) { try r.evaluate(["k": 10]) }
    }
}
