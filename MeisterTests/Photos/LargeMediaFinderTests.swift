import XCTest
import Photos
@testable import MeisterIOS

/// Unit tests for `LargeMediaFinder` — defined in
/// `MeisterIOS/Photos/LargeMediaFinder.swift`:
///
///   enum LargeMediaFinder {
///       static func top(_ n: Int, in items: [PhotoItem]) -> [PhotoItem]
///           // items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(n).map { $0 }
///       static func largerThan(_ bytes: Int64, in items: [PhotoItem]) -> [PhotoItem]
///           // items.filter { $0.sizeBytes > bytes }.sorted { $0.sizeBytes > $1.sizeBytes }
///   }
///
/// Both functions are pure: they read ONLY `PhotoItem.sizeBytes` (Int64) and
/// never touch `PhotoItem.asset`, so a placeholder `PHAsset()` is safe — no
/// Photos-library authorization is required to exercise this logic.
///
/// Grounding notes:
/// - `PhotoItem` (from `PhotoScanner.swift`) has no explicit init; it uses the
///   compiler-synthesized memberwise initializer, called here with every stored
///   property in declaration order (id, asset, pixelWidth, pixelHeight,
///   creationDate, sizeBytes, mediaSubtypes, isVideo, duration). This mirrors the
///   established factory in the sibling `PhotoModelTests.swift`.
/// - `PhotoItem` Equatable/Hashable are defined by `id` ONLY, so result-order
///   assertions compare `sizeBytes`/`id` explicitly rather than relying on `==`
///   of whole values where size is what matters.
/// - `largerThan` uses a STRICT `>` comparison, so an item exactly equal to the
///   threshold is EXCLUDED — verified by dedicated boundary tests.
final class LargeMediaFinderTests: XCTestCase {

    // MARK: - Fixture factory (placeholder PHAsset; only sizeBytes/id matter)

