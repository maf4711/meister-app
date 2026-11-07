// Frozen grouping core from ea7f865; identical to the working source before optimization.
enum ReferencePhotoGrouping {
    static func groupIndices(
        count: Int,
        threshold: Float,
        distance: (Int, Int) -> Float
    ) -> [[Int]] {
        guard count > 1 else { return [] }

        // Cache the pairwise distances once — `distance` may be expensive (Vision).
        var dist = [Float](repeating: 0, count: count * count)
        for i in 0..<count {
            for j in (i + 1)..<count {
                let d = distance(i, j)
                dist[i * count + j] = d
                dist[j * count + i] = d
            }
        }

        // Complete-link agglomerative merge on the cached matrix. A merge of two
        // clusters is valid iff their max cross-pair distance is < threshold; by
        // induction every cluster therefore stays within the diameter cap.
        var clusters: [[Int]] = (0..<count).map { [$0] }
        func completeLink(_ a: [Int], _ b: [Int]) -> Float {
            var m: Float = 0
            for x in a { for y in b { let v = dist[x * count + y]; if v > m { m = v } } }
            return m
        }

        while true {
            var bestI = -1, bestJ = -1
            var bestDist = Float.greatestFiniteMagnitude
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let cl = completeLink(clusters[i], clusters[j])
                    guard cl < threshold else { continue }
                    // Deterministic: smallest linkage first, tie-broken by representative.
                    if cl < bestDist
                        || (cl == bestDist
                            && (clusters[i][0], clusters[j][0]) < (clusters[bestI][0], clusters[bestJ][0])) {
                        bestDist = cl; bestI = i; bestJ = j
                    }
                }
            }
            if bestI < 0 { break }
            let merged = (clusters[bestI] + clusters[bestJ]).sorted()
            clusters.remove(at: bestJ)   // j > i — remove the higher index first
            clusters.remove(at: bestI)
            clusters.append(merged)
        }

        return clusters
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }

}
