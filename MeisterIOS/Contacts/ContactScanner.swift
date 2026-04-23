import Contacts
import Foundation

struct ContactItem: Identifiable, Hashable {
    let id: String // CNContact.identifier
    let fullName: String
    let givenName: String
    let familyName: String
    let phones: [String]         // normalized E.164
    let emails: [String]         // lowercased, trimmed
    let hasImage: Bool
    let organization: String
    let cn: CNContact

    var isEmpty: Bool { fullName.isEmpty && phones.isEmpty && emails.isEmpty }

    /// Quality score 0…1: presence of name, phone, email, image, organization.
    var quality: Double {
        var score = 0.0
        if !fullName.isEmpty { score += 0.3 }
        if !phones.isEmpty { score += 0.3 }
        if !emails.isEmpty { score += 0.2 }
        if hasImage { score += 0.1 }
        if !organization.isEmpty { score += 0.1 }
        return score
    }
}

enum ContactScanner {
    static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
    ]

    static func fetchAll() throws -> [ContactItem] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: keys)
        var items: [ContactItem] = []
        try store.enumerateContacts(with: request) { cn, _ in
            items.append(ContactItem(
                id: cn.identifier,
                fullName: CNContactFormatter.string(from: cn, style: .fullName) ?? "",
                givenName: cn.givenName,
                familyName: cn.familyName,
                phones: cn.phoneNumbers.compactMap { PhoneNormalizer.normalize($0.value.stringValue) },
                emails: cn.emailAddresses.map { ($0.value as String).trimmingCharacters(in: .whitespaces).lowercased() },
                hasImage: cn.thumbnailImageData != nil,
                organization: cn.organizationName,
                cn: cn
            ))
        }
        return items
    }

    /// Delete a contact (no confirmation UI — caller must confirm).
    static func delete(_ items: [ContactItem]) throws {
        let store = CNContactStore()
        let save = CNSaveRequest()
        for item in items {
            if let mutable = item.cn.mutableCopy() as? CNMutableContact {
                save.delete(mutable)
            }
        }
        try store.execute(save)
    }

    /// Merge: pick a "winner" (best quality), move missing phones/emails from losers onto winner, delete losers.
    static func merge(group: ContactGroup) throws {
        guard let winner = group.items.max(by: { $0.quality < $1.quality }) else { return }
        guard let mutable = winner.cn.mutableCopy() as? CNMutableContact else { return }
        let losers = group.items.filter { $0.id != winner.id }

        var phoneSet = Set(mutable.phoneNumbers.compactMap { PhoneNormalizer.normalize($0.value.stringValue) })
        var emailSet = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })
        var newPhones = mutable.phoneNumbers
        var newEmails = mutable.emailAddresses

        for loser in losers {
            for p in loser.phones where !phoneSet.contains(p) {
                phoneSet.insert(p)
                newPhones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: p)))
            }
            for e in loser.emails where !emailSet.contains(e) {
                emailSet.insert(e)
                newEmails.append(CNLabeledValue(label: CNLabelHome, value: e as NSString))
            }
        }
        mutable.phoneNumbers = newPhones
        mutable.emailAddresses = newEmails

        let store = CNContactStore()
        let save = CNSaveRequest()
        save.update(mutable)
        for loser in losers {
            if let m = loser.cn.mutableCopy() as? CNMutableContact { save.delete(m) }
        }
        try store.execute(save)
    }
}

struct ContactGroup: Identifiable {
    let id = UUID()
    var items: [ContactItem]
    var title: String {
        items.max { $0.quality < $1.quality }?.fullName ?? "Unnamed"
    }
}
