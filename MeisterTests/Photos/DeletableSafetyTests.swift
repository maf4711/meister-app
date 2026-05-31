import XCTest
@testable import MeisterIOS

/// Data-loss safety tests for duplicate deletion. Verify that the deletion
/// candidate set never includes the keeper, never includes a protected
/// (favorite/edited) photo, and is empty when there's no valid keeper — and
/// that the keeper is preserved across in-session deletions. Pure, no PHAsset.
final class DeletableSafetyTests: XCTestCase {

    private struct Stub: DuplicateCandidate {
        let id: String
        let isProtected: Bool
        init(_ id: String, protected: Bool = false) { self.id = id; self.isProtected = protected }
    }

    // MARK: deletableIDs — keeper + protected exclusion + fail-safe

    func testExcludesKeeper() {
        let items = [Stub("a"), Stub("b"), Stub("c")]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "a"), ["b", "c"])
    }

    func testExcludesProtectedPhotos() {
        let items = [Stub("a"), Stub("b", protected: true), Stub("c")]
        // b is a favorite/edited photo → never deletable, even though it isn't the keeper
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "a"), ["c"])
    }

    func testKeeperItselfProtectedStillDeletesOthers() {
        let items = [Stub("a", protected: true), Stub("b"), Stub("c")]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "a"), ["b", "c"])
    }

    func testAllProtectedDeletesNothing() {
        let items = [Stub("a", protected: true), Stub("b", protected: true)]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "a"), [])
    }

    func testNilKeeperDeletesNothing() {
        // fail-safe: no valid keeper => never offer the whole group for deletion
        let items = [Stub("a"), Stub("b")]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: nil), [])
    }

    func testKeeperNotInItemsDeletesNothing() {
        // fail-safe: a keeperID that isn't present must NOT make the whole group deletable
        let items = [Stub("a"), Stub("b")]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "ghost"), [])
    }

    func testEmptyItems() {
        XCTAssertEqual(SimilarityClustering.deletableIDs([Stub](), keeperID: "a"), [])
    }

    func testPreservesInputOrder() {
        let items = [Stub("z"), Stub("y"), Stub("x")]
        XCTAssertEqual(SimilarityClustering.deletableIDs(items, keeperID: "y"), ["z", "x"])
    }

    // MARK: preservedKeeperID — keeper survival across delete()

    func testKeeperSurvivesDeletion() {
        // keeper "a" still present among survivors → keep it (no silent flip to fallback)
        XCTAssertEqual(
            SimilarityClustering.preservedKeeperID(current: "a", survivingIDs: ["a", "c"]),
            "a"
        )
    }

    func testKeeperDeletedFallsBackToNil() {
        // keeper "a" was deleted → nil so the Cluster re-derives a keeper
        XCTAssertNil(
            SimilarityClustering.preservedKeeperID(current: "a", survivingIDs: ["b", "c"])
        )
    }

    func testNilCurrentKeeperStaysNil() {
        XCTAssertNil(SimilarityClustering.preservedKeeperID(current: nil, survivingIDs: ["a"]))
    }
}
