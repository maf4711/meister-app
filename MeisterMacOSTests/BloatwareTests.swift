import XCTest
@testable import Meister

final class BloatCatalogTests: XCTestCase {

    func test_p0_cleanmymac() {
        XCTAssertEqual(BloatCatalog.severity(for: "CleanMyMac X"), .p0)
        XCTAssertEqual(BloatCatalog.severity(for: "ccleaner"), .p0)
        XCTAssertEqual(BloatCatalog.severity(for: "com.avast.hub"), .p0)
    }

    func test_p1_keystone() {
        XCTAssertEqual(BloatCatalog.severity(for: "com.google.keystone.agent"), .p1)
        XCTAssertEqual(BloatCatalog.severity(for: "Microsoft AutoUpdate"), .p1)
    }

    func test_keep_wins_over_patterns() {
        XCTAssertNil(BloatCatalog.severity(for: "com.apple.Safari"))
        XCTAssertNil(BloatCatalog.severity(for: "com.merados.meister.macos"))
        XCTAssertNil(BloatCatalog.severity(for: "com.meister.keepcurrent"))
        XCTAssertTrue(BloatCatalog.isKeep("com.heald.agent"))
        XCTAssertTrue(BloatCatalog.isKeep("1Password"))
    }

    func test_ignore_file_forces_keep() {
        let sev = BloatCatalog.severity(for: "CleanMyMac", ignoreFileLines: ["cleanmymac"])
        XCTAssertNil(sev)
        XCTAssertTrue(BloatCatalog.isKeep("CleanMyMac", ignoreFileLines: ["cleanmymac"]))
    }

    func test_unknown_returns_nil() {
        XCTAssertNil(BloatCatalog.severity(for: "TotallyNormalApp"))
    }
}

final class BloatwareScannerTests: XCTestCase {

    private var fakeHome: URL!
    private var appsRoot: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-bloat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.fakeHome = tmp
        self.appsRoot = tmp.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: fakeHome.appendingPathComponent("Library/LaunchAgents"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fakeHome.appendingPathComponent("Library/Application Support"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    func test_finds_p0_app() throws {
        let app = appsRoot.appendingPathComponent("CleanMyMac X.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let scanner = BloatwareScanner(
            home: fakeHome,
            applicationRoots: [appsRoot],
            brewCaskList: { [] },
            loginItemNames: { [] }
        )
        let hits = scanner.scanAll()
        XCTAssertTrue(hits.contains { $0.kind == .app && $0.name == "CleanMyMac X" && $0.severity == .p0 })
    }

    func test_orphan_launch_agent_is_p0() throws {
        let missing = fakeHome.appendingPathComponent("gone/binary")
        let plist = fakeHome.appendingPathComponent("Library/LaunchAgents/com.example.bloat.plist")
        let dict: [String: Any] = [
            "Label": "com.example.bloat",
            "Program": missing.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plist)

        let scanner = BloatwareScanner(
            home: fakeHome,
            applicationRoots: [appsRoot],
            brewCaskList: { [] },
            loginItemNames: { [] }
        )
        let hits = scanner.scanAll()
        XCTAssertTrue(hits.contains {
            $0.kind == .launchAgent
                && $0.severity == .p0
                && $0.detail.contains("ORPHAN")
        })
    }

    func test_keep_agent_not_reported_even_if_orphan() throws {
        let missing = fakeHome.appendingPathComponent("gone/agent")
        let plist = fakeHome.appendingPathComponent("Library/LaunchAgents/com.merados.agent.plist")
        let dict: [String: Any] = [
            "Label": "com.merados.agent",
            "Program": missing.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plist)

        let scanner = BloatwareScanner(
            home: fakeHome,
            applicationRoots: [appsRoot],
            brewCaskList: { [] },
            loginItemNames: { [] }
        )
        let hits = scanner.scanAll()
        XCTAssertFalse(hits.contains { $0.name.contains("com.merados") })
    }

    func test_support_leftover_without_app() throws {
        let support = fakeHome.appendingPathComponent("Library/Application Support/CleanMyMac")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(count: 2048).write(to: support.appendingPathComponent("junk.bin"))

        let scanner = BloatwareScanner(
            home: fakeHome,
            applicationRoots: [appsRoot],
            brewCaskList: { [] },
            loginItemNames: { [] }
        )
        let hits = scanner.scanAll()
        XCTAssertTrue(hits.contains {
            $0.kind == .supportDir && $0.name == "CleanMyMac" && $0.severity == .p0
        })
    }

    func test_brew_cask_match() {
        let scanner = BloatwareScanner(
            home: fakeHome,
            applicationRoots: [appsRoot],
            brewCaskList: { ["cleanmymac", "firefox"] },
            loginItemNames: { [] }
        )
        let hits = scanner.scanAll()
        XCTAssertTrue(hits.contains { $0.kind == .brewCask && $0.name == "cleanmymac" })
        XCTAssertFalse(hits.contains { $0.name == "firefox" })
    }
}

final class BloatwareCleanerTests: XCTestCase {

    private var fakeHome: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-bloat-kill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.fakeHome = tmp
        try FileManager.default.createDirectory(
            at: fakeHome.appendingPathComponent("Library/LaunchAgents"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    @MainActor
    func test_quarantines_user_launch_agent() async throws {
        let plist = fakeHome.appendingPathComponent("Library/LaunchAgents/com.junk.agent.plist")
        try Data("test".utf8).write(to: plist)
        let finding = BloatFinding(
            kind: .launchAgent,
            severity: .p0,
            name: "com.junk.agent.plist",
            path: plist.path,
            detail: "test",
            bytes: 4
        )
        let cleaner = BloatwareCleaner(home: fakeHome)
        let manifest = try await cleaner.kill([finding])
        XCTAssertEqual(manifest.quarantinedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
        let q = cleaner.quarantineRoot()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: q.appendingPathComponent("com.junk.agent.plist").path
        ))
    }

    @MainActor
    func test_skips_system_launch_agent() async throws {
        let finding = BloatFinding(
            kind: .launchAgent,
            severity: .p0,
            name: "com.junk.system.plist",
            path: "/Library/LaunchAgents/com.junk.system.plist",
            detail: "system",
            bytes: 0
        )
        let cleaner = BloatwareCleaner(home: fakeHome)
        let manifest = try await cleaner.kill([finding])
        XCTAssertEqual(manifest.quarantinedCount, 0)
        XCTAssertEqual(manifest.entries.first?.error, "system LaunchAgent — needs admin")
    }
}
