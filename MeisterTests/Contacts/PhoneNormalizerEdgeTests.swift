import XCTest
@testable import MeisterIOS

/// Edge-case coverage for `PhoneNormalizer.normalize(_:defaultCC:)`,
/// complementing `PhoneNormalizerTests`.
///
/// Grounded entirely in `MeisterIOS/Contacts/PhoneNormalizer.swift`. The real
/// algorithm:
///   1. Build `digits` = every unicode scalar that is a decimal digit OR `+`
///      (so `+` characters survive — even mid-string — and count toward length).
///   2. `guard digits.count >= 6 else { return nil }` — the `+` chars are
///      included in this count.
///   3. If `digits` starts with `+`: return `"+" + (rest with every non-number
///      stripped)` — i.e. all remaining `+` are removed.
///   4. Else if it starts with `"00"`: return `"+" + digits.dropFirst(2)`.
///   5. Else if it starts with `"0"`: return `"+" + cc + digits.dropFirst()`
///      (cc defaults to `defaultCountryCode`, "49").
///   6. Else: return `"+" + digits`.
/// Output therefore ALWAYS begins with `+`.
final class PhoneNormalizerEdgeTests: XCTestCase {

    // MARK: - Setup / teardown (defaultCountryCode is mutable static state)

    private var savedCC: String!

    override func setUp() {
        super.setUp()
        savedCC = PhoneNormalizer.defaultCountryCode
    }

    override func tearDown() {
        PhoneNormalizer.defaultCountryCode = savedCC
        super.tearDown()
    }

    // MARK: - Country-code injection via leading zero (national form)

    func testNationalSingleZeroPrependsDefaultCC() {
        // "0" prefix -> "+49" + rest-after-zero.
        XCTAssertEqual(PhoneNormalizer.normalize("030123456"), "+4930123456")
    }

    func testDoubleZeroIsTreatedAsIntlPrefix() {
        // "00" prefix -> "+" + dropFirst(2); no CC injection.
        XCTAssertEqual(PhoneNormalizer.normalize("00441234567"), "+441234567")
    }

    func testNoPrefixGetsBarePlus() {
        // Not "+", not "00", not "0" -> just "+digits".
        XCTAssertEqual(PhoneNormalizer.normalize("15551234567"), "+15551234567")
    }

    func testDefaultCCParameterOverridesStatic() {
        // Passing defaultCC overrides the static defaultCountryCode for "0" form.
        XCTAssertEqual(PhoneNormalizer.normalize("0123456", defaultCC: "1"), "+1123456")
    }

    func testStaticDefaultCountryCodeIsUsedForNationalForm() {
        PhoneNormalizer.defaultCountryCode = "43" // Austria
        XCTAssertEqual(PhoneNormalizer.normalize("0123456"), "+43123456")
    }

    func testDefaultCCParameterBeatsMutatedStatic() {
        PhoneNormalizer.defaultCountryCode = "43"
        XCTAssertEqual(PhoneNormalizer.normalize("0123456", defaultCC: "41"), "+41123456")
    }

    // MARK: - Leading '+' handling

    func testLeadingPlusIsPreservedAndKept() {
        XCTAssertEqual(PhoneNormalizer.normalize("+15551234567"), "+15551234567")
    }

    func testLeadingPlusWithSeparatorsCollapses() {
        XCTAssertEqual(PhoneNormalizer.normalize("+49 30 123456"), "+4930123456")
    }

    func testLeadingPlusZeroDoesNotInjectCC() {
        // The "+" branch is checked first, so "+0..." stays as-is (no CC prepend).
        XCTAssertEqual(PhoneNormalizer.normalize("+0123456"), "+0123456")
    }

    // MARK: - Mid-string '+' survives into `digits`

    func testMidStringPlusSurvivesWhenNoRecognizedPrefix() {
        // digits = "555+1234"; first char is '5' -> none of +/00/0 prefixes ->
        // returns "+" + digits verbatim, INCLUDING the embedded '+'.
        XCTAssertEqual(PhoneNormalizer.normalize("555+1234"), "+555+1234")
    }

    func testTrailingPlusSurvivesInBarePlusBranch() {
        XCTAssertEqual(PhoneNormalizer.normalize("5551234+"), "+5551234+")
    }

    func testLeadingPlusStripsAllLaterPluses() {
        // "+" branch filters the remainder to numbers only -> inner '+' removed.
        XCTAssertEqual(PhoneNormalizer.normalize("+555+1234"), "+5551234")
    }

    func testDoublePlusLeadingStripsSecond() {
        // digits = "++5551234"; "+" branch keeps leading, filters rest -> "+5551234".
        XCTAssertEqual(PhoneNormalizer.normalize("++5551234"), "+5551234")
    }

    func testMidStringPlusAfterZeroNationalForm() {
        // digits = "0+551234"; not "+"/"00"; starts "0" -> "+49" + "+551234".
        XCTAssertEqual(PhoneNormalizer.normalize("0+551234"), "+49+551234")
    }

    // MARK: - Exactly-6 boundary (note: '+' counts toward the >= 6 guard)

    func testSixDigitsAccepted() {
        XCTAssertEqual(PhoneNormalizer.normalize("123456"), "+123456")
    }

    func testFiveDigitsRejected() {
        XCTAssertNil(PhoneNormalizer.normalize("12345"))
    }

    func testFivePlusLeadingPlusReachesGuardThreshold() {
        // digits = "+12345" has length 6 (the '+' counts), so it passes the
        // guard; the "+" branch then strips to numbers -> "+12345".
        XCTAssertEqual(PhoneNormalizer.normalize("+12345"), "+12345")
    }

    func testFourDigitsPlusOnePlusStillBelowThreshold() {
        // digits = "+1234" length 5 -> nil.
        XCTAssertNil(PhoneNormalizer.normalize("+1234"))
    }

