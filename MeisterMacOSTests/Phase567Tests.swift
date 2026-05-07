import XCTest
@testable import Meister

final class DockerSizeParserTests: XCTestCase {
    func test_parses_mixed_units() {
        let r = DockerCleanupReader()
        XCTAssertEqual(r.parseSize("1.5GB"), Int64(1.5 * 1_073_741_824))
        XCTAssertEqual(r.parseSize("128MB"), 128 * 1_048_576)
        XCTAssertEqual(r.parseSize("250kB"), 250 * 1024)
        XCTAssertEqual(r.parseSize("0B"), 0)
    }

    func test_reclaimable_strips_percentage() {
        let r = DockerCleanupReader()
        XCTAssertEqual(r.parseReclaimable("850MB (78%)"), 850 * 1_048_576)
        XCTAssertEqual(r.parseReclaimable("0B (0%)"), 0)
    }
}

final class BrewDoctorParserTests: XCTestCase {
    func test_groups_warnings_with_their_detail() {
        let r = BrewDoctorReader()
        let raw = """
        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue.

        Warning: Homebrew's "share/man" directory does not have a writable group permission.

        Warning: Some installed casks are outdated.
        Run `brew outdated --cask` to see them.
        """
        let issues = r.parseDoctor(raw)
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues[0].title.contains("share/man"))
        XCTAssertEqual(issues[0].level, .warning)
        XCTAssertTrue(issues[1].title.contains("outdated"))
        XCTAssertTrue(issues[1].detail?.contains("brew outdated") == true)
    }

    func test_distinguishes_error_from_warning() {
        let r = BrewDoctorReader()
        let raw = """
        Error: This is fatal.
        With detail.

        Warning: This is just a hint.
        """
        let issues = r.parseDoctor(raw)
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.first?.level, .error)
        XCTAssertEqual(issues.last?.level, .warning)
    }
}

final class RosettaAuditTests: XCTestCase {
    func test_classifies_arch() {
        let arm = AppArchInfo(id: "x", url: URL(fileURLWithPath: "/x"),
                              displayName: "X", architectures: ["arm64"], bundleSize: 0)
        let intel = AppArchInfo(id: "x", url: URL(fileURLWithPath: "/x"),
                                displayName: "X", architectures: ["x86_64"], bundleSize: 0)
        let universal = AppArchInfo(id: "x", url: URL(fileURLWithPath: "/x"),
                                    displayName: "X", architectures: ["arm64", "x86_64"], bundleSize: 0)
        XCTAssertEqual(arm.arch, .arm)
        XCTAssertEqual(intel.arch, .intel)
        XCTAssertEqual(universal.arch, .universal)
    }
}

final class QuickCleanModelTests: XCTestCase {
    @MainActor
    func test_initial_state_is_idle() {
        let m = QuickCleanModel()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertFalse(m.isRunning)
    }
}
