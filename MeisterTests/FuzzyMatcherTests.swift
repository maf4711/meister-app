import XCTest
@testable import MeisterIOS

final class FuzzyMatcherTests: XCTestCase {
    func testExactMatch() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("Jan Kowalski", "Jan Kowalski"), 1.0, accuracy: 0.001)
    }
    func testCaseAndDiacritics() {
        let s = FuzzyMatcher.nameSimilarity("müller", "Mueller")
        XCTAssertGreaterThan(s, 0.3)
    }
    func testReorderedTokens() {
        let s = FuzzyMatcher.nameSimilarity("Jan Kowalski", "Kowalski, Jan")
        XCTAssertGreaterThan(s, 0.7)
    }
    func testUnrelated() {
        XCTAssertLessThan(FuzzyMatcher.nameSimilarity("Alice Smith", "Bob Jones"), 0.3)
    }
    func testLevenshtein() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(FuzzyMatcher.levenshtein("", "abc"), 3)
    }
}
