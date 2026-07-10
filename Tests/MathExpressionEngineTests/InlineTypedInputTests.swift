import Testing
@testable import MathExpressionEngine

/// Inline input typing: `name: Type` declares a typed input at the use site,
/// as an alternative to a separate `in name: Type` statement. Such a name must
/// be used exactly once — a second use is an error asking for an `in` decl.
@Suite struct InlineTypedInputTests {

    // MARK: Deriving the interface

    @Test func inlineTypeDerivesTypedInput() {
        let r = compile("(p: vec3) * 2")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "p", type: .vec3)])
        #expect(r.interface.outputs.first?.type == .vec3)
    }

    @Test func inlineTypeMixesWithBareFloatInputs() {
        // `p` is a typed vec3, `s` is an ordinary (untyped) float input.
        let r = compile("(p: vec3) * s")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "p", type: .vec3),
                                       InputPort(name: "s", type: .float)])
    }

    @Test func inlineTypedArrayInput() {
        let r = compile("count(points: vec3[])")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "points", type: .array(.vec3))])
        #expect(r.interface.outputs.first?.type == .float)
    }

    @Test func inlineTypeAllowsSwizzle() {
        let r = compile("(p: vec3).x")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "p", type: .vec3)])
        #expect(r.interface.outputs.first?.type == .float)
    }

    @Test func inlineNamedOutput() {
        let r = compile("out o = (p: vec3) * 2")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "p", type: .vec3)])
        #expect(r.interface.outputNames == ["o"])
    }

    // MARK: Evaluation

    @Test func inlineTypedInputEvaluates() throws {
        let r = compile("(p: vec3) * 2")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        let out = try r.evaluateValue(with: ["p": .vec3(SIMD3(1, 2, 3))])
        #expect(out == .vec3(SIMD3(2, 4, 6)))
    }

    @Test func inlineAndBareInputEvaluateTogether() throws {
        let r = compile("(p: vec3) * s")
        let out = try r.evaluateValue(with: ["p": .vec3(SIMD3(1, 2, 3)), "s": .float(10)])
        #expect(out == .vec3(SIMD3(10, 20, 30)))
    }

    @Test func inlineTypedMatchesInDeclaration() throws {
        // Inline and `in` forms produce the same interface and result.
        let inline = compile("(p: vec3) + vec3(1)")
        let declared = compile("in p: vec3; out result = p + vec3(1)")
        #expect(inline.interface.inputs == declared.interface.inputs)
        let a = try inline.evaluateValue(with: ["p": .vec3(SIMD3(4, 5, 6))])
        let b = try declared.evaluateValue(with: ["p": .vec3(SIMD3(4, 5, 6))])
        #expect(a == b)
        #expect(a == .vec3(SIMD3(5, 6, 7)))
    }

    // MARK: The single-use rule

    private func expectUsedMoreThanOnce(_ src: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let r = compile(src)
        #expect(!r.isValid, "expected \(src) to be rejected", sourceLocation: sourceLocation)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding && $0.severity == .error },
                "expected a duplicate-binding error for \(src); got \(r.diagnostics)", sourceLocation: sourceLocation)
    }

    @Test func inlineTypedUsedBareAgainIsError() {
        expectUsedMoreThanOnce("(p: vec3) + p")   // typed then bare
    }

    @Test func bareThenInlineTypedIsError() {
        expectUsedMoreThanOnce("p + (p: vec3)")   // bare then typed
    }

    @Test func inlineTypedTwiceIsError() {
        expectUsedMoreThanOnce("(p: vec3) + (p: vec3)")
    }

    @Test func inlineTypeCollidingWithInDeclarationIsError() {
        expectUsedMoreThanOnce("in p: vec3; out o = (p: vec3)")
    }

    @Test func typingALoopVariableIsError() {
        let r = compile("[ (i: vec3) for i in 0..<n ]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding })
    }

    @Test func typingAConstantIsError() {
        let r = compile("pi: vec3")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding })
    }

    // A plain float used twice is still fine — the rule only restricts inline typing.
    @Test func bareFloatUsedTwiceIsStillAllowed() {
        let r = compile("x + x")
        #expect(r.isValid, "diagnostics: \(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "x", type: .float)])
    }
}
