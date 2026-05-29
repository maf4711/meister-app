#if canImport(Contacts)
import Contacts
import Foundation

public enum ContactExporterError: Error, LocalizedError {
    case accessDenied
    case nothingToExport

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "Contacts access denied. Grant permission in System Settings → Privacy → Contacts."
        case .nothingToExport: return "No contacts to export."
        }
    }
}

public enum ContactExporter {
    public static func writeVCard(to url: URL) async throws {
        let store = CNContactStore()
        try await requestAccess(store: store)

        let keys: [CNKeyDescriptor] = [
            CNContactVCardSerialization.descriptorForRequiredKeys(),
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        guard !contacts.isEmpty else { throw ContactExporterError.nothingToExport }

        let data = try CNContactVCardSerialization.data(with: contacts)
        try data.write(to: url, options: .atomic)
    }

    private static func requestAccess(store: CNContactStore) async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = try await store.requestAccess(for: .contacts)
            if !granted { throw ContactExporterError.accessDenied }
        default:
            throw ContactExporterError.accessDenied
        }
    }
}

@available(iOS 18, macOS 14, *)
private extension CNContactStore {
    func requestAccess(for entity: CNEntityType) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            self.requestAccess(for: entity) { granted, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: granted)
                }
            }
        }
    }
}
#endif
