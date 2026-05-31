import XCTest
@testable import MeisterIOS

/// Tests for the pure keeper/reclaimable math behind duplicate cleanup.
/// Operates on a `SizedPhoto` stub (id + sizeBytes) so no PHAsset is needed.
final class KeeperSelectionTests: XCTestCase {

    private struct Stub: SizedPhoto {
        let id: String
        let sizeBytes: Int64
    }

    // MARK: reclaimableBytes

    func testReclaimableEmptyIsZero() {
        XCTAssertEqual(SimilarityClustering.reclaimableBytes([Stub](), keeperID: "x"), 0)
    }

    func testReclaimableExcludesKeeper() {
        let items = [Stub(id: "a", sizeBytes: 100), Stub(id: "b", sizeBytes: 50), Stub(id: "c", sizeBytes: 30)]
        // keeper = a → reclaim b + c
        XCTAssertEqual(SimilarityClustering.reclaimableBytes(items, keeperID: "a"), 80)
    }

    func testReclaimableKeeperIsNotNecessarilyLargest() {
        let items = [Stub(id: "a", sizeBytes: 100), Stub(id: "b", sizeBytes: 50)]
        // keeping the SMALLER file (the best shot) reclaims the larger one
        XCTAssertEqual(SimilarityClustering.reclaimableBytes(items, keeperID: "b"), 100)
    }

    func testReclaimableKeeperAbsentSumsAll() {
        let items = [Stub(id: "a", sizeBytes: 100), Stub(id: "b", sizeBytes: 50)]
        XCTAssertEqual(SimilarityClustering.reclaimableBytes(items, keeperID: "missing"), 150)
    }

    func testReclaimableSingleKeeperIsZero() {
        XCTAssertEqual(SimilarityClustering.reclaimableBytes([Stub(id: "a", sizeBytes: 100)], keeperID: "a"), 0)
    }

    // MARK: fallbackKeeperID

    func testFallbackEmptyIsNil() {
        XCTAssertNil(SimilarityClustering.fallbackKeeperID([Stub]()))
    }

    func testFallbackSingleIsThatItem() {
        XCTAssertEqual(SimilarityClustering.fallbackKeeperID([Stub(id: "only", sizeBytes: 7)]), "only")
    }

    func testFallbackPicksLargestBytes() {
        let items = [Stub(id: "a", sizeBytes: 50), Stub(id: "b", sizeBytes: 100), Stub(id: "c", sizeBytes: 30)]
        XCTAssertEqual(SimilarityClustering.fallbackKeeperID(items), "b")
    }

    func testFallbackTieBreaksToSmallerIdDeterministically() {
        let items = [Stub(id: "z", sizeBytes: 100), Stub(id: "a", sizeBytes: 100), Stub(id: "m", sizeBytes: 100)]
        // equal sizes → stable tie-break = smallest id
        XCTAssertEqual(SimilarityClustering.fallbackKeeperID(items), "a")
    }

    func testFallbackIsDeterministicAcrossInputOrder() {
        let a = [Stub(id: "a", sizeBytes: 50), Stub(id: "b", sizeBytes: 100)]
        let b = [Stub(id: "b", sizeBytes: 100), Stub(id: "a", sizeBytes: 50)]
        XCTAssertEqual(SimilarityClustering.fallbackKeeperID(a), SimilarityClustering.fallbackKeeperID(b))
    }
}
