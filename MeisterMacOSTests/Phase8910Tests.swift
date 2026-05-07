import XCTest
@testable import Meister

final class VPNStatusParserTests: XCTestCase {
    func test_detects_utun_as_vpn() {
        let r = VPNStatusReader()
        XCTAssertTrue(r.isLikelyVPN(name: "utun4"))
        XCTAssertTrue(r.isLikelyVPN(name: "ipsec0"))
        XCTAssertTrue(r.isLikelyVPN(name: "wg0"))
        XCTAssertFalse(r.isLikelyVPN(name: "en0"))
        XCTAssertFalse(r.isLikelyVPN(name: "lo0"))
    }

    func test_parses_dns_servers() {
        let r = VPNStatusReader()
        let raw = """
            DNS configuration
            resolver #1
              search domain[0] : home
              nameserver[0] : 1.1.1.1
              nameserver[1] : 8.8.8.8
              flags    : Request A records, Request AAAA records
            resolver #2
              nameserver[0] : 9.9.9.9
        """
        let dns = r.parseDNS(raw)
        XCTAssertEqual(dns, ["1.1.1.1", "8.8.8.8", "9.9.9.9"])
    }
}

final class MemoryPressureParserTests: XCTestCase {
    func test_parses_vm_stat_pages() {
        let r = MemoryPressureReader()
        let raw = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                              123456.
        Pages active:                            234567.
        Pages wired down:                        345678.
        Pages occupied by compressor:            45678.
        """
        let s = r.parse(raw)
        XCTAssertEqual(s.free, 123456)
        XCTAssertEqual(s.active, 234567)
        XCTAssertEqual(s.wired, 345678)
        XCTAssertEqual(s.compressed, 45678)
    }

    func test_parses_swap_used_size() {
        let r = MemoryPressureReader()
        let raw = "total = 2048.00M  used = 512.50M  free = 1535.50M  (encrypted)"
        XCTAssertEqual(r.parseSwap(raw), Int64(512.50 * 1_048_576))
    }

    func test_parses_zero_swap() {
        let r = MemoryPressureReader()
        let raw = "total = 0.00M  used = 0.00M  free = 0.00M"
        XCTAssertEqual(r.parseSwap(raw), 0)
    }
}

final class NotifPermsFlagsTests: XCTestCase {
    func test_parses_apps_block() {
        let r = NotificationPermissionsReader()
        let raw = """
        {
            apps = (
                {
                    "bundle-id" = "com.apple.Mail";
                    flags = 13;
                },
                {
                    "bundle-id" = "com.tinyspeck.slackmacgap";
                    flags = 79;
                }
            );
        }
        """
        let entries = r.parse(raw)
        XCTAssertEqual(entries.count, 2)
        // flags 13 = 0b00001101 = alert (0x08) + banner (0x04) + badge (0x01); no sound
        let mail = entries.first { $0.bundleID == "com.apple.Mail" }
        XCTAssertEqual(mail?.allowedAlert, true)
        XCTAssertEqual(mail?.allowedBanner, true)
        XCTAssertEqual(mail?.allowedSound, false)
        XCTAssertEqual(mail?.allowedBadge, true)
    }
}

final class AutopilotPlistTests: XCTestCase {
    func test_plist_contains_correct_label_and_url() {
        let r = AutopilotReader()
        let plist = r.plistContents()
        XCTAssertTrue(plist.contains("com.merados.meister.autopilot"))
        XCTAssertTrue(plist.contains("meister://run/quick-clean"))
        XCTAssertTrue(plist.contains("<integer>3</integer>"))   // Hour
        XCTAssertTrue(plist.contains("<integer>30</integer>"))  // Minute
    }
}
