import XCTest
@testable import Meister

final class WiFiNetworksParserTests: XCTestCase {
    func test_parses_listpreferred_output() {
        let r = WiFiPasswordsReader()
        let raw = """
        Preferred networks on en1:
            HomeWiFi
            CafeNetwork
            iPhone Hotspot
        """
        let nets = r.parse(raw)
        XCTAssertEqual(nets.count, 3)
        XCTAssertTrue(nets.contains { $0.ssid == "HomeWiFi" })
        XCTAssertTrue(nets.contains { $0.ssid == "iPhone Hotspot" })
    }

    func test_skips_header() {
        let r = WiFiPasswordsReader()
        let raw = "Preferred networks on en1:\n    Net1\n"
        XCTAssertEqual(r.parse(raw).count, 1)
    }
}

final class TCCParserTests: XCTestCase {
    func test_parses_pipe_delimited_rows() {
        let r = AppPermissionsReader()
        let raw = """
        kTCCServiceCamera|com.zoom.xos|2
        kTCCServiceMicrophone|us.zoom.xos|2
        kTCCServiceSystemPolicyAllFiles|com.example.tool|0
        kTCCServiceUnknownThing|com.foo|2
        """
        let perms = r.parse(raw)
        // Unknown service is filtered out
        XCTAssertEqual(perms.count, 3)
        XCTAssertTrue(perms.contains { $0.service == .camera && $0.allowed })
        XCTAssertTrue(perms.contains { $0.service == .fda && !$0.allowed })
    }
}
