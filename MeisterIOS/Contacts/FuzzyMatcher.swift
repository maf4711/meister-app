import Foundation

/// Similarity scoring for names and simple strings. Returns 0.0…1.0.
enum FuzzyMatcher {
    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let inter = Set(ta).intersection(tb).count
        let union = Set(ta).union(tb).count
        let jaccard = union == 0 ? 0 : Double(inter) / Double(union)
        let ca = canonicalize(a), cb = canonicalize(b)
        let lev = 1.0 - Double(levenshtein(ca, cb)) / Double(max(ca.count, cb.count, 1))
        return 0.6 * jaccard + 0.4 * lev
    }

    private static func tokens(_ s: String) -> [String] {
        canonicalize(s)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    /// Lowercase + normalize German umlauts to digraphs (ue/oe/ae/ss), then strip remaining diacritics.
    /// Ensures "Müller" ↔ "Mueller" match in fuzzy comparison.
    static func canonicalize(_ s: String) -> String {
        var out = s.lowercased()
        let pairs = [("ü", "ue"), ("ö", "oe"), ("ä", "ae"), ("ß", "ss")]
        for (k, v) in pairs { out = out.replacingOccurrences(of: k, with: v) }
        return out.folding(options: .diacriticInsensitive, locale: .current)
    }

    static func levenshtein(_ s: String, _ t: String) -> Int {
        let sArr = Array(s), tArr = Array(t)
        let (m, n) = (sArr.count, tArr.count)
        if m == 0 { return n } ; if n == 0 { return m }
        var prev = Array(0...n), curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = sArr[i - 1] == tArr[j - 1] ? 0 : 1
                curr[j] = Swift.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
