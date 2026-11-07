import XCTest
@testable import MeisterIOS

/// Tests for the pure, filesystem-backed seams of `ContactBackup`.
///
/// Grounding notes:
/// - `exportAll()` is intentionally NOT tested: it constructs a live `CNContactStore`
///   and enumerates real contacts, which requires device authorization.
/// - Only `backupsDir` (path construction) and `listBackups()` (directory read + sort)
///   are exercised here. Both operate on the app's own documents directory, which is
///   available in the test host without any authorization.
final class ContactBackupTests: XCTestCase {

    /// File URLs created by an individual test, removed in tearDown so we never
    /// pollute the shared backups directory across runs.
    private var createdFiles: [URL] = []

    override func tearDownWithError() throws {
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdFiles = []
    }

    /// Creates a uniquely named file inside the real backups directory and tracks
    /// it for cleanup. Returns the URL it was written to.
    @discardableResult
    private func makeBackupFile(contents: String = "BEGIN:VCARD\nEND:VCARD\n") throws -> URL {
        let name = "test-\(UUID().uuidString).vcf"
        let url = ContactBackup.backupsDir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        createdFiles.append(url)
        return url
    }

    // MARK: - backupsDir

    func testBackupsDirLastComponentIsBackups() {
        XCTAssertEqual(ContactBackup.backupsDir.lastPathComponent, "backups")
    }

    func testBackupsDirIsUnderDocumentDirectory() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // The backups dir must be a direct child of the documents directory.
        XCTAssertEqual(
            ContactBackup.backupsDir.deletingLastPathComponent().standardizedFileURL,
            docs.standardizedFileURL
        )
    }

    func testBackupsDirIsStableAcrossCalls() {
        XCTAssertEqual(
            ContactBackup.backupsDir.standardizedFileURL,
            ContactBackup.backupsDir.standardizedFileURL
        )
    }

    func testBackupsDirIsCreatedOnAccess() {
        // Accessing the property has the side effect of creating the directory.
        let url = ContactBackup.backupsDir
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }

    func testBackupsDirPathIsNonEmpty() {
        XCTAssertFalse(ContactBackup.backupsDir.path.isEmpty)
    }

    // MARK: - listBackups: membership

    func testListBackupsIncludesACreatedFile() throws {
        let url = try makeBackupFile()
        let listed = ContactBackup.listBackups().map { $0.standardizedFileURL }
        XCTAssertTrue(listed.contains(url.standardizedFileURL))
    }

    func testListBackupsIncludesAllCreatedFiles() throws {
        let a = try makeBackupFile()
        let b = try makeBackupFile()
        let c = try makeBackupFile()
        let listed = Set(ContactBackup.listBackups().map { $0.standardizedFileURL })
        XCTAssertTrue(listed.contains(a.standardizedFileURL))
        XCTAssertTrue(listed.contains(b.standardizedFileURL))
        XCTAssertTrue(listed.contains(c.standardizedFileURL))
    }

    func testListBackupsDoesNotIncludeRemovedFile() throws {
        let url = try makeBackupFile()
        XCTAssertTrue(
            ContactBackup.listBackups().map { $0.standardizedFileURL }.contains(url.standardizedFileURL)
        )
        try FileManager.default.removeItem(at: url)
        createdFiles.removeAll { $0 == url }
        XCTAssertFalse(
            ContactBackup.listBackups().map { $0.standardizedFileURL }.contains(url.standardizedFileURL)
        )
    }

    // MARK: - listBackups: ordering (newest first by creation date)

    func testListBackupsOrdersOurFilesNewestFirst() throws {
        let first = try makeBackupFile()
        // Force a measurable gap in creation timestamps.
        usleep(20_000)
        let second = try makeBackupFile()
        usleep(20_000)
        let third = try makeBackupFile()

        let ours = Set([first, second, third].map { $0.standardizedFileURL })
        let ordered = ContactBackup.listBackups()
            .map { $0.standardizedFileURL }
            .filter { ours.contains($0) }

        XCTAssertEqual(ordered, [third, second, first].map { $0.standardizedFileURL })
    }

    func testListBackupsIsSortedNewestFirstOverall() throws {
        // Add a couple of files so the directory is guaranteed non-trivial,
        // then assert the global ordering invariant: creation dates are
        // non-increasing across the whole listing.
        try makeBackupFile()
        usleep(20_000)
        try makeBackupFile()

        let listed = ContactBackup.listBackups()
        let dates: [Date] = listed.map { url in
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        for i in 1..<max(dates.count, 1) where dates.count >= 2 {
            XCTAssertGreaterThanOrEqual(
                dates[i - 1], dates[i],
                "listBackups must be sorted newest-first by creation date"
            )
        }
    }

    // MARK: - listBackups: idempotency & determinism

    func testListBackupsIsIdempotentWithoutMutation() throws {
        try makeBackupFile()
        let a = ContactBackup.listBackups().map { $0.standardizedFileURL }
        let b = ContactBackup.listBackups().map { $0.standardizedFileURL }
        XCTAssertEqual(a, b)
    }

    func testListBackupsCountGrowsByOnePerAddedFile() throws {
        let before = ContactBackup.listBackups().count
        try makeBackupFile()
        let afterOne = ContactBackup.listBackups().count
        XCTAssertEqual(afterOne, before + 1)
        try makeBackupFile()
        let afterTwo = ContactBackup.listBackups().count
        XCTAssertEqual(afterTwo, before + 2)
    }

    func testListBackupsNeverThrows() {
        // listBackups has no throwing signature; this simply documents that it
        // returns a value (possibly empty) under normal conditions.
        let result = ContactBackup.listBackups()
        XCTAssertNotNil(result)
    }

    // MARK: - listBackups: unicode & content robustness

    func testListBackupsHandlesUnicodeContentFile() throws {
        let url = try makeBackupFile(contents: "BEGIN:VCARD\nFN:Müller 张三 😀\nEND:VCARD\n")
        let listed = ContactBackup.listBackups().map { $0.standardizedFileURL }
        XCTAssertTrue(listed.contains(url.standardizedFileURL))
    }

    func testListBackupsHandlesEmptyContentFile() throws {
        let url = try makeBackupFile(contents: "")
        let listed = ContactBackup.listBackups().map { $0.standardizedFileURL }
        XCTAssertTrue(listed.contains(url.standardizedFileURL))
    }

    func testListBackupsHandlesLargeContentFile() throws {
        let large = String(repeating: "A", count: 200_000)
        let url = try makeBackupFile(contents: "BEGIN:VCARD\nNOTE:\(large)\nEND:VCARD\n")
        let listed = ContactBackup.listBackups().map { $0.standardizedFileURL }
        XCTAssertTrue(listed.contains(url.standardizedFileURL))
    }

    func testListBackupsHandlesManyFiles() throws {
        let urls = try (0..<25).map { _ in try makeBackupFile() }
        let listed = Set(ContactBackup.listBackups().map { $0.standardizedFileURL })
        for url in urls {
            XCTAssertTrue(listed.contains(url.standardizedFileURL))
        }
    }

    // MARK: - listBackups: every entry lives in backupsDir

    func testListBackupsEntriesAllResideInBackupsDir() throws {
        try makeBackupFile()
        let dir = ContactBackup.backupsDir.standardizedFileURL
        for url in ContactBackup.listBackups() {
            XCTAssertEqual(
                url.deletingLastPathComponent().standardizedFileURL,
                dir,
                "every listed backup must live directly inside backupsDir"
            )
        }
    }
}
