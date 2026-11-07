import Foundation

enum ContactDeduplicator {
    /// Synchronous wrapper kept for tests and non-progress callers.
    static func dedupe(_ items: [ContactItem]) -> [ContactGroup] {
        var result: [ContactGroup] = []
        _ = dedupeSync(items, progress: { _, _ in }, collector: { result = $0 })
        return result
    }

    /// Async version that emits progress during the name-similarity pass,
    /// so the UI can show "fuzzy name matching — 240/1000".
    static func dedupe(
        _ items: [ContactItem],
        progress: @Sendable @escaping (Double, String) -> Void
    ) async -> [ContactGroup] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [ContactGroup] = []
                _ = dedupeSync(items, progress: progress) { result = $0 }
                continuation.resume(returning: result)
            }
        }
    }

    private static func dedupeSync(
        _ items: [ContactItem],
        progress: (Double, String) -> Void,
        collector: ([ContactGroup]) -> Void
    ) -> Int {
        var parent = Array(0..<items.count)
        var sizes = [Int](repeating: 1, count: items.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root {
                parent[root] = parent[parent[root]]
                root = parent[root]
            }
            return root
        }
        func union(_ i: Int, _ j: Int) {
            var (ri, rj) = (find(i), find(j))
            guard ri != rj else { return }
            if sizes[ri] < sizes[rj] { swap(&ri, &rj) }
            parent[rj] = ri
            sizes[ri] += sizes[rj]
        }

        progress(0.05, "Indexing phone numbers")
        var phoneIdx: [String: Int] = [:]
        for (i, c) in items.enumerated() {
            for p in c.phones {
                if let first = phoneIdx[p] { union(first, i) }
                else { phoneIdx[p] = i }
            }
        }

        progress(0.15, "Indexing email addresses")
        var emailIdx: [String: Int] = [:]
        for (i, c) in items.enumerated() {
            for e in c.emails {
                if let first = emailIdx[e] { union(first, i) }
                else { emailIdx[e] = i }
            }
        }

        // Fuzzy name matching — the expensive part. Cap at 5000 to stay responsive.
        let named = items.enumerated().filter { !$0.element.fullName.isEmpty }
        if named.count <= 5000 {
            let prepared = named.map { FuzzyMatcher.PreparedName($0.element.fullName) }
            var tokenIndex: [String: [Int]] = [:]
            for (i, name) in prepared.enumerated() {
                for token in name.tokens { tokenIndex[token, default: []].append(i) }
            }
            let pairs = named.count
            var done = 0
            for i in 0..<named.count {
                // With no shared token the score is at most 0.4, below 0.85.
                // Keep candidates only for this contact, not every pair in the library.
                var candidates = Set<Int>()
                for token in prepared[i].tokens {
                    for j in tokenIndex[token, default: []] where j > i { candidates.insert(j) }
                }
                for j in candidates.sorted() {
                    guard find(named[i].offset) != find(named[j].offset) else { continue }
                    if FuzzyMatcher.namesMatch(prepared[i], prepared[j], threshold: 0.85) {
                        union(named[i].offset, named[j].offset)
                    }
                }
                done += 1
                if done % 20 == 0 || done == pairs {
                    progress(0.25 + 0.65 * Double(done) / Double(max(1, pairs)),
                             "Fuzzy name matching — \(done)/\(pairs)")
                }
            }
        } else {
            progress(0.5, "Skipping fuzzy match — library too large (\(named.count))")
        }

        progress(0.95, "Building groups")
        var clusters: [Int: [Int]] = [:]
        for i in 0..<items.count { clusters[find(i), default: []].append(i) }
        let groups = clusters.values
            .filter { $0.count > 1 }
            .map { indices in ContactGroup(items: indices.map { items[$0] }) }
            .sorted { $0.items.count > $1.items.count }
        collector(groups)
        progress(1.0, "Complete")
        return groups.count
    }
}
