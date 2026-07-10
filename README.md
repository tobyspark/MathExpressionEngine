# FunctionEngine

Standalone, dependency-free engine for the Fabric **Function Node** (see the
`DESIGN-FunctionNode-*.md` docs at the repo root). No dependency on Fabric,
Metal, or Satin, so the correctness suite runs on a plain toolchain:

```sh
cd FunctionEngine
swift test
```

## Status

**Slice 1 — scalar Tier-0** (`Float` only), built test-first (red→green):

- `compile(source) -> CompileResult` — lex → parse → infer interface.
- Free identifiers become the interface's input ports (first-appearance order,
  deduplicated, constants excluded); the expression's value is the single output.
- `CompileResult.evaluate([name: Float]) throws(EvalError) -> Float` — evaluates
  via the tree-walking reference interpreter (also the differential oracle for
  the fast POD-tape engine added in a later slice).
- Builtins: trig, `sqrt/abs/exp/log/log2`, `floor/ceil/round/sign/fract`,
  `pow/min/max/mod/step`, `clamp/mix/smoothstep`, `radians/degrees/saturate`;
  constants `pi/tau/e`. `^` is exponent (right-associative); unary minus binds
  looser than `^` (`-2^2 == -4`).
- Diagnostics with source spans: unknown name, wrong arity, unmatched paren,
  empty/incomplete/trailing input.

Next slices (see `DESIGN-FunctionNode-Testing.md` §6): the flat POD tape +
differential test, then vectors/swizzles, `let`/`out` multiple outputs, arrays/
comprehensions, transforms/quaternions, guardrails, and node integration.

## Layout

```
Sources/FunctionEngine/
  PublicAPI.swift          // Span, Diagnostic, Interface, EvalError, CompileResult, Program
  Lexer.swift  AST.swift  Parser.swift  Sema.swift  Builtins.swift
  ReferenceInterpreter.swift
  Engine.swift             // compile(_:)
Tests/FunctionEngineTests/
  EvaluationTests  InterfaceTests  DiagnosticsTests  PropertyTests
```
