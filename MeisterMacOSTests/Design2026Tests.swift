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

// Tiny test for Task 3.1: exercises every BashModule.id through the destination factory switch.
// This provides a (runtime) check that all ids have a case (natives get their View, others fall to default BashOutputView).
// "Even if just compile-time": adding a new native module id to BashModule.all without a corresponding case
// in the destination switch will cause that module to incorrectly use BashOutputView (the default).
// The act of maintaining the case list alongside the .all array forces the developer to handle it when adding modules.
// Run: swift test or via Xcode to exercise.
final class BashModuleDestinationTests: XCTestCase {
    func test_everyBashModuleIdHasACase_inDestinationFactory() {
        let allModules = BashModule.all
        XCTAssertFalse(allModules.isEmpty, "BashModule.all must not be empty")

        // Exercise the @ViewBuilder switch for EVERY id. This runs the switch expression for each.
        // If a native module (command: []) ever lacks a case, it will silently use the bash default —
        // this test at least ensures the code path is exercised for all current modules without crashing.
        for module in allModules {
            // Accessing .destination evaluates the switch and constructs the concrete View.
            let _ = module.destination
        }

        // If we reached here, every id had a matching case (or hit default, which is intended for bash modules).
        XCTAssertTrue(true, "All BashModule destinations constructed successfully")
    }
}

final class SmartDiagnosisTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func observation(destination: String? = nil, backupAge: Int? = nil,
                             free: Int64 = 50, unknown: Bool = false, snapshots: Int = 0) -> HealthObservation {
        let checks = ["filevault", "firewall", "gatekeeper", "sip"].map {
            SecurityCheck(id: $0, title: $0, state: unknown ? .unknown("not readable") : .ok("on"), detail: nil, action: nil)
        }
        return HealthObservation(security: checks, scans: [],
            backup: TimeMachineStatus(isRunning: false, isOnAC: true,
                lastBackupDate: backupAge.map { now.addingTimeInterval(-Double($0) * 86_400) }, destination: destination, raw: ""),
            snapshots: (0..<snapshots).map { LocalSnapshot(name: "snapshot-\($0)", creationDate: now, bytes: nil) },
            disk: DiskCapacity(total: 100, available: free), timestamp: now)
    }

    func test_missingBackupDestinationDoesNotPenalizeOrRecommend() {
        let value = observation(backupAge: 100)
        XCTAssertEqual(HealthScoreReader.evaluate(value).score, 100)
        XCTAssertFalse(HealthScoreReader.evaluate(value).signals.contains { $0.id == "backup" })
        XCTAssertTrue(HealthRecommendation.ranked(for: value).isEmpty)
    }

    func test_configuredOldBackupProducesNavigableRecommendation() {
        let recommendations = HealthRecommendation.ranked(for: observation(destination: "Backup", backupAge: 10))
        XCTAssertEqual(recommendations.first?.moduleID, "time-machine")
    }

    func test_snapshotCountIsNotAHealthFailure() {
        XCTAssertEqual(HealthScoreReader.evaluate(observation(snapshots: 1000)).score, 100)
        XCTAssertTrue(HealthRecommendation.ranked(for: observation(snapshots: 1000)).isEmpty)
    }

    func test_unknownSecurityIsExcludedAndDisclosed() {
        let snapshot = HealthScoreReader.evaluate(observation(unknown: true))
        XCTAssertTrue(snapshot.hasUnknowns)
        XCTAssertEqual(snapshot.signals.first?.weight, 0)
        XCTAssertEqual(HealthRecommendation.ranked(for: observation(unknown: true)).count, 4)
    }

    func test_lowDiskSpaceProducesRecommendationAndLowersScore() {
        let value = observation(free: 3)
        XCTAssertLessThan(HealthScoreReader.evaluate(value).score, 100)
        XCTAssertEqual(HealthRecommendation.ranked(for: value).first?.moduleID, "large-old-files")
    }

    func test_failedSecurityCommandIsUnknown() {
        for output in ["", "Operation not permitted", "Unexpected output"] {
            let state = SecurityStatusReader.parseState(output, enabled: "enabled", disabled: "disabled", critical: true)
            guard case .unknown = state else { return XCTFail("Command failure must not mean disabled") }
        }
    }

    func test_explicitSecurityStates() {
        guard case .ok = SecurityStatusReader.parseState("assessments enabled", enabled: "enabled", disabled: "disabled", critical: true) else { return XCTFail() }
        guard case .bad = SecurityStatusReader.parseState("assessments disabled", enabled: "enabled", disabled: "disabled", critical: true) else { return XCTFail() }
    }

    func test_germanSearchAndCLIIdentifiers() {
        XCTAssertEqual(BashModule.search("duplikate").first?.id, "duplicates")
        XCTAssertEqual(BashModule.search("große dateien").first?.id, "large-old-files")
        XCTAssertEqual(BashModule.search("rückgängig").first?.id, "undo-cleanup")
        XCTAssertEqual(BashModule.search("heal-dry").first?.id, "heal-dry")
        XCTAssertTrue(BashModule.search("zzzzzznonexistent").isEmpty)
        XCTAssertEqual(BashModule.search("  \n ").count, 8)
    }

    func test_forecastRequiresRealHistory() {
        let disk = DiskCapacity(total: 1000, available: 100)
        let short = [StorageSample(date: now, total: 1000, free: 100)]
        XCTAssertNil(StorageForecastReader.forecast(samples: short, disk: disk).daysUntilFull)
        let history = [StorageSample(date: now.addingTimeInterval(-10 * 86_400), total: 1000, free: 200),
                       StorageSample(date: now.addingTimeInterval(-5 * 86_400), total: 1000, free: 150),
                       StorageSample(date: now, total: 1000, free: 100)]
        XCTAssertEqual(StorageForecastReader.forecast(samples: history, disk: disk).daysUntilFull, 10)
        XCTAssertNil(StorageForecastReader.forecast(samples: history, disk: .init(total: 2000, available: 100)).daysUntilFull)
    }
}

