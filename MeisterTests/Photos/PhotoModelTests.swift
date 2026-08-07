import XCTest
import Photos
@testable import MeisterIOS

/// Unit tests for `PhotoItem` — the lightweight `PHAsset` wrapper defined in
/// `MeisterIOS/Photos/PhotoScanner.swift`.
///
/// Grounding notes:
/// - The task brief named `PhotoItem.megapixels`, but no such symbol exists in
///   the source (verified by grep). It is NOT tested here — inventing it would
///   fail to compile.
/// - `PhotoItem` uses the compiler-synthesized memberwise initializer (the
///   source declares no custom `init`), reachable via `@testable import`.
/// - The pure, deterministic surface is: the stored properties (round-trip),
///   the computed `isScreenshot` (derived from the explicitly-passed
///   `mediaSubtypes`), the `Identifiable.id`, and the `Equatable`/`Hashable`
///   conformances — both keyed *solely* on `id` per the source:
///       static func == (lhs, rhs) -> Bool { lhs.id == rhs.id }
///       func hash(into:) { hasher.combine(id) }
/// - `PHAsset()` yields an empty placeholder. We only use it where the
///   initializer structurally requires a `PHAsset`; asserted behavior never
///   reads the asset's (unavailable) metadata, except the one conservative
///   `isBurst` check on a placeholder.
/// - Library-dependent symbols are intentionally SKIPPED — they need photo
///   authorization and real assets unavailable in a unit-test bundle:
///   `PhotoScanner.fetchAll`, `PhotoScanner.delete`, `PHAsset.estimatedSize`.
final class PhotoModelTests: XCTestCase {

    // MARK: - Fixture factory

