import Contacts
import EventKit
import Foundation

/// Cross-check calendar "Birthdays" entries (iOS-native) against contacts and fill in
/// the missing `birthday` field on a CNContact.
enum BirthdayEnricher {
    struct Enrichment {
        let contact: ContactItem
        let birthday: DateComponents
    }

    static func scan() async throws -> [Enrichment] {
        let store = EKEventStore()
        _ = try await store.requestFullAccessToEvents()
        let contacts = try ContactScanner.fetchAll()
        let candidates = contacts.filter { $0.cn.birthday == nil && !$0.fullName.isEmpty }

        // iOS creates a "Birthdays" calendar sourced from contacts that already have them.
        // Use the reverse: events that carry a name but where the corresponding contact lacks a birthday.
        let birthdayCalendars = store.calendars(for: .event).filter { $0.type == .birthday }
        guard !birthdayCalendars.isEmpty else { return [] }
        let past = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let future = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: past, end: future, calendars: birthdayCalendars)
        let events = store.events(matching: predicate)

        var enrichments: [Enrichment] = []
        for event in events {
            let title = event.title ?? ""
            for contact in candidates where FuzzyMatcher.nameSimilarity(title, contact.fullName) > 0.9 {
                let components = Calendar.current.dateComponents([.year, .month, .day], from: event.startDate)
                enrichments.append(Enrichment(contact: contact, birthday: components))
            }
        }
        return enrichments
    }

    static func apply(_ enrichment: Enrichment) throws {
        guard let mutable = enrichment.contact.cn.mutableCopy() as? CNMutableContact else { return }
        mutable.birthday = enrichment.birthday
        let store = CNContactStore()
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
    }
}