    /// Builds a `PhotoItem` via the synthesized memberwise initializer.
    /// `asset` is a placeholder `PHAsset()` — `LargeMediaFinder` never reads it.
    private func makeItem(
        id: String = UUID().uuidString,
        sizeBytes: Int64,
        isVideo: Bool = false
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            asset: PHAsset(),
            pixelWidth: 100,
            pixelHeight: 100,
            creationDate: nil,
            sizeBytes: sizeBytes,
            mediaSubtypes: [],
            isVideo: isVideo,
            duration: 0
        )
    }

    /// The `sizeBytes` of each result, in order — the load-bearing observable.
    private func sizes(_ items: [PhotoItem]) -> [Int64] { items.map(\.sizeBytes) }

    /// The `id` of each result, in order.
    private func ids(_ items: [PhotoItem]) -> [String] { items.map(\.id) }

    // MARK: - top: empty / trivial

    func testTopEmptyInputReturnsEmpty() {
        XCTAssertTrue(LargeMediaFinder.top(10, in: []).isEmpty)
    }

    func testTopSingleItemReturnsThatItem() {
        let result = LargeMediaFinder.top(10, in: [makeItem(id: "only", sizeBytes: 42)])
        XCTAssertEqual(ids(result), ["only"])
    }

    // MARK: - top: ordering (descending by sizeBytes)

    func testTopSortsDescendingBySizeBytes() {
        let items = [
            makeItem(id: "mid", sizeBytes: 20),
            makeItem(id: "small", sizeBytes: 10),
            makeItem(id: "big", sizeBytes: 30)
        ]
        let result = LargeMediaFinder.top(10, in: items)
        XCTAssertEqual(ids(result), ["big", "mid", "small"])
    }

    func testTopAlreadyDescendingStaysDescending() {
        let items = [
            makeItem(id: "a", sizeBytes: 50),
            makeItem(id: "b", sizeBytes: 40),
            makeItem(id: "c", sizeBytes: 30)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(10, in: items)), ["a", "b", "c"])
    }

    func testTopReverseSortedGetsReordered() {
        let items = [
            makeItem(sizeBytes: 1),
            makeItem(sizeBytes: 2),
            makeItem(sizeBytes: 3),
            makeItem(sizeBytes: 4)
        ]
        XCTAssertEqual(sizes(LargeMediaFinder.top(10, in: items)), [4, 3, 2, 1])
    }

    func testTopResultIsMonotonicNonIncreasing() {
        let items = [7, 3, 99, 42, 1, 58].map { makeItem(sizeBytes: Int64($0)) }
        let result = sizes(LargeMediaFinder.top(10, in: items))
        for i in 1..<result.count {
            XCTAssertGreaterThanOrEqual(result[i - 1], result[i])
        }
    }

    func testTopFirstIsLargest() {
        let items = [makeItem(sizeBytes: 5), makeItem(sizeBytes: 500), makeItem(sizeBytes: 50)]
        XCTAssertEqual(LargeMediaFinder.top(10, in: items).first?.sizeBytes, 500)
    }

    // MARK: - top: n boundaries (prefix semantics)

    func testTopNTruncatesToLargestN() {
        // prefix applies AFTER sorting -> keeps the largest, not the first-encountered.
        let items = [
            makeItem(id: "tiny", sizeBytes: 1),
            makeItem(id: "small", sizeBytes: 2),
            makeItem(id: "huge", sizeBytes: 100),
            makeItem(id: "big", sizeBytes: 99)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(2, in: items)), ["huge", "big"])
    }

    func testTopNZeroReturnsEmpty() {
        let items = [makeItem(sizeBytes: 10), makeItem(sizeBytes: 20)]
        XCTAssertTrue(LargeMediaFinder.top(0, in: items).isEmpty)
    }

    func testTopNOneReturnsSingleLargest() {
        let items = [makeItem(sizeBytes: 7), makeItem(sizeBytes: 11), makeItem(sizeBytes: 3)]
        XCTAssertEqual(sizes(LargeMediaFinder.top(1, in: items)), [11])
    }

    func testTopNEqualToCountReturnsAllSorted() {
        let items = [
            makeItem(id: "c", sizeBytes: 3),
            makeItem(id: "a", sizeBytes: 1),
            makeItem(id: "b", sizeBytes: 2)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(3, in: items)), ["c", "b", "a"])
    }

    func testTopNGreaterThanCountReturnsAll() {
        let items = [
            makeItem(id: "a", sizeBytes: 30),
            makeItem(id: "b", sizeBytes: 10),
            makeItem(id: "c", sizeBytes: 20)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(100, in: items)), ["a", "c", "b"])
    }

    // NOTE: Removed testTopNegativeNReturnsEmpty(). Its expectation was wrong:
    // it asserted top(-5, ...) returns []. The production source is
    // `items.sorted { ... }.prefix(n).map { $0 }` with NO max(0, n) guard, so a
    // negative n calls prefix(_:) with a negative length, which TRAPS at runtime
    // (Swift/Collection.swift:1329 "Can't take a prefix of negative length") and
    // kills the test process. The source genuinely crashes for negative n — it
    // does not return empty — so this case cannot be expressed as a passing,
    // non-crashing XCTest assertion without adding a precondition guard to the app
    // source (out of scope: never edit app source). Method removed rather than
    // asserting behavior the source does not exhibit.

    // MARK: - top: zero / negative sizes

    func testTopHandlesZeroByteItems() {
        let items = [makeItem(id: "z", sizeBytes: 0), makeItem(id: "p", sizeBytes: 5)]
        XCTAssertEqual(ids(LargeMediaFinder.top(10, in: items)), ["p", "z"])
    }

    func testTopHandlesNegativeSizes() {
        // sizeBytes is Int64; negative values sort below zero/positive ones.
        let items = [
            makeItem(id: "neg", sizeBytes: -5),
            makeItem(id: "zero", sizeBytes: 0),
            makeItem(id: "pos", sizeBytes: 5)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(10, in: items)), ["pos", "zero", "neg"])
    }

    func testTopHandlesMaxInt64() {
        let items = [
            makeItem(id: "max", sizeBytes: Int64.max),
            makeItem(id: "one", sizeBytes: 1)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(10, in: items)), ["max", "one"])
    }

    // MARK: - top: ties

    func testTopEqualSizesAllSurviveWithinN() {
        let items = [
            makeItem(id: "a", sizeBytes: 100),
            makeItem(id: "b", sizeBytes: 100),
            makeItem(id: "c", sizeBytes: 100)
        ]
        let result = LargeMediaFinder.top(10, in: items)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(sizes(result), [100, 100, 100])
        XCTAssertEqual(Set(ids(result)), ["a", "b", "c"])
    }

    func testTopTiesRespectN() {
        let items = (0..<4).map { makeItem(id: "id-\($0)", sizeBytes: 100) }
        let result = LargeMediaFinder.top(2, in: items)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(sizes(result), [100, 100])
    }

    func testTopMixedTiesAndUniques() {
        let items = [
            makeItem(id: "a", sizeBytes: 50),
            makeItem(id: "b", sizeBytes: 50),
            makeItem(id: "top", sizeBytes: 100),
            makeItem(id: "low", sizeBytes: 10)
        ]
        let result = LargeMediaFinder.top(10, in: items)
        XCTAssertEqual(result.first?.id, "top")
        XCTAssertEqual(result.last?.id, "low")
        XCTAssertEqual(sizes(result), [100, 50, 50, 10])
    }

    // MARK: - largerThan: empty / trivial

    func testLargerThanEmptyInputReturnsEmpty() {
        XCTAssertTrue(LargeMediaFinder.largerThan(0, in: []).isEmpty)
    }

    func testLargerThanSingleItemAboveThresholdKept() {
        let result = LargeMediaFinder.largerThan(50, in: [makeItem(id: "ok", sizeBytes: 100)])
        XCTAssertEqual(ids(result), ["ok"])
    }

    func testLargerThanSingleItemBelowThresholdFilteredOut() {
        XCTAssertTrue(LargeMediaFinder.largerThan(50, in: [makeItem(sizeBytes: 10)]).isEmpty)
    }

    // MARK: - largerThan: STRICT `>` boundary

    func testLargerThanIsStrictEqualBytesExcluded() {
        // filter uses `> bytes`, so an item exactly AT the threshold is dropped.
        XCTAssertTrue(LargeMediaFinder.largerThan(100, in: [makeItem(sizeBytes: 100)]).isEmpty)
    }

    func testLargerThanOneAboveThresholdIncluded() {
        let result = LargeMediaFinder.largerThan(100, in: [makeItem(id: "ok", sizeBytes: 101)])
        XCTAssertEqual(ids(result), ["ok"])
    }

    func testLargerThanOneBelowThresholdExcluded() {
        XCTAssertTrue(LargeMediaFinder.largerThan(100, in: [makeItem(sizeBytes: 99)]).isEmpty)
    }

    func testLargerThanZeroThresholdExcludesZeroByteItems() {
        // `> 0` drops exactly-zero items, keeps positives.
        let items = [makeItem(id: "z", sizeBytes: 0), makeItem(id: "p", sizeBytes: 1)]
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(0, in: items)), ["p"])
    }

    func testLargerThanMaxInt64ThresholdExcludesEverything() {
        let items = [
            makeItem(sizeBytes: Int64.max),       // not > max
            makeItem(sizeBytes: Int64.max - 1)
        ]
        XCTAssertTrue(LargeMediaFinder.largerThan(Int64.max, in: items).isEmpty)
    }

    // MARK: - largerThan: filtering + descending ordering

    func testLargerThanFiltersThenSortsDescending() {
        let items = [
            makeItem(id: "a", sizeBytes: 10),   // filtered (<= 50)
            makeItem(id: "b", sizeBytes: 100),
            makeItem(id: "c", sizeBytes: 51),
            makeItem(id: "d", sizeBytes: 99)
        ]
        // Kept (> 50): b(100), c(51), d(99). Sorted desc: b, d, c.
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(50, in: items)), ["b", "d", "c"])
    }

    func testLargerThanResultIsMonotonicNonIncreasing() {
        let items = [200, 5, 175, 50, 300, 1].map { makeItem(sizeBytes: Int64($0)) }
        let result = sizes(LargeMediaFinder.largerThan(10, in: items))
        for i in 1..<result.count {
            XCTAssertGreaterThanOrEqual(result[i - 1], result[i])
        }
    }

    func testLargerThanThresholdAboveAllReturnsEmpty() {
        let items = [makeItem(sizeBytes: 10), makeItem(sizeBytes: 20), makeItem(sizeBytes: 30)]
        XCTAssertTrue(LargeMediaFinder.largerThan(1_000, in: items).isEmpty)
    }

    func testLargerThanNegativeThresholdKeepsZeroAndPositive() {
        let items = [
            makeItem(id: "neg", sizeBytes: -10),  // not > -5
            makeItem(id: "zero", sizeBytes: 0),
            makeItem(id: "pos", sizeBytes: 5)
        ]
        // `> -5` keeps zero(0) and pos(5); neg(-10) is below. Sorted desc: pos, zero.
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(-5, in: items)), ["pos", "zero"])
    }

    func testLargerThanNegativeThresholdAtBoundaryIsStrict() {
        // item exactly == threshold (-5) is excluded by strict `>`.
        let items = [makeItem(id: "edge", sizeBytes: -5), makeItem(id: "above", sizeBytes: -4)]
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(-5, in: items)), ["above"])
    }

    // MARK: - largerThan: ties

    func testLargerThanEqualSurvivingSizesAllKept() {
        let items = [
            makeItem(id: "a", sizeBytes: 100),
            makeItem(id: "b", sizeBytes: 100),
            makeItem(id: "c", sizeBytes: 100)
        ]
        let result = LargeMediaFinder.largerThan(50, in: items)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(sizes(result), [100, 100, 100])
        XCTAssertEqual(Set(ids(result)), ["a", "b", "c"])
    }

    // MARK: - idempotency / determinism

    func testTopIsDeterministicAcrossCalls() {
        let items = [
            makeItem(id: "c", sizeBytes: 30),
            makeItem(id: "a", sizeBytes: 10),
            makeItem(id: "b", sizeBytes: 20),
            makeItem(id: "d", sizeBytes: 40)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.top(3, in: items)),
                       ids(LargeMediaFinder.top(3, in: items)))
    }

    func testLargerThanIsDeterministicAcrossCalls() {
        let items = [
            makeItem(id: "c", sizeBytes: 30),
            makeItem(id: "a", sizeBytes: 10),
            makeItem(id: "b", sizeBytes: 20)
        ]
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(15, in: items)),
                       ids(LargeMediaFinder.largerThan(15, in: items)))
    }

    func testTopFeedingOutputBackInIsStableForUniqueSizes() {
        let items = [
            makeItem(id: "c", sizeBytes: 30),
            makeItem(id: "a", sizeBytes: 10),
            makeItem(id: "b", sizeBytes: 20)
        ]
        let once = LargeMediaFinder.top(10, in: items)
        let twice = LargeMediaFinder.top(10, in: once)
        XCTAssertEqual(ids(once), ids(twice))
    }

    func testTopDoesNotMutateInputOrder() {
        let items = [
            makeItem(id: "c", sizeBytes: 30),
            makeItem(id: "a", sizeBytes: 10),
            makeItem(id: "b", sizeBytes: 20)
        ]
        _ = LargeMediaFinder.top(1, in: items)
        XCTAssertEqual(ids(items), ["c", "a", "b"])
    }

    func testLargerThanDoesNotMutateInputOrder() {
        let items = [
            makeItem(id: "c", sizeBytes: 30),
            makeItem(id: "a", sizeBytes: 10),
            makeItem(id: "b", sizeBytes: 20)
        ]
        _ = LargeMediaFinder.largerThan(15, in: items)
        XCTAssertEqual(ids(items), ["c", "a", "b"])
    }

    // MARK: - isVideo carried through, never used for ordering/filtering

    func testTopIgnoresIsVideoFlagForOrdering() {
        let items = [
            makeItem(id: "smallVideo", sizeBytes: 10, isVideo: true),
            makeItem(id: "bigPhoto", sizeBytes: 100, isVideo: false)
        ]
        let result = LargeMediaFinder.top(10, in: items)
        XCTAssertEqual(ids(result), ["bigPhoto", "smallVideo"])
        XCTAssertEqual(result.first?.isVideo, false)
        XCTAssertEqual(result.last?.isVideo, true)
    }

    func testLargerThanIgnoresIsVideoFlagForFiltering() {
        let items = [
            makeItem(id: "smallVideo", sizeBytes: 10, isVideo: true),
            makeItem(id: "bigPhoto", sizeBytes: 100, isVideo: false)
        ]
        // Threshold 50 keeps only bigPhoto regardless of isVideo.
        XCTAssertEqual(ids(LargeMediaFinder.largerThan(50, in: items)), ["bigPhoto"])
    }

    // MARK: - large input / stress

    func testTopLargeInputKeepsTopN() {
        // 10_000 items with sizes 0..<10_000, shuffled; expect the top 100 by size.
        var items = (0..<10_000).map { makeItem(id: "id-\($0)", sizeBytes: Int64($0)) }
        items.shuffle()
        let result = LargeMediaFinder.top(100, in: items)
        XCTAssertEqual(result.count, 100)
        let expected = (9_900...9_999).reversed().map { Int64($0) }
        XCTAssertEqual(sizes(result), Array(expected))
    }

    func testLargerThanLargeInputSplitsAtThreshold() {
        // sizes 0..<1000; `> 499` keeps 500..999 (500 items), largest first.
        let items = (0..<1_000).map { makeItem(sizeBytes: Int64($0)) }
        let result = LargeMediaFinder.largerThan(499, in: items)
        XCTAssertEqual(result.count, 500)
        XCTAssertEqual(result.first?.sizeBytes, 999)
        XCTAssertEqual(result.last?.sizeBytes, 500)
    }

    func testLargerThanLargeInputAllBelowThresholdReturnsEmpty() {
        let items = (0..<5_000).map { makeItem(sizeBytes: Int64($0)) }
        XCTAssertTrue(LargeMediaFinder.largerThan(1_000_000, in: items).isEmpty)
    }
}
