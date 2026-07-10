//
//  Engine.swift
//  FunctionEngine
//
//  RED (TDD): stub compile — returns no program, so evaluation and interface
//  tests fail. The GREEN commit replaces this with the real
//  lex → parse → infer → evaluate pipeline.
//

/// Compile a Function Node source expression into a `CompileResult`.
public func compile(_ source: String) -> CompileResult {
    // Stub: not yet implemented.
    CompileResult(
        interface: Interface(inputs: [], outputType: .float),
        diagnostics: [],
        program: nil
    )
}
