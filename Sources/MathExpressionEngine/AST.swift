//
//  AST.swift
//  MathExpressionEngine
//
//  Expression AST. Sendable so a compiled program's evaluator closure can
//  capture it across threads.
//

enum BinaryOp: Sendable, Equatable {
    case add, sub, mul, div, mod, pow
}

indirect enum Expr: Sendable {
    case number(Float, Span)
    case variable(String, Span)
    case typedVariable(String, ValueType, Span)   // inline-typed input, e.g. `p: vec3`
    case call(String, [Expr], Span)
    case negate(Expr, Span)
    case binary(BinaryOp, Expr, Expr, Span)
    case swizzle(Expr, String, Span)              // base.chars, e.g. p.xyz
    case arrayLiteral([Expr], Span)               // [a, b, c]
    case index(Expr, Expr, Span)                  // base[index]
    case comprehension(body: Expr, loopVar: String, lo: Expr, hi: Expr, inclusive: Bool, Span)  // [body for i in lo..<hi]
    case mapComprehension(body: Expr, indexVar: String?, elemVar: String, source: Expr, Span)    // [body for p in array] / [body for (i, p) in array]

    var span: Span {
        switch self {
        case .number(_, let s),
             .variable(_, let s),
             .typedVariable(_, _, let s),
             .call(_, _, let s),
             .negate(_, let s),
             .binary(_, _, _, let s),
             .swizzle(_, _, let s),
             .arrayLiteral(_, let s),
             .index(_, _, let s),
             .comprehension(_, _, _, _, _, let s),
             .mapComprehension(_, _, _, _, let s):
            return s
        }
    }
}

/// A statement in the function body. A bare single expression is normalized to
/// one implicit `.output("result", …)`.
enum Statement: Sendable {
    case input(name: String, type: ValueType, span: Span)  // `in name: Type` (typed input declaration)
    case local(name: String, value: Expr, span: Span)      // `let name = expr`
    case output(name: String, value: Expr, span: Span)     // `out name = expr` (or implicit result)
}

/// The whole function body: statements in source order.
struct Body: Sendable {
    let statements: [Statement]
}
