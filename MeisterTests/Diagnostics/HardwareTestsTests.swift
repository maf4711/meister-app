import XCTest
@testable import MeisterIOS

/// Unit tests for the pure, hardware-free surface of `HardwareTests.swift`:
/// the `HardwareTest` enum (raw values, `CaseIterable`, `Identifiable`, and its
/// `title` / `systemImage` lookup tables) and the `HardwareResult` value type
/// (memberwise init + result aggregation / pass-rate over arrays we build here).
///
/// Everything in `HardwareTestRunner` touches live hardware, permissions, audio,
/// or motion sensors (and is `private` anyway), so it is intentionally skipped.
final class HardwareTestsTests: XCTestCase {

    // MARK: - HardwareTest: raw values

    func testRawValuesMatchCaseNames() {
        XCTAssertEqual(HardwareTest.microphone.rawValue, "microphone")
        XCTAssertEqual(HardwareTest.speaker.rawValue, "speaker")
        XCTAssertEqual(HardwareTest.vibration.rawValue, "vibration")
        XCTAssertEqual(HardwareTest.accelerometer.rawValue, "accelerometer")
        XCTAssertEqual(HardwareTest.gyroscope.rawValue, "gyroscope")
        XCTAssertEqual(HardwareTest.touch.rawValue, "touch")
        XCTAssertEqual(HardwareTest.battery.rawValue, "battery")
    }

    func testInitFromValidRawValueRoundTrips() {
        for test in HardwareTest.allCases {
            XCTAssertEqual(HardwareTest(rawValue: test.rawValue), test)
        }
    }

    func testInitFromUnknownRawValueIsNil() {
        XCTAssertNil(HardwareTest(rawValue: "thermometer"))
        XCTAssertNil(HardwareTest(rawValue: ""))
        XCTAssertNil(HardwareTest(rawValue: "Microphone")) // case-sensitive
    }

    // MARK: - HardwareTest: Identifiable

    func testIDEqualsRawValue() {
        for test in HardwareTest.allCases {
            XCTAssertEqual(test.id, test.rawValue)
        }
    }

    func testIDsAreUniqueAcrossAllCases() {
        let ids = HardwareTest.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - HardwareTest: CaseIterable

    func testAllCasesCountAndOrder() {
        XCTAssertEqual(HardwareTest.allCases.count, 7)
        XCTAssertEqual(HardwareTest.allCases, [
            .microphone, .speaker, .vibration,
            .accelerometer, .gyroscope, .touch, .battery,
        ])
    }

    func testAllCasesContainsEveryKnownCase() {
        let cases = Set(HardwareTest.allCases)
        XCTAssertTrue(cases.contains(.microphone))
        XCTAssertTrue(cases.contains(.speaker))
        XCTAssertTrue(cases.contains(.vibration))
        XCTAssertTrue(cases.contains(.accelerometer))
        XCTAssertTrue(cases.contains(.gyroscope))
        XCTAssertTrue(cases.contains(.touch))
        XCTAssertTrue(cases.contains(.battery))
    }

    // MARK: - HardwareTest: title

    func testTitleExactValues() {
        XCTAssertEqual(HardwareTest.microphone.title, "Microphone")
        XCTAssertEqual(HardwareTest.speaker.title, "Speaker")
        XCTAssertEqual(HardwareTest.vibration.title, "Vibration")
        XCTAssertEqual(HardwareTest.accelerometer.title, "Accelerometer")
        XCTAssertEqual(HardwareTest.gyroscope.title, "Gyroscope")
        XCTAssertEqual(HardwareTest.touch.title, "Touch Response")
        XCTAssertEqual(HardwareTest.battery.title, "Battery")
    }

    func testTitleIsNonEmptyForEveryCase() {
        for test in HardwareTest.allCases {
            XCTAssertFalse(test.title.isEmpty, "title empty for \(test.rawValue)")
        }
    }

    func testTitlesAreUnique() {
        let titles = HardwareTest.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    // MARK: - HardwareTest: systemImage

    func testSystemImageExactValues() {
        XCTAssertEqual(HardwareTest.microphone.systemImage, "mic")
        XCTAssertEqual(HardwareTest.speaker.systemImage, "speaker.wave.2")
        XCTAssertEqual(HardwareTest.vibration.systemImage, "waveform")
        XCTAssertEqual(HardwareTest.accelerometer.systemImage, "gyroscope")
        XCTAssertEqual(HardwareTest.gyroscope.systemImage, "gauge")
        XCTAssertEqual(HardwareTest.touch.systemImage, "hand.tap")
        XCTAssertEqual(HardwareTest.battery.systemImage, "battery.100")
    }

    func testSystemImageIsNonEmptyForEveryCase() {
        for test in HardwareTest.allCases {
            XCTAssertFalse(test.systemImage.isEmpty, "systemImage empty for \(test.rawValue)")
        }
    }

    // MARK: - HardwareResult: memberwise init & property round-trip

    func testResultInitStoresAllProperties() {
        let result = HardwareResult(test: .battery, passed: true, detail: "100% charged")
        XCTAssertEqual(result.test, .battery)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.detail, "100% charged")
    }

    func testResultPreservesPassedFalseAndArbitraryDetail() {
        let result = HardwareResult(test: .microphone, passed: false, detail: "Permission denied")
        XCTAssertEqual(result.test, .microphone)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.detail, "Permission denied")
    }

