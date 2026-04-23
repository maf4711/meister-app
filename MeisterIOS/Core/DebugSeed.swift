#if DEBUG
import Contacts
import EventKit
import Foundation

/// Seeds the simulator with realistic test data — duplicate contacts, empties,
/// old calendar events, and completed reminders. Only compiled in DEBUG builds.
enum DebugSeed {
    static func populateContacts() async throws -> Int {
        let store = CNContactStore()
        _ = try await store.requestAccess(for: .contacts)

        let saveRequest = CNSaveRequest()

        // 1. Ten realistic unique contacts.
        let unique: [(String, String, String, String, String)] = [
            ("Anna",   "Becker",    "+4915112340001", "anna.becker@example.de",   "Acme GmbH"),
            ("Bernd",  "Weber",     "+4915112340002", "bw@example.com",           ""),
            ("Claudia","Schmidt",   "+4915112340003", "claudia@example.org",      "Beispiel AG"),
            ("Dennis", "Koch",      "+4915112340004", "",                         ""),
            ("Eva",    "Fischer",   "+4915112340005", "eva.fischer@example.de",   ""),
            ("Felix",  "Hoffmann",  "+4915112340006", "felix@example.net",        "Contoso"),
            ("Greta",  "Wagner",    "+4915112340007", "greta.w@example.de",       ""),
            ("Hannes", "Bauer",     "+4915112340008", "hb@example.de",            "Bauer & Söhne"),
            ("Isabel", "Lehmann",   "+4915112340009", "i.lehmann@example.com",    ""),
            ("Jan",    "Kowalski",  "+4915112340010", "jan@example.pl",           ""),
        ]
        for (given, family, phone, email, org) in unique {
            saveRequest.add(makeContact(given: given, family: family, phone: phone, email: email, org: org), toContainerWithIdentifier: nil)
        }

        // 2. Three fuzzy duplicate pairs (German umlaut variations + name order).
        saveRequest.add(makeContact(given: "Thomas", family: "Müller", phone: "+4917612345001", email: "tm@example.de", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "Thomas", family: "Mueller", phone: "+4917612345001", email: "thomas.mueller@example.de", org: ""), toContainerWithIdentifier: nil)

        saveRequest.add(makeContact(given: "Björn", family: "Åkesson", phone: "+46701234567", email: "bjorn@example.se", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "Bjoern", family: "Akesson", phone: "+46701234567", email: "", org: ""), toContainerWithIdentifier: nil)

        saveRequest.add(makeContact(given: "Jan", family: "Kowalski", phone: "+48601234567", email: "jan.k@example.pl", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "Kowalski", family: "Jan", phone: "", email: "jan.k@example.pl", org: ""), toContainerWithIdentifier: nil)

        // 3. Two exact duplicates (same phone number → will collapse).
        saveRequest.add(makeContact(given: "Support", family: "Merados", phone: "+4930123456789", email: "support@merados.com", org: "Merados"), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "", family: "", phone: "+4930123456789", email: "", org: "Merados"), toContainerWithIdentifier: nil)

        // 4. Three low-quality contacts (name only, no phone/email).
        saveRequest.add(makeContact(given: "Pizza", family: "Hotline", phone: "", email: "", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "Bank", family: "", phone: "", email: "", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "Arzt", family: "", phone: "", email: "", org: ""), toContainerWithIdentifier: nil)

        // 5. Two completely empty contacts.
        saveRequest.add(makeContact(given: "", family: "", phone: "", email: "", org: ""), toContainerWithIdentifier: nil)
        saveRequest.add(makeContact(given: "", family: "", phone: "", email: "", org: ""), toContainerWithIdentifier: nil)

        try store.execute(saveRequest)
        return 10 + 6 + 2 + 3 + 2
    }

    static func populateCalendar() async throws -> Int {
        let store = EKEventStore()
        _ = try await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()

        guard let calendar = store.defaultCalendarForNewEvents else { return 0 }

        var count = 0
        for i in 0..<5 {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "Ancient meeting #\(i + 1)"
            event.startDate = Date().addingTimeInterval(-Double(3 + i) * 365 * 86400)
            event.endDate = event.startDate.addingTimeInterval(3600)
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
    }

    private static func makeContact(given: String, family: String, phone: String, email: String, org: String) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.organizationName = org
        if !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        if !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        return contact
    }
}
#endif
