# MathExpressionEngine

A standalone typed-expression engine for Fabric's Math / Function node. It has no
package dependencies and doesn't touch Fabric, Metal, or Satin, so the correctness
suite runs without a GPU or the app — just a Swift toolchain. Its transform /
quaternion types are Apple `simd` (a zero-copy port boundary), so it targets Apple
platforms (macOS/iOS/visionOS):

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

- **[GUIDE.md](GUIDE.md)** — the expression language for end-users (tutorial + function reference).
- **[DESIGN.md](DESIGN.md)** — goal, present reality, and future steps (for contributors).

## Layout

```
Sources/MathExpressionEngine/
  PublicAPI.swift            // Span, Diagnostic, Interface, EngineValue, ValueType, EvalError, CompileResult
  Lexer.swift  AST.swift  Parser.swift  Sema.swift  Builtins.swift  Value.swift  Transform.swift  Suggestions.swift
  ReferenceInterpreter.swift // tree-walk oracle
  Tape.swift                 // register-machine bytecode (production)
  Engine.swift               // compile(_:)
Tests/MathExpressionEngineTests/
  Evaluation · Interface · Diagnostics · Property · Differential · Stress · Block · Vector · Array · Transform · Input · Hardening
```
