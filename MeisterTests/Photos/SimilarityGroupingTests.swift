import XCTest
@testable import MeisterIOS

/// Tests for the pure, deterministic grouping core extracted from
/// `SimilarityClustering.cluster(_:)`. No PHAsset / Vision required — the
/// distance function is injected, so single-link union-find behaviour is
/// verified in isolation.
final class SimilarityGroupingTests: XCTestCase {

    /// Distance helper: 0 between equal indices, otherwise driven by a lookup.
    private func dist(_ pairs: [[Int]: Float], default def: Float = 999) -> (Int, Int) -> Float {
        { a, b in
            if a == b { return 0 }
            let key = [min(a, b), max(a, b)]
            return pairs[key] ?? def
        }
    }

    func testEmptyReturnsNoGroups() {
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 0, threshold: 0.5) { _, _ in 0 }, [])
    }

    func testSingleItemReturnsNoGroups() {
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 1, threshold: 0.5) { _, _ in 0 }, [])
    }

    func testClosePairIsGrouped() {
        let d = dist([[0, 1]: 0.2])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 2, threshold: 0.5, distance: d), [[0, 1]])
    }

    func testDistanceEqualToThresholdIsNotGrouped() {
        // strict `<` — exactly the threshold must NOT merge
        let d = dist([[0, 1]: 0.5])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 2, threshold: 0.5, distance: d), [])
    }

    func testFarPairIsNotGrouped() {
        let d = dist([[0, 1]: 0.9])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 2, threshold: 0.5, distance: d), [])
    }

    func testTransitiveMergeViaChain() {
        // 0~1 and 1~2 are close, 0~2 is far → single-link still unites all three
        let d = dist([[0, 1]: 0.2, [1, 2]: 0.2, [0, 2]: 0.9])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 3, threshold: 0.5, distance: d), [[0, 1, 2]])
    }

    func testSingletonsAreExcluded() {
        // pair {0,1} close; 2 is far from everything → only the pair is returned
        let d = dist([[0, 1]: 0.1])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 3, threshold: 0.5, distance: d), [[0, 1]])
    }

    func testTwoDisjointClusters() {
        let d = dist([[0, 1]: 0.1, [2, 3]: 0.1])
        XCTAssertEqual(
            SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: d),
            [[0, 1], [2, 3]]
        )
    }

    func testOutputIsSortedAndDeterministic() {
        // close pair is {2,3}; result groups sorted by first index, indices sorted ascending
        let d = dist([[2, 3]: 0.1])
        let first = SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: d)
        let second = SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: d)
        XCTAssertEqual(first, [[2, 3]])
        XCTAssertEqual(first, second, "same input must yield identical output")
    }

    func testAllItemsOneCluster() {
        let d = dist([[0, 1]: 0.1, [0, 2]: 0.1, [1, 2]: 0.1])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 3, threshold: 0.5, distance: d), [[0, 1, 2]])
    }
}