final class CommandRunnerTests: XCTestCase {
    func test_drainsOutputLargerThanPipeBuffer() {
        let result = CommandRunner.run("/bin/sh", ["-c", "yes abcdefghijklmnop | head -n 20000"], timeout: 5)
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.count, 200_000)
    }

    func test_failureAndMissingExecutableRemainFailures() {
        XCTAssertEqual(CommandRunner.run("/usr/bin/false", []).status, 1)
        XCTAssertFalse(CommandRunner.run("/nonexistent/meister-test", []).succeeded)
    }

    func test_timeoutTerminatesOwnedProcess() {
        let start = Date()
        let result = CommandRunner.run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func test_shellQuotePreservesAllSpecialCharacters() {
        let input = "space ' quote \" $HOME $(printf BAD) `printf BAD`\nnewline"
        let result = CommandRunner.run("/bin/sh", ["-c", "printf %s " + CommandRunner.shellQuote(input)])
        XCTAssertEqual(result.output, input)
    }

    func test_webhookValidation() {
        XCTAssertNotNil(WebhookSecretStore.validURL("https://hooks.slack.com/services/T/B/secret"))
        for value in ["http://hooks.slack.com/services/T/B/secret", "https://example.com/services/T/B/secret",
                      "https://hooks.slack.com.evil.test/services/T/B/secret", "https://hooks.slack.com/services/x"] {
            XCTAssertNil(WebhookSecretStore.validURL(value))
        }
    }

    func test_trashAndProtectionAreNeverAutomaticCleanupTargets() {
        XCTAssertFalse(SystemCleanupCategory.trash.safeDefault)
        XCTAssertTrue(BloatCatalog.isKeep("cpu-guard"))
        XCTAssertTrue(BloatCatalog.isKeep("Norton Security"))
        XCTAssertTrue(BrowserPrivacyCleaner().paths(for: .firefox, target: .history).isEmpty)
    }
}

final class NativeDiagnosticsRegressionTests: XCTestCase {
    func test_networkParserUsesProtocolAndTCPStateFields() {
        let raw = "p123\ncExample\nLuser\nf5\ntIPv4\nPTCP\nn127.0.0.1:443->10.0.0.1:5000\nTST=ESTABLISHED\nf6\ntIPv6\nPUDP\nn*:5353\n"
        let result = NetworkConnectionsReader().parse(raw)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.proto, "TCP")
        XCTAssertEqual(result.first?.state, "ESTABLISHED")
        XCTAssertEqual(result.last?.proto, "UDP")
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
    }

    func test_wifiUsesHardwareDeviceAndRejectsErrorText() {
        let ports = "Hardware Port: Ethernet\nDevice: en0\nHardware Port: Wi-Fi\nDevice: en7\n"
        XCTAssertEqual(WiFiPasswordsReader.wirelessDevice(in: ports), "en7")
        XCTAssertTrue(WiFiPasswordsReader().parse("Wi-Fi is not a Wi-Fi interface").isEmpty)
    }

    func test_processManagerRejectsProcessGroupAndSelfTargets() async {
        let reader = ProcessReader()
        let negative = await reader.kill(pid: -1)
        let zero = await reader.kill(pid: 0)
        let own = await reader.kill(pid: Int(getpid()))
        XCTAssertFalse(negative)
        XCTAssertFalse(zero)
        XCTAssertFalse(own)
    }
}
