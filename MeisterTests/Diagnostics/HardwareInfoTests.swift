import XCTest
import UIKit
@testable import MeisterIOS

// Tests for MeisterIOS/Diagnostics/HardwareInfo.swift
//
// Grounding notes:
// - `HardwareInfo` is an internal struct with the compiler-synthesized internal
//   memberwise initializer. Every stored property is asserted via round-trip.
// - `HardwareInfo.read()` reads live `UIDevice.current` / `ProcessInfo` / `uname`
//   state, which is non-deterministic and (for battery) requires device support.
//   Per the test brief we do NOT assert its live values; one type-level smoke
//   test only confirms it is callable and returns the right type without crashing.
// - Enum cases used (`ProcessInfo.ThermalState`, `UIDevice.BatteryState`) are
//   real Foundation/UIKit cases; naming them needs no device authorization.
final class HardwareInfoTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a HardwareInfo via the synthesized memberwise init with overridable
    /// fields. Uses only the real property labels seen in HardwareInfo.swift.
    private func makeInfo(
        deviceName: String = "iPhone",
        systemName: String = "iOS",
        systemVersion: String = "17.0",
        model: String = "iPhone",
        identifier: String = "iPhone16,1",
        thermalState: ProcessInfo.ThermalState = .nominal,
        lowPowerMode: Bool = false,
        batteryLevel: Float = 1.0,
        batteryState: UIDevice.BatteryState = .full
    ) -> HardwareInfo {
        HardwareInfo(
            deviceName: deviceName,
            systemName: systemName,
            systemVersion: systemVersion,
            model: model,
            identifier: identifier,
            thermalState: thermalState,
            lowPowerMode: lowPowerMode,
            batteryLevel: batteryLevel,
            batteryState: batteryState
        )
    }

    // MARK: - Memberwise init: happy-path round-trip

    func testMemberwiseInit_storesAllStringFields() {
        let info = makeInfo(
            deviceName: "Marco's iPhone",
            systemName: "iOS",
            systemVersion: "17.4.1",
            model: "iPhone",
            identifier: "iPhone16,2"
        )
        XCTAssertEqual(info.deviceName, "Marco's iPhone")
        XCTAssertEqual(info.systemName, "iOS")
        XCTAssertEqual(info.systemVersion, "17.4.1")
        XCTAssertEqual(info.model, "iPhone")
        XCTAssertEqual(info.identifier, "iPhone16,2")
    }

    func testMemberwiseInit_storesAllScalarFields() {
        let info = makeInfo(
            thermalState: .serious,
            lowPowerMode: true,
            batteryLevel: 0.42,
            batteryState: .charging
        )
        XCTAssertEqual(info.thermalState, .serious)
        XCTAssertTrue(info.lowPowerMode)
        XCTAssertEqual(info.batteryLevel, 0.42, accuracy: 0.0001)
        XCTAssertEqual(info.batteryState, .charging)
    }

    // MARK: - String fields: empty

    func testEmptyStringFields_arePreservedNotCoerced() {
        let info = makeInfo(
            deviceName: "",
            systemName: "",
            systemVersion: "",
            model: "",
            identifier: ""
        )
        XCTAssertEqual(info.deviceName, "")
        XCTAssertEqual(info.systemName, "")
        XCTAssertEqual(info.systemVersion, "")
        XCTAssertEqual(info.model, "")
        XCTAssertTrue(info.identifier.isEmpty)
    }

    // MARK: - String fields: unicode

    func testUnicodeDeviceName_isPreservedExactly() {
        let name = "Müller’s 📱 iPhone — Über"
        let info = makeInfo(deviceName: name)
        XCTAssertEqual(info.deviceName, name)
        XCTAssertEqual(info.deviceName.count, name.count)
    }

    func testUnicodeIdentifier_isPreservedExactly() {
        let ident = "iPhone\u{2014}Test\u{1F50B}"
        let info = makeInfo(identifier: ident)
        XCTAssertEqual(info.identifier, ident)
    }

    // MARK: - String fields: large input

    func testLargeDeviceName_isPreservedExactly() {
        let big = String(repeating: "A", count: 100_000)
        let info = makeInfo(deviceName: big)
        XCTAssertEqual(info.deviceName.count, 100_000)
        XCTAssertEqual(info.deviceName, big)
    }

    // MARK: - batteryLevel: boundaries / zero / negative

    func testBatteryLevel_zero() {
        let info = makeInfo(batteryLevel: 0.0)
        XCTAssertEqual(info.batteryLevel, 0.0, accuracy: 0.0001)
    }

    func testBatteryLevel_fullBoundary() {
        let info = makeInfo(batteryLevel: 1.0)
        XCTAssertEqual(info.batteryLevel, 1.0, accuracy: 0.0001)
    }

    func testBatteryLevel_negativeOne_sentinelIsPreserved() {
        // UIDevice reports -1.0 when level is unavailable; the struct must not clamp it.
        let info = makeInfo(batteryLevel: -1.0)
        XCTAssertEqual(info.batteryLevel, -1.0, accuracy: 0.0001)
    }

    func testBatteryLevel_midRange() {
        let info = makeInfo(batteryLevel: 0.5)
        XCTAssertEqual(info.batteryLevel, 0.5, accuracy: 0.0001)
    }

    func testBatteryLevel_aboveOne_isPreservedNotClamped() {
        let info = makeInfo(batteryLevel: 1.5)
        XCTAssertEqual(info.batteryLevel, 1.5, accuracy: 0.0001)
    }

    // MARK: - lowPowerMode: both values

    func testLowPowerMode_falseIsStored() {
        XCTAssertFalse(makeInfo(lowPowerMode: false).lowPowerMode)
    }

    func testLowPowerMode_trueIsStored() {
        XCTAssertTrue(makeInfo(lowPowerMode: true).lowPowerMode)
    }

    // MARK: - thermalState: every case

    func testThermalState_nominal() {
        XCTAssertEqual(makeInfo(thermalState: .nominal).thermalState, .nominal)
    }

    func testThermalState_fair() {
        XCTAssertEqual(makeInfo(thermalState: .fair).thermalState, .fair)
    }

    func testThermalState_serious() {
        XCTAssertEqual(makeInfo(thermalState: .serious).thermalState, .serious)
    }

    func testThermalState_critical() {
        XCTAssertEqual(makeInfo(thermalState: .critical).thermalState, .critical)
    }

    func testThermalState_distinctCasesAreNotEqual() {
        XCTAssertNotEqual(makeInfo(thermalState: .nominal).thermalState,
                          makeInfo(thermalState: .critical).thermalState)
    }

    // MARK: - batteryState: every case

    func testBatteryState_unknown() {
        XCTAssertEqual(makeInfo(batteryState: .unknown).batteryState, .unknown)
    }

    func testBatteryState_unplugged() {
        XCTAssertEqual(makeInfo(batteryState: .unplugged).batteryState, .unplugged)
    }

    func testBatteryState_charging() {
        XCTAssertEqual(makeInfo(batteryState: .charging).batteryState, .charging)
    }

    func testBatteryState_full() {
        XCTAssertEqual(makeInfo(batteryState: .full).batteryState, .full)
    }

    func testBatteryState_distinctCasesAreNotEqual() {
        XCTAssertNotEqual(makeInfo(batteryState: .charging).batteryState,
                          makeInfo(batteryState: .unplugged).batteryState)
    }

    // MARK: - Field independence / no cross-talk

    func testFieldsAreIndependent_changingOneDoesNotAffectOthers() {
        let base = makeInfo()
        let changed = makeInfo(systemVersion: "99.9", batteryLevel: 0.1)
        // Only the two overridden fields differ; the rest match the shared defaults.
        XCTAssertEqual(changed.deviceName, base.deviceName)
        XCTAssertEqual(changed.systemName, base.systemName)
        XCTAssertEqual(changed.model, base.model)
        XCTAssertEqual(changed.identifier, base.identifier)
        XCTAssertEqual(changed.thermalState, base.thermalState)
        XCTAssertEqual(changed.lowPowerMode, base.lowPowerMode)
        XCTAssertEqual(changed.batteryState, base.batteryState)
        XCTAssertNotEqual(changed.systemVersion, base.systemVersion)
        XCTAssertNotEqual(changed.batteryLevel, base.batteryLevel)
    }

    // MARK: - Idempotency of construction

    func testConstruction_isIdempotentForIdenticalInputs() {
        let a = makeInfo(deviceName: "X", identifier: "iPhone1,1", batteryLevel: 0.33)
        let b = makeInfo(deviceName: "X", identifier: "iPhone1,1", batteryLevel: 0.33)
        XCTAssertEqual(a.deviceName, b.deviceName)
        XCTAssertEqual(a.identifier, b.identifier)
        XCTAssertEqual(a.batteryLevel, b.batteryLevel, accuracy: 0.0001)
        XCTAssertEqual(a.thermalState, b.thermalState)
        XCTAssertEqual(a.batteryState, b.batteryState)
        XCTAssertEqual(a.lowPowerMode, b.lowPowerMode)
    }

    // MARK: - read(): type-level smoke only (live state is non-deterministic)

    func testRead_returnsHardwareInfoWithoutCrashing() {
        // No value assertions: read() reflects live device/process state which is
        // not deterministic across hosts. We only confirm it is callable and that
        // its fields are of the declared types (compile-time + runtime guard).
        let info = HardwareInfo.read()
        XCTAssertTrue(type(of: info.identifier) == String.self)
        XCTAssertTrue(type(of: info.deviceName) == String.self)
        XCTAssertTrue(type(of: info.batteryLevel) == Float.self)
        XCTAssertTrue(type(of: info.lowPowerMode) == Bool.self)
    }
}
