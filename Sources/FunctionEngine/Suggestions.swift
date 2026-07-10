//
//  Suggestions.swift
//  FunctionEngine
//
//  Small edit-distance helper for "did you mean …?" diagnostics.
//

/// Levenshtein edit distance.
func editDistance(_ s: String, _ t: String) -> Int {
    let a = Array(s), b = Array(t)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var prev = Array(0...b.count)
    var curr = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
        curr[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[b.count]
}

/// The nearest candidate within `maxDistance`, or nil.
func nearestName(_ name: String, _ candidates: [String], maxDistance: Int = 2) -> String? {
    var best: String? = nil
    var bestDistance = maxDistance + 1
    for candidate in candidates {
        let d = editDistance(name, candidate)
        if d < bestDistance {
            bestDistance = d
            best = candidate
        }
    }
    return best
}
