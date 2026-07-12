import Foundation
import Testing
import MathParser
@testable import MathExpressionEngine

private struct ScalarBenchmarkCase {
    let name: String
    let source: String
}

private struct BenchmarkResult {
    let oldNanos: UInt64
    let newNanos: UInt64

    var ratio: Double {
        guard newNanos > 0 else { return .infinity }
        return Double(oldNanos) / Double(newNanos)
    }

    var deltaPercent: Double {
        guard oldNanos > 0 else { return 0 }
        return (Double(newNanos) - Double(oldNanos)) / Double(oldNanos) * 100
    }
}

private final class BenchmarkOutputBuffer<Value: AdditiveArithmetic>: @unchecked Sendable {
    private var values: ContiguousArray<Value>

    init(repeating value: Value, count: Int) {
        values = ContiguousArray(repeating: value, count: count)
    }

    func set(_ value: Value, at index: Int) {
        values[index] = value
    }

    func reduce() -> Value {
        values.reduce(.zero, +)
    }
}

private final class OldEvaluatorBox: @unchecked Sendable {
    let evaluator: Evaluator

    init(_ evaluator: Evaluator) {
        self.evaluator = evaluator
    }
}

@Suite struct PerformanceComparisonTests {

    private let scalarCases: [ScalarBenchmarkCase] = [
        .init(name: "literal arithmetic", source: "2 + 3 * 4"),
        .init(name: "three variables", source: "a * b + c"),
        .init(name: "trig mix", source: "sin(a) + cos(b) * 2"),
        .init(name: "sqrt abs divide", source: "sqrt(abs(a * b)) / (c + 1)"),
        .init(name: "pow atan2", source: "pow(a + 2, 2) + atan2(b, c)"),
        .init(name: "rounding log2", source: "log2(abs(a) + 1) + floor(b) - ceil(c) + round(a)"),
        .init(name: "nested scalar", source: "((a + b) * (b - c)) ^ 2 / (abs(c) + 0.5)"),
        .init(name: "constants", source: "sin(pi * a) + 1"),
    ]

    @Test func parseCompileBenchmarks() throws {
        let iterations = 2_000
        var rows: [(String, BenchmarkResult)] = []

        for testCase in scalarCases {
            let result = try measurePair(iterations: iterations) { _ in
                let parsed = MathParser().parseResult(testCase.source)
                if case .failure = parsed {
                    Issue.record("MathParser failed to parse `\(testCase.source)`")
                }
            } newWork: { _ in
                let compiled = compile(testCase.source)
                #expect(compiled.isValid, "MathExpressionEngine failed to compile `\(testCase.source)`")
            }
            rows.append((testCase.name, result))
        }

        printBenchmarkTable(title: "Parse / compile", iterations: iterations, rows: rows)
    }

    @Test func scalarEvaluationBenchmarks() throws {
        let iterations = 200_000
        var rows: [(String, BenchmarkResult)] = []

        for testCase in scalarCases {
            let oldEvaluator = try makeOldEvaluator(testCase.source)
            let newEvaluator = try makeNewEvaluator(testCase.source)
            try assertScalarAgreement(oldEvaluator, newEvaluator, source: testCase.source)

            var oldAccumulator = 0.0
            var newAccumulator: Float = 0

            let result = try measurePair(iterations: iterations) {
                let inputs = inputs(for: $0)
                oldAccumulator += oldEvaluator.eval { Double(inputs[$0] ?? 0) }
            } newWork: {
                let inputs = inputs(for: $0)
                newAccumulator += try newEvaluator.evaluate(inputs)
            }

            #expect(oldAccumulator.isFinite)
            #expect(newAccumulator.isFinite)
            rows.append((testCase.name, result))
        }

        printBenchmarkTable(title: "Scalar hot evaluation", iterations: iterations, rows: rows)
    }

    @Test func arrayStyleEvaluationBenchmarks() throws {
        let iterations = 128
        let elementCount = 4_096
        let oldSource = "dist * sin(t * 2 * pi) + cos(i / (n + 1))"
        let newSource = "let denom = max(n - 1, 1); [dist * sin((i / denom) * 2 * pi) + cos(i / (n + 1)) for i in 0..<n]"

        let oldEvaluator = try makeOldEvaluator(oldSource)
        let newEvaluator = try makeNewEvaluator(newSource)
        try assertArrayStyleAgreement(oldEvaluator, newEvaluator, oldSource: oldSource, newSource: newSource, count: elementCount)

        var oldAccumulator = 0.0
        var newAccumulator: Float = 0

        let result = try measurePair(iterations: iterations) { iteration in
            oldAccumulator += oldArrayStyleSum(
                evaluator: oldEvaluator,
                count: elementCount,
                dist: Float(iteration % 17) * 0.125 + 0.5
            )
        } newWork: { iteration in
            newAccumulator += try newArrayStyleSum(
                evaluator: newEvaluator,
                count: elementCount,
                dist: Float(iteration % 17) * 0.125 + 0.5
            )
        }

        #expect(oldAccumulator.isFinite)
        #expect(newAccumulator.isFinite)
        printBenchmarkTable(
            title: "Array workload: old Fabric loop vs new native array",
            iterations: iterations * elementCount,
            rows: [("array workload", result)]
        )
    }

