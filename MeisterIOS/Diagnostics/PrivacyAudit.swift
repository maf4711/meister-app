import Foundation

/// Summarises what privacy grants this app itself holds (Photos, Contacts, Calendar, Mic).
/// The system-wide TCC.db is SIP-protected and only readable by Apple's own tools,
/// so we stop at the per-app snapshot — still useful to reassure the user nothing
/// is being accessed silently.
struct PrivacyAudit {
    struct Grant {
        let service: String
        let systemImage: String
        let state: String
    }

    @MainActor
    static func snapshot(_ permissions: PermissionManager) -> [Grant] {
        [
            Grant(service: "Photos",   systemImage: "photo.on.rectangle.angled",
                  state: permissions.isPhotosAuthorized ? "Authorized" : "Denied / Not determined"),
            Grant(service: "Contacts", systemImage: "person.2",
                  state: permissions.isContactsAuthorized ? "Authorized" : "Denied / Not determined"),
            Grant(service: "Calendar", systemImage: "calendar",
                  state: permissions.isCalendarAuthorized ? "Authorized" : "Denied / Not determined"),
        ]
    }
}
