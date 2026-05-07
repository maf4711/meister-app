import XCTest
@testable import Meister

final class CleanupHistoryReaderTests: XCTestCase {

    private var fakeHome: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    func test_loads_cleanup_manifest() async throws {
        let dir = fakeHome.appendingPathComponent("Library/Application Support/Meister/cleanups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let manifest: [String: Any] = [
            "timestamp": "2026-05-07T15:30:00+02:00",
            "totalReclaimedBytes": 1_073_741_824,  // 1 GiB
            "entries": [
                ["category": "userCaches", "path": "/tmp/x", "bytes": 500, "recycled": true],
                ["category": "userCaches", "path": "/tmp/y", "bytes": 500, "recycled": true],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: dir.appendingPathComponent("2026-05-07T15-30-00.json"))

        let reader = CleanupHistoryReader(home: fakeHome)
        let entries = await reader.load()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .cleanup)
        XCTAssertEqual(entries.first?.bytes, 1_073_741_824)
        XCTAssertTrue(entries.first?.title.contains("2 item") == true)
    }

    func test_loads_uninstall_manifest() async throws {
        let dir = fakeHome.appendingPathComponent("Library/Application Support/Meister/uninstalls")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let manifest: [String: Any] = [
            "timestamp": "2026-05-07T16-00-00",
            "totalReclaimedBytes": 50_000_000,
            "appName": "TestApp",
            "entries": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: dir.appendingPathComponent("2026-05-07T16-00-00-TestApp.json"))

        let reader = CleanupHistoryReader(home: fakeHome)
        let entries = await reader.load()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .uninstall)
        XCTAssertEqual(entries.first?.title, "TestApp")
    }

    func test_returns_empty_when_no_manifests() async {
        let reader = CleanupHistoryReader(home: fakeHome)
        let entries = await reader.load()
        XCTAssertTrue(entries.isEmpty)
    }
}
