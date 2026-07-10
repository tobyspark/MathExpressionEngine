//
//  Sema.swift
//  FunctionEngine
//
//  Resolution + (trivial, for scalars) inference over the function body: derive
//  the node Interface (inputs + outputs) and report semantic diagnostics.
//  Free identifiers that aren't constants or locals become Float input ports in
//  first-appearance order; `out` declarations become outputs in source order.
//  Later slices grow this into the full type-constraint solver.
//

func analyze(_ body: Body) -> (interface: Interface, diagnostics: [Diagnostic]) {
    var diagnostics: [Diagnostic] = []
    var inputs: [String] = []
    var inputSeen = Set<String>()

    // All `let` names (used to classify a variable as local vs input).
    var letNames = Set<String>()
    for stmt in body.statements {
        if case .local(let name, _, _) = stmt { letNames.insert(name) }
    }

    var definedLocals = Set<String>()   // locals defined so far (source order)
    var declaredLocals = Set<String>()  // for duplicate detection
    var outputs: [OutputPort] = []
    var outputNamesSeen = Set<String>()

    func walk(_ e: Expr) {
        switch e {
        case .number:
            break

        case .variable(let name, let span):
            if Builtins.isConstant(name) { return }
            if letNames.contains(name) {
                if !definedLocals.contains(name) {
                    diagnostics.append(Diagnostic(code: .useBeforeDefinition, severity: .error,
                        message: "`\(name)` is used before it is defined.", span: span))
                }
                return
            }
            if inputSeen.insert(name).inserted { inputs.append(name) }

        case .negate(let x, _):
            walk(x)

        case .binary(_, let l, let r, _):
            walk(l); walk(r)

        case .call(let name, let args, let span):
            if let arity = Builtins.arities[name] {
                if args.count != arity {
                    let plural = arity == 1 ? "argument" : "arguments"
                    diagnostics.append(Diagnostic(code: .argumentCount, severity: .error,
                        message: "`\(name)` takes \(arity) \(plural), got \(args.count).", span: span))
                }
            } else if Builtins.isConstant(name) {
                diagnostics.append(Diagnostic(code: .unknownName, severity: .error,
                    message: "`\(name)` is a constant, not a function.", span: span))
            } else {
                diagnostics.append(Diagnostic(code: .unknownName, severity: .error,
                    message: "Unknown function `\(name)`.", span: span))
            }
            for a in args { walk(a) }
        }
    }

    for stmt in body.statements {
        switch stmt {
        case .local(let name, let value, let span):
            walk(value)
            if !declaredLocals.insert(name).inserted {
                diagnostics.append(Diagnostic(code: .duplicateBinding, severity: .error,
                    message: "`\(name)` is already defined.", span: span))
            }
            definedLocals.insert(name)

        case .output(let name, let value, let span):
            walk(value)
            if !outputNamesSeen.insert(name).inserted {
                diagnostics.append(Diagnostic(code: .duplicateOutput, severity: .error,
                    message: "Two outputs are both named `\(name)`.", span: span))
            }
            outputs.append(OutputPort(name: name, type: .float))
        }
    }

    return (Interface(inputs: inputs, outputs: outputs), diagnostics)
}
