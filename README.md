# FunctionEngine

Standalone, dependency-free engine for the Fabric **Function Node** (see the
`DESIGN-FunctionNode-*.md` docs at the repo root). No dependency on Fabric,
Metal, or Satin, so the correctness suite runs on a plain toolchain:

```sh
cd FunctionEngine
swift test
```

## Status

**Slices 1–5** — scalar Tier-0, POD tape (+ differential oracle), allocation-free
eval, `let`/`out` multiple outputs, and **vectors** (`vec2/3/4`: constructors,
swizzles, elementwise/broadcast ops, `length`/`dot`/`cross`/`normalize`,
componentwise `genN` math; output types inferred). Values are a trivial
`EngineValue` (SIMD payloads); vector *inputs* (needing type annotations) are
deferred. Built test-first:

- `compile(source) -> CompileResult` — lex → parse → infer interface → **lower to
  a flat POD bytecode tape** (register machine; `Instr`/`Tape` in `Tape.swift`).
- Free identifiers become the interface's input ports (first-appearance order,
  deduplicated, constants and locals excluded). Bodies may use `let` locals and
  `;`-separated statements; a bare expression is the implicit `result` output,
  or declare multiple named outputs with `out name = …` (`evaluate` returns the
  first, `evaluateAll` returns all in order).
- `CompileResult.evaluate([name: Float]) throws(EvalError) -> Float` — runs the
  tape over a **stack-allocated scratch** (`withUnsafeTemporaryAllocation`), so a
  typical scalar eval makes no heap allocation. The tree-walking
  `ReferenceInterpreter` remains as the **differential oracle**: `DifferentialTests`
  fuzz random expressions and assert `tape == reference` (bit-identical, NaN-aware);
  `StressTests` hammer the unsafe scratch path (~180k evals) against the oracle.

> A *strict* per-eval allocation-count gate needs Instruments / a malloc-count
> harness (macOS; see `DESIGN-FunctionNode-Engine.md` §11). The Linux CI proves
> correctness under load; the zero-alloc property is structural (stack scratch,
> no `[Float]` in the eval loop).
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
