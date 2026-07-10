# MathExpressionEngine — Design Summary

A single, concise record of what this engine is for, where it stands, and what's
left. (The earlier exploratory design docs are consolidated here; their detail
remains in git history.)

---

## Goal

A typed expression engine for Fabric's Math / Function node, where **the
expression is the single source of truth**: free identifiers become typed input
ports, `out name = …` declarations become typed output ports, and every type is
inferred. One node then expresses anything from `sin(x) + y^2` to a procedural
array of transforms.

Design commitments:
- **Native Swift + SIMD**, no C++/ExprTk — portable, and Fabric's port values
  (`Float`, `simd_float3`, `simd_float4x4`, …) map with little or no conversion.
- **Standalone & dependency-free** — no Fabric/Metal/Satin — so the correctness
  suite runs on a plain toolchain (Linux CI), independent of the app.
- **Compile off the render thread; evaluate per-frame on it.**
- North-star: `[translate(vec3(i,0,0)) for i in 0..<n]` → a `transform[]` output
  that drives an instanced mesh, with no glue nodes.

---

## Present reality (implemented, CI-green)

**Language**
- Scalars, `vec2/3/4` (constructors, `.xyz`/`.rgba` swizzles, elementwise +
  scalar↔vector broadcast, type-directed operators).
- `transform` (4×4) & `quat`: `translate`/`scale`/`rotateX,Y,Z`/`compose`,
  `transformPoint`/`transformDir`/`transpose`, `quatAxisAngle`/`conjugate`/
  `normalize`, and type-directed `*` (matmul, matrix·vec4, quat compose, quat·vec3).
- Arrays: literals, comprehensions `[body for i in lo..<hi]` (and `..`), indexing,
  reductions `sum`/`product`/`mean`/`count`.
- `let` locals and multiple named `out` outputs; a bare expression is the implicit
  `result`.
- Builtins: trig/exp/log/rounding/`clamp`/`mix`/`smoothstep`/… (componentwise over
  vectors), vector algebra (`length`/`dot`/`cross`/`normalize`/…), constants
  `pi`/`tau`/`e`.
- Diagnostics with source spans: type errors, arity, bad swizzle, unknown name
  (+ "did you mean …?"), array/output rules; advisory warnings (literal `/0`,
  unused `let`).
- Guardrails: comprehension size cap, index-out-of-bounds, and a parser nesting
  limit — all surface as errors/thrown `EvalError`s, never a hang or crash.

**Architecture**
- Pipeline: `lex → parse → infer (type synthesis) → lower`.
- Two back ends over one `EngineValue`: a flat **register-machine tape**
  (production) and a **tree-walk reference interpreter** (kept as the differential
  oracle). Comprehensions run as nested sub-tapes.
- Register file is a heap `[EngineValue]` (one value type; the allocation-free
  stack-scratch register file is recoverable later as a fast path — see Future).

**Verification** — 9 test suites: unit + inference-as-data + catalogue evaluation
+ **differential fuzzing** (tape == reference) + **metamorphic** property tests
(matrix/quat identities) + guardrails. Runs on Swift 6.1 in CI.

**Public API**
```swift
func compile(_ source: String) -> CompileResult
CompileResult.interface   // Interface(inputs: [String], outputs: [OutputPort])
CompileResult.diagnostics // [Diagnostic] (code, severity, message, span)
CompileResult.evaluateValues(_:) throws(EvalError) -> [EngineValue]
// + evaluate / evaluateAll / evaluateValue convenience
// EngineValue: float | vec2/3/4 | transform(Mat4) | quat(Quat) | array
```

---

## Future steps (deferred, roughly in order)

1. **Vector/matrix inputs.** Inputs are currently `Float`-only; vector/transform
   input *ports* need input-type annotation syntax (e.g. `in p: vec3`). This
   unlocks "processor" use (array/vector inputs), not just generators.
2. **More transform math:** general 4×4 `inverse`, `slerp`, `lookAt`, `quatEuler`.
3. **Allocation-free fast path:** reintroduce a trivial-register stack scratch +
   an array side-table for scalar/vector programs, behind the unchanged tests.
4. **Monomorphized tape** (per-inferred-type instructions) and, optionally,
   vertical-SIMD element batching for comprehensions.
5. **Fabric node integration:** the `EngineValue ↔ NodePort` adapter, dynamic
   typed ports diffed from `Interface`, Codable, the `CodeEditorView` editor with
   `Diagnostic → line:col` markers, and migration from the old MathExpression
   node. (App-side; needs macOS/Xcode/Metal, so it's out of this package's CI.)
6. **Nice-to-haves:** report-all parser error recovery; quick-fix metadata on
   diagnostics; a decision on stateful/feedback (`state`) bindings vs. the
   dedicated Integrator node.
