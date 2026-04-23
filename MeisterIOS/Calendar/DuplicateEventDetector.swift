import EventKit
import Foundation

enum DuplicateEventDetector {
    struct Group: Identifiable {
        let id = UUID()
        let events: [EKEvent]
    }

    /// Pure-exact duplicates: same title, same start minute, same duration. Good first pass.
    static func scan(in store: EKEventStore, range: DateInterval? = nil) -> [Group] {
        let start = range?.start ?? Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        let end = range?.end ?? Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)

        var buckets: [String: [EKEvent]] = [:]
        for event in events {
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !title.isEmpty else { continue }
            let startMinute = Int(event.startDate.timeIntervalSince1970) / 60
            let duration = Int(event.endDate.timeIntervalSince(event.startDate))
            let key = "\(title)|\(startMinute)|\(duration)"
            buckets[key, default: []].append(event)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map(Group.init(events:))
            .sorted { $0.events.count > $1.events.count }
    }

    static func delete(keeping event: EKEvent, in group: Group, store: EKEventStore) throws {
        for duplicate in group.events where duplicate.eventIdentifier != event.eventIdentifier {
            try? store.remove(duplicate, span: .thisEvent, commit: false)
        }
        try store.commit()
    }
}
