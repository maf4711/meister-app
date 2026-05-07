import XCTest
@testable import Meister

final class KeychainAuditTests: XCTestCase {
    func test_parses_keychain_list_output() {
        let r = KeychainAuditReader()
        let raw = """
            "/Users/a/Library/Keychains/login.keychain-db"
            "/Library/Keychains/System.keychain"
        """
        let paths = r.parseKeychainList(raw)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.first?.hasSuffix("login.keychain-db") == true)
    }

    func test_counts_items_by_class() {
        let r = KeychainAuditReader()
        let dump = """
        keychain: "x"
        version: 512
        class: "inet"
        ...
        class: "genp"
        class: "genp"
        class: "cert"
        """
        let counts = r.countItems(in: dump)
        XCTAssertEqual(counts.total, 4)
        XCTAssertEqual(counts.internet, 1)
        XCTAssertEqual(counts.generic, 2)
        XCTAssertEqual(counts.cert, 1)
    }
}

final class SSHKeyRiskTests: XCTestCase {
    func test_rsa_below_2048_is_high_risk() {
        let k = SSHKey(id: "x", publicPath: URL(fileURLWithPath: "/x.pub"),
                       privatePath: URL(fileURLWithPath: "/x"),
                       keyType: "ssh-rsa", bits: 1024,
                       fingerprint: nil, comment: nil,
                       hasPassphrase: .protected, lastModified: nil)
        XCTAssertEqual(k.risk, .high)
    }

    func test_dsa_is_high_risk() {
        let k = SSHKey(id: "x", publicPath: URL(fileURLWithPath: "/x.pub"),
                       privatePath: nil,
                       keyType: "ssh-dss", bits: 1024,
                       fingerprint: nil, comment: nil,
                       hasPassphrase: .noPrivate, lastModified: nil)
        XCTAssertEqual(k.risk, .high)
    }

    func test_unprotected_ed25519_is_medium() {
        let k = SSHKey(id: "x", publicPath: URL(fileURLWithPath: "/x.pub"),
                       privatePath: URL(fileURLWithPath: "/x"),
                       keyType: "ssh-ed25519", bits: 256,
                       fingerprint: nil, comment: nil,
                       hasPassphrase: .unprotected, lastModified: nil)
        XCTAssertEqual(k.risk, .medium)
    }

    func test_protected_modern_key_is_low() {
        let k = SSHKey(id: "x", publicPath: URL(fileURLWithPath: "/x.pub"),
                       privatePath: URL(fileURLWithPath: "/x"),
                       keyType: "ssh-ed25519", bits: 256,
                       fingerprint: nil, comment: nil,
                       hasPassphrase: .protected, lastModified: nil)
        XCTAssertEqual(k.risk, .low)
    }
}

final class UndoCleanupTests: XCTestCase {
    private var fakeHome: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    func test_parses_recycled_entries() throws {
        let dir = fakeHome.appendingPathComponent("Library/Application Support/Meister/cleanups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "timestamp": "2026-05-07T15:00:00+02:00",
            "totalReclaimedBytes": 1234,
            "entries": [
                ["category": "userCaches", "path": "/foo.cache", "bytes": 1000, "recycled": true],
                ["category": "trash",      "path": "/bar.txt",   "bytes": 234,  "recycled": false],
            ],
        ]
        let url = dir.appendingPathComponent("test.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)

        let reader = UndoCleanupReader(home: fakeHome)
        let entries = reader.parseManifest(at: url)
        // Only `recycled: true` entries are restorable.
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.category, "userCaches")
    }
}

final class SSDHealthSMARTStatusTests: XCTestCase {
    func test_smart_status_enum_distinguishes_states() {
        let v: SSDInfo.SMARTStatus = .verified
        let f: SSDInfo.SMARTStatus = .failing
        XCTAssertNotEqual(v, f)
    }
}
