import Contacts
import Foundation

/// vCard export + import for local backups. We always backup before destructive actions.
enum ContactBackup {
    static var backupsDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    static func exportAll() throws -> URL {
        let store = CNContactStore()
        let req = CNContactFetchRequest(keysToFetch: [CNContactVCardSerialization.descriptorForRequiredKeys()])
        var contacts: [CNContact] = []
        try store.enumerateContacts(with: req) { c, _ in contacts.append(c) }
        let data = try CNContactVCardSerialization.data(with: contacts)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsDir.appendingPathComponent("contacts-\(stamp).vcf")
        try data.write(to: url)
        return url
    }

    static func listBackups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
    }
}
