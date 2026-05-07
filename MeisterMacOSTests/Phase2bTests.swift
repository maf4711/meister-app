import XCTest
@testable import Meister

// MARK: - Duplicate Finder

final class DuplicateFinderTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let t = tmp { try? FileManager.default.removeItem(at: t) }
    }

    func test_finds_duplicate_pair() async throws {
        let payload = Data(repeating: 0xAB, count: 2_000_000)
        try payload.write(to: tmp.appendingPathComponent("a.bin"))
        try payload.write(to: tmp.appendingPathComponent("b.bin"))
        try Data(repeating: 0xCD, count: 2_000_000).write(to: tmp.appendingPathComponent("c.bin"))

        let finder = DuplicateFinder()
        let groups = await finder.find(in: [tmp], minSize: 1_048_576)
        XCTAssertEqual(groups.count, 1, "exactly one duplicate group expected")
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func test_skips_files_below_min_size() async throws {
        let small = Data(count: 1024)
        try small.write(to: tmp.appendingPathComponent("a.txt"))
        try small.write(to: tmp.appendingPathComponent("b.txt"))

        let finder = DuplicateFinder()
        let groups = await finder.find(in: [tmp], minSize: 1_048_576)
        XCTAssertTrue(groups.isEmpty)
    }

    func test_sha256_matches_known_value() {
        // SHA256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let url = tmp.appendingPathComponent("hello.txt")
        try? "hello".data(using: .utf8)?.write(to: url)
        let hash = DuplicateFinder.sha256(of: url)
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}

// MARK: - Hosts parser

final class HostsReaderTests: XCTestCase {

    func test_parses_active_and_commented_entries() async {
        let raw = """
        ##
        # Host Database
        ##
        127.0.0.1\tlocalhost
        ::1            localhost
        # 192.168.1.5  router.local   # alter Test
        10.0.0.42      buho.test  # nichts
        """
        let r = HostsReader()
        let entries = r.parse(raw)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].ip, "127.0.0.1")
        XCTAssertEqual(entries[0].hosts, ["localhost"])
        XCTAssertFalse(entries[0].isCommented)
        XCTAssertEqual(entries[1].ip, "::1")  // IPv6
        XCTAssertTrue(entries[2].isCommented)
        XCTAssertEqual(entries[2].ip, "192.168.1.5")
        XCTAssertEqual(entries[3].hosts, ["buho.test"])
    }

    func test_ignores_pure_comment_lines() async {
        let raw = """
        # nothing here
        ## also nothing
        """
        let r = HostsReader()
        XCTAssertTrue(r.parse(raw).isEmpty)
    }
}

// MARK: - sfltool parser

final class LoginItemsParserTests: XCTestCase {

    func test_parses_dumpbtm_block() {
        let raw = """
        UUID: ABCD-1234
        Name: SomeApp Helper
        Executable Path: /Applications/SomeApp.app/Contents/MacOS/Helper
        Team Identifier: ABC123XYZ
        Disposition: [enabled, allowed, visible, not notified]
        Item-1
        Name: Other Helper
        Executable Path: /usr/local/bin/other
        Disposition: [disabled]
        """
        let r = LoginItemsReader()
        let items = r.parseSfltool(raw)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].label, "SomeApp Helper")
        XCTAssertTrue(items[0].enabled)
        XCTAssertEqual(items[0].teamID, "ABC123XYZ")
        XCTAssertEqual(items[1].label, "Other Helper")
        XCTAssertFalse(items[1].enabled)
    }
}

// MARK: - Browser privacy paths

final class BrowserPrivacyTests: XCTestCase {

    func test_safari_history_paths_under_home() {
        let home = URL(fileURLWithPath: "/tmp/h")
        let cleaner = BrowserPrivacyCleaner(home: home)
        let paths = cleaner.paths(for: .safari, target: .history).map(\.path)
        XCTAssertTrue(paths.contains { $0.contains("Safari/History.db") })
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix(home.path) })
    }

    func test_chrome_cookies_includes_journal() {
        let home = URL(fileURLWithPath: "/tmp/h")
        let cleaner = BrowserPrivacyCleaner(home: home)
        let paths = cleaner.paths(for: .chrome, target: .cookies).map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Cookies") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Cookies-journal") })
    }
}
