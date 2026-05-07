import XCTest
@testable import Meister

final class SystemCleanupCategoryTests: XCTestCase {

    func test_paths_are_anchored_to_provided_home() {
        let fakeHome = URL(fileURLWithPath: "/tmp/meister-test-home")
        for category in SystemCleanupCategory.allCases {
            let paths = category.paths(home: fakeHome)
            for url in paths {
                XCTAssertTrue(url.path.hasPrefix(fakeHome.path),
                              "\(category) leaks outside of home: \(url.path)")
            }
        }
    }

    func test_browser_caches_includes_safari_chrome_firefox() {
        let home = URL(fileURLWithPath: "/tmp/h")
        let paths = SystemCleanupCategory.browserCaches.paths(home: home).map(\.path)
        XCTAssertTrue(paths.contains { $0.contains("com.apple.Safari") })
        XCTAssertTrue(paths.contains { $0.contains("Google/Chrome") })
        XCTAssertTrue(paths.contains { $0.contains("Firefox") })
    }

    func test_trash_preserves_container() {
        XCTAssertTrue(SystemCleanupCategory.trash.preserveContainer,
                      "Trash directory itself must always survive")
        XCTAssertTrue(SystemCleanupCategory.userCaches.preserveContainer)
    }

    func test_safe_defaults_exclude_user_data() {
        // Xcode Archives + Mail Downloads contain irreplaceable user data.
        XCTAssertFalse(SystemCleanupCategory.xcodeArchives.safeDefault)
        XCTAssertFalse(SystemCleanupCategory.mailDownloads.safeDefault)
    }
}

final class SystemCleanupScannerTests: XCTestCase {

    private var fakeHome: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-scan-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.fakeHome = tmp
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    func test_scan_returns_zero_for_missing_paths() async {
        let scanner = SystemCleanupScanner(home: fakeHome)
        let result = await scanner.scan(.userCaches)
        XCTAssertEqual(result.bytes, 0)
        XCTAssertEqual(result.itemCount, 0)
    }

    func test_scan_sums_file_sizes() async throws {
        let caches = fakeHome.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let payload = Data(count: 4096)
        try payload.write(to: caches.appendingPathComponent("a.bin"))
        try payload.write(to: caches.appendingPathComponent("b.bin"))

        let scanner = SystemCleanupScanner(home: fakeHome)
        let result = await scanner.scan(.userCaches)
        XCTAssertEqual(result.itemCount, 2)
        XCTAssertGreaterThanOrEqual(result.bytes, 4096)
    }
}

final class HumanBytesTests: XCTestCase {
    func test_zero() {
        XCTAssertEqual(Int64(0).humanBytes, ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
    }
    func test_kilobyte() {
        XCTAssertFalse(Int64(2048).humanBytes.isEmpty)
    }
}
