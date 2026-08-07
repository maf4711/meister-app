import XCTest
import UIKit
@testable import MeisterIOS

// Grounded entirely in MeisterIOS/Dashboard/IOSDeviceInfo.swift.
//
// NOTE on scope: the task focus named `formatUptime` / `thermalLabel`, but
// neither symbol exists in the real source (no uptime formatter, no thermal
// mapping is defined in IOSDeviceInfo.swift). Per the grounding rule we never
// invent symbols, so these tests instead cover the file's actual deterministic
// pure mappings:
//   - IOSDeviceSnapshot.RuntimeKind.label / .icon / rawValue
//   - IOSDeviceSnapshot.diskUsagePct (pure Double math + zero guard)
//   - Int64.humanBytes (ByteCountFormatter -> contains/non-empty only)
//   - UIDevice.BatteryState.label
//   - IOSDeviceSnapshot Equatable + memberwise init
// Live device readings (IOSDeviceReader.read, battery polling, sysctl,
// volume/container scans) are intentionally skipped — they require an actual
// device/runtime and are non-deterministic.
final class IOSDeviceInfoTests: XCTestCase {

    // MARK: - RuntimeKind.label (exhaustive, all 4 cases)

    func testRuntimeKindLabel_iPhone() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPhone.label, "iPhone")
    }

    func testRuntimeKindLabel_iPad() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPad.label, "iPad")
    }

    func testRuntimeKindLabel_macCatalyst() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.macCatalyst.label, "Mac (Catalyst)")
    }

    func testRuntimeKindLabel_iOSAppOnMac() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iOSAppOnMac.label, "Mac (iPad-App)")
    }

    func testRuntimeKindLabel_allCasesNonEmptyAndDistinct() {
        let cases: [IOSDeviceSnapshot.RuntimeKind] = [.iPhone, .iPad, .macCatalyst, .iOSAppOnMac]
        let labels = cases.map { $0.label }
        for label in labels {
            XCTAssertFalse(label.isEmpty, "label must never be empty")
        }
        XCTAssertEqual(Set(labels).count, labels.count, "labels must be distinct across cases")
    }

    func testRuntimeKindLabel_isIdempotent() {
        let kind = IOSDeviceSnapshot.RuntimeKind.macCatalyst
        XCTAssertEqual(kind.label, kind.label)
    }

    // MARK: - RuntimeKind.icon (exhaustive, both Mac cases collapse to "macbook")

    func testRuntimeKindIcon_iPhone() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPhone.icon, "iphone")
    }

    func testRuntimeKindIcon_iPad() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPad.icon, "ipad")
    }

    func testRuntimeKindIcon_macCatalyst() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.macCatalyst.icon, "macbook")
    }

    func testRuntimeKindIcon_iOSAppOnMac() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iOSAppOnMac.icon, "macbook")
    }

    func testRuntimeKindIcon_bothMacRuntimesShareSameIcon() {
        XCTAssertEqual(
            IOSDeviceSnapshot.RuntimeKind.macCatalyst.icon,
            IOSDeviceSnapshot.RuntimeKind.iOSAppOnMac.icon
        )
    }

    func testRuntimeKindIcon_deviceIconsDifferFromMacIcon() {
        XCTAssertNotEqual(
            IOSDeviceSnapshot.RuntimeKind.iPhone.icon,
            IOSDeviceSnapshot.RuntimeKind.macCatalyst.icon
        )
        XCTAssertNotEqual(
            IOSDeviceSnapshot.RuntimeKind.iPad.icon,
            IOSDeviceSnapshot.RuntimeKind.iOSAppOnMac.icon
        )
    }

    func testRuntimeKindIcon_allCasesNonEmpty() {
        let cases: [IOSDeviceSnapshot.RuntimeKind] = [.iPhone, .iPad, .macCatalyst, .iOSAppOnMac]
        for kind in cases {
            XCTAssertFalse(kind.icon.isEmpty)
        }
    }

    // MARK: - RuntimeKind rawValue (String-backed enum)

    func testRuntimeKindRawValue_roundTripsForAllCases() {
        let cases: [IOSDeviceSnapshot.RuntimeKind] = [.iPhone, .iPad, .macCatalyst, .iOSAppOnMac]
        for kind in cases {
            let recovered = IOSDeviceSnapshot.RuntimeKind(rawValue: kind.rawValue)
            XCTAssertEqual(recovered, kind, "rawValue must round-trip for \(kind)")
        }
    }

    func testRuntimeKindRawValue_exactStrings() {
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPhone.rawValue, "iPhone")
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iPad.rawValue, "iPad")
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.macCatalyst.rawValue, "macCatalyst")
        XCTAssertEqual(IOSDeviceSnapshot.RuntimeKind.iOSAppOnMac.rawValue, "iOSAppOnMac")
    }

    func testRuntimeKindRawValue_unknownReturnsNil() {
        XCTAssertNil(IOSDeviceSnapshot.RuntimeKind(rawValue: "AndroidTablet"))
        XCTAssertNil(IOSDeviceSnapshot.RuntimeKind(rawValue: ""))
    }

    func testRuntimeKindRawValue_isCaseSensitive() {
        XCTAssertNil(IOSDeviceSnapshot.RuntimeKind(rawValue: "iphone"))
        XCTAssertNil(IOSDeviceSnapshot.RuntimeKind(rawValue: "IPAD"))
    }

    // MARK: - diskUsagePct (pure Double math; guard total > 0)

    private func makeSnapshot(
        total: Int64,
        free: Int64,
        runtimeKind: IOSDeviceSnapshot.RuntimeKind = .iPhone
    ) -> IOSDeviceSnapshot {
        // Memberwise initializer of the internal struct — all `let` fields,
        // no custom init. Non-disk fields are inert for the property under test.
        IOSDeviceSnapshot(
            modelName: "TestModel",
            osName: "iOS",
            osVersion: "26.4",
            totalDiskBytes: total,
            freeDiskBytes: free,
            appUsedBytes: 0,
            physicalMemoryBytes: 0,
            processorCount: 1,
            uptimeSeconds: 0,
            batteryLevel: -1,
            batteryState: .unknown,
            hasBattery: false,
            runtimeKind: runtimeKind
        )
    }

    func testDiskUsagePct_halfFull() {
        let snap = makeSnapshot(total: 100, free: 50)
        XCTAssertEqual(snap.diskUsagePct, 0.5, accuracy: 1e-9)
    }

    func testDiskUsagePct_completelyFull_freeZero() {
        let snap = makeSnapshot(total: 100, free: 0)
        XCTAssertEqual(snap.diskUsagePct, 1.0, accuracy: 1e-9)
    }

    func testDiskUsagePct_completelyEmpty_freeEqualsTotal() {
        let snap = makeSnapshot(total: 100, free: 100)
        XCTAssertEqual(snap.diskUsagePct, 0.0, accuracy: 1e-9)
    }

    func testDiskUsagePct_zeroTotalGuardReturnsZero() {
        let snap = makeSnapshot(total: 0, free: 0)
        XCTAssertEqual(snap.diskUsagePct, 0.0, accuracy: 1e-9)
    }

    func testDiskUsagePct_zeroTotalWithNonzeroFreeStillReturnsZero() {
        // total <= 0 short-circuits before the division, regardless of free.
        let snap = makeSnapshot(total: 0, free: 999)
        XCTAssertEqual(snap.diskUsagePct, 0.0, accuracy: 1e-9)
    }

    func testDiskUsagePct_negativeTotalGuardReturnsZero() {
        // guard total > 0 also rejects negatives.
        let snap = makeSnapshot(total: -100, free: 10)
        XCTAssertEqual(snap.diskUsagePct, 0.0, accuracy: 1e-9)
    }

    func testDiskUsagePct_quarterFull() {
        let snap = makeSnapshot(total: 400, free: 300)
        XCTAssertEqual(snap.diskUsagePct, 0.25, accuracy: 1e-9)
    }

    func testDiskUsagePct_largeRealisticValues() {
        // 512 GB total, 128 GB free -> 0.75 used.
        let total: Int64 = 512_000_000_000
        let free: Int64 = 128_000_000_000
        let snap = makeSnapshot(total: total, free: free)
        XCTAssertEqual(snap.diskUsagePct, 0.75, accuracy: 1e-9)
    }

    func testDiskUsagePct_freeGreaterThanTotalGoesNegative() {
        // No clamping in the source: free > total yields a negative pct.
        let snap = makeSnapshot(total: 100, free: 150)
        XCTAssertEqual(snap.diskUsagePct, -0.5, accuracy: 1e-9)
    }

    func testDiskUsagePct_isIdempotent() {
        let snap = makeSnapshot(total: 1000, free: 250)
        XCTAssertEqual(snap.diskUsagePct, snap.diskUsagePct, accuracy: 1e-12)
    }

    // MARK: - Int64.humanBytes (ByteCountFormatter — assert non-empty/contains only)

    func testHumanBytes_zeroIsNonEmpty() {
        XCTAssertFalse(Int64(0).humanBytes.isEmpty)
    }

    func testHumanBytes_smallValueNonEmpty() {
        XCTAssertFalse(Int64(512).humanBytes.isEmpty)
    }

    func testHumanBytes_largeValueNonEmpty() {
        // 5 GB.
        XCTAssertFalse(Int64(5_000_000_000).humanBytes.isEmpty)
    }

    func testHumanBytes_negativeValueNonEmpty() {
        // ByteCountFormatter still returns a string for negatives; just non-empty.
        XCTAssertFalse(Int64(-1).humanBytes.isEmpty)
    }

    func testHumanBytes_containsByteUnitLetter() {
        // .file count style always emits a unit containing "B" (bytes/KB/MB/GB...).
        // Locale-agnostic: we only assert the unit letter is present, never an
        // exact localized number/format.
        XCTAssertTrue(Int64(1_000_000).humanBytes.contains("B"))
    }

    func testHumanBytes_isIdempotent() {
        let value = Int64(123_456_789)
        XCTAssertEqual(value.humanBytes, value.humanBytes)
    }

    func testHumanBytes_differentMagnitudesProduceStrings() {
        // Round-trip-style sanity: a range of magnitudes all yield non-empty output.
        for v in [Int64(1), 1_024, 1_048_576, 1_073_741_824, 1_099_511_627_776] {
            XCTAssertFalse(v.humanBytes.isEmpty, "humanBytes empty for \(v)")
        }
    }

    // MARK: - UIDevice.BatteryState.label (exhaustive over known cases)

    func testBatteryStateLabel_charging() {
        XCTAssertEqual(UIDevice.BatteryState.charging.label, "Lädt")
    }

    func testBatteryStateLabel_full() {
        XCTAssertEqual(UIDevice.BatteryState.full.label, "Voll")
    }

    func testBatteryStateLabel_unplugged() {
        XCTAssertEqual(UIDevice.BatteryState.unplugged.label, "Akku")
    }

    func testBatteryStateLabel_unknown() {
        XCTAssertEqual(UIDevice.BatteryState.unknown.label, "—")
    }

    func testBatteryStateLabel_unicodeEmDashForUnknown() {
        // The unknown label is the unicode em-dash (U+2014), a single character.
        let label = UIDevice.BatteryState.unknown.label
        XCTAssertEqual(label.count, 1)
        XCTAssertEqual(label.unicodeScalars.first?.value, 0x2014)
    }

    func testBatteryStateLabel_allKnownCasesNonEmpty() {
        let states: [UIDevice.BatteryState] = [.charging, .full, .unplugged, .unknown]
        for state in states {
            XCTAssertFalse(state.label.isEmpty)
        }
    }

    func testBatteryStateLabel_chargingDiffersFromFull() {
        XCTAssertNotEqual(
            UIDevice.BatteryState.charging.label,
            UIDevice.BatteryState.full.label
        )
    }

    // MARK: - IOSDeviceSnapshot Equatable + memberwise init

    func testSnapshotEquatable_identicalSnapshotsAreEqual() {
        let a = makeSnapshot(total: 100, free: 50)
        let b = makeSnapshot(total: 100, free: 50)
        XCTAssertEqual(a, b)
    }

    func testSnapshotEquatable_differingDiskMakesUnequal() {
        let a = makeSnapshot(total: 100, free: 50)
        let b = makeSnapshot(total: 100, free: 40)
        XCTAssertNotEqual(a, b)
    }

    func testSnapshotEquatable_differingRuntimeKindMakesUnequal() {
        let a = makeSnapshot(total: 100, free: 50, runtimeKind: .iPhone)
        let b = makeSnapshot(total: 100, free: 50, runtimeKind: .iPad)
        XCTAssertNotEqual(a, b)
    }

    func testSnapshotInit_preservesProvidedRuntimeKind() {
        let snap = makeSnapshot(total: 100, free: 50, runtimeKind: .iOSAppOnMac)
        XCTAssertEqual(snap.runtimeKind, .iOSAppOnMac)
        XCTAssertEqual(snap.runtimeKind.label, "Mac (iPad-App)")
        XCTAssertEqual(snap.runtimeKind.icon, "macbook")
    }
}
