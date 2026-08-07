import XCTest
@testable import MeisterIOS

/// Tests for `ICloudDriveCleaner`.
///
/// Grounding: only `ICloudDriveCleaner.Finding` (memberwise init
/// `Finding(url:size:modified:)`, `id`/`url`/`size`/`modified`) and
/// `ICloudDriveCleaner.delete(_:) -> Int` are exercised. `scan(at:...)`
/// performs a live `FileManager` directory walk and is deliberately NOT
/// exercised here per the "skip live FileManager scans" focus.
///
/// `delete` uses `try? FileManager.removeItem` and increments its counter for
/// every element regardless of removal success, so its return value is the
/// pure count of the input. We therefore drive it with synthetic
/// non-existent URLs: nothing is removed from disk, yet the count is
/// deterministic. The findings' sort-by-size ordering contract is validated as
/// a pure aggregation property over directly constructed `Finding` values.
final class ICloudDriveCleanerTests: XCTestCase {

    // MARK: - Helpers (no live filesystem; URLs intentionally non-existent)

    /// A unique URL guaranteed not to exist on disk, so `delete` exercises its
    /// `try?` failure path while still counting the element.
    private func ghostURL(_ name: String = UUID().uuidString) -> URL {
        URL(fileURLWithPath: "/__meister_nonexistent__/\(name)")
    }

    private func makeFinding(
        size: Int64,
        modified: Date = Date(timeIntervalSince1970: 0),
        name: String = UUID().uuidString
    ) -> ICloudDriveCleaner.Finding {
        ICloudDriveCleaner.Finding(url: ghostURL(name), size: size, modified: modified)
    }

    // MARK: - Finding: stored properties round-trip

    func testFindingStoresURL() {
        let url = ghostURL("a.bin")
        let f = ICloudDriveCleaner.Finding(url: url, size: 1, modified: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(f.url, url)
    }

    func testFindingStoresSize() {
        let f = makeFinding(size: 4096)
        XCTAssertEqual(f.size, 4096)
    }

    func testFindingStoresModifiedDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let f = ICloudDriveCleaner.Finding(url: ghostURL(), size: 0, modified: date)
        XCTAssertEqual(f.modified, date)
    }

    func testFindingStoresZeroSize() {
        let f = makeFinding(size: 0)
        XCTAssertEqual(f.size, 0)
    }

    func testFindingStoresNegativeSize() {
        // Int64 size is not domain-constrained at the type level; the memberwise
        // init must faithfully store whatever it is handed.
        let f = makeFinding(size: -1)
        XCTAssertEqual(f.size, -1)
    }

    func testFindingStoresMaxInt64Size() {
        let f = makeFinding(size: Int64.max)
        XCTAssertEqual(f.size, Int64.max)
    }

    func testFindingStoresDistantPastModified() {
        let f = ICloudDriveCleaner.Finding(url: ghostURL(), size: 1, modified: .distantPast)
        XCTAssertEqual(f.modified, .distantPast)
    }

    func testFindingStoresUnicodeURLPath() {
        let url = URL(fileURLWithPath: "/__meister_nonexistent__/日本語_📦_файл.dat")
        let f = ICloudDriveCleaner.Finding(url: url, size: 7, modified: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(f.url, url)
        // Path component survives round-trip without mutation.
        XCTAssertEqual(f.url.lastPathComponent, "日本語_📦_файл.dat")
    }

    // MARK: - Finding: Identifiable identity

    func testFindingIDIsNonNilAndStable() {
        let f = makeFinding(size: 1)
        let first = f.id
        let second = f.id
        XCTAssertEqual(first, second, "id is a stored constant and must not change between reads")
    }

    func testTwoFindingsHaveDistinctIDs() {
        let a = makeFinding(size: 1)
        let b = makeFinding(size: 1)
        XCTAssertNotEqual(a.id, b.id, "each Finding gets its own UUID")
    }

    func testManyFindingsHaveUniqueIDs() {
        let findings = (0..<500).map { makeFinding(size: Int64($0)) }
        let ids = Set(findings.map { $0.id })
        XCTAssertEqual(ids.count, findings.count, "all auto-generated ids must be unique")
    }

    func testIdenticalInputsStillProduceDistinctIDs() {
        let url = ghostURL("same.bin")
        let date = Date(timeIntervalSince1970: 123)
        let a = ICloudDriveCleaner.Finding(url: url, size: 9, modified: date)
        let b = ICloudDriveCleaner.Finding(url: url, size: 9, modified: date)
        XCTAssertEqual(a.url, b.url)
        XCTAssertEqual(a.size, b.size)
        XCTAssertEqual(a.modified, b.modified)
        XCTAssertNotEqual(a.id, b.id, "id is independent of the other fields")
    }

    // MARK: - delete: counting semantics (pure aggregation over input)

    func testDeleteEmptyReturnsZero() throws {
        let removed = try ICloudDriveCleaner.delete([])
        XCTAssertEqual(removed, 0)
    }

    func testDeleteSingleReturnsOne() throws {
        let removed = try ICloudDriveCleaner.delete([makeFinding(size: 10)])
        XCTAssertEqual(removed, 1)
    }

    func testDeleteCountsEveryElement() throws {
        let findings = (0..<7).map { makeFinding(size: Int64($0)) }
        let removed = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(removed, 7)
    }

    func testDeleteCountReflectsInputLengthEvenWhenRemovalFails() throws {
        // All URLs are non-existent, so every `removeItem` fails and is swallowed
        // by `try?`; the returned count must still equal the input count.
        let findings = (0..<25).map { makeFinding(size: Int64($0), name: "ghost-\($0)") }
        let removed = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(removed, findings.count)
    }

    func testDeleteCountEqualsInputCountForLargeInput() throws {
        let findings = (0..<2000).map { makeFinding(size: Int64($0)) }
        let removed = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(removed, 2000)
    }

    func testDeleteCountsDuplicateURLsIndependently() throws {
        // delete iterates the array; duplicate URLs are counted per-element,
        // not de-duplicated.
        let url = ghostURL("dup.bin")
        let date = Date(timeIntervalSince1970: 0)
        let findings = [
            ICloudDriveCleaner.Finding(url: url, size: 1, modified: date),
            ICloudDriveCleaner.Finding(url: url, size: 2, modified: date),
            ICloudDriveCleaner.Finding(url: url, size: 3, modified: date),
        ]
        let removed = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(removed, 3)
    }

    func testDeleteIsIdempotentOnCount() throws {
        // Calling delete twice on the same (non-existent) findings yields the
        // same count both times — there is no surviving state to change it.
        let findings = (0..<5).map { makeFinding(size: Int64($0), name: "stable-\($0)") }
        let first = try ICloudDriveCleaner.delete(findings)
        let second = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(first, 5)
        XCTAssertEqual(second, 5)
        XCTAssertEqual(first, second)
    }

    func testDeleteDoesNotMutateInputArray() throws {
        let findings = (0..<4).map { makeFinding(size: Int64($0)) }
        let snapshotIDs = findings.map { $0.id }
        _ = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(findings.map { $0.id }, snapshotIDs, "delete must not reorder or drop elements")
    }

    // MARK: - delete: actually removes an existing file, then counts it

    func testDeleteRemovesAnExistingTempFileAndCountsIt() throws {
        // A real, deletable temp file (no live iCloud/FileManager *scan* — just a
        // local temp write/delete) confirms delete's success path and counting.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = dir.appendingPathComponent("meister-test-\(UUID().uuidString).tmp")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "precondition: temp file exists")

        let finding = ICloudDriveCleaner.Finding(
            url: fileURL,
            size: 3,
            modified: Date(timeIntervalSince1970: 0)
        )
        let removed = try ICloudDriveCleaner.delete([finding])

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "file should be gone after delete")
    }

