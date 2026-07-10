//
//  PublicAPI.swift
//  FunctionEngine
//
//  The public surface consumed by the Fabric Function Node. Stable across the
//  red→green TDD split: only `compile(_:)` (in Engine.swift) changes from stub
//  to real implementation.
//

/// A source range: a start offset (in characters) and a length. Used to place
/// diagnostics at the exact site of a problem.
public struct Span: Equatable, Sendable {
    public let start: Int
    public let length: Int
    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }
}

public enum Severity: Sendable, Equatable {
    case error, warning, info
}

/// Stable diagnostic codes (a subset of the full `FN####` scheme for the
/// scalar Tier-0 slice — see DESIGN-FunctionNode-Diagnostics.md).
public enum DiagnosticCode: String, Sendable, Equatable {
    case unexpectedToken       // FN2001 / FN1001
    case unmatchedParen        // FN2002
    case incompleteExpression  // FN2004
    case emptyBody             // FN2005
    case unknownName           // FN3001
    case argumentCount         // FN4005
}

public struct Diagnostic: Sendable, Equatable {
    public let code: DiagnosticCode
    public let severity: Severity
    public let message: String
    public let span: Span
    public init(code: DiagnosticCode, severity: Severity, message: String, span: Span) {
        self.code = code
        self.severity = severity
        self.message = message
        self.span = span
    }
}

/// The value/port types the engine can produce. Scalar slice: `.float` only;
/// later slices add vec2/3/4, color, quat, transform, and arrays.
public enum ValueType: Sendable, Equatable {
    case float
}

/// The node interface *derived from the expression* — the single-source-of-truth
/// claim, expressed as data. `inputs` are the free identifiers in first-appearance
/// order (deduplicated, constants excluded).
public struct Interface: Sendable, Equatable {
    public let inputs: [String]
    public let outputType: ValueType
    public init(inputs: [String], outputType: ValueType) {
        self.inputs = inputs
        self.outputType = outputType
    }
}

public enum EvalError: Error, Equatable, Sendable {
    case notCompiled
    case missingInput(String)
}

/// A compiled expression: its derived interface, any diagnostics, and — when it
/// compiled cleanly — a pure evaluator.
public struct CompileResult: Sendable {
    public let interface: Interface
    public let diagnostics: [Diagnostic]

    /// Present iff the source compiled without error-severity diagnostics.
    let program: Program?

    init(interface: Interface, diagnostics: [Diagnostic], program: Program?) {
        self.interface = interface
        self.diagnostics = diagnostics
        self.program = program
    }

    /// True when the expression compiled to an evaluable program.
    public var isValid: Bool { program != nil }

    /// Evaluate the compiled expression against a set of input values.
    /// Throws `.notCompiled` if the source did not compile, or
    /// `.missingInput` if a required input was not supplied.
    public func evaluate(_ inputs: [String: Float]) throws(EvalError) -> Float {
        guard let program else { throw EvalError.notCompiled }
        return try program.run(inputs)
    }
}

/// An evaluable program. In the scalar slice this wraps the tree-walking
/// reference interpreter; later slices replace `run` with the flat POD tape
/// while keeping this surface (and add a differential test tape == reference).
struct Program: Sendable {
    let run: @Sendable ([String: Float]) throws(EvalError) -> Float
}
