import XCTest
@testable import MeisterIOS

/// TF 2026-04-21: "Das sind keine doppelten" — couple photos from different
/// days were grouped because Vision sees similar faces/composition. Copies
/// must share a capture window (burst / double-save), not a vibe.
final class CaptureWindowTests: XCTestCase {

    private struct Shot: CaptureTimed {
        let id: String
        let creationDate: Date?
    }

    private func date(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    func testSameSecondShotsStayTogether() {
        let a = date("2026-04-02T19:57:00Z")
        let items = [
            Shot(id: "1", creationDate: a),
            Shot(id: "2", creationDate: a.addingTimeInterval(0.4)),
            Shot(id: "3", creationDate: a.addingTimeInterval(1.1)),
        ]
        let groups = SimilarityClustering.splitByCaptureWindow(items, window: 60)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].map(\.id), ["1", "2", "3"])
    }

    func testTFScreenshotDaysApartAreNotCopies() {
        // Dates from the TestFlight duplicate list (Apr 21 screenshot).
        let items = [
            Shot(id: "apr19", creationDate: date("2026-04-19T14:13:00Z")),
            Shot(id: "apr4", creationDate: date("2026-04-04T14:28:00Z")),
            Shot(id: "apr2a", creationDate: date("2026-04-02T19:57:00Z")),
            Shot(id: "apr2b", creationDate: date("2026-04-02T19:57:02Z")),
            Shot(id: "mar31", creationDate: date("2026-03-31T11:02:00Z")),
            Shot(id: "mar20", creationDate: date("2026-03-20T23:12:00Z")),
        ]
        let groups = SimilarityClustering.splitByCaptureWindow(items, window: 60)
        XCTAssertEqual(groups.count, 1, "only the two Apr-2 19:57 shots share a window")
        XCTAssertEqual(Set(groups[0].map(\.id)), ["apr2a", "apr2b"])
    }

    func testMissingDatesNeverGroup() {
        let items = [
            Shot(id: "a", creationDate: nil),
            Shot(id: "b", creationDate: nil),
        ]
        XCTAssertEqual(SimilarityClustering.splitByCaptureWindow(items).count, 0)
    }

    func testSingletonsDropped() {
        let items = [Shot(id: "solo", creationDate: date("2026-04-19T14:13:00Z"))]
        XCTAssertEqual(SimilarityClustering.splitByCaptureWindow(items).count, 0)
    }
}

final class PhotoSizeEstimateTests: XCTestCase {
    func testPhotoEstimateIsPositiveAndCheap() {
        let bytes = PhotoScanner.estimateBytes(
            pixelWidth: 4032, pixelHeight: 3024, isVideo: false, duration: 0
        )
        XCTAssertGreaterThan(bytes, 1_000_000)
        XCTAssertLessThan(bytes, 50_000_000)
    }

    func testVideoEstimateScalesWithDuration() {
        let short = PhotoScanner.estimateBytes(
            pixelWidth: 1920, pixelHeight: 1080, isVideo: true, duration: 2
        )
        let long = PhotoScanner.estimateBytes(
            pixelWidth: 1920, pixelHeight: 1080, isVideo: true, duration: 20
        )
        XCTAssertGreaterThan(long, short)
    }
}
