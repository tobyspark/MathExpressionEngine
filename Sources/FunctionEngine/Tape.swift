//
//  Tape.swift
//  FunctionEngine
//
//  The flat POD bytecode: a register machine over `EngineValue` registers.
//  Instructions are trivially-copyable (register/const/input indices, a
//  payload-free `FnID`, small ints) — no strings/closures/arrays — so `Tape` is
//  `Sendable` and the eval loop touches no ARC. The register scratch is
//  stack-allocated (`withUnsafeTemporaryAllocation`), so eval allocates only the
//  small output array.
//
//  (Value math is dynamically dispatched via `EngineValue` for now; a later
//  slice can monomorphize per sema's static types.)
//

/// A single instruction. All payloads are trivial → POD / `Sendable`.
enum Instr: Sendable {
    case loadConst(dst: Int, constIndex: Int)
    case loadInput(dst: Int, inputIndex: Int)
    case negate(dst: Int, src: Int)
    case binary(BinaryOp, dst: Int, lhs: Int, rhs: Int)
    case call1(FnID, dst: Int, a: Int)
    case call2(FnID, dst: Int, a: Int, b: Int)
    case call3(FnID, dst: Int, a: Int, b: Int, c: Int)
    case construct2(dst: Int, a: Int, b: Int)
    case construct3(dst: Int, a: Int, b: Int, c: Int)
    case construct4(dst: Int, a: Int, b: Int, c: Int, d: Int)
    case splat(dst: Int, src: Int, width: Int)
    case swizzle(dst: Int, src: Int, i0: Int, i1: Int, i2: Int, i3: Int, count: Int)
}

struct Tape: Sendable {
    let instructions: [Instr]
    let constants: [Float]
    let inputOrder: [String]
    let registerCount: Int
    let outputRegisters: [(name: String, register: Int)]
}

private struct Lowerer {
    var instructions: [Instr] = []
    var constants: [Float] = []
    var inputIndex: [String: Int] = [:]
    var inputOrder: [String] = []
    var localRegister: [String: Int] = [:]
    var nextRegister = 0

    mutating func newRegister() -> Int {
        defer { nextRegister += 1 }
        return nextRegister
    }

    mutating func constSlot(_ v: Float) -> Int {
        constants.append(v)
        return constants.count - 1
    }

    mutating func inputSlot(_ name: String) -> Int {
        if let i = inputIndex[name] { return i }
        let i = inputOrder.count
        inputIndex[name] = i
        inputOrder.append(name)
        return i
    }

    mutating func lowerBody(_ body: Body) -> [(name: String, register: Int)] {
        var outputs: [(name: String, register: Int)] = []
        for stmt in body.statements {
            switch stmt {
            case .local(let name, let value, _):
                localRegister[name] = lower(value)
            case .output(let name, let value, _):
                outputs.append((name: name, register: lower(value)))
            }
        }
        return outputs
    }

    mutating func lower(_ e: Expr) -> Int {
        switch e {
        case .number(let value, _):
            let dst = newRegister()
            instructions.append(.loadConst(dst: dst, constIndex: constSlot(value)))
            return dst

        case .variable(let name, _):
            if let reg = localRegister[name] { return reg }
            let dst = newRegister()
            if let constant = Builtins.constants[name] {
                instructions.append(.loadConst(dst: dst, constIndex: constSlot(constant)))
            } else {
                instructions.append(.loadInput(dst: dst, inputIndex: inputSlot(name)))
            }
            return dst

        case .negate(let x, _):
            let src = lower(x)
            let dst = newRegister()
            instructions.append(.negate(dst: dst, src: src))
            return dst

        case .binary(let op, let l, let r, _):
            let lhs = lower(l)
            let rhs = lower(r)
            let dst = newRegister()
            instructions.append(.binary(op, dst: dst, lhs: lhs, rhs: rhs))
            return dst

        case .swizzle(let base, let chars, _):
            let src = lower(base)
            let idx = swizzleIndices(chars) ?? [0]
            let i0 = idx[0]
            let i1 = idx.count > 1 ? idx[1] : 0
            let i2 = idx.count > 2 ? idx[2] : 0
            let i3 = idx.count > 3 ? idx[3] : 0
            let dst = newRegister()
            instructions.append(.swizzle(dst: dst, src: src, i0: i0, i1: i1, i2: i2, i3: i3, count: idx.count))
            return dst

        case .call(let name, let args, _):
            if Builtins.isConstructor(name) {
                let width = name == "vec2" ? 2 : (name == "vec3" ? 3 : 4)
                let regs = args.map { lower($0) }
                let dst = newRegister()
                if regs.count == 1 {
                    instructions.append(.splat(dst: dst, src: regs[0], width: width))
                } else {
                    switch width {
                    case 2:  instructions.append(.construct2(dst: dst, a: regs[0], b: regs[1]))
                    case 3:  instructions.append(.construct3(dst: dst, a: regs[0], b: regs[1], c: regs[2]))
                    default: instructions.append(.construct4(dst: dst, a: regs[0], b: regs[1], c: regs[2], d: regs[3]))
                    }
                }
                return dst
            }

            guard let id = Builtins.id(forName: name) else {
                let dst = newRegister()
                instructions.append(.loadConst(dst: dst, constIndex: constSlot(.nan)))
                return dst
            }
            let regs = args.map { lower($0) }
            let dst = newRegister()
            switch regs.count {
            case 1:  instructions.append(.call1(id, dst: dst, a: regs[0]))
            case 2:  instructions.append(.call2(id, dst: dst, a: regs[0], b: regs[1]))
            default: instructions.append(.call3(id, dst: dst, a: regs[0], b: regs[1], c: regs[2]))
            }
            return dst
        }
    }
}

