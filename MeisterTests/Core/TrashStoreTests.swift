import XCTest
@testable import MeisterIOS

// Grounding note:
// The task focus mentioned `TrashStore.init(fileURL:)`, but the real source
// (MeisterIOS/Core/TrashStore.swift) has NO such initializer. `TrashStore`
// exposes only `init()` (hardcoding applicationSupportDirectory) and keeps
// `directory`/`manifest` private, so a temp-dir cannot be injected without
// inventing a symbol. Per the grounding rule, these tests reference ONLY the
// symbols that literally exist:
//   - TrashEntry (Codable, Identifiable): id, kind, summary, createdAt, payloadFile
//   - TrashEntry.Kind: .contact, .calendarEvent (String raw values)
//   - TrashStore.shared, entries(), store(kind:summary:payload:),
//     payload(for:), remove(_:), purgeExpired()
// TrashStore is @MainActor, so its tests run on the main actor. They operate
// against the shared instance and clean up everything they create via the
// public remove(_:) API, keeping each test self-contained and idempotent.
// No device authorization is required: TrashStore is pure FileManager + JSON.

final class TrashStoreTests: XCTestCase {

    // MARK: - TrashEntry: Codable round-trip

    func testTrashEntryEncodesAndDecodesToEqualValues_contact() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TrashEntry(
            id: id,
            kind: .contact,
            summary: "Jane Doe",
            createdAt: createdAt,
            payloadFile: "\(id.uuidString).vcf"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrashEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertEqual(decoded.payloadFile, original.payloadFile)
    }

    func testTrashEntryEncodesAndDecodesToEqualValues_calendarEvent() throws {
        let id = UUID()
        let original = TrashEntry(
            id: id,
            kind: .calendarEvent,
            summary: "Team Sync",
            createdAt: Date(timeIntervalSince1970: 0),
            payloadFile: "\(id.uuidString).ics"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrashEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.kind, .calendarEvent)
        XCTAssertEqual(decoded.summary, "Team Sync")
        XCTAssertEqual(decoded.payloadFile, original.payloadFile)
    }

    func testTrashEntryArrayCodableRoundTripPreservesOrderAndCount() throws {
        let entries = (0..<5).map { i in
            TrashEntry(
                id: UUID(),
                kind: i % 2 == 0 ? .contact : .calendarEvent,
                summary: "Entry \(i)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                payloadFile: "file\(i)"
            )
        }

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([TrashEntry].self, from: data)

        XCTAssertEqual(decoded.count, entries.count)
        XCTAssertEqual(decoded.map(\.id), entries.map(\.id))
        XCTAssertEqual(decoded.map(\.summary), entries.map(\.summary))
        XCTAssertEqual(decoded.map(\.kind), entries.map(\.kind))
    }

