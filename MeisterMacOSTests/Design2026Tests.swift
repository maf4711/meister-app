import XCTest
@testable import Meister

final class ContinuousSquircleTests: XCTestCase {
    func test_concentric_radius() {
        XCTAssertEqual(ContinuousSquircle.concentric(parent: 20, padding: 6), 14)
    }
    func test_concentric_clamps_to_zero() {
        XCTAssertEqual(ContinuousSquircle.concentric(parent: 4, padding: 12), 0)
    }
}

final class EnergyImpactParserTests: XCTestCase {
    func test_parses_top_output() {
        let raw = """
        Processes: 100 total
        PID    COMMAND          %CPU       POWER
        123    Xcode            45.2       82.5
        456    Chrome Helper    12.0       40.1
        789    kernel_task      0.5        2.0
        """
        let r = EnergyImpactReader()
        let hogs = r.parse(raw)
        XCTAssertEqual(hogs.count, 3)
        XCTAssertEqual(hogs.first?.name, "Xcode")
        XCTAssertEqual(hogs.first?.energyImpact ?? -1, 82.5, accuracy: 0.01)
        XCTAssertEqual(hogs.first?.cpuPercent ?? -1, 45.2, accuracy: 0.01)
        // Sorted descending by energy
        XCTAssertGreaterThan(hogs[0].energyImpact, hogs[1].energyImpact)
        XCTAssertGreaterThan(hogs[1].energyImpact, hogs[2].energyImpact)
    }

    func test_parses_command_with_spaces() {
        let raw = """
        PID    COMMAND          %CPU       POWER
        100    Chrome Helper (Renderer)    7.0    25.0
        """
        let hogs = EnergyImpactReader().parse(raw)
        XCTAssertEqual(hogs.first?.name, "Chrome Helper (Renderer)")
    }
}