func lower(_ body: Body) -> Tape {
    var lowerer = Lowerer()
    let outputs = lowerer.lowerBody(body)
    return Tape(
        instructions: lowerer.instructions,
        constants: lowerer.constants,
        inputOrder: lowerer.inputOrder,
        registerCount: lowerer.nextRegister,
        outputRegisters: outputs
    )
}

// MARK: - Execution

private func executeValues(_ tape: Tape, into r: UnsafeMutableBufferPointer<EngineValue>, base: Int) {
    for ins in tape.instructions {
        switch ins {
        case .loadConst(let dst, let ci):
            r[base + dst] = .float(tape.constants[ci])
        case .loadInput(let dst, let ii):
            r[base + dst] = r[ii]
        case .negate(let dst, let src):
            r[base + dst] = EngineValue.negate(r[base + src])
        case .binary(let op, let dst, let lhs, let rhs):
            r[base + dst] = EngineValue.binary(op, r[base + lhs], r[base + rhs])
        case .call1(let id, let dst, let a):
            r[base + dst] = Builtins.evaluateValue(id, r[base + a], .float(0), .float(0))
        case .call2(let id, let dst, let a, let b):
            r[base + dst] = Builtins.evaluateValue(id, r[base + a], r[base + b], .float(0))
        case .call3(let id, let dst, let a, let b, let c):
            r[base + dst] = Builtins.evaluateValue(id, r[base + a], r[base + b], r[base + c])
        case .construct2(let dst, let a, let b):
            r[base + dst] = EngineValue.construct2(r[base + a].scalar, r[base + b].scalar)
        case .construct3(let dst, let a, let b, let c):
            r[base + dst] = EngineValue.construct3(r[base + a].scalar, r[base + b].scalar, r[base + c].scalar)
        case .construct4(let dst, let a, let b, let c, let d):
            r[base + dst] = EngineValue.construct4(r[base + a].scalar, r[base + b].scalar, r[base + c].scalar, r[base + d].scalar)
        case .splat(let dst, let src, let width):
            r[base + dst] = EngineValue.splat(width, r[base + src].scalar)
        case .swizzle(let dst, let src, let i0, let i1, let i2, let i3, let count):
            r[base + dst] = EngineValue.swizzle(r[base + src], i0, i1, i2, i3, count: count)
        }
    }
}

/// Evaluate all outputs, in source order. The register scratch stays on the
/// stack; only the returned array allocates.
func runTapeValues(_ tape: Tape, _ inputs: [String: Float]) throws(EvalError) -> [EngineValue] {
    let inputCount = tape.inputOrder.count
    let total = inputCount + tape.registerCount
    var missing: String? = nil
    var result = [EngineValue](repeating: .float(0), count: tape.outputRegisters.count)

    withUnsafeTemporaryAllocation(of: EngineValue.self, capacity: total) { scratch in
        var i = 0
        while i < inputCount {
            let name = tape.inputOrder[i]
            if let value = inputs[name] { scratch[i] = .float(value) } else { missing = name; return }
            i += 1
        }
        executeValues(tape, into: scratch, base: inputCount)
        for (k, output) in tape.outputRegisters.enumerated() {
            result[k] = scratch[inputCount + output.register]
        }
    }

    if let missing { throw EvalError.missingInput(missing) }
    return result
}
