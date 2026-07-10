import Testing
@testable import MathExpressionEngine

/// The core "expression is the interface" claim, asserted as data: free
/// identifiers become input ports, in first-appearance order, deduplicated,
/// with constants excluded.
@Suite struct InterfaceTests {

    @Test func freeVariablesBecomeInputs() {
        #expect(compile("sin(x) + y ^ 2").interface.inputs == ["x", "y"])
    }

    @Test func inputsAreFirstAppearanceOrdered() {
        #expect(compile("b + a").interface.inputs == ["b", "a"])
        #expect(compile("a + b").interface.inputs == ["a", "b"])
    }

    @Test func inputsAreDeduplicated() {
        #expect(compile("a + a + b").interface.inputs == ["a", "b"])
        #expect(compile("x * x").interface.inputs == ["x"])
    }

    @Test func constantsAreNotInputs() {
        #expect(compile("pi * r").interface.inputs == ["r"])
        #expect(compile("tau").interface.inputs == [])
    }

    @Test func literalOnlyExpressionHasNoInputs() {
        #expect(compile("2 + 3").interface.inputs == [])
    }

    @Test func functionNamesAreNotInputs() {
        // `sin` is a function, not a free variable — only `x` is an input.
        #expect(compile("sin(x)").interface.inputs == ["x"])
    }

    @Test func scalarOutputType() {
        #expect(compile("x + 1").interface.outputType == .float)
    }
}