    /// Builds a `PhotoItem` via the synthesized memberwise initializer.
    /// `asset` defaults to a placeholder `PHAsset()` since no asserted behavior
    /// (other than the dedicated `isBurst` test) reads from it.
    private func makeItem(
        id: String = "asset/1",
        asset: PHAsset = PHAsset(),
        pixelWidth: Int = 4032,
        pixelHeight: Int = 3024,
        creationDate: Date? = nil,
        sizeBytes: Int64 = 1_500_000,
        mediaSubtypes: PHAssetMediaSubtype = [],
        isVideo: Bool = false,
        duration: TimeInterval = 0
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            asset: asset,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            creationDate: creationDate,
            sizeBytes: sizeBytes,
            mediaSubtypes: mediaSubtypes,
            isVideo: isVideo,
            duration: duration
        )
    }

    // MARK: - Stored property round-trip

    func testStoredPropertiesRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let item = makeItem(
            id: "round/trip",
            pixelWidth: 1920,
            pixelHeight: 1080,
            creationDate: date,
            sizeBytes: 987_654,
            mediaSubtypes: .photoHDR,
            isVideo: true,
            duration: 12.5
        )
        XCTAssertEqual(item.id, "round/trip")
        XCTAssertEqual(item.pixelWidth, 1920)
        XCTAssertEqual(item.pixelHeight, 1080)
        XCTAssertEqual(item.creationDate, date)
        XCTAssertEqual(item.sizeBytes, 987_654)
        XCTAssertEqual(item.mediaSubtypes, .photoHDR)
        XCTAssertTrue(item.isVideo)
        XCTAssertEqual(item.duration, 12.5, accuracy: 0.0001)
    }

    func testCreationDateNilByDefault() {
        XCTAssertNil(makeItem().creationDate)
    }

    func testCreationDateEpochRoundTrip() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(makeItem(creationDate: date).creationDate, date)
    }

    func testCreationDateDistantPastRoundTrip() {
        XCTAssertEqual(makeItem(creationDate: .distantPast).creationDate, .distantPast)
    }

    // MARK: - isVideo / duration

    func testIsVideoTrue() {
        XCTAssertTrue(makeItem(isVideo: true).isVideo)
    }

    func testIsVideoFalse() {
        XCTAssertFalse(makeItem(isVideo: false).isVideo)
    }

    func testDurationZeroForPhoto() {
        XCTAssertEqual(makeItem(isVideo: false, duration: 0).duration, 0, accuracy: 0.0001)
    }

    func testDurationPositiveForVideo() {
        XCTAssertEqual(makeItem(isVideo: true, duration: 90.25).duration, 90.25, accuracy: 0.0001)
    }

    func testDurationLargeValueNotTruncated() {
        // 4-hour recording in seconds — guards against accidental truncation.
        XCTAssertEqual(makeItem(duration: 14_400).duration, 14_400, accuracy: 0.0001)
    }

    // MARK: - sizeBytes (signed Int64 boundaries, no validation in struct)

    func testSizeBytesZero() {
        XCTAssertEqual(makeItem(sizeBytes: 0).sizeBytes, 0)
    }

    func testSizeBytesNegativeStoredVerbatim() {
        // Signed Int64 with no validation — a negative input round-trips unchanged.
        XCTAssertEqual(makeItem(sizeBytes: -1).sizeBytes, -1)
    }

    func testSizeBytesInt64Max() {
        XCTAssertEqual(makeItem(sizeBytes: Int64.max).sizeBytes, Int64.max)
    }

    func testSizeBytesInt64Min() {
        XCTAssertEqual(makeItem(sizeBytes: Int64.min).sizeBytes, Int64.min)
    }

    // MARK: - pixel dimensions (Int boundaries)

    func testPixelDimensionsZero() {
        let item = makeItem(pixelWidth: 0, pixelHeight: 0)
        XCTAssertEqual(item.pixelWidth, 0)
        XCTAssertEqual(item.pixelHeight, 0)
    }

    func testPixelDimensionsLarge() {
        let item = makeItem(pixelWidth: 12_000, pixelHeight: 9_000)
        XCTAssertEqual(item.pixelWidth, 12_000)
        XCTAssertEqual(item.pixelHeight, 9_000)
    }

    func testPixelDimensionsNegativeStoredVerbatim() {
        let item = makeItem(pixelWidth: -1, pixelHeight: -2)
        XCTAssertEqual(item.pixelWidth, -1)
        XCTAssertEqual(item.pixelHeight, -2)
    }

    func testPixelDimensionsAsymmetric() {
        // Portrait vs landscape must not get swapped by the initializer.
        let item = makeItem(pixelWidth: 100, pixelHeight: 999)
        XCTAssertEqual(item.pixelWidth, 100)
        XCTAssertEqual(item.pixelHeight, 999)
    }

    // MARK: - isScreenshot (computed: mediaSubtypes.contains(.photoScreenshot))

    func testIsScreenshotTrueForScreenshotSubtype() {
        XCTAssertTrue(makeItem(mediaSubtypes: .photoScreenshot).isScreenshot)
    }

    func testIsScreenshotFalseForEmptySubtypes() {
        XCTAssertFalse(makeItem(mediaSubtypes: []).isScreenshot)
    }

    func testIsScreenshotFalseForUnrelatedSubtype() {
        XCTAssertFalse(makeItem(mediaSubtypes: .photoHDR).isScreenshot)
    }

    func testIsScreenshotTrueWhenCombinedWithOtherFlags() {
        // OptionSet membership must still report true when other flags are set.
        let combined: PHAssetMediaSubtype = [.photoScreenshot, .photoHDR]
        XCTAssertTrue(makeItem(mediaSubtypes: combined).isScreenshot)
    }

    func testIsScreenshotFalseWhenOnlyOtherFlagsSet() {
        let combined: PHAssetMediaSubtype = [.photoHDR, .photoPanorama]
        XCTAssertFalse(makeItem(mediaSubtypes: combined).isScreenshot)
    }

    func testIsScreenshotIdempotent() {
        // Computed property must yield a stable result across repeated reads.
        let item = makeItem(mediaSubtypes: .photoScreenshot)
        XCTAssertEqual(item.isScreenshot, item.isScreenshot)
        XCTAssertTrue(item.isScreenshot)
    }

    // MARK: - isBurst (computed: asset.representsBurst)

    func testIsBurstFalseForPlaceholderAsset() {
        // The only property that reads from the asset. A freshly constructed
        // placeholder `PHAsset` does not represent a burst — assert only this
        // conservative, deterministic behavior.
        XCTAssertFalse(makeItem(asset: PHAsset()).isBurst)
    }

    // MARK: - Identifiable

    func testIdMatchesStoredIdentifier() {
        XCTAssertEqual(makeItem(id: "ABC-123/L0/001").id, "ABC-123/L0/001")
    }

    func testIdEmptyString() {
        XCTAssertEqual(makeItem(id: "").id, "")
    }

    func testIdUnicode() {
        let unicodeId = "照片/📸/Ñoño/Æ"
        XCTAssertEqual(makeItem(id: unicodeId).id, unicodeId)
    }

    func testIdLongValue() {
        let longId = String(repeating: "x", count: 5_000)
        let item = makeItem(id: longId)
        XCTAssertEqual(item.id, longId)
        XCTAssertEqual(item.id.count, 5_000)
    }

    // MARK: - Equatable (== compares id only)

    func testEqualWhenIdsMatchDespiteDifferentFields() {
        let a = makeItem(id: "same", pixelWidth: 100)
        let b = makeItem(id: "same", pixelWidth: 999, isVideo: true)
        // Equality is keyed solely on `id`; differing non-id fields must not matter.
        XCTAssertEqual(a, b)
    }

    func testNotEqualWhenIdsDiffer() {
        XCTAssertNotEqual(makeItem(id: "left"), makeItem(id: "right"))
    }

    func testEqualReflexive() {
        let item = makeItem(id: "self")
        XCTAssertEqual(item, item)
    }

    func testEqualSymmetric() {
        let a = makeItem(id: "sym", sizeBytes: 1)
        let b = makeItem(id: "sym", sizeBytes: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, a)
    }

    func testEqualEmptyIds() {
        XCTAssertEqual(makeItem(id: ""), makeItem(id: ""))
    }

    func testNotEqualEmptyVsNonEmptyId() {
        XCTAssertNotEqual(makeItem(id: ""), makeItem(id: "x"))
    }

    func testEqualityCaseSensitiveOnId() {
        XCTAssertNotEqual(makeItem(id: "Asset"), makeItem(id: "asset"))
    }

    // MARK: - Hashable (hash combines id only)

    func testHashValueEqualForMatchingIds() {
        let a = makeItem(id: "hash", pixelWidth: 1)
        let b = makeItem(id: "hash", pixelWidth: 2, isVideo: true)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testHashConsistentWithEquality() {
        // Equal values must produce equal hashes (Hashable contract).
        let a = makeItem(id: "contract", sizeBytes: 10)
        let b = makeItem(id: "contract", sizeBytes: 20)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testHashStableAcrossReads() {
        let item = makeItem(id: "stable")
        XCTAssertEqual(item.hashValue, item.hashValue)
    }

    func testSetDeduplicatesByIdRegardlessOfOtherFields() {
        let a = makeItem(id: "dup", pixelWidth: 100, sizeBytes: 1)
        let b = makeItem(id: "dup", pixelWidth: 200, sizeBytes: 2)
        let c = makeItem(id: "unique")
        let set: Set<PhotoItem> = [a, b, c]
        // a and b collapse to one entry because they share an id.
        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(a))
        XCTAssertTrue(set.contains(b))
        XCTAssertTrue(set.contains(c))
    }

    func testSetKeepsDistinctIds() {
        let items = (0..<50).map { makeItem(id: "id-\($0)") }
        XCTAssertEqual(Set(items).count, 50)
    }

    // MARK: - mediaSubtypes round-trip

    func testMediaSubtypesEmptyByDefault() {
        XCTAssertEqual(makeItem().mediaSubtypes, [])
    }

    func testMediaSubtypesCombinedRoundTrip() {
        let combined: PHAssetMediaSubtype = [.photoScreenshot, .photoHDR, .videoTimelapse]
        let stored = makeItem(mediaSubtypes: combined).mediaSubtypes
        XCTAssertEqual(stored, combined)
        XCTAssertTrue(stored.contains(.photoScreenshot))
        XCTAssertTrue(stored.contains(.photoHDR))
        XCTAssertTrue(stored.contains(.videoTimelapse))
    }
}
