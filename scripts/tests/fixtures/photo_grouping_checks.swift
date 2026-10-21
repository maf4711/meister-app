import Foundation

@main struct PhotoGroupingChecks {
    struct Shot: CaptureTimed {
        let id: String
        let creationDate: Date?
    }

    static func equivalent(count: Int, threshold: Float, distance: (Int, Int) -> Float) {
        let expected = ReferencePhotoGrouping.groupIndices(count: count, threshold: threshold, distance: distance)
        var calls: [(Int, Int)] = []
        let actual = SimilarityClustering.groupIndices(count: count, threshold: threshold) { a, b in
            calls.append((a, b))
            return distance(a, b)
        }
        precondition(actual == expected, "Grouping changed: \(actual) vs \(expected)")
        let pairs = (0..<max(count, 0)).flatMap { i in ((i + 1)..<count).map { (i, $0) } }
        precondition(calls.elementsEqual(pairs, by: { $0.0 == $1.0 && $0.1 == $1.1 }),
                     "Distance evaluation count or order changed")
        for group in actual {
            precondition(group.count > 1 && group == group.sorted())
            for (i, a) in group.enumerated() {
                for b in group.dropFirst(i + 1) {
                    precondition(distance(a, b) < threshold, "Cluster exceeded the diameter cap")
                }
            }
        }
    }

    static func checks() {
        let shots = [0, 50, 100, 150].map { Shot(id: String($0), creationDate: Date(timeIntervalSince1970: Double($0))) }
        let timed = SimilarityClustering.splitByCaptureWindow(Array(shots.reversed()), window: 60)
        precondition(timed.map { $0.map(\.id) } == [["0", "50"], ["100", "150"]],
                     "Adjacent captures must not chain beyond the full capture window")
        precondition(SimilarityClustering.splitByCaptureWindow([Shot(id: "missing", creationDate: nil)]).isEmpty)
        let boundary = [Shot(id: "first", creationDate: Date(timeIntervalSince1970: 0)),
                        Shot(id: "last", creationDate: Date(timeIntervalSince1970: 60))]
        precondition(SimilarityClustering.splitByCaptureWindow(boundary).count == 1)
        for count in 0...2 {
            equivalent(count: count, threshold: 0.5, distance: { _, _ in 0.2 })
        }
        // NaN previously behaved like a zero distance and could create unsafe groups.
        for invalid: Float in [.nan, .infinity, -.infinity] {
            precondition(SimilarityClustering.groupIndices(count: 2, threshold: 0.5) { _, _ in invalid }.isEmpty,
                         "Invalid distances must never imply duplicate photos")
        }
        let tieDistance: (Int, Int) -> Float = { a, b in a == 1 && b == 2 ? 1 : 0 }
        equivalent(count: 4, threshold: 0.5, distance: tieDistance)
        precondition(SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: tieDistance) ==
                     [[0, 1], [2, 3]], "Merge order changed the tie break")
        let staleNearest: [[Int]: Float] = [[2, 3]: 0, [0, 2]: 0.1, [0, 3]: 1,
                                          [0, 1]: 0.2, [1, 2]: 1, [1, 3]: 1]
        equivalent(count: 4, threshold: 0.5) { staleNearest[[$0, $1]]! }
        equivalent(count: 3, threshold: 0.5) { _, _ in 0 }
        equivalent(count: 3, threshold: 0.5) { a, b in a == 0 && b == 2 ? -0.1 : -Float.zero }
        equivalent(count: 3, threshold: 0.5) { a, b in a == 0 && b == 2 ? .greatestFiniteMagnitude : 0.1 }
        let partlyInvalid = SimilarityClustering.groupIndices(count: 3, threshold: 0.5) { a, b in
            a == 0 && b == 2 ? .nan : 0.1
        }
        precondition(partlyInvalid == [[0, 1]], "An invalid cross-pair must block a larger merge")
        equivalent(count: 7, threshold: 0.5) { a, b in b == a + 1 ? 0.1 : 0.9 }
        equivalent(count: 8, threshold: 0.5) { a, b in a / 3 == b / 3 ? 0.1 : 0.9 }
        for threshold: Float in [-1, 0, 0.1, 0.5, 1, .infinity, .nan] {
            equivalent(count: 6, threshold: threshold) { a, b in Float((a + b) % 5) / 10 }
        }

        // Exhaust all four-item matrices with three levels, including ties and the boundary.
        for code in 0..<729 {
            var value = code
            var matrix = [Float](repeating: 0, count: 16)
            for a in 0..<4 {
                for b in (a + 1)..<4 {
                    matrix[a * 4 + b] = [Float(0.1), 0.3, 0.5][value % 3]
                    value /= 3
                }
            }
            equivalent(count: 4, threshold: 0.5) { matrix[$0 * 4 + $1] }
        }
        var seed: UInt64 = 918273645
        for count in 3...24 {
            for _ in 0..<24 {
                var matrix = [Float](repeating: 0, count: count * count)
                for a in 0..<count {
                    for b in (a + 1)..<count {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        matrix[a * count + b] = Float((seed >> 32) % 11) / 10
                    }
                }
                equivalent(count: count, threshold: 0.5) { matrix[$0 * count + $1] }
            }
        }
        equivalent(count: 300, threshold: 0.5) { _, _ in 0.2 }
        print("Photo grouping checks passed: exhaustive ties, random matrices, diameter, invalid distances, calls")
    }

    static func benchmark() {
        let count = 500
        let workloads: [(String, (Int, Int) -> Float)] = [
            ("all-similar-500", { _, _ in 0.2 }),
            ("groups-of-five-500", { a, b in a / 5 == b / 5 ? 0.1 : 0.9 }),
            ("chain-500", { a, b in b == a + 1 ? 0.1 : 0.9 }),
            ("all-distinct-500", { _, _ in 0.9 }),
        ]
        for (name, distance) in workloads {
            equivalent(count: count, threshold: 0.5, distance: distance)
            var before: [Double] = [], after: [Double] = []
            func measure(_ operation: () -> [[Int]]) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = operation()
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                precondition(result.count <= count / 2)
                return elapsed
            }
            for iteration in 0..<3 {
                if iteration % 2 == 0 {
                    before.append(measure { ReferencePhotoGrouping.groupIndices(count: count, threshold: 0.5, distance: distance) })
                    after.append(measure { SimilarityClustering.groupIndices(count: count, threshold: 0.5, distance: distance) })
                } else {
                    after.append(measure { SimilarityClustering.groupIndices(count: count, threshold: 0.5, distance: distance) })
                    before.append(measure { ReferencePhotoGrouping.groupIndices(count: count, threshold: 0.5, distance: distance) })
                }
            }
            let baseline = before.sorted()[1], optimized = after.sorted()[1]
            print("\(name): baseline_ms=\(baseline) optimized_ms=\(optimized) speedup=\(baseline / optimized)")
            fflush(stdout)
        }
        print("distance_cache_bytes: baseline=\(count * count * MemoryLayout<Float>.stride) optimized=\(count * (count - 1) / 2 * MemoryLayout<Float>.stride)")
    }

    static func main() {
        if CommandLine.arguments.contains("--benchmark") { benchmark() }
        else { checks() }
    }
}
