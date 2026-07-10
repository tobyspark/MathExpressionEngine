//
//  Lexer.swift
//  FunctionEngine
//
//  Single-pass tokenizer. Every token carries a `Span` so diagnostics land at
//  the exact site of a problem.
//

struct Token: Equatable {
    enum Kind: Equatable {
        case number(Float)
        case identifier(String)
        case plus, minus, star, slash, percent, caret
        case lparen, rparen, comma
        case equals, semicolon, dot
        case eof
    }
    let kind: Kind
    let span: Span
}

struct Lexer {
    private let chars: [Character]
    private var i = 0

    init(_ source: String) { self.chars = Array(source) }

    mutating func tokenize() -> (tokens: [Token], diagnostics: [Diagnostic]) {
        var tokens: [Token] = []
        var diagnostics: [Diagnostic] = []

        while i < chars.count {
            let c = chars[i]

            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                i += 1
                continue
            }

            // Line comment: // ... to end of line
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }

            let start = i

            // Number: digits [ . digits ] [ (e|E) [+|-] digits ]
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var text = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    text.append(chars[i]); i += 1
                }
                if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                    text.append(chars[i]); i += 1
                    if i < chars.count && (chars[i] == "+" || chars[i] == "-") {
                        text.append(chars[i]); i += 1
                    }
                    while i < chars.count && chars[i].isNumber {
                        text.append(chars[i]); i += 1
                    }
                }
                let span = Span(start: start, length: i - start)
                if let value = Float(text) {
                    tokens.append(Token(kind: .number(value), span: span))
                } else {
                    diagnostics.append(Diagnostic(code: .unexpectedToken, severity: .error,
                                                  message: "`\(text)` isn't a valid number.", span: span))
                }
                continue
            }

            // Identifier: [A-Za-z_][A-Za-z0-9_]*
            if c.isLetter || c == "_" {
                var text = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    text.append(chars[i]); i += 1
                }
                tokens.append(Token(kind: .identifier(text), span: Span(start: start, length: i - start)))
                continue
            }

            // Single-character operators / punctuation
            let kind: Token.Kind?
            switch c {
            case "+": kind = .plus
            case "-": kind = .minus
            case "*": kind = .star
            case "/": kind = .slash
            case "%": kind = .percent
            case "^": kind = .caret
            case "(": kind = .lparen
            case ")": kind = .rparen
            case ",": kind = .comma
            case "=": kind = .equals
            case ";": kind = .semicolon
            case ".": kind = .dot
            default:  kind = nil
            }
            if let kind {
                tokens.append(Token(kind: kind, span: Span(start: start, length: 1)))
                i += 1
            } else {
                diagnostics.append(Diagnostic(code: .unexpectedToken, severity: .error,
                                              message: "Unexpected character `\(c)`.",
                                              span: Span(start: start, length: 1)))
                i += 1
            }
        }

        tokens.append(Token(kind: .eof, span: Span(start: i, length: 0)))
        return (tokens, diagnostics)
    }
}
