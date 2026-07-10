import Testing
@testable import MathExpressionEngine

// Typed inputs (`in name: Type`) and array iteration (`for p in arr`).

@Suite struct InputTests {

    // MARK: Declared input types on the interface

    @Test func declaredInputCarriesItsType() throws {
        let r = compile("in p: vec3; out y = p.x + p.y + p.z")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "p", type: .vec3)])
        #expect(r.interface.outputType == .float)
    }

    @Test func undeclaredInputsStayFloat() throws {
        // Declared inputs come first (declaration order), then undeclared floats.
        let r = compile("in p: vec3; out y = p.x * k")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.inputs == [
            InputPort(name: "p", type: .vec3),
            InputPort(name: "k", type: .float),
        ])
    }

    @Test func degenerateDefaultIsUnchanged() throws {
        // The current Fabric "Math Expression" node default: two float ports,
        // one float output — no declarations, nothing new triggered.
        let r = compile("sin(x) + y^2")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.inputs == [
            InputPort(name: "x", type: .float),
            InputPort(name: "y", type: .float),
        ])
        #expect(r.interface.outputType == .float)
    }

    @Test func declaredArrayInputType() throws {
        let r = compile("in pts: vec3[]; out n = count(pts)")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.inputs == [InputPort(name: "pts", type: .array(.vec3))])
        #expect(r.interface.outputType == .float)
    }

    // MARK: Evaluating with typed inputs

    @Test func vectorInputEvaluates() throws {
        let r = compile("in p: vec3; out y = p.x + p.y + p.z")
        let y = try r.evaluateValue(with: ["p": .vec3(SIMD3<Float>(1, 2, 3))])
        #expect(y == .float(6))
    }

    @Test func arrayInputReduction() throws {
        let r = compile("in xs: float[]; out s = sum(xs)")
        let s = try r.evaluateValue(with: ["xs": .array([.float(1), .float(2), .float(3), .float(4)])])
        #expect(s == .float(10))
    }

    @Test func arrayInputIndexingWithCount() throws {
        let r = compile("in xs: float[]; out last = xs[count(xs) - 1]")
        let last = try r.evaluateValue(with: ["xs": .array([.float(5), .float(6), .float(7)])])
        #expect(last == .float(7))
    }

    // MARK: Iterating an array input

    @Test func mapComprehensionOverInput() throws {
        let r = compile("in pts: vec3[]; out lifted = [ p + vec3(0, 1, 0) for p in pts ]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputType == .array(.vec3))
        let out = try r.evaluateValue(with: [
            "pts": .array([.vec3(SIMD3<Float>(0, 0, 0)), .vec3(SIMD3<Float>(1, 0, 0))])
        ])
        #expect(out == .array([.vec3(SIMD3<Float>(0, 1, 0)), .vec3(SIMD3<Float>(1, 1, 0))]))
    }

    @Test func mapComprehensionLoopVarTakesElementType() throws {
        // `x` here is a float (element of a float[]), so sin(x) type-checks.
        let r = compile("in xs: float[]; out s = [ sin(x) for x in xs ]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputType == .array(.float))
    }

    @Test func mapComprehensionOverLiteralArray() throws {
        // No input needed — iterate a literal.
        let r = compile("[ n * n for n in [1, 2, 3, 4] ]")
        #expect(r.isValid, "\(r.diagnostics)")
        let out = try r.evaluateValue([:])
        #expect(out == .array([.float(1), .float(4), .float(9), .float(16)]))
    }

    @Test func rangeComprehensionStillWorks() throws {
        // Regression: the numeric-range form is untouched.
        let r = compile("[ i * 2 for i in 0..<4 ]")
        #expect(r.isValid, "\(r.diagnostics)")
        let out = try r.evaluateValue([:])
        #expect(out == .array([.float(0), .float(2), .float(4), .float(6)]))
    }

    // MARK: Enumerate — `for (i, p) in arr`

    @Test func enumerateBindsIndexAndElement() throws {
        // Weight each element by its position, reading a second array in step.
        let r = compile("in xs: float[]; in ws: float[]; out o = [ x * ws[i] for (i, x) in xs ]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputType == .array(.float))
        let out = try r.evaluateValue(with: [
            "xs": .array([.float(1), .float(2), .float(3)]),
            "ws": .array([.float(10), .float(100), .float(1000)]),
        ])
        #expect(out == .array([.float(10), .float(200), .float(3000)]))
    }

    @Test func enumerateIndexIsAFloat() throws {
        // The index behaves like any number — usable in arithmetic.
        let r = compile("[ p + i for (i, p) in [10, 10, 10] ]")
        #expect(r.isValid, "\(r.diagnostics)")
        let out = try r.evaluateValue([:])
        #expect(out == .array([.float(10), .float(11), .float(12)]))
    }

    @Test func enumerateElementTakesElementType() throws {
        // `p` is a vec3 (element type), `i` a float — `p * i` broadcasts.
        let r = compile("in pts: vec3[]; out o = [ p * i for (i, p) in pts ]")
        #expect(r.isValid, "\(r.diagnostics)")
        #expect(r.interface.outputType == .array(.vec3))
    }

    @Test func enumeratePatternWithRangeIsError() throws {
        let r = compile("[ i for (i, p) in 0..<4 ]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .expectedRange })
    }

    @Test func enumerateDuplicateNamesIsError() throws {
        let r = compile("in xs: float[]; out o = [ a for (a, a) in xs ]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding })
    }

    @Test func enumerateTapeMatchesReference() throws {
        let src = "in xs: vec2[]; out o = [ x * i + x for (i, x) in xs ]"
        let tape = compile(src)
        let reference = compileReferenceInterpreter(src)
        #expect(tape.isValid && reference.isValid, "\(tape.diagnostics)")
        let inputs: [String: EngineValue] = [
            "xs": .array([.vec2(SIMD2<Float>(1, 2)), .vec2(SIMD2<Float>(3, 4)), .vec2(SIMD2<Float>(5, 6))])
        ]
        #expect(try tape.evaluateValue(with: inputs) == (try reference.evaluateValue(with: inputs)))
    }

    // MARK: Errors

    @Test func iteratingANonArrayIsAnError() throws {
        let r = compile("in y: float; out z = [ p for p in y ]")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .notAnArray })
    }

    @Test func unknownTypeReported() throws {
        let r = compile("in p: flt; out y = p")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .unknownType })
    }

    @Test func missingColonReported() throws {
        let r = compile("in p vec3; out y = p.x")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .expectedColon })
    }

    @Test func duplicateInputReported() throws {
        let r = compile("in p: vec3; in p: vec2; out y = p.x")
        #expect(!r.isValid)
        #expect(r.diagnostics.contains { $0.code == .duplicateBinding })
    }

    // MARK: Tape vs. reference agreement on the new forms

    @Test func tapeMatchesReferenceForArrayInput() throws {
        let src = "in pts: vec3[]; out o = [ p * scale + vec3(0, lift, 0) for p in pts ]"
        let tape = compile(src)
        let reference = compileReferenceInterpreter(src)
        #expect(tape.isValid && reference.isValid, "\(tape.diagnostics)")

        let inputs: [String: EngineValue] = [
            "pts": .array([.vec3(SIMD3<Float>(1, 2, 3)), .vec3(SIMD3<Float>(-4, 5, 6))]),
            "scale": .float(2),
            "lift": .float(10),
        ]
        #expect(try tape.evaluateValue(with: inputs) == (try reference.evaluateValue(with: inputs)))
    }
}