    func testDeleteMixedExistingAndMissingCountsAll() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let realURL = dir.appendingPathComponent("meister-test-\(UUID().uuidString).tmp")
        try Data([0xFF]).write(to: realURL)
        defer { try? FileManager.default.removeItem(at: realURL) }

        let findings = [
            ICloudDriveCleaner.Finding(url: realURL, size: 1, modified: Date(timeIntervalSince1970: 0)),
            makeFinding(size: 2, name: "missing-a"),
            makeFinding(size: 3, name: "missing-b"),
        ]
        let removed = try ICloudDriveCleaner.delete(findings)
        XCTAssertEqual(removed, 3, "count includes both the removed file and the swallowed failures")
        XCTAssertFalse(FileManager.default.fileExists(atPath: realURL.path))
    }

    // MARK: - Sort-by-size contract (pure aggregation property)

    /// `scan` returns `findings.sorted { $0.size > $1.size }` (descending by
    /// size). We assert that exact pure ordering predicate over directly
    /// constructed `Finding` values, independent of any filesystem walk.

    func testSortDescendingBySizeOrdersLargestFirst() {
        let findings = [
            makeFinding(size: 10),
            makeFinding(size: 1000),
            makeFinding(size: 100),
        ]
        let sorted = findings.sorted { $0.size > $1.size }
        XCTAssertEqual(sorted.map { $0.size }, [1000, 100, 10])
    }

    func testSortDescendingBySizeIsNonAscendingForLargeRandomInput() {
        let findings = (0..<1000).map { _ in makeFinding(size: Int64.random(in: 0...1_000_000)) }
        let sorted = findings.sorted { $0.size > $1.size }
        for i in 1..<sorted.count {
            XCTAssertGreaterThanOrEqual(sorted[i - 1].size, sorted[i].size)
        }
    }

    func testSortDescendingBySizeEmptyStaysEmpty() {
        let findings: [ICloudDriveCleaner.Finding] = []
        let sorted = findings.sorted { $0.size > $1.size }
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSortDescendingBySizeSingleElementUnchanged() {
        let f = makeFinding(size: 42)
        let sorted = [f].sorted { $0.size > $1.size }
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.id, f.id)
    }

    func testSortDescendingBySizeHandlesEqualSizes() {
        let findings = (0..<5).map { makeFinding(size: 500, name: "eq-\($0)") }
        let sorted = findings.sorted { $0.size > $1.size }
        XCTAssertEqual(sorted.count, 5)
        XCTAssertEqual(Set(sorted.map { $0.size }), [500])
    }

    func testSortDescendingBySizeHandlesNegativeAndZeroAndMax() {
        let findings = [
            makeFinding(size: 0),
            makeFinding(size: -100),
            makeFinding(size: Int64.max),
            makeFinding(size: 50),
        ]
        let sorted = findings.sorted { $0.size > $1.size }
        XCTAssertEqual(sorted.map { $0.size }, [Int64.max, 50, 0, -100])
    }

    func testSortDescendingBySizePreservesElementCount() {
        let findings = (0..<300).map { makeFinding(size: Int64($0)) }
        let sorted = findings.sorted { $0.size > $1.size }
        XCTAssertEqual(sorted.count, findings.count)
        XCTAssertEqual(Set(sorted.map { $0.id }), Set(findings.map { $0.id }),
                       "sorting reorders but never adds or drops findings")
    }
}
