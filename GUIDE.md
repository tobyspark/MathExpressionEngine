# Expression Language Guide

A friendly, example-first tour of the expression language you write in the Math
Expression node. No programming background assumed.

The idea in one sentence: **you write an expression, and the node figures out the
rest** — the values you refer to become input ports, the results you name become
output ports, and every type (number, vector, transform, …) is worked out for you.

- [Your first expressions](#your-first-expressions)
- [Values and types](#values-and-types)
- [Inputs, outputs, and locals](#inputs-outputs-and-locals)
- [Operators](#operators)
- [Vectors](#vectors)
- [Transforms and rotations](#transforms-and-rotations)
- [Arrays and comprehensions](#arrays-and-comprehensions)
- [Function reference](#function-reference)
- [Constants](#constants)
- [When something is wrong](#when-something-is-wrong)
- [Current limits and gotchas](#current-limits-and-gotchas)

---

## Your first expressions

Start simple and build up. Each of these is a complete, valid expression.

```
1 + 2 * 3
```
A plain number. (Multiplication happens before addition, so this is `7`.)

```
sin(x) + y
```
The moment you mention `x` and `y`, the node grows two number input ports named
`x` and `y`. Wire anything into them and the result updates.

```
vec3(x, y, 0)
```
Builds a 3-component vector. The output port is now a `vec3` — the node worked
that out from `vec3(...)`, you didn't have to declare it.

```
out position = vec3(x, y, 0)
```
Same thing, but the output port is now named `position` instead of the default
`result`.

```
[ translate(vec3(i, 0, 0)) for i in 0..<count ]
```
A whole row of transforms — one per `i` from `0` up to (but not including)
`count`. This output can drive an instanced mesh. `count` becomes an input port.

That last line is the whole point of the language: one expression, and the node's
ports fall out of it automatically.

---

## Values and types

Every value has a type. You never write types down — they are inferred — but it
helps to know what exists:

| Type | What it is | Example that produces it |
|------|------------|--------------------------|
| `float` | a single number | `3.14`, `x`, `sin(x)` |
| `vec2` | 2 numbers (x, y) | `vec2(u, v)` |
| `vec3` | 3 numbers (x, y, z) | `vec3(x, y, z)` |
| `vec4` | 4 numbers (x, y, z, w) | `vec4(r, g, b, 1)` |
| `transform` | a 4×4 transform (position/rotation/scale) | `translate(vec3(x,0,0))` |
| `quat` | a rotation (quaternion) | `quatAxisAngle(angle, vec3(0,1,0))` |
| *`type`*`[]` | an array (list) of any type above | `[a, b, c]`, a comprehension |

Numbers can be written as `10`, `2.5`, `.5`, or in scientific form `1e3`, `2.5e-2`.

---

## Inputs, outputs, and locals

**Inputs** appear automatically. Any name you use that isn't a built-in function
or constant becomes a **number** input port, in the order it first appears:

```
a * b + c        // three number input ports: a, b, c
```

When you need an input that's richer than a number — a vector, a transform, or a
whole array of them — declare its type with `in`:

```
in center: vec3;
in p: vec3;
out offset = p - center       // two vec3 input ports
```

The rule is simple:

- A name you **don't** declare is a **number** (`float`), exactly as before.
- A name you **do** declare with `in` has the type you gave it.

So `in` is only for ports that aren't plain numbers — the everyday all-numbers
case needs no ceremony. The types you can declare are the same ones the language
uses everywhere: `float`, `vec2`, `vec3`, `vec4`, `transform`, `quat`, and arrays
like `vec3[]` or `float[]`.

**Typing a name inline.** For a one-off you can give a name its type right where
you use it — the same `name: Type` syntax, no separate `in` line:

```
(p: vec3) * 2                 // one vec3 input port, p
count(points: vec3[])         // one vec3[] input port, points
```

This is shorthand for a single use. If you refer to the same name more than once,
give it a proper `in` declaration instead — an inline-typed name used twice is an
error:

```
(p: vec3) + p                 // ✗ p is used twice — declare `in p: vec3;`
in p: vec3; out o = p + p     // ✓
```

**Taking an array in.** Declare an array input and you can measure, index, and
loop over it:

```
in points: vec3[];
out howMany = count(points);         // number of elements
out first   = points[0];             // one element by index
out middle  = mean(points)           // reductions work on it directly
```

To turn every element into a new array, loop over it with `for … in` — read it as
"*this value, for each `p` in `points`*". The loop variable takes the array's
element type (here each `p` is a `vec3`):

```
in points: vec3[];
in lift: float;
out raised = [ p + vec3(0, lift, 0) for p in points ]    // lift every point on Y
```

```
in placements: transform[];
in spin: float;
out spun = [ rotateY(spin) * m for m in placements ]     // spin each instance
```

Looping directly gives you the **element**. When you also need its **position** —
to offset by index, or read a second array in step — name both with an
`(index, element)` pattern:

```
in points:  vec3[];
in weights: float[];
out weighted = [ p * weights[i] for (i, p) in points ]   // index first, element second
```

```
in placements: transform[];
out spread = [ translate(vec3(i, 0, 0)) * m for (i, m) in placements ]
```

Reading past the end of an incoming array is reported as an *"index out of
bounds"* error — its length comes from whatever is wired in, so it's only known
while the node runs.

**Outputs** are what the node produces. You have three ways to declare them:

```
sin(x)                       // a bare expression → one output called "result"
```

```
out height = sin(x)          // a named output port "height"
```

```
out x = cos(t);              // several named outputs, separated by ;
out y = sin(t)
```

You can have as many `out` declarations as you like, each becomes its own output
port. You **cannot** mix a bare expression with `out` declarations — either give
everything a name, or use a single bare expression.

**Locals** let you name an intermediate value with `let`, to avoid repeating
yourself:

```
let r = length(vec2(x, y));
out inside = saturate(1 - r);
out glow   = 1 - saturate(r)
```

A `let` must be defined before it is used. Statements are separated by `;` (a
trailing `;` is fine). Whitespace and line breaks don't matter, so format across
multiple lines freely.

**Comments** start with `//` and run to the end of the line:

```
out y = amplitude * sin(t * frequency)   // a simple oscillator
```

---

## Operators

| Operator | Meaning | Notes |
|----------|---------|-------|
| `+` `-` | add, subtract | |
| `*` `/` | multiply, divide | `*` is also transform/rotation composition (below) |
| `%` | remainder | `5 % 3` is `2`; sign follows the left side, so `-1 % 3` is `-1` (use `wrap` to stay positive) |
| `^` | power | `2 ^ 10` is `1024` |
| `-x` | negate | |

**Precedence**, lowest to highest: `+ -`, then `* / %`, then unary `-`, then `^`,
then function calls. Use parentheses whenever you want to be explicit.

Two things worth memorising because they follow maths convention, not keyboard
intuition:

- `^` is **right-associative**: `2 ^ 3 ^ 2` means `2 ^ (3 ^ 2)` = `512`.
- Unary minus binds **looser** than `^`, so `-2 ^ 2` means `-(2 ^ 2)` = `-4`.

Arithmetic on vectors works **component by component**, and a number spreads
across every component ("broadcast"):

```
vec3(1, 2, 3) * 2          // → vec3(2, 4, 6)
vec3(1, 2, 3) + vec3(10, 20, 30)   // → vec3(11, 22, 33)
```

Mixing two different vector sizes (like a `vec2` plus a `vec3`) is an error.

---

## Vectors

**Build** them with `vec2` / `vec3` / `vec4`. Pass one number to fill every
component, or one number per component:

```
vec3(0)            // → vec3(0, 0, 0)
vec4(rgb, 1)       // ✗ not allowed — pass 4 numbers, or 1
vec4(r, g, b, 1)   // ✓
```

**Read** components with a swizzle — a `.` followed by component letters. You can
use either `xyzw` or `rgba` (they mean the same lanes), reorder them, and repeat
them:

```
let p = vec4(1, 2, 3, 4);
out a = p.x         // 1        (a float)
out b = p.xy        // vec2(1, 2)
out c = p.zyx       // vec3(3, 2, 1)   — reversed
out d = p.rrr       // vec3(1, 1, 1)   — repeated
```

Swizzling only applies to vectors, and you can't name a component the vector
doesn't have (`.z` on a `vec2` is an error).

Common **vector functions**: `length`, `distance`, `dot`, `cross`, `normalize`
(see the [reference](#function-reference)). Also, ordinary maths functions like
`sin` or `floor` apply to a vector one component at a time:

```
sin(vec2(a, b))    // → vec2(sin(a), sin(b))
```

---

## Transforms and rotations

A `transform` is a 4×4 matrix — the thing you feed into a mesh to place, rotate,
and size it. Build transforms with these:

```
identity()                       // no-op transform
translate(vec3(x, y, z))         // move
scale(vec3(sx, sy, sz))          // stretch per-axis
scale(2)                         // uniform scale (a single number is fine here)
rotateX(angle)                   // rotate about X (angle in radians)
rotateY(angle)   rotateZ(angle)
```

**Combine** transforms by multiplying them with `*`. They apply right-to-left,
like maths:

```
out xform = translate(vec3(x, 0, 0)) * rotateY(spin) * scale(0.5)
// scale first, then rotate, then move
```

**Apply** a transform to a position or a direction with dedicated functions:

```
transformPoint(xform, p)    // moves a point   (translation counts)
transformDir(xform, d)      // rotates/scales a direction (translation ignored)
```

> `transform * vec3` is deliberately **not** allowed — a bare vec3 is ambiguous
> (is it a point or a direction?). Use `transformPoint` or `transformDir` so the
> intent is explicit.

**Undo** a transform with `inverse` — `inverse(t) * t` is the identity, so it
takes a transformed point back where it came from:

```
let t = translate(vec3(x, 0, 0)) * rotateY(spin);
out worldToLocal = inverse(t)
```

**Aim** a transform with `lookAt(eye, center, up)`. It builds a right-handed
**view** matrix — world → camera, looking from `eye` toward `center` with -Z
forward. To instead *place* an object at `eye` so it faces `center`, invert it:

```
out place = inverse(lookAt(eye, target, vec3(0, 1, 0)))   // object faces `target`
```

**Rotations** can also be expressed as quaternions (`quat`), which are nicer to
interpolate and compose:

```
let q = quatAxisAngle(angle, vec3(0, 1, 0));   // rotate `angle` about the Y axis
out spun = rotate(q, p)                          // apply q to a vec3
```

Build one from three **Euler angles** with `quatEuler(vec3(x, y, z))` (radians,
applied X then Y then Z), and blend two rotations along the shortest arc with
`slerp`:

```
in a: quat; in b: quat; in t: float;
out tween = slerp(a, b, t)                       // a at t=0, b at t=1
```

The `*` operator is overloaded by type, so it always "does the sensible thing":

| Left `*` Right | Result | Meaning |
|----------------|--------|---------|
| `transform * transform` | `transform` | compose transforms |
| `transform * vec4` | `vec4` | apply to a homogeneous vector |
| `quat * quat` | `quat` | compose rotations |
| `quat * vec3` | `vec3` | rotate a vector |

(The function `mul(a, b)` does exactly the same as `*` if you prefer a named
call.)

---

## Arrays and comprehensions

An **array** is a list of values that all share one type.

```
[1, 2, 3]                          // float[]
[vec3(0,0,0), vec3(1,0,0)]         // vec3[]
```

A **comprehension** generates an array from a range — read it as "*this value,
for each i in the range*":

```
[ i * i for i in 0..<n ]           // 0, 1, 4, 9, …  (n items)
[ i for i in 1..5 ]                // 1, 2, 3, 4, 5
```

Ranges come in two flavours:

- `lo..<hi` — from `lo` up to **but not including** `hi` (this is the common one).
- `lo..hi` — from `lo` up to **and including** `hi`.

The loop variable (`i` above) is a number you can use anywhere in the body:

```
[ translate(vec3(cos(i * step), sin(i * step), 0)) for i in 0..<count ]
// `count` points evenly around a circle
```

A comprehension can also loop over an **existing array** instead of a range —
`for p in arr` — binding each element in turn (see
[Taking an array in](#inputs-outputs-and-locals)). The range form gives you the
position `i`; the array form gives you the element `p`; and an
`(index, element)` pattern gives you **both** at once:

```
[ n * n for n in [1, 2, 3, 4] ]          // element only:  1, 4, 9, 16
[ p * i for (i, p) in [5, 5, 5, 5] ]     // index + element: 0, 5, 10, 15
```

**Read** an element by index with `[...]` (indices start at `0`):

```
let xs = [10, 20, 30];
out first = xs[0];       // 10
out picked = xs[k]       // k becomes an input port
```

**Summarise** an array with a reduction:

| Function | Result |
|----------|--------|
| `sum(a)` | total of all elements |
| `product(a)` | all elements multiplied |
| `mean(a)` | average |
| `count(a)` | how many elements (a number) |
| `min(a)` `max(a)` | smallest / largest element (componentwise for vectors) |

```
let samples = [ sin(i * 0.1) for i in 0..<100 ];
out average = mean(samples)
```

---

## Function reference

Maths functions marked *componentwise* also work on vectors, applying to each
component. Everything takes and returns numbers unless noted otherwise.

**Trigonometry**

| Function | Meaning |
|----------|---------|
| `sin(x)` `cos(x)` `tan(x)` | trig (radians), *componentwise* |
| `asin(x)` `acos(x)` `atan(x)` | inverse trig, *componentwise* |
| `atan2(y, x)` | angle of the vector (x, y), *componentwise* |
| `radians(d)` `degrees(r)` | convert degrees↔radians, *componentwise* |

**Powers and logs**

| Function | Meaning |
|----------|---------|
| `sqrt(x)` | square root, *componentwise* |
| `exp(x)` | e to the x, *componentwise* |
| `log(x)` | natural log, *componentwise* |
| `log2(x)` | base-2 log, *componentwise* |
| `pow(a, b)` | a to the b (or use the `^` operator), *componentwise* |

**Rounding and sign**

| Function | Meaning |
|----------|---------|
| `floor(x)` `ceil(x)` `round(x)` | round down / up / to nearest, *componentwise* |
| `fract(x)` | fractional part, *componentwise* |
| `sign(x)` | −1, 0, or +1, *componentwise* |
| `abs(x)` | absolute value, *componentwise* |

**Ranges and blending**

| Function | Meaning |
|----------|---------|
| `min(a, b)` `max(a, b)` | smaller / larger, *componentwise* (or `min(array)` / `max(array)` to reduce) |
| `clamp(x, lo, hi)` | keep x within [lo, hi], *componentwise* |
| `saturate(x)` | clamp to [0, 1], *componentwise* |
| `mix(a, b, t)` | linear blend: `a` at t=0, `b` at t=1, *componentwise* |
| `step(edge, x)` | 0 below the edge, 1 at/above, *componentwise* |
| `smoothstep(lo, hi, x)` | smooth 0→1 ramp between lo and hi, *componentwise* |
| `mod(a, b)` | remainder, sign follows `a` (same as the `%` operator), *componentwise* |
| `wrap(a, b)` | wraps `a` into `[0, b)` — stays positive for negative `a`, *componentwise* |

For these, vectors must share a size and a plain number broadcasts across the
components — so `clamp(v, 0, 1)` clamps every component of `v` to `[0, 1]`.

**Vectors**

| Function | Meaning |
|----------|---------|
| `length(v)` | magnitude of a vector |
| `distance(a, b)` | distance between two vectors |
| `dot(a, b)` | dot product |
| `cross(a, b)` | cross product (vec3 only) |
| `normalize(v)` | unit-length version of a vector (or a quat) |

**Transforms and rotations** — see [that section](#transforms-and-rotations) for
usage.

| Function | Result |
|----------|--------|
| `identity()` | `transform` |
| `translate(vec3)` | `transform` |
| `scale(vec3)` or `scale(float)` | `transform` |
| `rotateX/Y/Z(float)` | `transform` |
| `compose(position, rotation, scale)` | `transform` from a vec3, quat, vec3 |
| `transpose(transform)` | `transform` |
| `inverse(transform)` | `transform` (undoes the transform) |
| `lookAt(eye, center, up)` | `transform` — a view matrix from three vec3 |
| `transformPoint(transform, vec3)` | `vec3` |
| `transformDir(transform, vec3)` | `vec3` |
| `quatAxisAngle(angle, axis)` | `quat` from a float and a vec3 |
| `quatEuler(vec3)` | `quat` from XYZ Euler angles (radians) |
| `conjugate(quat)` | `quat` (inverse rotation) |
| `rotate(quat, vec3)` | `vec3` |
| `slerp(a, b, t)` | `quat` — shortest-path blend between two rotations |
| `mul(a, b)` | same as the `*` operator |

**Arrays** — `sum`, `product`, `mean`, `count`, and `min` / `max` over an array
(see [Arrays](#arrays-and-comprehensions)).

---

## Constants

| Name | Value |
|------|-------|
| `pi` | 3.14159… |
| `tau` | 2·pi (a full turn) |
| `e` | 2.71828… |

These are built in — using them does **not** create an input port.

```
out angle = tau * fraction    // fraction of a full turn
```

---

## When something is wrong

The node checks your expression as you type and points at the exact spot. Errors
(red) stop evaluation; warnings (yellow) don't. Some you'll meet:

- **Unknown name** — a misspelled function. It suggests the closest match:
  *"Unknown function `lenght`. Did you mean `length`?"*
- **Wrong number of arguments** — *"`clamp` takes 3 arguments, got 2."*
- **Type mismatch** — using a value where its type doesn't fit, e.g.
  *"`+` needs matching types — got `vec2` and `vec3`."*
- **Bad swizzle** — *".z can't be applied to a vec2."*
- **Output rules** — mixing a bare expression with `out`, two outputs sharing a
  name, or no output at all.
- **Division by literal zero** (warning) — `x / 0` still runs but yields a
  non-finite number.
- **Unused `let`** (warning) — you named something and never used it.

A couple of limits keep a runaway expression from hanging the app, and surface as
errors if hit: comprehensions have a maximum element count, indexing past the end
of an array is caught (*"index out of bounds"*), and expressions can't be nested
absurdly deep.

---

## Current limits and gotchas

The language is deliberately small. Things that are **not** in it (yet):

- **Undeclared inputs are numbers.** A bare name is always a `float` — to take in
  a vector, transform, or array, declare it with `in name: Type`, or type it
  inline at a single use as `name: Type` (see
  [Inputs](#inputs-outputs-and-locals)).
- **No `if` / conditionals, comparisons, or booleans.** Reach for `step`,
  `clamp`, `mix`, and `smoothstep` to get branch-like behaviour smoothly.
- **No time variable is built in.** If you want animation, wire a time value into
  an input port (e.g. call it `t`) and use it.
- **Arrays are homogeneous** — every element must be the same type — and an empty
  `[]` isn't allowed because its element type can't be known.
