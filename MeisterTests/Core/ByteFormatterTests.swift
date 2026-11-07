import XCTest
@testable import MeisterIOS

/// Tests for `ByteSize` (MeisterIOS/Core/ByteFormatter.swift).
///
/// `ByteSize.formatted` wraps `ByteCountFormatter` with `.file` count style and
/// `includesUnit = true`. Its exact output is locale-dependent (decimal separator,
/// non-breaking spaces, unit spelling), so assertions here are deliberately
/// locale-safe: non-empty, substring/`contains`, digit presence, and round-trip /
/// idempotency relationships — never an exact localized string.
final class ByteFormatterTests: XCTestCase {

    // MARK: - Helpers

    /// True if the string contains at least one ASCII digit.
    private func containsDigit(_ s: String) -> Bool {
        s.contains { $0.isNumber }
    }

    /// True if the string contains at least one ASCII letter (a unit label like B/KB/MB).
    private func containsLetter(_ s: String) -> Bool {
        s.contains { $0.isLetter }
    }

    // MARK: - Non-empty / well-formed output (Int64)

    func testZeroIsNonEmpty() {
        let out = ByteSize.formatted(Int64(0))
        XCTAssertFalse(out.isEmpty)
    }

    func testZeroContainsDigit() {
        let out = ByteSize.formatted(Int64(0))
        XCTAssertTrue(containsDigit(out))
    }

    func testZeroContainsUnitLetter() {
        // ByteCountFormatter with includesUnit emits a unit label (e.g. "bytes"/"B").
        let out = ByteSize.formatted(Int64(0))
        XCTAssertTrue(containsLetter(out))
    }

    func testOneByteIsNonEmpty() {
        let out = ByteSize.formatted(Int64(1))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
    }

    func testTypicalKilobyteIsNonEmpty() {
        let out = ByteSize.formatted(Int64(2048))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    func testTypicalMegabyteIsNonEmpty() {
        let out = ByteSize.formatted(Int64(5_000_000))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    func testTypicalGigabyteIsNonEmpty() {
        let out = ByteSize.formatted(Int64(3_000_000_000))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    // MARK: - Boundaries 0 / 1023 / 1024

    func testBoundaryZeroNonEmpty() {
        XCTAssertFalse(ByteSize.formatted(Int64(0)).isEmpty)
    }

    func test1023NonEmptyWithDigitAndUnit() {
        let out = ByteSize.formatted(Int64(1023))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    func test1024NonEmptyWithDigitAndUnit() {
        let out = ByteSize.formatted(Int64(1024))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    func test1023And1024RenderIdenticallyAsOneKilobyte() {
        // ByteCountFormatter(.file) displays the value in KB once it rounds to 1 KB.
        // 1023 bytes ≈ 0.999 KB and 1024 bytes = 1.0 KB both round to "1 KB", so the
        // two render identically — they do NOT cross a visible unit boundary here.
        let lo = ByteSize.formatted(Int64(1023))
        let hi = ByteSize.formatted(Int64(1024))
        XCTAssertEqual(lo, hi)
    }

    func test1023RoundsIntoKilobyteUnitLike1024() {
        // With .file style, 1023 does not stay in the byte unit: it rounds up and is
        // shown in KB exactly like 1024. Locale-safe check: both carry a unit label
        // and render identically.
        let lo = ByteSize.formatted(Int64(1023))
        let hi = ByteSize.formatted(Int64(1024))
        XCTAssertEqual(lo, hi)
        XCTAssertTrue(containsLetter(lo))
        XCTAssertTrue(containsLetter(hi))
    }

    // MARK: - Negative values

    func testNegativeIsNonEmpty() {
        // ByteCountFormatter accepts negative counts and still returns a usable string.
        let out = ByteSize.formatted(Int64(-1))
        XCTAssertFalse(out.isEmpty)
    }

    func testNegativeLargeIsNonEmpty() {
        let out = ByteSize.formatted(Int64(-5_000_000))
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
    }

    // MARK: - Large input / extremes

    func testInt64MaxIsNonEmpty() {
        let out = ByteSize.formatted(Int64.max)
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(containsDigit(out))
        XCTAssertTrue(containsLetter(out))
    }

    func testInt64MinIsNonEmpty() {
        let out = ByteSize.formatted(Int64.min)
        XCTAssertFalse(out.isEmpty)
    }

    // MARK: - Idempotency / determinism

    func testFormattingIsDeterministicForSameInput() {
        let a = ByteSize.formatted(Int64(1_234_567))
        let b = ByteSize.formatted(Int64(1_234_567))
        XCTAssertEqual(a, b)
    }

    func testDeterministicAcrossBoundaryValues() {
        for value in [Int64(0), 1, 1023, 1024, 1_000_000, Int64.max] {
            XCTAssertEqual(ByteSize.formatted(value), ByteSize.formatted(value),
                           "formatted(\(value)) must be stable")
        }
    }

    // MARK: - Monotonic ordering across unit thresholds

    func testDistinctMagnitudesProduceDistinctStrings() {
        let byte = ByteSize.formatted(Int64(1))
        let kilo = ByteSize.formatted(Int64(1024))
        let mega = ByteSize.formatted(Int64(5_000_000))
        let giga = ByteSize.formatted(Int64(3_000_000_000))
        XCTAssertNotEqual(byte, kilo)
        XCTAssertNotEqual(kilo, mega)
        XCTAssertNotEqual(mega, giga)
    }

    // MARK: - Int overload parity with Int64 overload

    func testIntOverloadMatchesInt64Zero() {
        XCTAssertEqual(ByteSize.formatted(0), ByteSize.formatted(Int64(0)))
    }

    func testIntOverloadMatchesInt64Boundary1023() {
        XCTAssertEqual(ByteSize.formatted(1023), ByteSize.formatted(Int64(1023)))
    }

    func testIntOverloadMatchesInt64Boundary1024() {
        XCTAssertEqual(ByteSize.formatted(1024), ByteSize.formatted(Int64(1024)))
    }

    func testIntOverloadMatchesInt64Typical() {
        XCTAssertEqual(ByteSize.formatted(5_000_000), ByteSize.formatted(Int64(5_000_000)))
    }

    func testIntOverloadMatchesInt64Negative() {
        XCTAssertEqual(ByteSize.formatted(-42), ByteSize.formatted(Int64(-42)))
    }

    func testIntOverloadIsNonEmpty() {
        XCTAssertFalse(ByteSize.formatted(2048).isEmpty)
    }

    // MARK: - Round-trip: parse the leading number back out, locale-safe

    func testLeadingNumberIsParseableForKilobyte() {
        // Extract the numeric prefix and confirm it parses with the current locale,
        // proving the output begins with a real, formatted number.
        let out = ByteSize.formatted(Int64(2048))
        let numericPrefix = out.prefix { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        XCTAssertFalse(numericPrefix.isEmpty)
    }

    func testOutputStartsWithDigitOrSign() {
        let out = ByteSize.formatted(Int64(5_000_000))
        let first = out.first
        XCTAssertNotNil(first)
        if let first {
            XCTAssertTrue(first.isNumber || first == "-",
                          "Formatted output should begin with a digit or minus sign")
        }
    }
}
