//
//  Tape.swift
//  FunctionEngine
//
//  The flat POD bytecode: a register machine. Lowering turns the typed AST into
//  a linear array of trivially-copyable `Instr` addressing a register file by
//  index, plus a constant pool and an ordered input list. There are no classes,
//  no closures, and no strings in the instruction stream — so `Tape` is
//  `Sendable` and the eval loop touches no ARC.
//
//  The eval loop uses `withUnsafeTemporaryAllocation` for the combined
//  input + register scratch, so a typical scalar evaluation makes NO heap
//  allocation (small scratch is stack-allocated). Moving to `InlineArray`
//  and SIMD kernels is a later slice (DESIGN-FunctionNode-Engine.md §9).
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
    let inputOrder: [String]   // inputIndex → name
    let registerCount: Int
    let resultRegister: Int
}

/// Lowers an `Expr` to a `Tape`. Each subexpression's result is written to a
/// fresh register (SSA-like); simple and correct. Register reuse is a later
/// optimization and doesn't affect results.
private struct Lowerer {
    var instructions: [Instr] = []
    var constants: [Float] = []
    var inputIndex: [String: Int] = [:]
    var inputOrder: [String] = []
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

    /// Lower `e`, returning the register that will hold its value.
    mutating func lower(_ e: Expr) -> Int {
        switch e {
        case .number(let value, _):
            let dst = newRegister()
            instructions.append(.loadConst(dst: dst, constIndex: constSlot(value)))
            return dst

        case .variable(let name, _):
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
            // Sema guarantees the name is a known builtin with the right arity
            // before we lower; fall back to a NaN constant if that ever breaks,
            // rather than trapping.
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

/// Lower a typed AST to a `Tape`.
func lower(_ ast: Expr) -> Tape {
    var lowerer = Lowerer()
    let result = lowerer.lower(ast)
    return Tape(
        instructions: lowerer.instructions,
        constants: lowerer.constants,
        inputOrder: lowerer.inputOrder,
        registerCount: lowerer.nextRegister,
        resultRegister: result
    )
}

/// Execute a tape against a set of input values. Throws `.missingInput` if a
/// required input is absent. The dispatch loop is a `switch` over POD
/// instructions operating on a stack-allocated scratch buffer — no heap
/// allocation, no ARC, no closures in the loop.
///
/// The scratch holds the resolved inputs at `[0, inputCount)` and the register
/// file at `[inputCount, inputCount + registerCount)`. Input resolution can fail
/// (missing input), so it records the offending name and bails without throwing
/// *inside* the allocation closure — keeping `withUnsafeTemporaryAllocation`
/// non-throwing (it is `rethrows`, which would otherwise erase the typed error).
func runTape(_ tape: Tape, _ inputs: [String: Float]) throws(EvalError) -> Float {
    let inputCount = tape.inputOrder.count
    let total = inputCount + tape.registerCount

    var missing: String? = nil

    let result = withUnsafeTemporaryAllocation(of: Float.self, capacity: total) { scratch -> Float in
        // Resolve inputs into the front of the scratch (index == loadInput.inputIndex).
        var i = 0
        while i < inputCount {
            let name = tape.inputOrder[i]
            if let value = inputs[name] {
                scratch[i] = value
            } else {
                missing = name
                return .nan   // bail without throwing; the throw happens after the closure
            }
            i += 1
        }

        let base = inputCount   // registers live after the inputs

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

        return scratch[base + tape.resultRegister]
    }

    if let missing { throw EvalError.missingInput(missing) }
    return result
}
