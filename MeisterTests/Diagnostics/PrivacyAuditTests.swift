import XCTest
@testable import MeisterIOS

// Grounded entirely in MeisterIOS/Diagnostics/PrivacyAudit.swift.
//
// Verified surface of PrivacyAudit:
//   struct Grant { let service: String; let systemImage: String; let state: String }
//   @MainActor static func snapshot(_ permissions: PermissionManager) -> [Grant]
//
// snapshot(_:) is intentionally NOT exercised here: it takes a PermissionManager
// whose isPhotosAuthorized / isContactsAuthorized / isCalendarAuthorized values are
// driven by live TCC authorization state (an un-constructible / device-authorization
// dependent system object). Per the grounding rules we do not invent a constructor or
// stub for it. The deterministic, fully-grounded surface is the value type Grant,
// whose @testable-accessible memberwise initializer and let storage we round-trip
// across the standard boundary cases (empty, unicode, large input, etc.).
final class PrivacyAuditTests: XCTestCase {

    // MARK: - Grant: memberwise init stores each field verbatim (happy path)

    func testGrantStoresServiceVerbatim() {
        let g = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        XCTAssertEqual(g.service, "Photos")
    }

    func testGrantStoresSystemImageVerbatim() {
        let g = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        XCTAssertEqual(g.systemImage, "photo.on.rectangle.angled")
    }

    func testGrantStoresStateVerbatim() {
        let g = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        XCTAssertEqual(g.state, "Authorized")
    }

    func testGrantAllThreeFieldsIndependent() {
        let g = PrivacyAudit.Grant(service: "Contacts",
                                   systemImage: "person.2",
                                   state: "Denied / Not determined")
        XCTAssertEqual(g.service, "Contacts")
        XCTAssertEqual(g.systemImage, "person.2")
        XCTAssertEqual(g.state, "Denied / Not determined")
    }

    // MARK: - Field independence: changing one argument changes only that field

    func testGrantServiceDoesNotLeakIntoSystemImage() {
        let g = PrivacyAudit.Grant(service: "A", systemImage: "B", state: "C")
        XCTAssertEqual(g.service, "A")
        XCTAssertEqual(g.systemImage, "B")
        XCTAssertEqual(g.state, "C")
        XCTAssertNotEqual(g.service, g.systemImage)
        XCTAssertNotEqual(g.systemImage, g.state)
        XCTAssertNotEqual(g.service, g.state)
    }

    func testGrantArgumentOrderIsRespected() {
        // Guards against any accidental transposition of the three String fields.
        let g = PrivacyAudit.Grant(service: "first", systemImage: "second", state: "third")
        XCTAssertEqual([g.service, g.systemImage, g.state], ["first", "second", "third"])
    }

    // MARK: - Empty-string boundaries

    func testGrantEmptyService() {
        let g = PrivacyAudit.Grant(service: "", systemImage: "x", state: "y")
        XCTAssertEqual(g.service, "")
        XCTAssertTrue(g.service.isEmpty)
    }

    func testGrantEmptySystemImage() {
        let g = PrivacyAudit.Grant(service: "x", systemImage: "", state: "y")
        XCTAssertEqual(g.systemImage, "")
        XCTAssertTrue(g.systemImage.isEmpty)
    }

    func testGrantEmptyState() {
        let g = PrivacyAudit.Grant(service: "x", systemImage: "y", state: "")
        XCTAssertEqual(g.state, "")
        XCTAssertTrue(g.state.isEmpty)
    }

    func testGrantAllEmpty() {
        let g = PrivacyAudit.Grant(service: "", systemImage: "", state: "")
        XCTAssertTrue(g.service.isEmpty)
        XCTAssertTrue(g.systemImage.isEmpty)
        XCTAssertTrue(g.state.isEmpty)
    }

    // MARK: - Real literal values used by the production code

    func testGrantAcceptsAuthorizedStateLiteral() {
        // "Authorized" is the literal produced by snapshot(_:) when authorized.
        let g = PrivacyAudit.Grant(service: "Calendar", systemImage: "calendar", state: "Authorized")
        XCTAssertEqual(g.state, "Authorized")
    }

    func testGrantAcceptsDeniedStateLiteral() {
        // "Denied / Not determined" is the literal produced by snapshot(_:) otherwise.
        let g = PrivacyAudit.Grant(service: "Calendar",
                                   systemImage: "calendar",
                                   state: "Denied / Not determined")
        XCTAssertEqual(g.state, "Denied / Not determined")
        XCTAssertTrue(g.state.contains("Denied"))
        XCTAssertTrue(g.state.contains("Not determined"))
    }

    func testGrantPhotosSystemImageLiteralRoundTrips() {
        let g = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        XCTAssertEqual(g.systemImage, "photo.on.rectangle.angled")
    }

    func testGrantContactsSystemImageLiteralRoundTrips() {
        let g = PrivacyAudit.Grant(service: "Contacts", systemImage: "person.2", state: "Authorized")
        XCTAssertEqual(g.systemImage, "person.2")
    }

