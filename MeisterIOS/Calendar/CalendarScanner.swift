import EventKit
import Foundation

struct CalendarFinding {
    let emptyCalendars: [EKCalendar]
    let oldEvents: [EKEvent]
    let completedReminders: [EKReminder]
}

enum CalendarScanner {
    static func scan() async throws -> CalendarFinding {
        let store = EKEventStore()
        _ = try await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()

        let calendars = store.calendars(for: .event)
        let past = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: .distantPast, end: past, calendars: nil)
        let old = store.events(matching: predicate)

        let empties: [EKCalendar] = calendars.filter { cal in
            let p = store.predicateForEvents(withStart: .distantPast, end: .distantFuture, calendars: [cal])
            return store.events(matching: p).isEmpty
        }

        var completed: [EKReminder] = []
        let remindP = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: past, calendars: nil)
        completed = await withCheckedContinuation { cont in
            store.fetchReminders(matching: remindP) { cont.resume(returning: $0 ?? []) }
        }

        return CalendarFinding(emptyCalendars: empties, oldEvents: old, completedReminders: completed)
    }

    static func delete(events: [EKEvent]) throws {
        let store = EKEventStore()
        for event in events {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    static func delete(reminders: [EKReminder]) throws {
        let store = EKEventStore()
        for r in reminders { try? store.remove(r, commit: false) }
        try store.commit()
    }
}
