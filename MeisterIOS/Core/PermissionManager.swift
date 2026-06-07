import Contacts
import EventKit
import Foundation
import Observation
import Photos

/// Reads and requests authorization for the user-data frameworks Meister needs.
///
/// The manager stays intentionally shallow — it publishes the latest status and
/// exposes `request…` methods that individual screens call from their gates.
@Observable
@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    private(set) var photosStatus: PHAuthorizationStatus = .notDetermined
    private(set) var contactsStatus: CNAuthorizationStatus = .notDetermined
    private(set) var calendarStatus: EKAuthorizationStatus = .notDetermined

    var isPhotosAuthorized: Bool { photosStatus == .authorized || photosStatus == .limited }
    var isContactsAuthorized: Bool { contactsStatus == .authorized }
    var isCalendarAuthorized: Bool {
        // iOS 17+ only returns .fullAccess / .writeOnly; the legacy .authorized
        // case is deprecated and never produced at our deployment target.
        calendarStatus == .fullAccess || calendarStatus == .writeOnly
    }

    var photosGateState: PermissionState {
        switch photosStatus {
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        default:                    return .notDetermined
        }
    }

    var contactsGateState: PermissionState {
        switch contactsStatus {
        case .authorized:           return .granted
        case .denied, .restricted:  return .denied
        default:                    return .notDetermined
        }
    }

    var calendarGateState: PermissionState {
        switch calendarStatus {
        case .fullAccess, .writeOnly, .authorized: return .granted
        case .denied, .restricted:                 return .denied
        default:                                   return .notDetermined
        }
    }

    private init() { refresh() }

    func refresh() {
        photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestPhotosAccess() async -> Bool {
        let before = photosStatus
        photosStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        // Same fallback as Contacts: if the status didn't change and is still
        // notDetermined, iOS suppressed the dialog — treat as denied.
        if photosStatus == .notDetermined && before == .notDetermined {
            photosStatus = .denied
        }
        return isPhotosAuthorized
    }

    @discardableResult
    func requestContactsAccess() async -> Bool {
        let before = contactsStatus
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            // The framework reports permanent denial as a thrown error.
        }
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)

        // Tom report 2026-05-10 11:33: "Kontakte Zugriff geht nicht".
        // If the request returned and the status is STILL .notDetermined
        // (no transition since before the call), iOS suppressed the prompt
        // — usually because the user already denied it once before iOS
        // remembered the choice, or the running runtime can't show the
        // dialog. Treat this case as denied so the gate falls through to
        // the Settings deeplink instead of looping back to "Grant Access"
        // forever.
        if contactsStatus == .notDetermined && before == .notDetermined {
            contactsStatus = .denied
        }
        return isContactsAuthorized
    }

    @discardableResult
    func requestCalendarAccess() async -> Bool {
        let before = calendarStatus
        do {
            _ = try await EKEventStore().requestFullAccessToEvents()
        } catch {
            // Same handling as Contacts: status is the source of truth.
        }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        if calendarStatus == .notDetermined && before == .notDetermined {
            calendarStatus = .denied
        }
        return isCalendarAuthorized
    }
}
