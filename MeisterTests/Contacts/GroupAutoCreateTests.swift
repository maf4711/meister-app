import Contacts
import XCTest
@testable import MeisterIOS

/// Tests for `GroupAutoCreate.suggestions(from:)` (`Contacts/GroupAutoCreate.swift`).
///
/// `suggestions(from:)` is the only pure, deterministic surface: it groups contacts by
/// the domain of their *first* email, keeps domains shared by `>= 3` contacts, drops
/// free-mail providers, titles each group from the domain's first label `.capitalized`,
/// and returns the result sorted by member count descending.
///
/// `GroupAutoCreate.create(_:)` is intentionally NOT tested — it instantiates a live
/// `CNContactStore`/`CNSaveRequest` and writes to the system address book, which needs
/// contacts authorization and a real store, so it is not unit-testable in isolation.
///
/// Fixtures reuse the `ContactModelTests` pattern: `ContactItem` is a value struct whose
/// `cn` field only needs an in-memory `CNContact()` (no `CNContactStore` access), so it is
/// fully constructible here via its memberwise initializer.
final class GroupAutoCreateTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a `ContactItem`. Only `emails` matters for `suggestions(from:)` (it groups by
    /// the first email's domain and filters out empty-email contacts), but every field of
    /// the memberwise init is supplied so the fixture matches the real struct shape.
    private func makeContact(
        id: String = UUID().uuidString,
        emails: [String] = []
    ) -> ContactItem {
        ContactItem(
            id: id,
            fullName: "",
            givenName: "",
            familyName: "",
            phones: [],
            emails: emails,
            hasImage: false,
            organization: "",
            cn: CNContact()
        )
    }

    /// `n` contacts that all share the same first-email domain.
    private func contacts(count n: Int, domain: String) -> [ContactItem] {
        (0..<n).map { makeContact(id: "\(domain)-\($0)", emails: ["user\($0)@\(domain)"]) }
    }

    private func suggestion(for domain: String, in suggestions: [GroupAutoCreate.Suggestion]) -> GroupAutoCreate.Suggestion? {
        suggestions.first { $0.reason.contains(domain) }
    }

    // MARK: - Empty / trivial input

    func testEmptyInputYieldsNoSuggestions() {
        XCTAssertTrue(GroupAutoCreate.suggestions(from: []).isEmpty)
    }

    func testSingleContactYieldsNoSuggestions() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 1, domain: "acme.com"))
        XCTAssertTrue(result.isEmpty)
    }

    func testAllContactsWithoutEmailYieldNoSuggestions() {
        // Contacts with empty `emails` are filtered out before grouping.
        let noEmail = (0..<5).map { makeContact(id: "x\($0)", emails: []) }
        XCTAssertTrue(GroupAutoCreate.suggestions(from: noEmail).isEmpty)
    }

    // MARK: - minMembers >= 3 boundary

    func testTwoSharedContactsBelowThresholdYieldNoSuggestion() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 2, domain: "acme.com"))
        XCTAssertTrue(result.isEmpty)
    }

    func testExactlyThreeSharedContactsYieldOneSuggestion() {
        // 3 is the inclusive lower bound (`members.count >= 3`).
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "acme.com"))
        XCTAssertEqual(result.count, 1)
    }

    func testFourSharedContactsYieldOneSuggestionWithAllMembers() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 4, domain: "acme.com"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.members.count, 4)
    }

    func testThresholdIsPerDomainNotGlobal() {
        // Two distinct domains, each with exactly 2 members: neither reaches 3, total is 4.
        var input = contacts(count: 2, domain: "acme.com")
        input += contacts(count: 2, domain: "globex.com")
        XCTAssertTrue(GroupAutoCreate.suggestions(from: input).isEmpty)
    }

    func testLargeGroupKeepsEveryMember() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 500, domain: "acme.com"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.members.count, 500)
    }

    // MARK: - Free-mail provider exclusion

    func testGmailDomainIsExcludedEvenAboveThreshold() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 5, domain: "gmail.com"))
        XCTAssertTrue(result.isEmpty)
    }

    func testYahooDomainIsExcluded() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 5, domain: "yahoo.com"))
        XCTAssertTrue(result.isEmpty)
    }

    func testEveryListedFreeProviderIsExcluded() {
        // The full free-mail set from `isFreeMail` — none may ever produce a suggestion.
        let free = [
            "gmail.com", "icloud.com", "me.com", "yahoo.com", "hotmail.com",
            "outlook.com", "live.com", "gmx.de", "gmx.net", "web.de", "proton.me",
            "protonmail.com", "mail.com", "t-online.de",
        ]
        for domain in free {
            let result = GroupAutoCreate.suggestions(from: contacts(count: 4, domain: domain))
            XCTAssertTrue(result.isEmpty, "Expected free provider \(domain) to be excluded")
        }
    }

    func testFreeMailExclusionIsCaseInsensitive() {
        // `isFreeMail` lowercases the domain before the set lookup.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 4, domain: "GMAIL.COM"))
        XCTAssertTrue(result.isEmpty)
    }

    func testFreeMailExclusionIsCaseInsensitiveMixedCase() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 4, domain: "GmX.De"))
        XCTAssertTrue(result.isEmpty)
    }

    func testCorporateDomainIsNotExcluded() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "acme.com"))
        XCTAssertEqual(result.count, 1)
    }

    func testFreeAndCorporateMix_OnlyCorporateSurvives() {
        var input = contacts(count: 4, domain: "gmail.com")   // excluded
        input += contacts(count: 4, domain: "acme.com")       // kept
        let result = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(suggestion(for: "acme.com", in: result))
        XCTAssertNil(suggestion(for: "gmail.com", in: result))
    }

    // MARK: - Title capitalization

    func testTitleIsDomainRootCapitalized() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "acme.com"))
        // Root before the first dot ("acme") -> .capitalized -> "Acme".
        XCTAssertEqual(result.first?.title, "Acme")
    }

    func testTitleUsesOnlyFirstDomainLabel() {
        // Multi-label domain: only the leading label is titled, not the TLD/subdomains.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "contoso.co.uk"))
        XCTAssertEqual(result.first?.title, "Contoso")
    }

    func testTitleCapitalizesLowercaseRoot() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "globex.org"))
        XCTAssertEqual(result.first?.title, "Globex")
    }

    func testTitleCapitalizationLowercasesTrailingLetters() {
        // Swift's `.capitalized` uppercases the first letter of each word and lowercases the
        // rest, so an all-caps root collapses to title-case.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "IBM.com"))
        XCTAssertEqual(result.first?.title, "Ibm")
    }

    func testTitleHyphenatedRootCapitalizesEachWord() {
        // `.capitalized` treats the hyphen as a word boundary.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "foo-bar.com"))
        XCTAssertEqual(result.first?.title, "Foo-Bar")
    }

    func testTitleIsNonEmptyForValidDomain() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "acme.com"))
        XCTAssertFalse(result.first?.title.isEmpty ?? true)
    }

    // MARK: - reason text

    func testReasonContainsMemberCountAndDomain() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "acme.com"))
        let reason = result.first?.reason ?? ""
        // Format-tolerant: assert substrings, not the exact localized sentence.
        XCTAssertTrue(reason.contains("3"))
        XCTAssertTrue(reason.contains("acme.com"))
    }

    func testReasonReflectsActualMemberCount() {
        let result = GroupAutoCreate.suggestions(from: contacts(count: 7, domain: "acme.com"))
        XCTAssertTrue(result.first?.reason.contains("7") ?? false)
    }

    // MARK: - Grouping by first email only

    func testGroupingUsesFirstEmailDomainNotSubsequent() {
        // Each contact's *first* email is acme.com; secondary emails on a free domain
        // must not affect grouping.
        let input = (0..<3).map {
            makeContact(id: "m\($0)", emails: ["user\($0)@acme.com", "user\($0)@gmail.com"])
        }
        let result = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Acme")
    }

    func testDifferentFirstEmailDomainsDoNotGroupTogether() {
        // Same secondary domain, different first domains -> they split, none reaches 3.
        let input = [
            makeContact(id: "a", emails: ["a@one.com", "shared@acme.com"]),
            makeContact(id: "b", emails: ["b@two.com", "shared@acme.com"]),
            makeContact(id: "c", emails: ["c@three.com", "shared@acme.com"]),
        ]
        XCTAssertTrue(GroupAutoCreate.suggestions(from: input).isEmpty)
    }

    // MARK: - Multiple groups / ordering

    func testMultipleQualifyingDomainsEachProduceASuggestion() {
        var input = contacts(count: 3, domain: "acme.com")
        input += contacts(count: 3, domain: "globex.com")
        let result = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(result.count, 2)
        XCTAssertNotNil(suggestion(for: "acme.com", in: result))
        XCTAssertNotNil(suggestion(for: "globex.com", in: result))
    }

    func testResultsSortedByMemberCountDescending() {
        var input = contacts(count: 3, domain: "small.com")
        input += contacts(count: 8, domain: "big.com")
        input += contacts(count: 5, domain: "mid.com")
        let result = GroupAutoCreate.suggestions(from: input)
        let counts = result.map { $0.members.count }
        XCTAssertEqual(counts, counts.sorted(by: >))
        XCTAssertEqual(result.first?.members.count, 8)
        XCTAssertEqual(result.last?.members.count, 3)
    }

    func testLargestGroupAppearsFirst() {
        var input = contacts(count: 3, domain: "tiny.com")
        input += contacts(count: 10, domain: "huge.com")
        let result = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(result.first?.title, "Huge")
    }

    // MARK: - Idempotency / determinism

    func testSuggestionCountIsIdempotent() {
        let input = contacts(count: 4, domain: "acme.com")
        XCTAssertEqual(
            GroupAutoCreate.suggestions(from: input).count,
            GroupAutoCreate.suggestions(from: input).count
        )
    }

    func testRepeatedRunsProduceSameTitlesAndCounts() {
        var input = contacts(count: 4, domain: "acme.com")
        input += contacts(count: 6, domain: "globex.com")
        let first = GroupAutoCreate.suggestions(from: input)
        let second = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(first.map { $0.title }, second.map { $0.title })
        XCTAssertEqual(first.map { $0.members.count }, second.map { $0.members.count })
    }

    func testInputOrderDoesNotChangeMemberCount() {
        let forward = contacts(count: 5, domain: "acme.com")
        let reversed = Array(forward.reversed())
        XCTAssertEqual(
            GroupAutoCreate.suggestions(from: forward).first?.members.count,
            GroupAutoCreate.suggestions(from: reversed).first?.members.count
        )
    }

    // MARK: - Unicode / unusual domains

    func testUnicodeDomainRootIsTitled() {
        // A non-ASCII root must still produce a non-empty, capitalized-first title and survive.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "müller.de"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Müller")
    }

    func testNumericDomainRootSurvives() {
        // Digits have no case; `.capitalized` leaves them unchanged but the group still forms.
        let result = GroupAutoCreate.suggestions(from: contacts(count: 3, domain: "123corp.com"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "123Corp")
    }

    func testTrailingAtSignStillYieldsNonEmptyDomainAndGroups() {
        // Source contract (per `suggestions(from:)`): domain = email.split(separator: "@").last.
        // Swift's `split` omits empty subsequences by default, so "name@".split(separator: "@")
        // is ["name"] and .last is "name" — NON-empty. The `!domain.isEmpty` guard does NOT fire,
        // so 3 contacts sharing the domain "name" form exactly one suggestion (it is "name",
        // not a free-mail provider). The original expectation (empty result) was wrong about
        // Swift's split semantics: a trailing "@" does not produce an empty domain segment.
        let input = (0..<3).map { makeContact(id: "n\($0)", emails: ["name@"]) }
        let result = GroupAutoCreate.suggestions(from: input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.members.count, 3)
    }

    func testMembersBelongToTheReportedDomain() {
        var input = contacts(count: 3, domain: "acme.com")
        input += contacts(count: 4, domain: "globex.com")
        let result = GroupAutoCreate.suggestions(from: input)
        let acme = suggestion(for: "acme.com", in: result)
        XCTAssertEqual(acme?.members.count, 3)
        XCTAssertTrue(acme?.members.allSatisfy { $0.emails.first?.hasSuffix("@acme.com") ?? false } ?? false)
    }
}