    func testResultAcceptsEmptyDetail() {
        let result = HardwareResult(test: .speaker, passed: true, detail: "")
        XCTAssertTrue(result.detail.isEmpty)
    }

    func testResultPreservesUnicodeDetail() {
        let detail = "Magnitude: 1,02 g — café ✅ 测试"
        let result = HardwareResult(test: .accelerometer, passed: true, detail: detail)
        XCTAssertEqual(result.detail, detail)
        XCTAssertEqual(result.detail.count, detail.count)
    }

    func testResultPreservesLargeDetailString() {
        let detail = String(repeating: "x", count: 100_000)
        let result = HardwareResult(test: .gyroscope, passed: false, detail: detail)
        XCTAssertEqual(result.detail.count, 100_000)
    }

    func testResultsForEveryTestConstructible() {
        for test in HardwareTest.allCases {
            let result = HardwareResult(test: test, passed: true, detail: test.title)
            XCTAssertEqual(result.test, test)
            XCTAssertEqual(result.detail, test.title)
        }
    }

    // MARK: - Result aggregation / pass-rate (built from real HardwareResult values)

    func testPassRateAllPassed() {
        let results = HardwareTest.allCases.map {
            HardwareResult(test: $0, passed: true, detail: "ok")
        }
        let passed = results.filter(\.passed).count
        XCTAssertEqual(passed, results.count)
        XCTAssertEqual(Double(passed) / Double(results.count), 1.0, accuracy: 0.0001)
    }

    func testPassRateNonePassed() {
        let results = HardwareTest.allCases.map {
            HardwareResult(test: $0, passed: false, detail: "fail")
        }
        let passed = results.filter(\.passed).count
        XCTAssertEqual(passed, 0)
        XCTAssertEqual(Double(passed) / Double(results.count), 0.0, accuracy: 0.0001)
    }

    func testPassRateMixed() {
        let results = [
            HardwareResult(test: .microphone, passed: true, detail: "a"),
            HardwareResult(test: .speaker, passed: true, detail: "b"),
            HardwareResult(test: .vibration, passed: false, detail: "c"),
            HardwareResult(test: .battery, passed: true, detail: "d"),
        ]
        let passed = results.filter(\.passed).count
        XCTAssertEqual(passed, 3)
        XCTAssertEqual(Double(passed) / Double(results.count), 0.75, accuracy: 0.0001)
    }

    func testPassRateEmptyCollection() {
        let results: [HardwareResult] = []
        XCTAssertEqual(results.filter(\.passed).count, 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testFailedResultsCanBeIsolated() {
        let results = [
            HardwareResult(test: .microphone, passed: false, detail: "denied"),
            HardwareResult(test: .speaker, passed: true, detail: "tick"),
            HardwareResult(test: .accelerometer, passed: false, detail: "Not available"),
        ]
        let failedTests = results.filter { !$0.passed }.map(\.test)
        XCTAssertEqual(failedTests, [.microphone, .accelerometer])
    }

    func testAggregationCountIdempotentOnRepeatedReads() {
        let results = [
            HardwareResult(test: .touch, passed: true, detail: "x"),
            HardwareResult(test: .battery, passed: false, detail: "y"),
        ]
        let first = results.filter(\.passed).count
        let second = results.filter(\.passed).count
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, 1)
    }
}
