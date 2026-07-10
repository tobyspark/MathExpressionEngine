import Testing
@testable import FunctionEngine

private func eval(_ src: String, _ inputs: [String: Float] = [:]) throws -> Float {
    let r = compile(src)
    #expect(r.isValid, "expected `\(src)` to compile; diagnostics: \(r.diagnostics)")
    return try r.evaluate(inputs)
}

private func approx(_ a: Float, _ b: Float, _ eps: Float = 1e-4) -> Bool {
    abs(a - b) <= eps
}

@Suite struct EvaluationTests {

    @Test func arithmeticAndPrecedence() throws {
        #expect(try eval("2 + 3") == 5)
        #expect(try eval("2 + 3 * 4") == 14)          // * binds tighter than +
        #expect(try eval("(2 + 3) * 4") == 20)
        #expect(try eval("10 - 4 - 2") == 4)          // - left-associative
        #expect(try eval("10 / 4") == 2.5)
        #expect(approx(try eval("7 % 3"), 1))
    }

    @Test func powerIsRightAssociative() throws {
        #expect(try eval("2 ^ 3 ^ 2") == 512)         // 2^(3^2) = 2^9
        #expect(try eval("2 ^ 2 ^ 3") == 256)         // 2^(2^3) = 2^8
    }

    @Test func unaryMinusBindsLooserThanPower() throws {
        #expect(try eval("-2 ^ 2") == -4)             // -(2^2), math convention
        #expect(try eval("(-2) ^ 2") == 4)
        #expect(try eval("-3 + 5") == 2)
        #expect(approx(try eval("2 ^ -2"), 0.25))     // negative exponent
    }

    @Test func builtinFunctions() throws {
        #expect(approx(try eval("sin(0)"), 0))
        #expect(approx(try eval("cos(0)"), 1))
        #expect(approx(try eval("sqrt(9)"), 3))
        #expect(approx(try eval("abs(-4)"), 4))
        #expect(approx(try eval("pow(2, 10)"), 1024))
        #expect(approx(try eval("min(3, 5)"), 3))
        #expect(approx(try eval("max(3, 5)"), 5))
        #expect(approx(try eval("floor(3.7)"), 3))
        #expect(approx(try eval("ceil(3.2)"), 4))
        #expect(approx(try eval("round(3.5)"), 4))
        #expect(approx(try eval("clamp(5, 0, 1)"), 1))
        #expect(approx(try eval("clamp(-5, 0, 1)"), 0))
        #expect(approx(try eval("mix(0, 10, 0.5)"), 5))
    }

    @Test func constants() throws {
        #expect(approx(try eval("pi"), .pi))
        #expect(approx(try eval("tau"), 2 * .pi))
        #expect(approx(try eval("2 * pi"), 2 * .pi))
    }

    @Test func variables() throws {
        #expect(try eval("x + y", ["x": 2, "y": 3]) == 5)
        #expect(approx(try eval("sin(x) + y ^ 2", ["x": 0, "y": 3]), 9))
        #expect(approx(try eval("a * b + c", ["a": 2, "b": 3, "c": 1]), 7))
    }

    @Test func nestedCalls() throws {
        #expect(approx(try eval("sqrt(pow(3, 2) + pow(4, 2))"), 5))   // hypotenuse
        #expect(approx(try eval("max(min(x, 10), 0)", ["x": 15]), 10))
    }
}
