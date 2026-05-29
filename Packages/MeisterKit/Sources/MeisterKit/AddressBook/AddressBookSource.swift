import Foundation

public struct AddressBookSource: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: URL
    public let sizeBytes: Int64
    public let account: String?
    public let lastMigrationEvent: String?
    public let hasDestructiveMarker: Bool
    public let contactCount: Int?

    public var shortID: String {
        String(id.uuidString.prefix(8))
    }

    public var humanSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public init(
        id: UUID,
        path: URL,
        sizeBytes: Int64,
        account: String?,
        lastMigrationEvent: String?,
        hasDestructiveMarker: Bool,
        contactCount: Int?
    ) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.account = account
        self.lastMigrationEvent = lastMigrationEvent
        self.hasDestructiveMarker = hasDestructiveMarker
        self.contactCount = contactCount
    }
}
