import XCTest
@testable import MeisterIOS

final class PhoneNormalizerTests: XCTestCase {
    func testIntlPrefix() {
        XCTAssertEqual(PhoneNormalizer.normalize("+49 151 12345678"), "+4915112345678")
        XCTAssertEqual(PhoneNormalizer.normalize("0049 151 12345678"), "+4915112345678")
    }
    func testNationalGermany() {
        XCTAssertEqual(PhoneNormalizer.normalize("0151 12345678"), "+4915112345678")
    }
    func testFormattingNoise() {
        XCTAssertEqual(PhoneNormalizer.normalize("+49 (151) 1234-5678"), "+4915112345678")
    }
    func testTooShort() {
        XCTAssertNil(PhoneNormalizer.normalize("12"))
    }
}