    func testEmptyTrashEntryArrayCodableRoundTrip() throws {
        let empty: [TrashEntry] = []
        let data = try JSONEncoder().encode(empty)
        let decoded = try JSONDecoder().decode([TrashEntry].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: - TrashEntry: empty / unicode / large summaries

    func testTrashEntryPreservesEmptySummary() throws {
        let entry = TrashEntry(
            id: UUID(),
            kind: .contact,
            summary: "",
            createdAt: .now,
            payloadFile: "x.vcf"
        )
        let decoded = try JSONDecoder().decode(
            TrashEntry.self,
            from: try JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decoded.summary, "")
    }

    func testTrashEntryPreservesUnicodeSummary() throws {
        let summary = "José 日本語 — café 🗑️ Ωμέγα"
        let entry = TrashEntry(
            id: UUID(),
            kind: .calendarEvent,
            summary: summary,
            createdAt: .now,
            payloadFile: "u.ics"
        )
        let decoded = try JSONDecoder().decode(
            TrashEntry.self,
            from: try JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decoded.summary, summary)
    }

    func testTrashEntryPreservesLargeSummary() throws {
        let summary = String(repeating: "A", count: 50_000)
        let entry = TrashEntry(
            id: UUID(),
            kind: .contact,
            summary: summary,
            createdAt: .now,
            payloadFile: "big.vcf"
        )
        let decoded = try JSONDecoder().decode(
            TrashEntry.self,
            from: try JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decoded.summary.count, 50_000)
        XCTAssertEqual(decoded.summary, summary)
    }

    // MARK: - TrashEntry.Kind: raw values

    func testKindRawValuesAreStable() {
        XCTAssertEqual(TrashEntry.Kind.contact.rawValue, "contact")
        XCTAssertEqual(TrashEntry.Kind.calendarEvent.rawValue, "calendarEvent")
    }

    func testKindDecodesFromRawString() throws {
        XCTAssertEqual(TrashEntry.Kind(rawValue: "contact"), .contact)
        XCTAssertEqual(TrashEntry.Kind(rawValue: "calendarEvent"), .calendarEvent)
        XCTAssertNil(TrashEntry.Kind(rawValue: "photo"))
        XCTAssertNil(TrashEntry.Kind(rawValue: ""))
    }

    func testKindEncodesAsItsRawString() throws {
        let data = try JSONEncoder().encode(TrashEntry.Kind.calendarEvent)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(json, "\"calendarEvent\"")
    }

    // MARK: - TrashEntry: Identifiable

    func testTrashEntryIdentifiableIdMatchesStoredId() {
        let id = UUID()
        let entry = TrashEntry(
            id: id,
            kind: .contact,
            summary: "id-check",
            createdAt: .now,
            payloadFile: "id.vcf"
        )
        // Identifiable conformance: `id` is the stored UUID.
        XCTAssertEqual(entry.id, id)
    }

    // MARK: - TrashStore: store / entries / payload round-trip
    //
    // These run against TrashStore.shared (@MainActor). Each test removes the
    // entries it creates via the public remove(_:) API so it leaves no residue.

    @MainActor
    private func newSummary(_ label: String) -> String {
        // Unique per run so concurrent/previous data never collides with asserts.
        "TrashStoreTests-\(label)-\(UUID().uuidString)"
    }

    @MainActor
    private func cleanup(summaries: Set<String>) {
        for entry in TrashStore.shared.entries() where summaries.contains(entry.summary) {
            TrashStore.shared.remove(entry)
        }
    }

    @MainActor
    func testStoreThenEntriesContainsTheStoredEntry() {
        let summary = newSummary("happy")
        defer { cleanup(summaries: [summary]) }

        let payload = Data("BEGIN:VCARD\nEND:VCARD".utf8)
        TrashStore.shared.store(kind: .contact, summary: summary, payload: payload)

        let match = TrashStore.shared.entries().first { $0.summary == summary }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.kind, .contact)
    }

    @MainActor
    func testStoredPayloadRoundTripsBackByteForByte() {
        let summary = newSummary("payload")
        defer { cleanup(summaries: [summary]) }

        let payload = Data("BEGIN:VCARD\nFN:Round Trip\nEND:VCARD".utf8)
        TrashStore.shared.store(kind: .contact, summary: summary, payload: payload)

        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }
        XCTAssertEqual(TrashStore.shared.payload(for: entry), payload)
    }

