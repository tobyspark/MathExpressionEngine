//
//  AST.swift
//  FunctionEngine
//
//  Expression AST for the scalar Tier-0 slice. Sendable so a compiled program's
//  evaluator closure can capture it across threads (the array/parallel path in
//  later slices relies on this).
//

enum BinaryOp: Sendable, Equatable {
    case add, sub, mul, div, mod, pow
}

indirect enum Expr: Sendable {
    case number(Float, Span)
    case variable(String, Span)
    case call(String, [Expr], Span)
    case negate(Expr, Span)
    case binary(BinaryOp, Expr, Expr, Span)

    var span: Span {
        switch self {
        case .number(_, let s),
             .variable(_, let s),
             .call(_, _, let s),
             .negate(_, let s),
             .binary(_, _, _, let s):
            return s
        }
    }
}

/// A statement in the function body. A bare single expression is normalized to
/// one implicit `.output("result", …)`.
enum Statement: Sendable {
    case local(name: String, value: Expr, span: Span)    // `let name = expr`
    case output(name: String, value: Expr, span: Span)   // `out name = expr` (or implicit result)
}

/// The whole function body: statements in source order.
struct Body: Sendable {
    let statements: [Statement]
}
