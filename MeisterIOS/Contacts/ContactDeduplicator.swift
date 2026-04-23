import Foundation

enum ContactDeduplicator {
    /// Synchronous wrapper kept for tests and non-progress callers.
    static func dedupe(_ items: [ContactItem]) -> [ContactGroup] {
        var result: [ContactGroup] = []
        _ = dedupeSync(items, progress: { _, _ in }, collector: { result = $0 })
        return result
    }

    /// Async version that emits progress during the O(n²) name-similarity pass,
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
        func find(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = find(parent[i]); return parent[i] }() }
        func union(_ i: Int, _ j: Int) {
            let (ri, rj) = (find(i), find(j)); if ri != rj { parent[ri] = rj }
        }

        progress(0.05, "Indexing phone numbers")
        var phoneIdx: [String: [Int]] = [:]
        for (i, c) in items.enumerated() {
            for p in c.phones { phoneIdx[p, default: []].append(i) }
        }
        for (_, group) in phoneIdx where group.count > 1 {
            for j in 1..<group.count { union(group[0], group[j]) }
        }

        progress(0.15, "Indexing email addresses")
        var emailIdx: [String: [Int]] = [:]
        for (i, c) in items.enumerated() {
            for e in c.emails { emailIdx[e, default: []].append(i) }
        }
        for (_, group) in emailIdx where group.count > 1 {
            for j in 1..<group.count { union(group[0], group[j]) }
        }

        // Fuzzy name matching — the expensive part. Cap at 5000 to stay responsive.
        let named = items.enumerated().filter { !$0.element.fullName.isEmpty }
        if named.count <= 5000 {
            let pairs = named.count
            var done = 0
            for i in 0..<named.count {
                for j in (i + 1)..<named.count {
                    let (a, b) = (named[i].element, named[j].element)
                    if FuzzyMatcher.nameSimilarity(a.fullName, b.fullName) >= 0.85 {
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
