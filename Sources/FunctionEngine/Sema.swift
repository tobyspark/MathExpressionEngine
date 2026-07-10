//
//  Sema.swift
//  FunctionEngine
//
//  Resolution + (trivial, for scalars) inference: derive the node Interface from
//  the expression. Free identifiers become Float input ports in first-appearance
//  order (deduplicated, constants excluded); calls are validated against the
//  builtin table. Later slices grow this into the full type-constraint solver.
//

func analyze(_ expr: Expr) -> (interface: Interface, diagnostics: [Diagnostic]) {
    var inputs: [String] = []
    var seen = Set<String>()
    var diagnostics: [Diagnostic] = []

    func walk(_ e: Expr) {
        switch e {
        case .number:
            break

        case .variable(let name, _):
            if Builtins.isConstant(name) { return }
            if seen.insert(name).inserted { inputs.append(name) }

        case .negate(let x, _):
            walk(x)

        case .binary(_, let l, let r, _):
            walk(l)
            walk(r)

        case .call(let name, let args, let span):
            if let arity = Builtins.arities[name] {
                if args.count != arity {
                    let plural = arity == 1 ? "argument" : "arguments"
                    diagnostics.append(Diagnostic(code: .argumentCount, severity: .error,
                                                  message: "`\(name)` takes \(arity) \(plural), got \(args.count).",
                                                  span: span))
                }
            } else if Builtins.isConstant(name) {
                diagnostics.append(Diagnostic(code: .unknownName, severity: .error,
                                              message: "`\(name)` is a constant, not a function.",
                                              span: span))
            } else {
                diagnostics.append(Diagnostic(code: .unknownName, severity: .error,
                                              message: "Unknown function `\(name)`.",
                                              span: span))
            }
            for arg in args { walk(arg) }
        }
    }

    walk(expr)
    return (Interface(inputs: inputs, outputType: .float), diagnostics)
}
