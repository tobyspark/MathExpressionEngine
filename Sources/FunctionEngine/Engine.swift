//
//  Engine.swift
//  FunctionEngine
//
//  The scalar Tier-0 pipeline. `compile(_:)` lowers to the flat POD tape (the
//  fast path); `compileReferenceInterpreter(_:)` wraps the tree-walking
//  interpreter and is used as the differential oracle in tests
//  (assert tape == reference). Both share the same front end, so they always
//  agree on the interface and diagnostics.
//

/// Front end shared by both back ends: lex → parse → infer interface.
private func frontEnd(_ source: String) -> (ast: Expr?, interface: Interface, diagnostics: [Diagnostic]) {
    var lexer = Lexer(source)
    let (tokens, lexDiagnostics) = lexer.tokenize()

    var parser = Parser(tokens)
    let ast = parser.parse()

    var diagnostics = lexDiagnostics + parser.diagnostics
    var interface = Interface(inputs: [], outputType: .float)

    if let ast {
        let (derived, semaDiagnostics) = analyze(ast)
        interface = derived
        diagnostics += semaDiagnostics
    }

    return (ast, interface, diagnostics)
}

/// Compile a Function Node source expression to a tape-backed program.
///
/// Free identifiers become the interface's input ports; the value of the
/// expression is its single output. When any diagnostic is error-severity no
/// program is produced (`isValid == false`).
public func compile(_ source: String) -> CompileResult {
    let (ast, interface, diagnostics) = frontEnd(source)

    var program: Program? = nil
    if let ast, !diagnostics.contains(where: { $0.severity == .error }) {
        let tape = lower(ast)
        program = Program(run: { @Sendable (inputs: [String: Float]) throws(EvalError) -> Float in
            try runTape(tape, inputs)
        })
    }

    return CompileResult(interface: interface, diagnostics: diagnostics, program: program)
}

/// Compile to a program backed by the tree-walking reference interpreter.
/// Internal: the differential oracle for the tape (see DifferentialTests).
func compileReferenceInterpreter(_ source: String) -> CompileResult {
    let (ast, interface, diagnostics) = frontEnd(source)

    var program: Program? = nil
    if let ast, !diagnostics.contains(where: { $0.severity == .error }) {
        program = Program(run: { @Sendable (inputs: [String: Float]) throws(EvalError) -> Float in
            try ReferenceInterpreter.eval(ast, inputs)
        })
    }

    return CompileResult(interface: interface, diagnostics: diagnostics, program: program)
}
