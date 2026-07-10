//
//  Parser.swift
//  FunctionEngine
//
//  Recursive-descent / precedence-climbing parser for the scalar Tier-0 grammar.
//  Precedence (low→high): + -  |  * / %  |  unary -  |  ^ (right-assoc)  |  call / primary.
//  Unary minus binds looser than `^`, so `-2 ^ 2` == -(2^2) (math convention).
//

struct Parser {
    private let tokens: [Token]
    private var p = 0
    private(set) var diagnostics: [Diagnostic] = []

    init(_ tokens: [Token]) { self.tokens = tokens }

    private var current: Token { tokens[p] }

    @discardableResult
    private mutating func advance() -> Token {
        let t = tokens[p]
        if p < tokens.count - 1 { p += 1 }
        return t
    }

    /// Parse a whole expression, requiring it to consume all input.
    mutating func parse() -> Expr? {
        if case .eof = current.kind {
            diagnostics.append(Diagnostic(code: .emptyBody, severity: .error,
                                          message: "The function is empty — enter an expression.",
                                          span: current.span))
            return nil
        }
        guard let expr = parseAdditive() else { return nil }
        guard case .eof = current.kind else {
            diagnostics.append(Diagnostic(code: .unexpectedToken, severity: .error,
                                          message: "Unexpected `\(describe(current))` after the expression.",
                                          span: current.span))
            return nil
        }
        return expr
    }

    private mutating func parseAdditive() -> Expr? {
        guard var left = parseMultiplicative() else { return nil }
        while true {
            let op: BinaryOp
            switch current.kind {
            case .plus:  op = .add
            case .minus: op = .sub
            default:     return left
            }
            advance()
            guard let right = parseMultiplicative() else { return nil }
            left = .binary(op, left, right, merge(left.span, right.span))
        }
    }

    private mutating func parseMultiplicative() -> Expr? {
        guard var left = parseUnary() else { return nil }
        while true {
            let op: BinaryOp
            switch current.kind {
            case .star:    op = .mul
            case .slash:   op = .div
            case .percent: op = .mod
            default:       return left
            }
            advance()
            guard let right = parseUnary() else { return nil }
            left = .binary(op, left, right, merge(left.span, right.span))
        }
    }

    private mutating func parseUnary() -> Expr? {
        if case .minus = current.kind {
            let s = current.span
            advance()
            guard let operand = parseUnary() else { return nil }
            return .negate(operand, merge(s, operand.span))
        }
        if case .plus = current.kind {          // unary plus: no-op
            advance()
            return parseUnary()
        }
        return parsePower()
    }

    private mutating func parsePower() -> Expr? {
        guard let base = parsePrimary() else { return nil }
        if case .caret = current.kind {
            advance()
            // Right operand is a unary so `2 ^ -3` parses; recursion gives right-assoc.
            guard let exponent = parseUnary() else { return nil }
            return .binary(.pow, base, exponent, merge(base.span, exponent.span))
        }
        return base
    }

    private mutating func parsePrimary() -> Expr? {
        switch current.kind {
        case .number(let value):
            let s = current.span; advance()
            return .number(value, s)

        case .identifier(let name):
            let s = current.span; advance()
            if case .lparen = current.kind {
                advance()
                var args: [Expr] = []
                if case .rparen = current.kind {
                    // zero-argument call
                } else {
                    while true {
                        guard let arg = parseAdditive() else { return nil }
                        args.append(arg)
                        if case .comma = current.kind { advance(); continue }
                        break
                    }
                }
                guard case .rparen = current.kind else {
                    diagnostics.append(Diagnostic(code: .unmatchedParen, severity: .error,
                                                  message: "Expected `)` to close `\(name)(`.",
                                                  span: current.span))
                    return nil
                }
                let end = current.span; advance()
                return .call(name, args, merge(s, end))
            }
            return .variable(name, s)

        case .lparen:
            advance()
            guard let inner = parseAdditive() else { return nil }
            guard case .rparen = current.kind else {
                diagnostics.append(Diagnostic(code: .unmatchedParen, severity: .error,
                                              message: "Expected `)`.", span: current.span))
                return nil
            }
            advance()
            return inner

        case .eof:
            diagnostics.append(Diagnostic(code: .incompleteExpression, severity: .error,
                                          message: "The expression is incomplete.", span: current.span))
            return nil

        default:
            diagnostics.append(Diagnostic(code: .unexpectedToken, severity: .error,
                                          message: "Unexpected `\(describe(current))`.", span: current.span))
            return nil
        }
    }
}

private func merge(_ a: Span, _ b: Span) -> Span {
    let start = min(a.start, b.start)
    let end = max(a.start + a.length, b.start + b.length)
    return Span(start: start, length: end - start)
}

private func describe(_ t: Token) -> String {
    switch t.kind {
    case .number(let v):     return "\(v)"
    case .identifier(let s): return s
    case .plus:              return "+"
    case .minus:             return "-"
    case .star:              return "*"
    case .slash:             return "/"
    case .percent:           return "%"
    case .caret:             return "^"
    case .lparen:            return "("
    case .rparen:            return ")"
    case .comma:             return ","
    case .eof:               return "end of input"
    }
}
