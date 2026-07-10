import Testing
@testable import MathExpressionEngine

/// The core "expression is the interface" claim, asserted as data: free
/// identifiers become input ports, in first-appearance order, deduplicated,
/// with constants excluded.
@Suite struct InterfaceTests {

    @Test func freeVariablesBecomeInputs() {
        #expect(compile("sin(x) + y ^ 2").interface.inputNames == ["x", "y"])
    }

    @Test func inputsAreFirstAppearanceOrdered() {
        #expect(compile("b + a").interface.inputNames == ["b", "a"])
        #expect(compile("a + b").interface.inputNames == ["a", "b"])
    }

    @Test func inputsAreDeduplicated() {
        #expect(compile("a + a + b").interface.inputNames == ["a", "b"])
        #expect(compile("x * x").interface.inputNames == ["x"])
    }

    @Test func constantsAreNotInputs() {
        #expect(compile("pi * r").interface.inputNames == ["r"])
        #expect(compile("tau").interface.inputNames == [])
    }

    @Test func literalOnlyExpressionHasNoInputs() {
        #expect(compile("2 + 3").interface.inputNames == [])
    }

    @Test func functionNamesAreNotInputs() {
        // `sin` is a function, not a free variable — only `x` is an input.
        #expect(compile("sin(x)").interface.inputNames == ["x"])
    }

    @Test func scalarOutputType() {
        #expect(compile("x + 1").interface.outputType == .float)
    }
}
