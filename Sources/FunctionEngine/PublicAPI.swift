//
//  PublicAPI.swift
//  FunctionEngine
//
//  The public surface consumed by the Fabric Function Node.
//

/// A source range: a start offset (in characters) and a length.
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

/// Stable diagnostic codes (a subset of the `FN####` scheme; see
/// DESIGN-FunctionNode-Diagnostics.md).
public enum DiagnosticCode: String, Sendable, Equatable {
    case unexpectedToken
    case unmatchedParen
    case incompleteExpression
    case emptyBody
    case unknownName
    case argumentCount
    case typeMismatch          // operator / function argument type error
    case badSwizzle            // invalid swizzle (bad component, or swizzling a scalar)
    case mixedOutput           // FN5001
    case duplicateOutput       // FN5002
    case noOutput              // FN5003
    case duplicateBinding
    case useBeforeDefinition
    case expectedName
    case expectedEquals
    case emptyArray            // `[]` with no elements (element type can't be inferred)
    case heterogeneousArray    // array literal with mixed element types
    case notAnArray            // indexing / reducing a non-array
    case expectedRange         // comprehension range malformed
    case divisionByZero        // literal `/ 0` (warning)
    case unusedBinding         // a `let` never referenced (warning)
    case expressionTooDeep     // nesting-depth guard
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

/// The value/port types the engine can produce.
public indirect enum ValueType: Sendable, Equatable {
    case float, vec2, vec3, vec4
    case transform, quat
    case array(ValueType)

    public var width: Int {
        switch self {
        case .float: return 1
        case .vec2:  return 2
        case .vec3:  return 3
        case .vec4:  return 4
        case .transform, .quat, .array: return 0
        }
    }

    public var isVector: Bool {
        switch self { case .vec2, .vec3, .vec4: return true; default: return false }
    }

    public var elementType: ValueType? {
        if case .array(let t) = self { return t } else { return nil }
    }
    public var isArray: Bool { elementType != nil }

    public var name: String {
        switch self {
        case .float: return "float"
        case .vec2:  return "vec2"
        case .vec3:  return "vec3"
        case .vec4:  return "vec4"
        case .transform: return "transform"
        case .quat: return "quat"
        case .array(let t): return "\(t.name)[]"
        }
    }

    static func ofWidth(_ w: Int) -> ValueType? {
        switch w {
        case 1: return .float
        case 2: return .vec2
        case 3: return .vec3
        case 4: return .vec4
        default: return nil
        }
    }
}

/// A typed value the engine produces. Scalars/vectors are trivial (SIMD
/// payloads); `.array` is heap-backed.
public enum EngineValue: Sendable, Equatable {
    case float(Float)
    case vec2(SIMD2<Float>)
    case vec3(SIMD3<Float>)
    case vec4(SIMD4<Float>)
    case transform(Mat4)
    case quat(Quat)
    case array([EngineValue])

    public var type: ValueType {
        switch self {
        case .float: return .float
        case .vec2:  return .vec2
        case .vec3:  return .vec3
        case .vec4:  return .vec4
        case .transform: return .transform
        case .quat: return .quat
        case .array(let els): return .array(els.first?.type ?? .float)
        }
    }

    /// The scalar value (float), the first component (vectors), or the first
    /// element's scalar (arrays).
    public var scalar: Float {
        switch self {
        case .float(let x): return x
        case .vec2(let v):  return v.x
        case .vec3(let v):  return v.x
        case .vec4(let v):  return v.x
        case .transform(let m): return m.c0.x
        case .quat(let q): return q.x
        case .array(let els): return els.first?.scalar ?? 0
        }
    }

    /// Components as a `[Float]` (vectors), `[x]` (float), the 16 column-major
    /// entries (transform), (x,y,z,w) (quat), or per-element scalars (arrays).
    public var components: [Float] {
        switch self {
        case .float(let x): return [x]
        case .vec2(let v):  return [v.x, v.y]
        case .vec3(let v):  return [v.x, v.y, v.z]
        case .vec4(let v):  return [v.x, v.y, v.z, v.w]
        case .transform(let m):
            return [m.c0.x, m.c0.y, m.c0.z, m.c0.w,
                    m.c1.x, m.c1.y, m.c1.z, m.c1.w,
                    m.c2.x, m.c2.y, m.c2.z, m.c2.w,
                    m.c3.x, m.c3.y, m.c3.z, m.c3.w]
        case .quat(let q): return [q.x, q.y, q.z, q.w]
        case .array(let els): return els.map(\.scalar)
        }
    }

    /// The elements of an array value (nil for scalars/vectors).
    public var arrayElements: [EngineValue]? {
        if case .array(let els) = self { return els } else { return nil }
    }
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

/// The node interface *derived from the expression*. `inputs` are the free
/// identifiers in first-appearance order (all `float` in this slice; deduplicated,
/// constants and locals excluded). `outputs` are the `out` declarations in source
/// order (types inferred), or a single implicit `result`.
public struct Interface: Sendable, Equatable {
    public let inputs: [String]
    public let outputs: [OutputPort]

    public init(inputs: [String], outputs: [OutputPort]) {
        self.inputs = inputs
        self.outputs = outputs
    }

    public var outputType: ValueType { outputs.first?.type ?? .float }
    public var outputNames: [String] { outputs.map(\.name) }
}

public enum EvalError: Error, Equatable, Sendable {
    case notCompiled
    case missingInput(String)
    case indexOutOfBounds(index: Int, count: Int)
    case limitExceeded(String)
}

/// A compiled program: its derived interface, any diagnostics, and — when it
/// compiled cleanly — evaluators.
public struct CompileResult: Sendable {
    public let interface: Interface
    public let diagnostics: [Diagnostic]

    let program: Program?

    init(interface: Interface, diagnostics: [Diagnostic], program: Program?) {
        self.interface = interface
        self.diagnostics = diagnostics
        self.program = program
    }

    public var isValid: Bool { program != nil }

    /// The first output as a typed value.
    public func evaluateValue(_ inputs: [String: Float]) throws(EvalError) -> EngineValue {
        guard let program else { throw EvalError.notCompiled }
        return try program.runValues(inputs).first ?? .float(.nan)
    }

    /// All outputs as typed values, in `interface.outputs` order.
    public func evaluateValues(_ inputs: [String: Float]) throws(EvalError) -> [EngineValue] {
        guard let program else { throw EvalError.notCompiled }
        return try program.runValues(inputs)
    }

    /// The first output as a `Float` (its scalar / first component). Convenience.
    public func evaluate(_ inputs: [String: Float]) throws(EvalError) -> Float {
        try evaluateValue(inputs).scalar
    }

    /// All outputs as `Float` (scalar / first component each). Convenience.
    public func evaluateAll(_ inputs: [String: Float]) throws(EvalError) -> [Float] {
        try evaluateValues(inputs).map(\.scalar)
    }
}

/// An evaluable program (tape-backed in production, reference-backed as the
/// test oracle). Produces all outputs as typed values in source order.
struct Program: Sendable {
    let outputCount: Int
    let runValues: @Sendable ([String: Float]) throws(EvalError) -> [EngineValue]
}