    func testGrantCalendarSystemImageLiteralRoundTrips() {
        let g = PrivacyAudit.Grant(service: "Calendar", systemImage: "calendar", state: "Authorized")
        XCTAssertEqual(g.systemImage, "calendar")
    }

    // MARK: - Unicode / whitespace / control characters

    func testGrantPreservesUnicodeService() {
        let s = "Fotografías 📷 müller 北京"
        let g = PrivacyAudit.Grant(service: s, systemImage: "x", state: "y")
        XCTAssertEqual(g.service, s)
    }

    func testGrantPreservesEmojiState() {
        let s = "✅ Authorized 🔒"
        let g = PrivacyAudit.Grant(service: "x", systemImage: "y", state: s)
        XCTAssertEqual(g.state, s)
    }

    func testGrantPreservesCombiningDiacriticsByteForByte() {
        // Decomposed form must not be silently normalized away.
        let decomposed = "Cafe\u{0301}" // "Café" via combining acute accent
        let g = PrivacyAudit.Grant(service: decomposed, systemImage: "x", state: "y")
        XCTAssertEqual(g.service, decomposed)
        XCTAssertEqual(g.service.unicodeScalars.count, decomposed.unicodeScalars.count)
    }

    func testGrantPreservesLeadingTrailingWhitespace() {
        let g = PrivacyAudit.Grant(service: "  spaced  ", systemImage: "\tx\n", state: " y ")
        XCTAssertEqual(g.service, "  spaced  ")
        XCTAssertEqual(g.systemImage, "\tx\n")
        XCTAssertEqual(g.state, " y ")
    }

    func testGrantPreservesNewlinesAndControlChars() {
        let s = "line1\nline2\r\ttab\u{0000}null"
        let g = PrivacyAudit.Grant(service: s, systemImage: "x", state: "y")
        XCTAssertEqual(g.service, s)
    }

    // MARK: - Large input

    func testGrantPreservesLargeStringExactly() {
        let big = String(repeating: "permission-", count: 50_000) // ~550k chars
        let g = PrivacyAudit.Grant(service: big, systemImage: "x", state: "y")
        XCTAssertEqual(g.service, big)
        XCTAssertEqual(g.service.count, big.count)
    }

    // MARK: - Independence across instances (no shared/static state)

    func testDistinctGrantInstancesDoNotShareState() {
        let a = PrivacyAudit.Grant(service: "A", systemImage: "ai", state: "as")
        let b = PrivacyAudit.Grant(service: "B", systemImage: "bi", state: "bs")
        XCTAssertEqual(a.service, "A")
        XCTAssertEqual(b.service, "B")
        XCTAssertNotEqual(a.service, b.service)
        XCTAssertNotEqual(a.systemImage, b.systemImage)
        XCTAssertNotEqual(a.state, b.state)
    }

    // MARK: - Value-type / idempotency semantics

    func testGrantConstructionIsIdempotentForEqualArguments() {
        let a = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        let b = PrivacyAudit.Grant(service: "Photos",
                                   systemImage: "photo.on.rectangle.angled",
                                   state: "Authorized")
        XCTAssertEqual(a.service, b.service)
        XCTAssertEqual(a.systemImage, b.systemImage)
        XCTAssertEqual(a.state, b.state)
    }

    // MARK: - Array of Grants preserves ordering (mirrors snapshot's fixed ordering)

    func testGrantArrayPreservesInsertionOrder() {
        // snapshot(_:) returns Photos, Contacts, Calendar in that fixed order.
        // We can deterministically assert ordering of a hand-built array of the
        // same value type without depending on PermissionManager.
        let grants = [
            PrivacyAudit.Grant(service: "Photos",   systemImage: "photo.on.rectangle.angled", state: "Authorized"),
            PrivacyAudit.Grant(service: "Contacts", systemImage: "person.2",                  state: "Authorized"),
            PrivacyAudit.Grant(service: "Calendar", systemImage: "calendar",                  state: "Authorized"),
        ]
        XCTAssertEqual(grants.map { $0.service }, ["Photos", "Contacts", "Calendar"])
        XCTAssertEqual(grants.count, 3)
    }

    func testGrantArrayMapExtractsEachFieldInOrder() {
        let grants = [
            PrivacyAudit.Grant(service: "Photos",   systemImage: "photo.on.rectangle.angled", state: "Authorized"),
            PrivacyAudit.Grant(service: "Contacts", systemImage: "person.2",                  state: "Denied / Not determined"),
            PrivacyAudit.Grant(service: "Calendar", systemImage: "calendar",                  state: "Authorized"),
        ]
        XCTAssertEqual(grants.map { $0.systemImage },
                       ["photo.on.rectangle.angled", "person.2", "calendar"])
        XCTAssertEqual(grants.map { $0.state },
                       ["Authorized", "Denied / Not determined", "Authorized"])
    }

    func testEmptyGrantArrayHasNoElements() {
        let grants: [PrivacyAudit.Grant] = []
        XCTAssertTrue(grants.isEmpty)
        XCTAssertEqual(grants.count, 0)
    }
}