    @MainActor
    func testStoredEmptyPayloadRoundTripsAsEmptyData() {
        let summary = newSummary("empty-payload")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .calendarEvent, summary: summary, payload: Data())

        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }
        XCTAssertEqual(TrashStore.shared.payload(for: entry), Data())
    }

    @MainActor
    func testStoredLargePayloadRoundTrips() {
        let summary = newSummary("large-payload")
        defer { cleanup(summaries: [summary]) }

        let payload = Data((0..<200_000).map { UInt8($0 % 256) })
        TrashStore.shared.store(kind: .calendarEvent, summary: summary, payload: payload)

        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }
        XCTAssertEqual(TrashStore.shared.payload(for: entry), payload)
    }

    @MainActor
    func testContactPayloadFileUsesVcfExtension() {
        let summary = newSummary("vcf-ext")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([1, 2, 3]))

        let entry = TrashStore.shared.entries().first { $0.summary == summary }
        XCTAssertEqual((entry?.payloadFile as NSString?)?.pathExtension, "vcf")
    }

    @MainActor
    func testCalendarEventPayloadFileUsesIcsExtension() {
        let summary = newSummary("ics-ext")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .calendarEvent, summary: summary, payload: Data([1, 2, 3]))

        let entry = TrashStore.shared.entries().first { $0.summary == summary }
        XCTAssertEqual((entry?.payloadFile as NSString?)?.pathExtension, "ics")
    }

    @MainActor
    func testPayloadFileNameStartsWithEntryId() {
        let summary = newSummary("filename-id")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([9]))

        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }
        // store() builds "\(id.uuidString).vcf"
        XCTAssertTrue(entry.payloadFile.hasPrefix(entry.id.uuidString))
    }

    // MARK: - TrashStore: ordering (entries() sorts newest-first)

    @MainActor
    func testEntriesAreSortedNewestFirst() {
        let a = newSummary("order-a")
        let b = newSummary("order-b")
        defer { cleanup(summaries: [a, b]) }

        TrashStore.shared.store(kind: .contact, summary: a, payload: Data([1]))
        TrashStore.shared.store(kind: .contact, summary: b, payload: Data([2]))

        let listed = TrashStore.shared.entries()
        guard let idxA = listed.firstIndex(where: { $0.summary == a }),
              let idxB = listed.firstIndex(where: { $0.summary == b }) else {
            return XCTFail("both entries should be present")
        }
        // b was stored last -> newer createdAt -> appears before a.
        XCTAssertLessThan(idxB, idxA)
    }

    @MainActor
    func testEntriesGloballySortedDescendingByCreatedAt() {
        let summaries = (0..<4).map { newSummary("desc-\($0)") }
        defer { cleanup(summaries: Set(summaries)) }

        for s in summaries {
            TrashStore.shared.store(kind: .contact, summary: s, payload: Data([0]))
        }

        let dates = TrashStore.shared.entries().map(\.createdAt)
        for i in 1..<dates.count {
            XCTAssertGreaterThanOrEqual(dates[i - 1], dates[i])
        }
    }

    // MARK: - TrashStore: remove

    @MainActor
    func testRemoveDropsEntryFromManifest() {
        let summary = newSummary("remove")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([7]))
        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }

        TrashStore.shared.remove(entry)

        XCTAssertNil(TrashStore.shared.entries().first { $0.id == entry.id })
    }

    @MainActor
    func testRemoveDeletesPayloadSoItIsNoLongerReadable() {
        let summary = newSummary("remove-payload")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .calendarEvent, summary: summary, payload: Data([3, 1, 4]))
        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }

        TrashStore.shared.remove(entry)

        XCTAssertNil(TrashStore.shared.payload(for: entry))
    }

    @MainActor
    func testRemoveLeavesOtherEntriesIntact() {
        let keep = newSummary("keep")
        let drop = newSummary("drop")
        defer { cleanup(summaries: [keep, drop]) }

        TrashStore.shared.store(kind: .contact, summary: keep, payload: Data([1]))
        TrashStore.shared.store(kind: .contact, summary: drop, payload: Data([2]))

        guard let dropEntry = TrashStore.shared.entries().first(where: { $0.summary == drop }) else {
            return XCTFail("drop entry not found")
        }
        TrashStore.shared.remove(dropEntry)

        XCTAssertNotNil(TrashStore.shared.entries().first { $0.summary == keep })
        XCTAssertNil(TrashStore.shared.entries().first { $0.summary == drop })
    }

    @MainActor
    func testRemovingSameEntryTwiceIsIdempotent() {
        let summary = newSummary("remove-twice")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([5]))
        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("stored entry not found")
        }

        TrashStore.shared.remove(entry)
        // Second remove of an already-removed entry must not crash or resurrect.
        TrashStore.shared.remove(entry)

        XCTAssertNil(TrashStore.shared.entries().first { $0.id == entry.id })
    }

    // MARK: - TrashStore: payload(for:) on unknown entries

    @MainActor
    func testPayloadForUnknownEntryReturnsNil() {
        let phantom = TrashEntry(
            id: UUID(),
            kind: .contact,
            summary: newSummary("phantom"),
            createdAt: .now,
            payloadFile: "\(UUID().uuidString).vcf"
        )
        XCTAssertNil(TrashStore.shared.payload(for: phantom))
    }

    // MARK: - TrashStore: purgeExpired

    @MainActor
    func testPurgeExpiredKeepsFreshlyStoredEntries() {
        let summary = newSummary("purge-keep")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([1]))
        // A just-stored entry (createdAt == .now) is well inside the 30-day window.
        TrashStore.shared.purgeExpired()

        XCTAssertNotNil(TrashStore.shared.entries().first { $0.summary == summary })
    }

    @MainActor
    func testPurgeExpiredIsIdempotentAndDoesNotCrashOnRepeatedCalls() {
        let summary = newSummary("purge-idempotent")
        defer { cleanup(summaries: [summary]) }

        TrashStore.shared.store(kind: .contact, summary: summary, payload: Data([1]))

        TrashStore.shared.purgeExpired()
        TrashStore.shared.purgeExpired()
        TrashStore.shared.purgeExpired()

        XCTAssertNotNil(TrashStore.shared.entries().first { $0.summary == summary })
    }

    // MARK: - TrashStore: store/remove full lifecycle

    @MainActor
    func testFullLifecycleStorePayloadEntriesRemove() {
        let summary = newSummary("lifecycle")
        defer { cleanup(summaries: [summary]) }

        let payload = Data("lifecycle-bytes".utf8)

        // store
        TrashStore.shared.store(kind: .calendarEvent, summary: summary, payload: payload)

        // entries + payload
        guard let entry = TrashStore.shared.entries().first(where: { $0.summary == summary }) else {
            return XCTFail("entry missing after store")
        }
        XCTAssertEqual(entry.kind, .calendarEvent)
        XCTAssertEqual(TrashStore.shared.payload(for: entry), payload)

        // remove
        TrashStore.shared.remove(entry)
        XCTAssertNil(TrashStore.shared.entries().first { $0.id == entry.id })
        XCTAssertNil(TrashStore.shared.payload(for: entry))
    }
}