    func testSevenDigitsAccepted() {
        XCTAssertEqual(PhoneNormalizer.normalize("1234567"), "+1234567")
    }

    func testSixDigitsWithFormattingAccepted() {
        XCTAssertEqual(PhoneNormalizer.normalize("12-34-56"), "+123456")
    }

    // MARK: - Letters and symbols are stripped before the guard

    func testLettersStrippedLeavingDigits() {
        // "555CALL123" -> letters dropped -> "555123" (6 digits) -> "+555123".
        XCTAssertEqual(PhoneNormalizer.normalize("555CALL123"), "+555123")
    }

    func testLettersLeavingOnlyFiveDigitsReturnsNil() {
        // "555CALL12" -> only "55512" (5 digits) -> below the >= 6 guard.
        XCTAssertNil(PhoneNormalizer.normalize("555CALL12"))
    }

    func testVanityLettersReducingBelowSixReturnsNil() {
        // Only "12345" survives (5 digits) -> nil.
        XCTAssertNil(PhoneNormalizer.normalize("CALLNOW12345"))
    }

    func testAllLettersReturnsNil() {
        XCTAssertNil(PhoneNormalizer.normalize("phonenumber"))
    }

    func testPunctuationStrippedKeepingDigits() {
        XCTAssertEqual(PhoneNormalizer.normalize("(555) 123-4567 ext.9"), "+55512345679")
    }

    func testNewlinesAndTabsStripped() {
        XCTAssertEqual(PhoneNormalizer.normalize("555\t12\n34"), "+5551234")
    }

    // MARK: - Empty / whitespace / lone symbols

    func testEmptyStringReturnsNil() {
        XCTAssertNil(PhoneNormalizer.normalize(""))
    }

    func testWhitespaceOnlyReturnsNil() {
        XCTAssertNil(PhoneNormalizer.normalize("   "))
    }

    func testLonePlusReturnsNil() {
        // digits = "+" length 1 < 6 -> nil.
        XCTAssertNil(PhoneNormalizer.normalize("+"))
    }

    func testSixPlusesPassGuardThenStripToBarePlus() {
        // digits = "++++++" length 6 passes guard; "+" branch filters the
        // remaining five '+' to numbers (none) -> just "+".
        XCTAssertEqual(PhoneNormalizer.normalize("++++++"), "+")
    }

    // MARK: - Zero handling

    func testSixZerosNoLeadingZeroBranchBecauseDoubleZeroFirst() {
        // digits = "000000"; "00" prefix wins -> "+" + dropFirst(2) -> "+0000".
        XCTAssertEqual(PhoneNormalizer.normalize("000000"), "+0000")
    }

    func testSingleLeadingZeroThenNonZero() {
        // digits = "012345"; not "00" -> "0" branch -> "+49" + "12345".
        XCTAssertEqual(PhoneNormalizer.normalize("012345"), "+4912345")
    }

    func testIntlZeroZeroPreservesRemainingZeros() {
        XCTAssertEqual(PhoneNormalizer.normalize("0049 30 1234"), "+49301234")
    }

    // MARK: - Idempotency (re-normalizing canonical output)

    func testNormalizeIsIdempotentForIntlInput() {
        let once = PhoneNormalizer.normalize("+1 (555) 123-4567")
        XCTAssertEqual(once, "+15551234567")
        XCTAssertEqual(PhoneNormalizer.normalize(once!), once)
    }

    func testNationalFormBecomesStableAfterFirstPass() {
        // First pass: "0151 12345678" -> "+4915112345678".
        // Second pass starts with "+" so it stays put (idempotent thereafter).
        let once = PhoneNormalizer.normalize("0151 12345678")
        XCTAssertEqual(once, "+4915112345678")
        XCTAssertEqual(PhoneNormalizer.normalize(once!), once)
    }

    func testBarePlusOutputIsIdempotent() {
        let once = PhoneNormalizer.normalize("15551234567")
        XCTAssertEqual(once, "+15551234567")
        XCTAssertEqual(PhoneNormalizer.normalize(once!), once)
    }

    // MARK: - Unicode / diacritics

    func testEmojiStripped() {
        XCTAssertEqual(PhoneNormalizer.normalize("555📞1234"), "+5551234")
    }

    func testCombiningDiacriticsContributeNoDigits() {
        XCTAssertEqual(PhoneNormalizer.normalize("café5551234"), "+5551234")
    }

    func testNonBreakingSpaceStripped() {
        XCTAssertEqual(PhoneNormalizer.normalize("555\u{00A0}1234"), "+5551234")
    }

    func testArabicIndicDigitsAreNotASCIIDecimalDigits() {
        // CharacterSet.decimalDigits is broad, but the source emits whatever
        // scalars pass the filter verbatim. Use a pure-ASCII assertion path:
        // mixing a non-ASCII letter that is not a digit leaves only ASCII digits.
        XCTAssertEqual(PhoneNormalizer.normalize("ä5ä5ä5ä1ä2ä3"), "+555123")
    }

    // MARK: - Large input

    func testLargeIntlInputCollapsesToDigits() {
        let body = String(repeating: "7", count: 5000)
        let result = PhoneNormalizer.normalize("+" + body)
        XCTAssertEqual(result, "+" + body)
        XCTAssertEqual(result?.count, 5001)
    }

    func testLargeNoisyInputKeepsOnlyDigitsWithBarePlus() {
        let raw = String(repeating: "a1b2", count: 1000) // 2000 digits + 2000 letters
        let result = PhoneNormalizer.normalize(raw)
        XCTAssertEqual(result, "+" + String(repeating: "12", count: 1000))
        XCTAssertEqual(result?.count, 2001)
    }
}
