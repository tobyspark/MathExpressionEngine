//
//  PublicAPI.swift
//  FunctionEngine
//
//  The public surface consumed by the Fabric Function Node.
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

/// Stable diagnostic codes (a subset of the full `FN####` scheme; see
/// DESIGN-FunctionNode-Diagnostics.md).
public enum DiagnosticCode: String, Sendable, Equatable {
    case unexpectedToken       // FN2001 / FN1001
    case unmatchedParen        // FN2002
    case incompleteExpression  // FN2004
    case emptyBody             // FN2005
    case unknownName           // FN3001
    case argumentCount         // FN4005
    case mixedOutput           // FN5001 — bare trailing expression mixed with `out`
    case duplicateOutput       // FN5002
    case noOutput              // FN5003
    case duplicateBinding      // a `let` name declared twice
    case useBeforeDefinition   // a `let` referenced before its definition
    case expectedName          // `let`/`out` without a valid identifier
    case expectedEquals        // `let`/`out` without `=`
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

/// A named, typed output port derived from the expression.
public struct OutputPort: Sendable, Equatable {
    public let name: String
    public let type: ValueType
    public init(name: String, type: ValueType) {
        self.name = name
        self.type = type
    }
}

/// The node interface *derived from the expression* — the single-source-of-truth
/// claim, expressed as data. `inputs` are the free identifiers in first-appearance
/// order (deduplicated, constants and locals excluded). `outputs` are the `out`
/// declarations in source order, or a single implicit `result` for a bare
/// expression.
public struct Interface: Sendable, Equatable {
    public let inputs: [String]
    public let outputs: [OutputPort]

    public init(inputs: [String], outputs: [OutputPort]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    /// Convenience: the first output's type (the common single-output case).
    public var outputType: ValueType { outputs.first?.type ?? .float }

    /// Convenience: output names in order.
    public var outputNames: [String] { outputs.map(\.name) }
}

public enum EvalError: Error, Equatable, Sendable {
    case notCompiled
    case missingInput(String)
}

/// A compiled program: its derived interface, any diagnostics, and — when it
/// compiled cleanly — evaluators.
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

    /// Evaluate the first (or only) output. Allocation-free fast path.
    /// Throws `.notCompiled` if the source did not compile, or `.missingInput`
    /// if a required input was not supplied.
    public func evaluate(_ inputs: [String: Float]) throws(EvalError) -> Float {
        guard let program else { throw EvalError.notCompiled }
        return try program.runFirst(inputs)
    }

    /// Evaluate all outputs, in `interface.outputs` order.
    public func evaluateAll(_ inputs: [String: Float]) throws(EvalError) -> [Float] {
        guard let program else { throw EvalError.notCompiled }
        return try program.runAll(inputs)
    }
}

/// An evaluable program (tape-backed in production, reference-backed as the
/// test oracle). Immutable value with `@Sendable` evaluators.
struct Program: Sendable {
    let outputCount: Int
    let runFirst: @Sendable ([String: Float]) throws(EvalError) -> Float
    let runAll: @Sendable ([String: Float]) throws(EvalError) -> [Float]
}
