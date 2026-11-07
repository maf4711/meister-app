import XCTest
@testable import MeisterIOS

/// Tests for `CleanupReport` (declared in `MeisterIOS/Storage/ReportExporter.swift`).
///
/// Grounding notes:
/// - The real source exposes a value type `CleanupReport` with a nested `Section`,
///   the stored properties `generatedAt: Date`, `deviceInfo: String`, `sections: [Section]`,
///   and the single internal API `func renderPDF() throws -> URL`.
/// - There is NO markdown/JSON export in the source, so those are intentionally not tested
///   (only literally-present symbols are exercised).
/// - `renderPDF()` uses `UIGraphicsPDFRenderer`, which runs headless in the iOS simulator
///   with no device authorization, so it is safe to invoke here.
/// - Locale/format output (the rendered PDF text) is non-deterministic across locales, so we
///   only assert structural facts about the produced file (existence, extension, PDF magic
///   header, non-emptiness), never exact rendered strings.
final class ReportExporterTests: XCTestCase {

    // MARK: - Helpers

    /// Reads back the first bytes of a file and confirms it is a PDF stream.
    private func assertIsPDFFile(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "renderPDF() should write a file at the returned URL",
            file: file, line: line
        )
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "PDF file must not be empty", file: file, line: line)
        // PDF files always start with the ASCII signature "%PDF".
        let header = data.prefix(4)
        XCTAssertEqual(Array(header), Array("%PDF".utf8), "File should start with the PDF magic header", file: file, line: line)
    }

    private func sampleSections() -> [CleanupReport.Section] {
        [
            CleanupReport.Section(
                title: "Photos",
                rows: [
                    (label: "Screenshots", value: "128"),
                    (label: "Duplicates", value: "42")
                ]
            ),
            CleanupReport.Section(
                title: "Contacts",
                rows: [
                    (label: "Duplicate groups", value: "7")
                ]
            )
        ]
    }

    private func makeReport(
        generatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        deviceInfo: String = "iPhone15,2 · iOS 17.0",
        sections: [CleanupReport.Section]? = nil
    ) -> CleanupReport {
        CleanupReport(
            generatedAt: generatedAt,
            deviceInfo: deviceInfo,
            sections: sections ?? sampleSections()
        )
    }

    // MARK: - Model: Section property storage

    func testSectionStoresTitle() {
        let section = CleanupReport.Section(title: "Storage", rows: [])
        XCTAssertEqual(section.title, "Storage")
    }

    func testSectionStoresRowsInOrder() {
        let rows: [(label: String, value: String)] = [
            (label: "A", value: "1"),
            (label: "B", value: "2"),
            (label: "C", value: "3")
        ]
        let section = CleanupReport.Section(title: "T", rows: rows)
        XCTAssertEqual(section.rows.count, 3)
        XCTAssertEqual(section.rows.map { $0.label }, ["A", "B", "C"])
        XCTAssertEqual(section.rows.map { $0.value }, ["1", "2", "3"])
    }

    func testSectionEmptyRows() {
        let section = CleanupReport.Section(title: "Empty", rows: [])
        XCTAssertTrue(section.rows.isEmpty)
    }

    func testSectionEmptyTitle() {
        let section = CleanupReport.Section(title: "", rows: [(label: "x", value: "y")])
        XCTAssertEqual(section.title, "")
        XCTAssertEqual(section.rows.count, 1)
    }

    func testSectionTupleLabelsPreserved() {
        let section = CleanupReport.Section(title: "T", rows: [(label: "Free space", value: "12 GB")])
        let first = section.rows[0]
        XCTAssertEqual(first.label, "Free space")
        XCTAssertEqual(first.value, "12 GB")
    }

    func testSectionUnicodeContent() {
        let section = CleanupReport.Section(
            title: "Fotos 📸",
            rows: [(label: "Größe (Ω)", value: "1 234 ✓")]
        )
        XCTAssertEqual(section.title, "Fotos 📸")
        XCTAssertEqual(section.rows[0].label, "Größe (Ω)")
        XCTAssertEqual(section.rows[0].value, "1 234 ✓")
    }

    // MARK: - Model: CleanupReport property storage

    func testReportStoresGeneratedAt() {
        let date = Date(timeIntervalSince1970: 42)
        let report = makeReport(generatedAt: date)
        XCTAssertEqual(report.generatedAt, date)
    }

    func testReportStoresDeviceInfo() {
        let report = makeReport(deviceInfo: "TestDevice")
        XCTAssertEqual(report.deviceInfo, "TestDevice")
    }

    func testReportStoresSectionsInOrder() {
        let report = makeReport()
        XCTAssertEqual(report.sections.count, 2)
        XCTAssertEqual(report.sections.map { $0.title }, ["Photos", "Contacts"])
    }

    func testReportEmptySections() {
        let report = makeReport(sections: [])
        XCTAssertTrue(report.sections.isEmpty)
    }

    func testReportEmptyDeviceInfo() {
        let report = makeReport(deviceInfo: "")
        XCTAssertEqual(report.deviceInfo, "")
    }

    func testReportDistantPastDate() {
        let report = makeReport(generatedAt: .distantPast)
        XCTAssertEqual(report.generatedAt, .distantPast)
    }

    func testReportDistantFutureDate() {
        let report = makeReport(generatedAt: .distantFuture)
        XCTAssertEqual(report.generatedAt, .distantFuture)
    }

    func testReportNegativeEpochDate() {
        let date = Date(timeIntervalSince1970: -1_000)
        let report = makeReport(generatedAt: date)
        XCTAssertEqual(report.generatedAt.timeIntervalSince1970, -1_000, accuracy: 0.0001)
    }

    func testReportZeroEpochDate() {
        let date = Date(timeIntervalSince1970: 0)
        let report = makeReport(generatedAt: date)
        XCTAssertEqual(report.generatedAt.timeIntervalSince1970, 0, accuracy: 0.0001)
    }

    func testReportNestedRowsRoundTripThroughModel() {
        let sections = sampleSections()
        let report = makeReport(sections: sections)
        // Storage is a faithful round-trip: rows survive nesting intact.
        XCTAssertEqual(report.sections[0].rows[0].label, "Screenshots")
        XCTAssertEqual(report.sections[0].rows[0].value, "128")
        XCTAssertEqual(report.sections[1].rows[0].label, "Duplicate groups")
        XCTAssertEqual(report.sections[1].rows[0].value, "7")
    }

    func testReportLargeNumberOfSections() {
        let sections = (0..<500).map { i in
            CleanupReport.Section(title: "S\(i)", rows: [(label: "L\(i)", value: "\(i)")])
        }
        let report = makeReport(sections: sections)
        XCTAssertEqual(report.sections.count, 500)
        XCTAssertEqual(report.sections.last?.title, "S499")
        XCTAssertEqual(report.sections.last?.rows.last?.value, "499")
    }

    func testReportSectionWithManyRows() {
        let rows = (0..<1_000).map { (label: "row\($0)", value: "\($0)") }
        let report = makeReport(sections: [CleanupReport.Section(title: "Big", rows: rows)])
        XCTAssertEqual(report.sections[0].rows.count, 1_000)
        XCTAssertEqual(report.sections[0].rows[999].label, "row999")
    }

    // MARK: - renderPDF(): produces a valid PDF file

    func testRenderPDFReturnsExistingFile() throws {
        let url = try makeReport().renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRenderPDFHasPDFExtension() throws {
        let url = try makeReport().renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "pdf")
    }

    func testRenderPDFFilenamePrefix() throws {
        let url = try makeReport().renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(
            url.lastPathComponent.hasPrefix("MeisterReport-"),
            "Filename should start with the MeisterReport- prefix, got \(url.lastPathComponent)"
        )
    }

    func testRenderPDFWritesIntoTemporaryDirectory() throws {
        let url = try makeReport().renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(
            url.deletingLastPathComponent().standardizedFileURL.path == tmp,
            "PDF should be written into the temporary directory"
        )
    }

    func testRenderPDFFileIsNonEmptyPDF() throws {
        let url = try makeReport().renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithEmptySectionsStillProducesPDF() throws {
        let url = try makeReport(sections: []).renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithEmptyDeviceInfoStillProducesPDF() throws {
        let url = try makeReport(deviceInfo: "").renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithSectionContainingNoRows() throws {
        let report = makeReport(sections: [CleanupReport.Section(title: "Only title", rows: [])])
        let url = try report.renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithUnicodeContent() throws {
        let report = makeReport(
            deviceInfo: "Gerät 📱 · iOS",
            sections: [
                CleanupReport.Section(
                    title: "Überblick — Ω≈3.14 — 日本語",
                    rows: [(label: "Größe", value: "1 234 567 ✓")]
                )
            ]
        )
        let url = try report.renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithLongStringsStillProducesPDF() throws {
        let longTitle = String(repeating: "VeryLongSectionTitle ", count: 200)
        let longValue = String(repeating: "9", count: 5_000)
        let report = makeReport(
            deviceInfo: String(repeating: "D", count: 2_000),
            sections: [CleanupReport.Section(title: longTitle, rows: [(label: "L", value: longValue)])]
        )
        let url = try report.renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithManySectionsStillProducesPDF() throws {
        let sections = (0..<200).map { i in
            CleanupReport.Section(title: "Section \(i)", rows: [(label: "Count", value: "\(i)")])
        }
        let url = try makeReport(sections: sections).renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithDistantPastDate() throws {
        let url = try makeReport(generatedAt: .distantPast).renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    func testRenderPDFWithDistantFutureDate() throws {
        let url = try makeReport(generatedAt: .distantFuture).renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try assertIsPDFFile(url)
    }

    // MARK: - renderPDF(): repeatability / locale safety

    func testRenderPDFIsRepeatable() throws {
        // Each invocation must independently yield a valid PDF on disk.
        let report = makeReport()
        let first = try report.renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: first) }
        try assertIsPDFFile(first)

        let second = try report.renderPDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: second) }
        try assertIsPDFFile(second)
    }

    func testRenderPDFLocaleSafetyAcrossDifferentReports() throws {
        // Different locale-sensitive dates/device strings all yield structurally valid PDFs;
        // we never assert on the localized rendered text itself.
        let reports = [
            makeReport(generatedAt: Date(timeIntervalSince1970: 0), deviceInfo: "A"),
            makeReport(generatedAt: Date(timeIntervalSince1970: 1_700_000_000), deviceInfo: "B"),
            makeReport(generatedAt: .distantFuture, deviceInfo: "C")
        ]
        for report in reports {
            let url = try report.renderPDF()
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            try assertIsPDFFile(url)
        }
    }
}
