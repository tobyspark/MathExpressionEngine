//
//  Engine.swift
//  FunctionEngine
//
//  GREEN (TDD): the real scalar Tier-0 pipeline —
//  lex → parse → infer interface → build an evaluable program.
//  The program currently wraps the tree-walking reference interpreter; a later
//  slice lowers to a flat POD tape behind this same surface.
//

/// Compile a Function Node source expression.
///
/// Free identifiers become the interface's input ports; the value of the
/// expression is its single output. Errors are reported as diagnostics and, when
/// any is error-severity, no program is produced (`isValid == false`).
public func compile(_ source: String) -> CompileResult {
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

    let hasError = diagnostics.contains { $0.severity == .error }

    let program: Program?
    if let ast, !hasError {
        program = Program(run: { @Sendable (inputs: [String: Float]) throws(EvalError) -> Float in
            try ReferenceInterpreter.eval(ast, inputs)
        })
    } else {
        program = nil
    }

    return CompileResult(interface: interface, diagnostics: diagnostics, program: program)
}
