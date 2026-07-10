# MathExpressionEngine

A standalone, dependency-free typed-expression engine for Fabric's Math / Function
node. No dependency on Fabric, Metal, or Satin, so the correctness suite runs on a
plain toolchain (macOS or Linux):

```sh
cd MathExpressionEngine
swift test
```

The expression is the single source of truth: free identifiers become typed input
ports, `out name = …` declarations become typed outputs, and all types are
inferred. Example — a procedural array of transforms for an instanced mesh:

```
[ translate(vec3(i, 0, 0)) * rotateY(i * spacing) for i in 0..<n ]
```

See **[DESIGN.md](DESIGN.md)** for goal, present reality, and future steps.

## Layout

```
Sources/MathExpressionEngine/
  PublicAPI.swift            // Span, Diagnostic, Interface, EngineValue, ValueType, EvalError, CompileResult
  Lexer.swift  AST.swift  Parser.swift  Sema.swift  Builtins.swift  Value.swift  Transform.swift  Suggestions.swift
  ReferenceInterpreter.swift // tree-walk oracle
  Tape.swift                 // register-machine bytecode (production)
  Engine.swift               // compile(_:)
Tests/MathExpressionEngineTests/
  Evaluation · Interface · Diagnostics · Property · Differential · Stress · Block · Vector · Array · Transform · Hardening
```
