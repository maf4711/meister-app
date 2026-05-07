import XCTest
@testable import Meister

final class UninstallerScannerTests: XCTestCase {

    private var fakeHome: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-uninstall-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.fakeHome = tmp
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    private func makeApp(name: String, bundleID: String) -> InstalledApp {
        InstalledApp(
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleID: bundleID,
            displayName: name,
            version: "1.0",
            iconPath: nil,
            bundleSize: 0
        )
    }

    func test_finds_application_support_by_bundle_id() throws {
        let app = makeApp(name: "TestApp", bundleID: "com.example.testapp")
        let asDir = fakeHome.appendingPathComponent("Library/Application Support/com.example.testapp")
        try FileManager.default.createDirectory(at: asDir, withIntermediateDirectories: true)
        try Data(count: 1024).write(to: asDir.appendingPathComponent("data.bin"))

        let scanner = UninstallerScanner(home: fakeHome)
        let leftovers = scanner.leftovers(for: app)
        XCTAssertTrue(leftovers.contains { $0.source == .applicationSupport
                                            && $0.url.lastPathComponent == "com.example.testapp" })
    }

    func test_finds_application_support_by_display_name() throws {
        let app = makeApp(name: "Sublime Text", bundleID: "com.sublimetext.4")
        let asDir = fakeHome.appendingPathComponent("Library/Application Support/Sublime Text")
        try FileManager.default.createDirectory(at: asDir, withIntermediateDirectories: true)

        let scanner = UninstallerScanner(home: fakeHome)
        let leftovers = scanner.leftovers(for: app)
        XCTAssertTrue(leftovers.contains { $0.url.lastPathComponent == "Sublime Text" })
    }

    func test_finds_preferences_plist() throws {
        let app = makeApp(name: "Foo", bundleID: "com.example.foo")
        let prefs = fakeHome.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data().write(to: prefs.appendingPathComponent("com.example.foo.plist"))
        try Data().write(to: prefs.appendingPathComponent("com.example.foo.helper.plist"))
        try Data().write(to: prefs.appendingPathComponent("com.unrelated.app.plist"))

        let scanner = UninstallerScanner(home: fakeHome)
        let leftovers = scanner.leftovers(for: app)
        let names = Set(leftovers.filter { $0.source == .preferences }.map(\.url.lastPathComponent))
        XCTAssertEqual(names, ["com.example.foo.plist", "com.example.foo.helper.plist"])
    }

    func test_finds_caches_with_dotted_suffix() throws {
        let app = makeApp(name: "Bar", bundleID: "com.example.bar")
        let caches = fakeHome.appendingPathComponent("Library/Caches")
        let exact = caches.appendingPathComponent("com.example.bar")
        let helper = caches.appendingPathComponent("com.example.bar.helper")
        let unrelated = caches.appendingPathComponent("com.example.unrelated")
        try FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let scanner = UninstallerScanner(home: fakeHome)
        let names = Set(scanner.leftovers(for: app)
            .filter { $0.source == .caches }
            .map(\.url.lastPathComponent))
        XCTAssertTrue(names.contains("com.example.bar"))
        XCTAssertTrue(names.contains("com.example.bar.helper"))
        XCTAssertFalse(names.contains("com.example.unrelated"))
    }

    func test_misses_unrelated_apps() throws {
        let app = makeApp(name: "TheirApp", bundleID: "com.them.theirapp")
        let asDir = fakeHome.appendingPathComponent("Library/Application Support/com.us.ourapp")
        try FileManager.default.createDirectory(at: asDir, withIntermediateDirectories: true)

        let scanner = UninstallerScanner(home: fakeHome)
        XCTAssertTrue(scanner.leftovers(for: app).isEmpty)
    }
}

final class LargeFilesScannerScopeTests: XCTestCase {
    func test_default_scope_is_user_content_dirs_only() {
        let scope = LargeFilesScanner.defaultScope.map { $0.lastPathComponent }
        XCTAssertEqual(Set(scope), ["Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures"])
    }
}

final class LargeFileItemTests: XCTestCase {
    func test_freshness_picks_newer_of_two() {
        let oldest = Date(timeIntervalSince1970: 1_000_000)
        let newer  = Date(timeIntervalSince1970: 2_000_000)
        let item = LargeFileItem(url: URL(fileURLWithPath: "/tmp/x"), bytes: 1,
                                 lastUsed: oldest, lastModified: newer)
        XCTAssertEqual(item.freshness, newer)
    }
    func test_freshness_handles_one_nil() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let a = LargeFileItem(url: URL(fileURLWithPath: "/tmp/a"), bytes: 1,
                              lastUsed: nil, lastModified: when)
        let b = LargeFileItem(url: URL(fileURLWithPath: "/tmp/b"), bytes: 1,
                              lastUsed: when, lastModified: nil)
        XCTAssertEqual(a.freshness, when)
        XCTAssertEqual(b.freshness, when)
    }
    func test_freshness_nil_when_both_missing() {
        let item = LargeFileItem(url: URL(fileURLWithPath: "/tmp/x"), bytes: 1,
                                 lastUsed: nil, lastModified: nil)
        XCTAssertNil(item.freshness)
    }
}
