import XCTest
@testable import MeisterIOS

/// Additional, deeper edge-case coverage for `FuzzyMatcher` that is NOT already
/// exercised in `FuzzyMatcherTests`. Every numeric expectation below was derived
/// by hand from the real implementation in `MeisterIOS/Contacts/FuzzyMatcher.swift`:
///   - `levenshtein` is the standard Wagner–Fischer edit distance (NO Damerau
///     transposition shortcut → an adjacent swap costs 2).
///   - `canonicalize` = lowercase → German digraph expansion (ü/ö/ä/ß) →
///     diacritic-insensitive folding.
///   - `nameSimilarity` = 0.6 * Jaccard(token sets) + 0.4 * (1 - lev/maxLen),
///     with a `return 0` guard whenever either side has no letter tokens.
final class FuzzyMatcherDeepTests: XCTestCase {

    // MARK: - levenshtein: empty strings

    func testLevenshteinBothEmptyIsZero() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("", ""), 0)
    }

    func testLevenshteinNonEmptyToEmptyEqualsLength() {
        // Reverse of the existing `("", "abc")` case: source non-empty, target empty.
        XCTAssertEqual(FuzzyMatcher.levenshtein("abc", ""), 3)
    }

    func testLevenshteinEmptyToNonEmptyEqualsLength() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("", "hello"), 5)
    }

    // MARK: - levenshtein: single character

    func testLevenshteinSingleCharIdenticalIsZero() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("a", "a"), 0)
    }

    func testLevenshteinSingleCharSubstitutionIsOne() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("a", "b"), 1)
    }

    func testLevenshteinSingleCharToEmptyIsOne() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("a", ""), 1)
    }

    // MARK: - levenshtein: transposition (non-Damerau → costs 2)

    func testLevenshteinAdjacentTranspositionCostsTwo() {
        // "ab" → "ba" has no special transposition rule, so it is two edits.
        XCTAssertEqual(FuzzyMatcher.levenshtein("ab", "ba"), 2)
    }

    func testLevenshteinThreeCharSwapCostsTwo() {
        // "abc" → "acb": substitute positions 2 and 3.
        XCTAssertEqual(FuzzyMatcher.levenshtein("abc", "acb"), 2)
    }

    // MARK: - levenshtein: insertion / deletion semantics

    func testLevenshteinPureSuffixInsertion() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("abc", "abcdef"), 3)
    }

    func testLevenshteinWhitespaceCountsAsCharacter() {
        // Deleting the single space is one edit.
        XCTAssertEqual(FuzzyMatcher.levenshtein("a b", "ab"), 1)
    }

    // MARK: - levenshtein: symmetry

    func testLevenshteinIsSymmetric() {
        XCTAssertEqual(
            FuzzyMatcher.levenshtein("kitten", "sitting"),
            FuzzyMatcher.levenshtein("sitting", "kitten")
        )
    }

    func testLevenshteinIsSymmetricForEmptyAndNonEmpty() {
        XCTAssertEqual(
            FuzzyMatcher.levenshtein("xyz", ""),
            FuzzyMatcher.levenshtein("", "xyz")
        )
    }

    // MARK: - levenshtein: identity & bounds

    func testLevenshteinIdentityIsZero() {
        XCTAssertEqual(FuzzyMatcher.levenshtein("Kowalski", "Kowalski"), 0)
    }

    func testLevenshteinNeverExceedsLongerLength() {
        let d = FuzzyMatcher.levenshtein("abc", "xyzw")
        XCTAssertLessThanOrEqual(d, max("abc".count, "xyzw".count))
        XCTAssertGreaterThanOrEqual(d, 0)
    }

    func testLevenshteinAtLeastLengthDifference() {
        // Edit distance must cover the raw length gap at minimum.
        let d = FuzzyMatcher.levenshtein("a", "aaaaa")
        XCTAssertGreaterThanOrEqual(d, abs("a".count - "aaaaa".count))
        XCTAssertEqual(d, 4)
    }

    // MARK: - levenshtein: long input

    func testLevenshteinLongIdenticalIsZero() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(FuzzyMatcher.levenshtein(long, long), 0)
    }

    func testLevenshteinLongSingleSubstitution() {
        let base = String(repeating: "a", count: 100)
        let mutated = String(repeating: "a", count: 99) + "b"
        XCTAssertEqual(FuzzyMatcher.levenshtein(base, mutated), 1)
    }

    func testLevenshteinLongToEmptyEqualsLength() {
        let long = String(repeating: "z", count: 150)
        XCTAssertEqual(FuzzyMatcher.levenshtein(long, ""), 150)
    }

    // MARK: - levenshtein: unicode grapheme clusters

    func testLevenshteinTreatsAccentedCharAsSingleEdit() {
        // "café" vs "cafe" differ only in the final grapheme.
        XCTAssertEqual(FuzzyMatcher.levenshtein("café", "cafe"), 1)
    }

    func testLevenshteinFlagEmojiIsSingleGrapheme() {
        // A regional-indicator flag is one Swift Character (grapheme cluster).
        XCTAssertEqual(FuzzyMatcher.levenshtein("🇩🇪", "🇩🇪"), 0)
        XCTAssertEqual(FuzzyMatcher.levenshtein("🇩🇪", "🇫🇷"), 1)
    }

    // MARK: - canonicalize: empty

    func testCanonicalizeEmptyStaysEmpty() {
        XCTAssertEqual(FuzzyMatcher.canonicalize(""), "")
    }

    // MARK: - canonicalize: German umlauts → digraphs (exact, no locale folding ambiguity)

    func testCanonicalizeUmlautUExpandsToUe() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("Müller"), "mueller")
    }

    func testCanonicalizeUmlautOExpandsToOe() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("Öl"), "oel")
    }

    func testCanonicalizeUmlautAExpandsToAe() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("Ärger"), "aerger")
    }

    func testCanonicalizeEszettExpandsToSs() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("Straße"), "strasse")
    }

    func testCanonicalizeAllUmlautsCombined() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("äöüß"), "aeoeuess")
    }

    // MARK: - canonicalize: German equivalence (cross-call, no hardcoded folding output)

    func testCanonicalizeMuellerVariantsAreEqual() {
        XCTAssertEqual(
            FuzzyMatcher.canonicalize("Müller"),
            FuzzyMatcher.canonicalize("Mueller")
        )
    }

    func testCanonicalizeEszettAndSsAreEqual() {
        XCTAssertEqual(
            FuzzyMatcher.canonicalize("Straße"),
            FuzzyMatcher.canonicalize("Strasse")
        )
    }

    // MARK: - canonicalize: case folding

    func testCanonicalizeUppercaseAsciiBecomesLowercase() {
        XCTAssertEqual(FuzzyMatcher.canonicalize("HELLO WORLD"), "hello world")
    }

    func testCanonicalizeIsCaseInsensitive() {
        XCTAssertEqual(
            FuzzyMatcher.canonicalize("KOWALSKI"),
            FuzzyMatcher.canonicalize("kowalski")
        )
    }

    // MARK: - canonicalize: diacritic stripping (non-German), conservative on locale

    func testCanonicalizeStripsNonGermanDiacritics() {
        // é → e is canonical diacritic folding; assert via cross-call equality and
        // absence of the accented scalar rather than a hardcoded localized string.
        let folded = FuzzyMatcher.canonicalize("Café")
        XCTAssertEqual(folded, FuzzyMatcher.canonicalize("cafe"))
        XCTAssertFalse(folded.contains("é"))
        XCTAssertFalse(folded.isEmpty)
    }

    // MARK: - canonicalize: idempotency

    func testCanonicalizeIsIdempotentForGermanInput() {
        let once = FuzzyMatcher.canonicalize("Müller-Straße")
        XCTAssertEqual(FuzzyMatcher.canonicalize(once), once)
    }

    func testCanonicalizeIsIdempotentForMixedInput() {
        let once = FuzzyMatcher.canonicalize("ÄÖÜ Café HELLO")
        XCTAssertEqual(FuzzyMatcher.canonicalize(once), once)
    }

    // MARK: - nameSimilarity: empty / guard / non-letter input

    func testNameSimilarityBothEmptyIsZero() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("", ""), 0.0, accuracy: 0.0001)
    }

    func testNameSimilarityEmptyRightIsZero() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("Jan", ""), 0.0, accuracy: 0.0001)
    }

    func testNameSimilarityEmptyLeftIsZero() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("", "Jan"), 0.0, accuracy: 0.0001)
    }

    func testNameSimilarityDigitsOnlyHaveNoTokensIsZero() {
        // Digits are non-letters → no tokens → guard returns 0.
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("123", "456"), 0.0, accuracy: 0.0001)
    }

    func testNameSimilarityPunctuationOnlyIsZero() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("---", "Jan"), 0.0, accuracy: 0.0001)
    }

    // MARK: - nameSimilarity: identity / reflexivity

    func testNameSimilaritySingleTokenIdenticalIsOne() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("Jan", "Jan"), 1.0, accuracy: 0.0001)
    }

    func testNameSimilarityReflexiveIsOne() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("Hello", "Hello"), 1.0, accuracy: 0.0001)
    }

    // MARK: - nameSimilarity: case folding & diacritics collapse to exact 1.0

    func testNameSimilarityIsCaseInsensitiveExactlyOne() {
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("HELLO", "hello"), 1.0, accuracy: 0.0001)
    }

    func testNameSimilarityMuellerVariantsAreExactlyOne() {
        // canonicalize maps both to "mueller" → Jaccard 1, lev 0 → score 1.0.
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("Müller", "Mueller"), 1.0, accuracy: 0.0001)
    }

    // MARK: - nameSimilarity: multi-token Jaccard (exact derived scores)

    func testNameSimilaritySupersetTokenExactScore() {
        // tokens {ab,cd} vs {ab,cd,ef}: Jaccard 2/3; lev("ab cd","ab cd ef")=3, max len 8.
        // score = 0.6*(2/3) + 0.4*(1 - 3/8) = 0.4 + 0.25 = 0.65
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("ab cd", "ab cd ef"), 0.65, accuracy: 0.0001)
    }

    func testNameSimilarityDuplicateTokensCollapseInJaccard() {
        // "ab ab" → token set {ab}; vs "ab" → {ab}: Jaccard 1.
        // lev("ab ab","ab")=3, max len 5 → score = 0.6 + 0.4*(1 - 3/5) = 0.6 + 0.16 = 0.76
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("ab ab", "ab"), 0.76, accuracy: 0.0001)
    }

    func testNameSimilarityDisjointShortTokensIsZero() {
        // tokens {ab} vs {cd}: Jaccard 0; lev("ab","cd")=2, max len 2 → lev term 0.
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("ab", "cd"), 0.0, accuracy: 0.0001)
    }

    func testNameSimilarityPartialOverlapExactScore() {
        // {ab,cd} vs {ab,ef}: Jaccard 1/3; lev("ab cd","ab ef")=2, max len 5.
        // score = 0.6*(1/3) + 0.4*(1 - 2/5) = 0.2 + 0.24 = 0.44
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("ab cd", "ab ef"), 0.44, accuracy: 0.0001)
    }

    func testNameSimilarityFullyDisjointMultiTokenExactScore() {
        // {ab,cd} vs {gh,ij}: Jaccard 0; lev("ab cd","gh ij")=4 (space aligns), max len 5.
        // score = 0.4*(1 - 4/5) = 0.08
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("ab cd", "gh ij"), 0.08, accuracy: 0.0001)
    }

    // MARK: - nameSimilarity: transposition penalty (single token)

    func testNameSimilarityTransposedSingleTokenExactScore() {
        // {abc} vs {acb}: Jaccard 0; lev("abc","acb")=2, max len 3.
        // score = 0.4*(1 - 2/3) = 0.1333…
        XCTAssertEqual(FuzzyMatcher.nameSimilarity("abc", "acb"), 0.4 * (1.0 / 3.0), accuracy: 0.0001)
    }

    // MARK: - nameSimilarity: reordered tokens (Jaccard 1, lev penalised)

    func testNameSimilarityReorderedTokensBoundedBetweenSixtyAndOne() {
        // Same token set → Jaccard 1 → score >= 0.6; word order differs → lev < 1 → score < 1.
        let s = FuzzyMatcher.nameSimilarity("Anna Schmidt", "Schmidt Anna")
        XCTAssertGreaterThan(s, 0.6)
        XCTAssertLessThan(s, 1.0)
    }

    // MARK: - nameSimilarity: symmetry

    func testNameSimilarityIsSymmetricForReorderedTokens() {
        XCTAssertEqual(
            FuzzyMatcher.nameSimilarity("Anna Schmidt", "Schmidt Anna"),
            FuzzyMatcher.nameSimilarity("Schmidt Anna", "Anna Schmidt"),
            accuracy: 0.0001
        )
    }

    func testNameSimilarityIsSymmetricForDiacritics() {
        XCTAssertEqual(
            FuzzyMatcher.nameSimilarity("Müller", "Mueller"),
            FuzzyMatcher.nameSimilarity("Mueller", "Müller"),
            accuracy: 0.0001
        )
    }

    func testNameSimilarityIsSymmetricForPartialOverlap() {
        XCTAssertEqual(
            FuzzyMatcher.nameSimilarity("ab cd", "ab ef"),
            FuzzyMatcher.nameSimilarity("ab ef", "ab cd"),
            accuracy: 0.0001
        )
    }

    // MARK: - nameSimilarity: range invariant & ordering

    func testNameSimilarityAlwaysWithinUnitInterval() {
        let pairs: [(String, String)] = [
            ("Hello World", "World Hello"),
            ("Jan Kowalski", "Jan Smith"),
            ("foo", "bar"),
            ("Straße 12", "Strasse 99"),
            ("", "anything")
        ]
        for (a, b) in pairs {
            let s = FuzzyMatcher.nameSimilarity(a, b)
            XCTAssertGreaterThanOrEqual(s, 0.0, "\(a) vs \(b)")
            XCTAssertLessThanOrEqual(s, 1.0, "\(a) vs \(b)")
        }
    }

    func testNameSimilarityRanksByCloseness() {
        let identical = FuzzyMatcher.nameSimilarity("ab cd", "ab cd")
        let partial = FuzzyMatcher.nameSimilarity("ab cd", "ab ef")
        let disjoint = FuzzyMatcher.nameSimilarity("ab cd", "gh ij")
        XCTAssertGreaterThan(identical, partial)
        XCTAssertGreaterThan(partial, disjoint)
    }

    // MARK: - nameSimilarity: large input

    func testNameSimilarityLargeIdenticalInputIsOne() {
        let many = (0..<100).map { "tok\($0)" }.joined(separator: " ")
        XCTAssertEqual(FuzzyMatcher.nameSimilarity(many, many), 1.0, accuracy: 0.0001)
    }
}
