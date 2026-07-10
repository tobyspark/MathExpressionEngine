//
//  Tape.swift
//  FunctionEngine
//
//  The flat POD bytecode: a register machine. Lowering turns the typed body into
//  a linear array of trivially-copyable `Instr` addressing a register file by
//  index, plus a constant pool, an ordered input list, and one result register
//  per output. No classes, closures, or strings in the instruction stream — so
//  `Tape` is `Sendable` and the eval loop touches no ARC.
//
//  The eval loop uses `withUnsafeTemporaryAllocation` for the combined
//  input + register scratch, so a typical scalar evaluation makes NO heap
//  allocation (small scratch is stack-allocated).
//

import Foundation

/// A single instruction. Payloads are register/constant/input indices and a
/// payload-free `FnID` — all trivial, so `Instr` is POD and `Sendable`.
enum Instr: Sendable {
    case loadConst(dst: Int, constIndex: Int)
    case loadInput(dst: Int, inputIndex: Int)
    case negate(dst: Int, src: Int)
    case binary(BinaryOp, dst: Int, lhs: Int, rhs: Int)
    case call1(FnID, dst: Int, a: Int)
    case call2(FnID, dst: Int, a: Int, b: Int)
    case call3(FnID, dst: Int, a: Int, b: Int, c: Int)
}

/// A compiled program in register-machine form.
struct Tape: Sendable {
    let instructions: [Instr]
    let constants: [Float]
    let inputOrder: [String]                               // inputIndex → name
    let registerCount: Int
    let outputRegisters: [(name: String, register: Int)]   // outputs in source order
}

/// Lowers a `Body` to a `Tape`. Each subexpression's result is written to a
/// fresh register (SSA-like); a `let` records its register so later references
/// reuse it directly. Register reuse is a later optimization and doesn't affect
/// results.
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

    /// Lower `e`, returning the register that will hold its value.
    mutating func lower(_ e: Expr) -> Int {
        switch e {
        case .number(let value, _):
            let dst = newRegister()
            instructions.append(.loadConst(dst: dst, constIndex: constSlot(value)))
            return dst

        case .variable(let name, _):
            if let reg = localRegister[name] { return reg }   // reference to a `let`
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

        case .call(let name, let args, _):
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

/// Lower a typed body to a `Tape`.
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

/// Run the instruction stream over a scratch buffer whose `[0, base)` prefix
/// already holds the resolved inputs; registers live at `[base, base + n)`.
private func execute(_ tape: Tape, into scratch: UnsafeMutableBufferPointer<Float>, base: Int) {
    for ins in tape.instructions {
        switch ins {
        case .loadConst(let dst, let ci):
            scratch[base + dst] = tape.constants[ci]
        case .loadInput(let dst, let ii):
            scratch[base + dst] = scratch[ii]
        case .negate(let dst, let src):
            scratch[base + dst] = -scratch[base + src]
        case .binary(let op, let dst, let lhs, let rhs):
            let a = scratch[base + lhs], b = scratch[base + rhs]
            switch op {
            case .add: scratch[base + dst] = a + b
            case .sub: scratch[base + dst] = a - b
            case .mul: scratch[base + dst] = a * b
            case .div: scratch[base + dst] = a / b
            case .mod: scratch[base + dst] = a.truncatingRemainder(dividingBy: b)
            case .pow: scratch[base + dst] = Float(pow(Double(a), Double(b)))
            }
        case .call1(let id, let dst, let a):
            scratch[base + dst] = Builtins.evaluate(id, scratch[base + a], 0, 0)
        case .call2(let id, let dst, let a, let b):
            scratch[base + dst] = Builtins.evaluate(id, scratch[base + a], scratch[base + b], 0)
        case .call3(let id, let dst, let a, let b, let c):
            scratch[base + dst] = Builtins.evaluate(id, scratch[base + a], scratch[base + b], scratch[base + c])
        }
    }
}

/// Evaluate the first output. Allocation-free (stack scratch).
func runTapeFirst(_ tape: Tape, _ inputs: [String: Float]) throws(EvalError) -> Float {
    let inputCount = tape.inputOrder.count
    let total = inputCount + tape.registerCount
    var missing: String? = nil

    let result = withUnsafeTemporaryAllocation(of: Float.self, capacity: total) { scratch -> Float in
        var i = 0
        while i < inputCount {
            let name = tape.inputOrder[i]
            if let value = inputs[name] { scratch[i] = value } else { missing = name; return .nan }
            i += 1
        }
        execute(tape, into: scratch, base: inputCount)
        return scratch[inputCount + tape.outputRegisters[0].register]
    }

    if let missing { throw EvalError.missingInput(missing) }
    return result
}

/// Evaluate all outputs, in source order. Allocates only the returned array;
/// the register scratch stays on the stack.
func runTapeAll(_ tape: Tape, _ inputs: [String: Float]) throws(EvalError) -> [Float] {
    let inputCount = tape.inputOrder.count
    let total = inputCount + tape.registerCount
    var missing: String? = nil
    var result = [Float](repeating: 0, count: tape.outputRegisters.count)

    withUnsafeTemporaryAllocation(of: Float.self, capacity: total) { scratch in
        var i = 0
        while i < inputCount {
            let name = tape.inputOrder[i]
            if let value = inputs[name] { scratch[i] = value } else { missing = name; return }
            i += 1
        }
        execute(tape, into: scratch, base: inputCount)
        for (k, output) in tape.outputRegisters.enumerated() {
            result[k] = scratch[inputCount + output.register]
        }
    }

    if let missing { throw EvalError.missingInput(missing) }
    return result
}
