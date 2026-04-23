import Contacts
import Foundation

/// Suggests contact groups based on metadata — mail domains become "Work", shared
/// family calendars become "Family", etc. Conservative: only proposes, never auto-applies.
enum GroupAutoCreate {
    struct Suggestion {
        let title: String
        let members: [ContactItem]
        let reason: String
    }

    static func suggestions(from contacts: [ContactItem]) -> [Suggestion] {
        let byDomain: [String: [ContactItem]] = Dictionary(grouping: contacts.filter { !$0.emails.isEmpty }) { item in
            item.emails.first?.split(separator: "@").last.map(String.init) ?? ""
        }
        var result: [Suggestion] = []
        for (domain, members) in byDomain where members.count >= 3 && !domain.isEmpty {
            // Skip free-mail providers — too generic to be a "group".
            if isFreeMail(domain) { continue }
            result.append(Suggestion(
                title: workTitle(from: domain),
                members: members,
                reason: "\(members.count) contacts share the \(domain) domain"
            ))
        }
        return result.sorted { $0.members.count > $1.members.count }
    }

    /// Persist a suggestion as an actual CNGroup.
    static func create(_ suggestion: Suggestion) throws {
        let store = CNContactStore()
        let group = CNMutableGroup()
        group.name = suggestion.title
        let save = CNSaveRequest()
        save.add(group, toContainerWithIdentifier: nil)
        try store.execute(save)
        let add = CNSaveRequest()
        for contact in suggestion.members {
            if let mutable = contact.cn.mutableCopy() as? CNMutableContact {
                add.addMember(mutable, to: group)
            }
        }
        try store.execute(add)
    }

    private static func isFreeMail(_ domain: String) -> Bool {
        let free: Set<String> = [
            "gmail.com", "icloud.com", "me.com", "yahoo.com", "hotmail.com",
            "outlook.com", "live.com", "gmx.de", "gmx.net", "web.de", "proton.me",
            "protonmail.com", "mail.com", "t-online.de",
        ]
        return free.contains(domain.lowercased())
    }

    private static func workTitle(from domain: String) -> String {
        let root = domain.split(separator: ".").first.map(String.init) ?? domain
        return root.capitalized
    }
}
