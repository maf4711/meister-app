import Contacts
import XCTest
@testable import MeisterIOS

/// Tests for `ContactDeduplicator.dedupe(_:)` in `Contacts/ContactDeduplicator.swift`.
///
/// The deduper unions contacts into groups via a union-find over three signals:
///   1. shared phone string (exact match on the normalized `phones` entries),
///   2. shared email string (exact match on the `emails` entries),
///   3. fuzzy full-name similarity `FuzzyMatcher.nameSimilarity(a, b) >= 0.85`
///      (only contacts whose `fullName` is non-empty participate).
/// Transitivity is inherited from union-find: A~B and B~C ⇒ A, B, C in one group.
///
/// CONTRACT verified against the source:
///   - Only clusters with `count > 1` are returned; singletons are dropped entirely.
///   - The returned groups are `sorted { $0.items.count > $1.items.count }` (largest first).
///   - Each `ContactGroup.items` is the subset of the *input* items in that cluster.
///
/// `ContactItem` is a plain `Hashable` value type backed by a `CNContact`; an in-memory
/// `CNContact()` needs no `CNContactStore` authorization, so fixtures are fully
/// constructible here — mirroring the `makeContact` pattern in `ContactModelTests`.
///
/// Fuzzy assertions deliberately use only inputs whose similarity is pinned by
/// `FuzzyMatcherTests`: identical full names score `1.0` (always `>= 0.85`, so they MUST
/// group), and clearly unrelated names ("Alice Smith" vs "Bob Jones") score `< 0.3`
/// (so they MUST NOT group). Borderline similarity values are never asserted on.
final class ContactDeduplicatorTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a `ContactItem` directly. `fullName` is derived from the non-empty
    /// name components — the same join `ContactScanner.fetchAll` produces.
    private func makeContact(
        id: String = UUID().uuidString,
        given: String = "",
        family: String = "",
        phones: [String] = [],
        emails: [String] = [],
        hasImage: Bool = false,
        organization: String = ""
    ) -> ContactItem {
        let fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        return ContactItem(
            id: id,
            fullName: fullName,
            givenName: given,
            familyName: family,
            phones: phones,
            emails: emails,
            hasImage: hasImage,
            organization: organization,
            cn: CNContact()
        )
    }

    /// All `id`s present across every returned group, as a set (order-independent membership).
    private func groupedIDs(_ groups: [ContactGroup]) -> Set<String> {
        Set(groups.flatMap { $0.items.map(\.id) })
    }

    /// The set of `id`s for one specific group (clusters are order-independent internally).
    private func idSet(_ group: ContactGroup) -> Set<String> {
        Set(group.items.map(\.id))
    }

    /// A globally-unique, letter-only name token for index `i` (base-26 over a…z).
    ///
    /// The large-input tests need filler contacts that the fuzzy-name pass can never union.
    /// `FuzzyMatcher.tokens` splits on non-letters, so a name like "Given\(i) Family\(i)"
    /// collapses to the same two tokens {given, family} for *every* `i` (the digits are
    /// stripped as separators) → token-set Jaccard 1.0 → similarity ≥ 0.85 → spurious union.
    /// A single distinct letter token per contact guarantees Jaccard 0 between any two
    /// fillers, so `nameSimilarity == 0.6·0 + 0.4·lev ≤ 0.4 < 0.85` — never unioned.
    private func uniqueLetterName(_ i: Int) -> String {
        var n = i, out = ""
        repeat {
            out = String(UnicodeScalar(UInt8(97 + n % 26))) + out
            n = n / 26 - 1
        } while n >= 0
        return out
    }

    // MARK: - Empty / trivial input

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(ContactDeduplicator.dedupe([]).isEmpty)
    }

    func testSingleContactIsNotAGroup() {
        // A lone contact forms a singleton cluster (count == 1) and is dropped.
        let only = makeContact(id: "solo", given: "Jan", family: "Kowalski", phones: ["+4915112340010"])
        XCTAssertTrue(ContactDeduplicator.dedupe([only]).isEmpty)
    }

    func testTwoFullyDistinctContactsProduceNoGroups() {
        // Disjoint phones, disjoint emails, unrelated names (< 0.3 similarity): no union.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4915112340001"], emails: ["alice@example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4915112340002"], emails: ["bob@example.com"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testEmptyContactsWithNoSignalsDoNotGroup() {
        // Two completely empty contacts share nothing (empty fullName excluded from fuzzy,
        // no phones, no emails) → each stays a singleton → no groups.
        let a = makeContact(id: "a")
        let b = makeContact(id: "b")
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    // MARK: - Phone-match grouping

    func testSharedPhoneGroupsTwoContacts() {
        // Same phone string, different (unrelated) names → one group of 2 via phone index.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    func testDifferentPhonesDoNotGroup() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930111111111"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930222222222"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testPhoneMatchIsExactStringNotSubstring() {
        // "+49301234567" is a prefix of "+493012345678" but the index keys on exact
        // equality, so a prefix relationship does NOT cause a union.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+49301234567"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+493012345678"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testSharedPhoneGroupsThreeContacts() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let c = makeContact(id: "c", given: "Carol", family: "White", phones: ["+4930123456789"])
        let groups = ContactDeduplicator.dedupe([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b", "c"])
    }

    func testSecondOfMultiplePhonesStillMatches() {
        // The match is on the second phone of `a` and the only phone of `b`.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930000000001", "+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    // MARK: - Email-match grouping

    func testSharedEmailGroupsTwoContacts() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", emails: ["shared@example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", emails: ["shared@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    func testDifferentEmailsDoNotGroup() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", emails: ["alice@example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", emails: ["bob@example.com"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testEmailMatchIsCaseSensitiveAtThisLayer() {
        // The deduper keys the email index on the stored strings verbatim; it does NOT
        // re-lowercase. `ContactScanner` lowercases on ingest, but with differing-case
        // fixtures here the raw strings differ → no union.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", emails: ["Shared@Example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", emails: ["shared@example.com"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testSecondOfMultipleEmailsStillMatches() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", emails: ["alt@example.com", "shared@example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", emails: ["shared@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    // MARK: - Fuzzy-name grouping

    func testIdenticalFullNamesGroupViaFuzzy() {
        // similarity("Jan Kowalski", "Jan Kowalski") == 1.0 >= 0.85 → must union,
        // even though phones and emails are disjoint.
        let a = makeContact(id: "a", given: "Jan", family: "Kowalski", phones: ["+4930111111111"])
        let b = makeContact(id: "b", given: "Jan", family: "Kowalski", phones: ["+4930222222222"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    func testUnrelatedNamesDoNotGroupViaFuzzy() {
        // similarity("Alice Smith", "Bob Jones") < 0.3 (per FuzzyMatcherTests) → below 0.85.
        let a = makeContact(id: "a", given: "Alice", family: "Smith")
        let b = makeContact(id: "b", given: "Bob", family: "Jones")
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testEmptyFullNameIsExcludedFromFuzzyPass() {
        // A no-name contact never enters the fuzzy candidate list (`!fullName.isEmpty`),
        // so it cannot fuzzy-union with anyone — and with no phone/email it stays singleton.
        let named = makeContact(id: "named", given: "Jan", family: "Kowalski")
        let nameless = makeContact(id: "nameless", phones: [], emails: [])
        XCTAssertTrue(ContactDeduplicator.dedupe([named, nameless]).isEmpty)
    }

    func testTwoEmptyNamesAreNotFuzzyUnioned() {
        // Both have empty fullName → both excluded from fuzzy → no union from names.
        // They DO share a phone here, but that is the phone path, not fuzzy; assert the
        // fuzzy path alone does nothing by giving them distinct phones.
        let a = makeContact(id: "a", phones: ["+4930111111111"])
        let b = makeContact(id: "b", phones: ["+4930222222222"])
        XCTAssertTrue(ContactDeduplicator.dedupe([a, b]).isEmpty)
    }

    func testIdenticalUnicodeNamesGroupViaFuzzy() {
        // Diacritics preserved in fullName; identical strings → similarity 1.0 → union.
        let a = makeContact(id: "a", given: "Søren", family: "Müller", phones: ["+4930111111111"])
        let b = makeContact(id: "b", given: "Søren", family: "Müller", phones: ["+4930222222222"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }

    // MARK: - Transitivity (union-find closure)

    func testTransitivityAcrossPhoneAndEmail() {
        // a~b via shared phone, b~c via shared email ⇒ {a, b, c} collapse to one group.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"], emails: ["link@example.com"])
        let c = makeContact(id: "c", given: "Carol", family: "White", emails: ["link@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b", "c"])
    }

    func testTransitivityAcrossFuzzyAndPhone() {
        // a~b via identical name (fuzzy 1.0), b~c via shared phone ⇒ all three in one group.
        let a = makeContact(id: "a", given: "Jan", family: "Kowalski", phones: ["+4930111111111"])
        let b = makeContact(id: "b", given: "Jan", family: "Kowalski", phones: ["+4930123456789"])
        let c = makeContact(id: "c", given: "Carol", family: "White", phones: ["+4930123456789"])
        let groups = ContactDeduplicator.dedupe([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b", "c"])
    }

    func testTwoSeparateGroupsStayDistinct() {
        // {a,b} share one phone, {c,d} share a different phone; the two pairs never link.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930000000001"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930000000001"])
        let c = makeContact(id: "c", given: "Carol", family: "White", phones: ["+4930000000002"])
        let d = makeContact(id: "d", given: "Dave", family: "Brown", phones: ["+4930000000002"])
        let groups = ContactDeduplicator.dedupe([a, b, c, d])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map { idSet($0) }), [["a", "b"], ["c", "d"]])
    }

    // MARK: - Singletons dropped alongside real groups

    func testSingletonsAreExcludedFromOutput() {
        // a~b group; c, d, e are unrelated singletons → only the one group is returned.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let c = makeContact(id: "c", given: "Carol", family: "White", phones: ["+4930000000003"])
        let d = makeContact(id: "d", given: "Dave", family: "Brown", emails: ["dave@example.com"])
        let e = makeContact(id: "e", given: "Erin", family: "Green")
        let groups = ContactDeduplicator.dedupe([a, b, c, d, e])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
        XCTAssertEqual(groupedIDs(groups), ["a", "b"])
        // The three singletons must NOT appear anywhere in the output.
        XCTAssertFalse(groupedIDs(groups).contains("c"))
        XCTAssertFalse(groupedIDs(groups).contains("d"))
        XCTAssertFalse(groupedIDs(groups).contains("e"))
    }

    // MARK: - Ordering (largest group first)

    func testGroupsSortedByDescendingItemCount() {
        // Group P has 3 members (shared phone), group E has 2 (shared email).
        // Output must be sorted largest-first → P before E.
        let p1 = makeContact(id: "p1", given: "P", family: "One", phones: ["+4930000000010"])
        let p2 = makeContact(id: "p2", given: "P", family: "Two", phones: ["+4930000000010"])
        let p3 = makeContact(id: "p3", given: "P", family: "Three", phones: ["+4930000000010"])
        let e1 = makeContact(id: "e1", given: "E", family: "One", emails: ["epair@example.com"])
        let e2 = makeContact(id: "e2", given: "E", family: "Two", emails: ["epair@example.com"])
        let groups = ContactDeduplicator.dedupe([e1, e2, p1, p2, p3])
        XCTAssertEqual(groups.count, 2)
        XCTAssertGreaterThanOrEqual(groups[0].items.count, groups[1].items.count)
        XCTAssertEqual(groups[0].items.count, 3)
        XCTAssertEqual(groups[1].items.count, 2)
        XCTAssertEqual(idSet(groups[0]), ["p1", "p2", "p3"])
        XCTAssertEqual(idSet(groups[1]), ["e1", "e2"])
    }

    func testOutputIsSortedRegardlessOfInputOrder() {
        // Same data as above but with the small group's items placed first in the input.
        let big1 = makeContact(id: "b1", given: "B", family: "One", phones: ["+4930000000020"])
        let big2 = makeContact(id: "b2", given: "B", family: "Two", phones: ["+4930000000020"])
        let big3 = makeContact(id: "b3", given: "B", family: "Three", phones: ["+4930000000020"])
        let small1 = makeContact(id: "s1", given: "S", family: "One", emails: ["spair@example.com"])
        let small2 = makeContact(id: "s2", given: "S", family: "Two", emails: ["spair@example.com"])
        let groups = ContactDeduplicator.dedupe([small1, small2, big1, big2, big3])
        XCTAssertEqual(groups.first?.items.count, 3)
        XCTAssertEqual(groups.last?.items.count, 2)
    }

    // MARK: - Idempotency / determinism

    func testDedupeIsDeterministicAcrossRuns() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let c = makeContact(id: "c", given: "Carol", family: "White", emails: ["c@example.com"])
        let d = makeContact(id: "d", given: "Dana", family: "Black", emails: ["c@example.com"])
        let first = ContactDeduplicator.dedupe([a, b, c, d])
        let second = ContactDeduplicator.dedupe([a, b, c, d])
        XCTAssertEqual(first.map { idSet($0) }, second.map { idSet($0) })
        XCTAssertEqual(first.map { $0.items.count }, second.map { $0.items.count })
    }

    func testReDedupingResultGroupsIsStable() {
        // Feed the items of an already-found group back through dedupe: still one group,
        // identical membership (the grouping is a fixed point for true duplicates).
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        let again = ContactDeduplicator.dedupe(groups[0].items)
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(idSet(again[0]), ["a", "b"])
    }

    // MARK: - Completeness of group membership

    func testEveryGroupedItemAppearsExactlyOnce() {
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"])
        let c = makeContact(id: "c", given: "Carol", family: "White", emails: ["c@example.com"])
        let d = makeContact(id: "d", given: "Dana", family: "Black", emails: ["c@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b, c, d])
        let flat = groups.flatMap { $0.items.map(\.id) }
        // No id appears in more than one group / more than once overall.
        XCTAssertEqual(flat.count, Set(flat).count)
        XCTAssertEqual(Set(flat), ["a", "b", "c", "d"])
    }

    func testGroupMembersAreActualInputItems() {
        // Returned items must be the same value-type instances supplied (by id) —
        // the deduper indexes into the original array, it does not synthesize new items.
        let a = makeContact(id: "a", given: "Alice", family: "Smith", phones: ["+4930123456789"], emails: ["a@example.com"])
        let b = makeContact(id: "b", given: "Bob", family: "Jones", phones: ["+4930123456789"], emails: ["b@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        let byID = Dictionary(uniqueKeysWithValues: groups[0].items.map { ($0.id, $0) })
        XCTAssertEqual(byID["a"]?.emails, ["a@example.com"])
        XCTAssertEqual(byID["b"]?.emails, ["b@example.com"])
    }

    // MARK: - Large input (fuzzy pass still runs under the 5000 cap)

    func testLargeManyUniqueContactsProduceNoGroups() {
        // 1000 contacts, each with a unique phone, a unique email, and a unique name.
        // Each name is a single distinct letter token (see `uniqueLetterName`), so pairwise
        // fuzzy similarity is 0.6·0 + 0.4·lev ≤ 0.4 < 0.85 — the fuzzy pass never unions
        // them. With disjoint phones and emails there is nothing else to group on → 0 groups.
        var items: [ContactItem] = []
        for i in 0..<1000 {
            items.append(makeContact(
                id: "u\(i)",
                given: uniqueLetterName(i),
                phones: ["+49300000\(String(format: "%05d", i))"],
                emails: ["user\(i)@example.com"]
            ))
        }
        XCTAssertTrue(ContactDeduplicator.dedupe(items).isEmpty)
    }

    func testLargeInputWithOneEmbeddedDuplicatePairFindsExactlyOneGroup() {
        // 200 fuzzy-disjoint filler contacts (single distinct letter token each, so the
        // fuzzy pass never unions them) plus a single phone-duplicate pair buried in the
        // middle. Only the buried pair shares a phone → exactly one group of {dupA, dupB}.
        var items: [ContactItem] = []
        for i in 0..<200 {
            items.append(makeContact(
                id: "u\(i)",
                given: uniqueLetterName(i),
                phones: ["+49311000\(String(format: "%05d", i))"],
                emails: ["filler\(i)@example.com"]
            ))
        }
        let dupA = makeContact(id: "dupA", given: "Dup", family: "Able", phones: ["+4930999999999"])
        let dupB = makeContact(id: "dupB", given: "Dup", family: "Baker", phones: ["+4930999999999"])
        items.insert(dupA, at: 100)
        items.insert(dupB, at: 150)
        let groups = ContactDeduplicator.dedupe(items)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(idSet(groups[0]), ["dupA", "dupB"])
    }

    // MARK: - Mixed signals reinforcing one cluster

    func testPhoneAndEmailAndNameAllAgreeStillOneGroup() {
        // All three signals point at the same pair; union-find collapses to a single group
        // of exactly 2 (no double counting).
        let a = makeContact(id: "a", given: "Jan", family: "Kowalski", phones: ["+4930123456789"], emails: ["jan@example.com"])
        let b = makeContact(id: "b", given: "Jan", family: "Kowalski", phones: ["+4930123456789"], emails: ["jan@example.com"])
        let groups = ContactDeduplicator.dedupe([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(idSet(groups[0]), ["a", "b"])
    }
}