    private func makeOldEvaluator(_ source: String) throws -> Evaluator {
        switch MathParser().parseResult(source) {
        case .success(let evaluator):
            return evaluator
        case .failure:
            Issue.record("MathParser failed to parse `\(source)`")
            throw BenchmarkSetupError.oldParserFailed
        }
    }

    private func makeNewEvaluator(_ source: String) throws -> CompileResult {
        let result = compile(source)
        #expect(result.isValid, "MathExpressionEngine failed to compile `\(source)`; diagnostics: \(result.diagnostics)")
        guard result.isValid else { throw BenchmarkSetupError.newCompilerFailed }
        return result
    }

    private func assertScalarAgreement(_ oldEvaluator: Evaluator, _ newEvaluator: CompileResult, source: String) throws {
        for index in stride(from: 0, to: 256, by: 17) {
            let values = inputs(for: index)
            let oldValue = Float(oldEvaluator.eval { Double(values[$0] ?? 0) })
            let newValue = try newEvaluator.evaluate(values)
            #expect(approximatelyEqual(oldValue, newValue), "mismatch for `\(source)` @ \(values): old=\(oldValue), new=\(newValue)")
        }
    }

    private func assertArrayStyleAgreement(_ oldEvaluator: Evaluator, _ newEvaluator: CompileResult, oldSource: String, newSource: String, count: Int) throws {
        for dist in [0.5, 1.0, 1.75] as [Float] {
            let oldValue = Float(oldArrayStyleSum(evaluator: oldEvaluator, count: count, dist: dist))
            let newValue = try newArrayStyleSum(evaluator: newEvaluator, count: count, dist: dist)
            #expect(approximatelyEqual(oldValue, newValue, epsilon: 1e-2), "array-style mismatch old=`\(oldSource)` new=`\(newSource)`: old=\(oldValue), new=\(newValue)")
        }
    }

    private func inputs(for index: Int) -> [String: Float] {
        let x = Float(index % 10_000) * 0.001 - 5
        return [
            "a": x,
            "b": x * 0.5 - 1,
            "c": 2 - x * 0.25,
        ]
    }

    private func oldArrayStyleSum(evaluator: Evaluator, count: Int, dist: Float) -> Double {
        let evaluatorBox = OldEvaluatorBox(evaluator)
        let nAsDouble = Double(count)
        let tDivisor = Float(max(1, count - 1))
        let concurrentThreshold = 512
        let output = BenchmarkOutputBuffer<Double>(repeating: 0, count: count)

        let evalElement: @Sendable (Int) -> Void = { index in
            let iAsDouble = Double(index)
            let tAsDouble = Double(Float(index) / tDivisor)
            let value = evaluatorBox.evaluator.eval { variable in
                switch variable {
                case "i": return iAsDouble
                case "n": return nAsDouble
                case "t": return tAsDouble
                case "dist": return Double(dist)
                default: return 0
                }
            }
            output.set(value, at: index)
        }

        if count >= concurrentThreshold {
            DispatchQueue.concurrentPerform(iterations: count) { evalElement($0) }
        } else {
            for index in 0..<count { evalElement(index) }
        }

        return output.reduce()
    }

    private func newArrayStyleSum(evaluator: CompileResult, count: Int, dist: Float) throws -> Float {
        let value = try evaluator.evaluateValue(["n": Float(count), "dist": dist])
        return value.components.reduce(0, +)
    }

    private func measurePair(
        iterations: Int,
        oldWork: (Int) throws -> Void,
        newWork: (Int) throws -> Void
    ) throws -> BenchmarkResult {
        try oldWork(0)
        try newWork(0)

        let oldNanos = try measure(iterations: iterations, work: oldWork)
        let newNanos = try measure(iterations: iterations, work: newWork)
        return BenchmarkResult(oldNanos: oldNanos, newNanos: newNanos)
    }

    private func measure(iterations: Int, work: (Int) throws -> Void) throws -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            try work(index)
        }
        return DispatchTime.now().uptimeNanoseconds - start
    }

    private func printBenchmarkTable(title: String, iterations: Int, rows: [(String, BenchmarkResult)]) {
        print("\n\(title) benchmark (\(iterations) iterations)")
        print("case | old total | new total | old/ new | delta")
        for (name, result) in rows {
            print("\(name) | \(formatNanos(result.oldNanos)) | \(formatNanos(result.newNanos)) | \(format(result.ratio))x | \(format(result.deltaPercent))%")
        }
    }

    private func formatNanos(_ nanos: UInt64) -> String {
        if nanos >= 1_000_000_000 {
            return "\(format(Double(nanos) / 1_000_000_000))s"
        }
        if nanos >= 1_000_000 {
            return "\(format(Double(nanos) / 1_000_000))ms"
        }
        if nanos >= 1_000 {
            return "\(format(Double(nanos) / 1_000))us"
        }
        return "\(nanos)ns"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func approximatelyEqual(_ lhs: Float, _ rhs: Float, epsilon: Float = 1e-4) -> Bool {
        if lhs == rhs || (lhs.isNaN && rhs.isNaN) { return true }
        let scale = max(Float(1), abs(lhs), abs(rhs))
        return abs(lhs - rhs) <= epsilon * scale
    }

    private enum BenchmarkSetupError: Error {
        case oldParserFailed
        case newCompilerFailed
    }
}
