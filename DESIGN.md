# MathExpressionEngine — Design

Goal, present reality, and future steps for the engine.

---

## Goal

A typed expression engine where **the expression is the single source of truth**:
free identifiers become typed input ports, `out name = …` declarations become
typed output ports, and every type is inferred. One expression then covers
anything from `sin(x) + y^2` to a procedural array of transforms.

Design commitments:
- **Native Swift + SIMD**, no C or C++. Portable, and its value types map to
  Fabric's port values (`Float`, `simd_float3`, `simd_float4x4`, …) with little or
  no conversion.
- **Standalone and dependency-free** — no Fabric, Metal, or Satin — so the
  correctness suite runs on a plain toolchain, independent of any app.
- **Compile once, evaluate many:** compilation is a pure function safe to run off
  a render thread; evaluation is cheap enough to run per frame.
- A representative target: `[ translate(vec3(i, 0, 0)) for i in 0..<n ]` produces a
  `transform[]` output that can drive an instanced mesh, with the whole expression
  as its single source of truth.

---

## Present reality

### Language

- **Scalars** and **`vec2/3/4`**: constructors, `.xyz`/`.rgba` swizzles, elementwise
  arithmetic with scalar↔vector broadcast, and type-directed operators.
- **`transform`** (4×4) and **`quat`**: `translate` / `scale` / `rotateX,Y,Z` /
  `compose`, `transformPoint` / `transformDir` / `transpose`, `quatAxisAngle` /
  `conjugate` / `normalize`, and type-directed `*` (matrix·matrix, matrix·vec4,
  quaternion compose, quaternion·vec3). `transform * vec3` is deliberately
  undefined — use `transformPoint` / `transformDir`.
- **Arrays**: literals `[a, b, c]`; comprehensions over a numeric range
  `[body for i in lo..<hi]` (and the inclusive `..`) or over an array
  `[body for p in arr]` (the loop variable takes the element type); indexing
  `a[i]`; and reductions `sum` / `product` / `mean` / `count`.
- **Inputs**: free identifiers are `float` input ports; `in name: Type` declares a
  typed input (`vec3`, `transform`, `quat`, `vec3[]`, …). Inference never widens
  an input beyond `float`, so declaration is the single escape hatch — and the
  all-scalar default keeps working with no `in` at all.
- **Statements**: `in` typed-input declarations, `let` locals, and multiple named
  `out` outputs; a bare expression is the implicit `result` output.
- **Builtins**: trig, exp/log, rounding, `clamp` / `mix` / `smoothstep`, etc.
  (componentwise over vectors); vector algebra `length` / `dot` / `cross` /
  `normalize` / `distance`; constants `pi` / `tau` / `e`. `^` is exponentiation
  (right-associative); unary minus binds looser than `^`, so `-2^2 == -4`.
- **Diagnostics** carry source spans: type errors, wrong arity, invalid swizzles,
  unknown names (with a "did you mean …?" suggestion), and array/output rules.
  Advisory warnings cover literal division by zero and unused `let` bindings, and
  never block evaluation.
- **Guardrails**: a comprehension element-count cap, index-out-of-bounds checks,
  and a parser nesting limit. All surface as diagnostics or thrown `EvalError`s —
  never a hang or crash.

### Architecture

- Pipeline: **lex → parse → infer (type synthesis) → lower**.
- Two evaluators over one `EngineValue` type:
  - a flat **register-machine bytecode tape** (the production evaluator), and
  - a **tree-walking interpreter** used as a differential oracle in tests.
  Comprehensions execute as nested sub-tapes.
- The register file is a heap `[EngineValue]` (one allocation per evaluation). A
  reduced-allocation path for scalar/vector programs is possible later without
  changing behaviour (see Future).

### Verification

Twelve test suites: unit tests, interface-as-data checks, per-builtin evaluation
tables, **differential fuzzing** (bytecode tape versus the reference interpreter
on randomized well-typed expressions), **metamorphic property tests** (matrix and
quaternion identities), stress tests, and guardrail tests. Run with `swift test`
on any Swift 6.1+ toolchain (macOS or Linux).

### Public API

```swift
func compile(_ source: String) -> CompileResult

// CompileResult
//   .interface    Interface(inputs: [InputPort], outputs: [OutputPort])
//   .diagnostics  [Diagnostic] (code, severity, message, span)
//   .isValid
//   .evaluateValues(with: [String: EngineValue]) throws(EvalError) -> [EngineValue]
//   + [String: Float] conveniences: evaluate / evaluateAll / evaluateValue(s)

// InputPort / OutputPort: (name, type)
// EngineValue: float | vec2/3/4 | transform(Mat4) | quat(Quat) | array
// ValueType:   float | vec2/3/4 | transform | quat | array(element)
```

Both input and output ports carry inferred/declared types. Supply inputs as typed
`EngineValue`s via `evaluateValues(with:)`; the `[String: Float]` overloads are a
convenience for the all-scalar case.

---

## Future steps

Roughly in priority order:

1. **Vector/array-aware multi-arg builtins.** `min` / `max` / `clamp` / `mix` /
   `smoothstep` / `step` are scalar-only today; typed inputs make componentwise
   versions (and vector reductions like `max` over an array) the obvious next want.
2. **Direct element+index iteration.** The array comprehension gives either the
   element (`for p in arr`) or the index (`for i in 0..<count(arr)`); an
   enumerate-style form yielding both would remove the index/`count` boilerplate.
3. **More transform math:** general 4×4 `inverse`, spherical-linear interpolation
   (`slerp`), `lookAt`, and Euler-angle quaternion construction.
4. **Reduced-allocation evaluation:** a stack-allocated register scratch plus an
   out-of-line array store for scalar/vector programs, leaving array-producing
   programs (which must allocate their output anyway) unchanged.
5. **Type-specialized bytecode** (one instruction variant per resolved type) and,
   optionally, batched SIMD evaluation of comprehension bodies.
6. **Fabric node integration:** an adapter between `EngineValue` and the node
   port types, dynamic typed ports derived from the compiled interface, document
   serialization, a source editor that renders diagnostics at their `line:column`,
   and migration of existing math-expression nodes. This layer is part of the app,
   not this package.
7. **Additional polish:** parser error recovery that reports every error in one
   pass, machine-applyable fix hints on diagnostics, and support for stateful
   (feedback) bindings that persist across evaluations.
