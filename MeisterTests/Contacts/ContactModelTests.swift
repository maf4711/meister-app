import Contacts
import XCTest
@testable import MeisterIOS

/// Tests for the value-type contact models in `Contacts/ContactScanner.swift`:
/// `ContactItem.fullName` / `.quality` / `.isEmpty` and `ContactGroup.title` (+ `.id`).
///
/// `ContactItem` is a plain `Hashable` struct backed by a `CNContact`. The `cn` field
/// only needs an in-memory `CNContact()` (no `CNContactStore` authorization required),
/// so the models are fully constructible in a unit test via their memberwise initializers.
///
/// Fixtures are built with the local `makeContact` / `makeGroup` factories below.
/// `makeContact` derives `fullName` by space-joining the non-empty `given`/`family`
/// components — mirroring how `ContactScanner.fetchAll` populates the field — so the
/// `fullName` assertions exercise that derivation contract.
final class ContactModelTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a `ContactItem` directly. `fullName` is derived from the non-empty
    /// name components (the same join `CNContactFormatter` produces for given+family),
    /// so empty components never yield leading/trailing/double spaces.
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

    private func makeGroup(_ items: [ContactItem]) -> ContactGroup {
        ContactGroup(items: items)
    }

    // MARK: - fullName derivation

    func testFactoryFullNameJoinsGivenAndFamily() {
        let c = makeContact(given: "Jan", family: "Kowalski")
        XCTAssertEqual(c.fullName, "Jan Kowalski")
    }

    func testFactoryFullNameGivenOnly() {
        let c = makeContact(given: "Jan", family: "")
        XCTAssertEqual(c.fullName, "Jan")
    }

    func testFactoryFullNameFamilyOnly() {
        let c = makeContact(given: "", family: "Kowalski")
        XCTAssertEqual(c.fullName, "Kowalski")
    }

    func testFactoryFullNameBothEmptyIsEmptyString() {
        let c = makeContact(given: "", family: "")
        XCTAssertEqual(c.fullName, "")
    }

    func testFactoryFullNameSingleSpaceSeparatorNoDoubleSpace() {
        // Empty components are filtered out before joining, so there is never a leading/trailing/double space.
        let c = makeContact(given: "Jan", family: "")
        XCTAssertFalse(c.fullName.contains("  "))
        XCTAssertFalse(c.fullName.hasPrefix(" "))
        XCTAssertFalse(c.fullName.hasSuffix(" "))
    }

    func testFactoryFullNameUnicodeDiacriticsPreserved() {
        let c = makeContact(given: "Søren", family: "Müller")
        XCTAssertEqual(c.fullName, "Søren Müller")
    }

    func testFactoryFullNameDoesNotMutateStoredGivenFamily() {
        // fullName is derived; the raw givenName/familyName remain exactly as supplied.
        let c = makeContact(given: "Jan", family: "Kowalski")
        XCTAssertEqual(c.givenName, "Jan")
        XCTAssertEqual(c.familyName, "Kowalski")
    }

    // MARK: - ContactItem.quality

    func testQualityAllFieldsPresentIsOne() {
        let c = makeContact(
            given: "Jan",
            family: "Kowalski",
            phones: ["+4915112345678"],
            emails: ["jan@example.com"],
            hasImage: true,
            organization: "ACME"
        )
        // 0.3 name + 0.3 phone + 0.2 email + 0.1 image + 0.1 org = 1.0
        XCTAssertEqual(c.quality, 1.0, accuracy: 0.0001)
    }

    func testQualityEmptyContactIsZero() {
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.0, accuracy: 0.0001)
    }

    func testQualityNameOnly() {
        let c = makeContact(given: "Jan", family: "Kowalski", phones: [], emails: [], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.3, accuracy: 0.0001)
    }

    func testQualityPhoneOnly() {
        let c = makeContact(given: "", family: "", phones: ["+4915112345678"], emails: [], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.3, accuracy: 0.0001)
    }

    func testQualityEmailOnly() {
        let c = makeContact(given: "", family: "", phones: [], emails: ["jan@example.com"], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.2, accuracy: 0.0001)
    }

    func testQualityImageOnly() {
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: true, organization: "")
        XCTAssertEqual(c.quality, 0.1, accuracy: 0.0001)
    }

    func testQualityOrganizationOnly() {
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: false, organization: "ACME")
        XCTAssertEqual(c.quality, 0.1, accuracy: 0.0001)
    }

    func testQualityNamePlusPhone() {
        let c = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: [], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.6, accuracy: 0.0001)
    }

    func testQualityNamePhoneEmail() {
        let c = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        XCTAssertEqual(c.quality, 0.8, accuracy: 0.0001)
    }

    func testQualityImagePlusOrganization() {
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: true, organization: "ACME")
        XCTAssertEqual(c.quality, 0.2, accuracy: 0.0001)
    }

    func testQualityMultiplePhonesStillCountsOnce() {
        // Scoring keys off non-emptiness, not count: two phones score the same 0.3 as one.
        let one = makeContact(given: "", family: "", phones: ["+4915112345678"], emails: [], hasImage: false, organization: "")
        let many = makeContact(given: "", family: "", phones: ["+4915112345678", "+4915187654321"], emails: [], hasImage: false, organization: "")
        XCTAssertEqual(one.quality, many.quality, accuracy: 0.0001)
    }

    func testQualityMultipleEmailsStillCountsOnce() {
        let one = makeContact(given: "", family: "", phones: [], emails: ["a@example.com"], hasImage: false, organization: "")
        let many = makeContact(given: "", family: "", phones: [], emails: ["a@example.com", "b@example.com"], hasImage: false, organization: "")
        XCTAssertEqual(one.quality, many.quality, accuracy: 0.0001)
    }

    func testQualityWithinUnitInterval() {
        // Quality is documented as 0…1; every combination must stay in bounds.
        let samples = [
            makeContact(given: "", family: "", phones: [], emails: [], hasImage: false, organization: ""),
            makeContact(given: "Jan", family: "Kowalski"),
            makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: true, organization: "ACME")
        ]
        for c in samples {
            XCTAssertGreaterThanOrEqual(c.quality, 0.0)
            XCTAssertLessThanOrEqual(c.quality, 1.0)
        }
    }

    func testQualityIsDeterministic() {
        let c = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: [], hasImage: true, organization: "")
        XCTAssertEqual(c.quality, c.quality, accuracy: 0.0001)
    }

    func testQualityNamePhoneOutweighsEmailImageOrg() {
        // Ordering property used by merge/title winner selection.
        let nameAndPhone = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: [], hasImage: false, organization: "")
        let emailImageOrg = makeContact(given: "", family: "", phones: [], emails: ["jan@example.com"], hasImage: true, organization: "ACME")
        XCTAssertGreaterThan(nameAndPhone.quality, emailImageOrg.quality)
    }

    // MARK: - ContactItem.isEmpty

    func testIsEmptyTrueWhenNoNameNoPhoneNoEmail() {
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: false, organization: "")
        XCTAssertTrue(c.isEmpty)
    }

    func testIsEmptyFalseWhenHasName() {
        let c = makeContact(given: "Jan", family: "Kowalski", phones: [], emails: [], hasImage: false, organization: "")
        XCTAssertFalse(c.isEmpty)
    }

    func testIsEmptyFalseWhenHasPhone() {
        let c = makeContact(given: "", family: "", phones: ["+4915112345678"], emails: [], hasImage: false, organization: "")
        XCTAssertFalse(c.isEmpty)
    }

    func testIsEmptyFalseWhenHasEmail() {
        let c = makeContact(given: "", family: "", phones: [], emails: ["jan@example.com"], hasImage: false, organization: "")
        XCTAssertFalse(c.isEmpty)
    }

    func testIsEmptyIgnoresImageAndOrganization() {
        // isEmpty only considers fullName, phones, emails — not image or organization.
        let c = makeContact(given: "", family: "", phones: [], emails: [], hasImage: true, organization: "ACME")
        XCTAssertTrue(c.isEmpty)
    }

    // MARK: - ContactItem: Hashable / identity

    func testEqualityIncludesWrappedCNContactIdentity() {
        // `ContactItem` uses Swift's *synthesized* Hashable/Equatable over ALL stored
        // properties — including `cn: CNContact`. `CNContact` compares/hashes by its
        // per-instance identifier (a fresh UUID per `CNContact()`), so two items built
        // with identical value fields but *distinct* `cn` instances are NOT equal.
        let a = makeContact(id: "fixed-id", given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        let b = makeContact(id: "fixed-id", given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.hashValue, b.hashValue)

        // Sharing the same `cn` instance (alongside identical value fields) DOES yield
        // equality and an equal hash — the real positive case of the synthesized contract.
        let cn = CNContact()
        let c = ContactItem(id: "fixed-id", fullName: "Jan Kowalski", givenName: "Jan", familyName: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "", cn: cn)
        let d = ContactItem(id: "fixed-id", fullName: "Jan Kowalski", givenName: "Jan", familyName: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "", cn: cn)
        XCTAssertEqual(c, d)
        XCTAssertEqual(c.hashValue, d.hashValue)
    }

    func testInequalityByID() {
        let a = makeContact(id: "id-a", given: "Jan", family: "Kowalski")
        let b = makeContact(id: "id-b", given: "Jan", family: "Kowalski")
        XCTAssertNotEqual(a, b)
    }

    func testFactoryDefaultIDsAreUnique() {
        let a = makeContact()
        let b = makeContact()
        XCTAssertNotEqual(a.id, b.id)
    }

    func testUsableInSet() {
        // Synthesized Hashable includes the wrapped `cn`, whose identity is unique per
        // `CNContact()`. `dupOfA` shares `a`'s value fields but gets a *fresh* `cn`, so it
        // is a distinct element — the Set keeps all three.
        let a = makeContact(id: "id-a", given: "Jan", family: "Kowalski")
        let b = makeContact(id: "id-b", given: "Eva", family: "Nowak")
        let dupOfA = makeContact(id: "id-a", given: "Jan", family: "Kowalski")
        let set: Set<ContactItem> = [a, b, dupOfA]
        XCTAssertEqual(set.count, 3)

        // True duplicates (same `cn` instance + same fields) DO dedupe to one element.
        let dedupSet: Set<ContactItem> = [a, b, a]
        XCTAssertEqual(dedupSet.count, 2)
    }

    // MARK: - ContactGroup.title

    func testGroupTitleEmptyGroupIsUnnamed() {
        let g = makeGroup([])
        XCTAssertEqual(g.title, "Unnamed")
    }

    func testGroupTitleSingleItemUsesItsFullName() {
        let g = makeGroup([makeContact(given: "Jan", family: "Kowalski")])
        XCTAssertEqual(g.title, "Jan Kowalski")
    }

    func testGroupTitlePicksHighestQualityFullName() {
        // Low-quality item has only a name (0.3); high-quality item has name+phone+email (0.8).
        let low = makeContact(given: "Old", family: "Stub", phones: [], emails: [], hasImage: false, organization: "")
        let high = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        let g = makeGroup([low, high])
        XCTAssertEqual(g.title, "Jan Kowalski")
    }

    func testGroupTitleIndependentOfItemOrder() {
        let low = makeContact(given: "Old", family: "Stub", phones: [], emails: [], hasImage: false, organization: "")
        let high = makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        let forward = makeGroup([low, high])
        let reversed = makeGroup([high, low])
        XCTAssertEqual(forward.title, reversed.title)
        XCTAssertEqual(forward.title, "Jan Kowalski")
    }

    func testGroupTitleWinnerWithEmptyFullNameYieldsEmptyTitle() {
        // The highest-quality item wins even if its fullName is empty:
        // here the no-name item scores 0.8 (phone+email) and beats the name-only item (0.3),
        // so title resolves to the winner's empty fullName — NOT "Unnamed" (group is non-empty).
        let nameOnly = makeContact(given: "Jan", family: "Kowalski", phones: [], emails: [], hasImage: false, organization: "")
        let richNoName = makeContact(given: "", family: "", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        let g = makeGroup([nameOnly, richNoName])
        XCTAssertEqual(g.title, "")
    }

    func testGroupTitleUnicodePreserved() {
        let g = makeGroup([makeContact(given: "Søren", family: "Müller")])
        XCTAssertEqual(g.title, "Søren Müller")
    }

    func testGroupTitleLargeGroupSelectsBest() {
        var items: [ContactItem] = []
        for i in 0..<500 {
            items.append(makeContact(given: "Filler\(i)", family: "", phones: [], emails: [], hasImage: false, organization: ""))
        }
        // One clearly superior item buried in the middle.
        items.insert(
            makeContact(given: "Best", family: "Match", phones: ["+4915112345678"], emails: ["best@example.com"], hasImage: true, organization: "ACME"),
            at: 250
        )
        let g = makeGroup(items)
        XCTAssertEqual(g.title, "Best Match")
    }

    func testGroupTitleIsIdempotent() {
        let g = makeGroup([
            makeContact(given: "A", family: "One"),
            makeContact(given: "Jan", family: "Kowalski", phones: ["+4915112345678"], emails: ["jan@example.com"], hasImage: false, organization: "")
        ])
        XCTAssertEqual(g.title, g.title)
    }

    // MARK: - ContactGroup.items / id

    func testGroupRetainsAllItems() {
        let items = [
            makeContact(given: "A", family: "One"),
            makeContact(given: "B", family: "Two"),
            makeContact(given: "C", family: "Three")
        ]
        let g = makeGroup(items)
        XCTAssertEqual(g.items.count, 3)
    }

    func testGroupItemsPreserveInsertionOrder() {
        let a = makeContact(id: "a", given: "A", family: "One")
        let b = makeContact(id: "b", given: "B", family: "Two")
        let g = makeGroup([a, b])
        XCTAssertEqual(g.items.map(\.id), ["a", "b"])
    }

    func testGroupIDsAreUniquePerInstance() {
        // ContactGroup.id is a fresh UUID per instance, so two groups never collide.
        let g1 = makeGroup([makeContact()])
        let g2 = makeGroup([makeContact()])
        XCTAssertNotEqual(g1.id, g2.id)
    }
}
