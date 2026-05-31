import XCTest
@testable import MeisterIOS

/// Tests for the pure, deterministic grouping core extracted from
/// `SimilarityClustering.cluster(_:)`. No PHAsset / Vision required — the
/// distance function is injected, so complete-link (diameter-capped)
/// clustering behaviour is verified in isolation.
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

    func testChainingIsPreventedByCompleteLink() {
        // 0~1 and 1~2 are close, but 0~2 is FAR. Single-link would chain all three
        // together (dragging the dissimilar #2 in → wrong delete). Complete-link
        // refuses: a cluster only forms if EVERY internal pair is within threshold.
        // Result: only the first valid pair {0,1} survives; #2 is a dropped singleton.
        let d = dist([[0, 1]: 0.2, [1, 2]: 0.2, [0, 2]: 0.9])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 3, threshold: 0.5, distance: d), [[0, 1]])
    }

    func testMutuallyCloseTripleFormsOneCluster() {
        // all three pairwise close → complete-link merges all (diameter < threshold)
        let d = dist([[0, 1]: 0.1, [0, 2]: 0.2, [1, 2]: 0.15])
        XCTAssertEqual(SimilarityClustering.groupIndices(count: 3, threshold: 0.5, distance: d), [[0, 1, 2]])
    }

    func testLongChainDoesNotCollapseToOneCluster() {
        // 0-1-2-3 consecutive close, but the ends are far apart. Single-link would
        // make one cluster of 4; complete-link must NOT (diameter would exceed t).
        let d = dist([[0, 1]: 0.1, [1, 2]: 0.1, [2, 3]: 0.1,
                      [0, 2]: 0.9, [0, 3]: 0.9, [1, 3]: 0.9])
        let groups = SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: d)
        XCTAssertFalse(groups.contains([0, 1, 2, 3]), "complete-link must not chain the whole line")
        for g in groups {
            // every returned cluster must be internally tight (diameter < threshold)
            for a in g { for b in g where a < b { XCTAssertLessThan(d(a, b), 0.5) } }
        }
    }

    func testDiameterCapSplitsAlmostCompleteCluster() {
        // {0,1,2} all close, but adding 3 would breach the diameter via 0~3.
        let d = dist([[0, 1]: 0.1, [0, 2]: 0.1, [1, 2]: 0.1,
                      [1, 3]: 0.2, [2, 3]: 0.2, [0, 3]: 0.9])
        let groups = SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: d)
        XCTAssertTrue(groups.contains([0, 1, 2]), "the tight triple stays together")
        XCTAssertFalse(groups.contains(where: { $0.contains(3) && $0.contains(0) }),
                       "3 must not join a cluster containing 0 (0~3 too far)")
    }

    func testDistanceFunctionCalledOncePerPair() {
        // The injected distance is expensive (Vision). It must be memoized:
        // exactly C(n,2) calls, never O(n^3).
        var calls = 0
        let base = dist([[0, 1]: 0.1, [0, 2]: 0.1, [1, 2]: 0.1])
        let counting: (Int, Int) -> Float = { a, b in calls += 1; return base(a, b) }
        _ = SimilarityClustering.groupIndices(count: 4, threshold: 0.5, distance: counting)
        XCTAssertEqual(calls, 6, "4 items → C(4,2)=6 distance evaluations")
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
