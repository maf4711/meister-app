import Foundation

/// Similarity scoring for names and simple strings. Returns 0.0…1.0.
enum FuzzyMatcher {
    /// Normalize once when comparing one name against many other contacts.
    struct PreparedName {
        let tokens: Set<String>
        fileprivate let characters: [Character]

        init(_ name: String) {
            let canonical = FuzzyMatcher.canonicalize(name)
            tokens = Set(canonical.components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty })
            characters = Array(canonical)
        }
    }

    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        nameSimilarity(PreparedName(a), PreparedName(b))
    }

    static func nameSimilarity(_ a: PreparedName, _ b: PreparedName) -> Double {
        guard !a.tokens.isEmpty, !b.tokens.isEmpty else { return 0 }
        return score(a, b, jaccard: tokenSimilarity(a, b))
    }

    /// Edit distance cannot contribute more than 0.4 to the combined score.
    /// Reject impossible matches before allocating the dynamic-programming rows.
    static func namesMatch(_ a: PreparedName, _ b: PreparedName, threshold: Double) -> Bool {
        guard !a.tokens.isEmpty, !b.tokens.isEmpty else { return 0 >= threshold }
        let jaccard = tokenSimilarity(a, b)
        guard 0.6 * jaccard + 0.4 >= threshold else { return false }
        return score(a, b, jaccard: jaccard) >= threshold
    }

    private static func tokenSimilarity(_ a: PreparedName, _ b: PreparedName) -> Double {
        let smaller = a.tokens.count <= b.tokens.count ? a.tokens : b.tokens
        let larger = a.tokens.count <= b.tokens.count ? b.tokens : a.tokens
        let intersection = smaller.reduce(0) { $0 + (larger.contains($1) ? 1 : 0) }
        let union = a.tokens.count + b.tokens.count - intersection
        return Double(intersection) / Double(union)
    }

    private static func score(_ a: PreparedName, _ b: PreparedName, jaccard: Double) -> Double {
        let lev = 1.0 - Double(levenshtein(a.characters, b.characters)) /
            Double(max(a.characters.count, b.characters.count, 1))
        return 0.6 * jaccard + 0.4 * lev
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
        levenshtein(Array(s), Array(t))
    }

    private static func levenshtein(_ s: [Character], _ t: [Character]) -> Int {
        if s == t { return 0 }
        // Only the shorter dimension needs to be retained in the two work rows.
        let (sArr, tArr) = s.count >= t.count ? (s, t) : (t, s)
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
