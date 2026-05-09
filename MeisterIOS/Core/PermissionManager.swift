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
        calendarStatus == .fullAccess || calendarStatus == .writeOnly || calendarStatus == .authorized
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
        photosStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return isPhotosAuthorized
    }

    @discardableResult
    func requestContactsAccess() async -> Bool {
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            // The framework reports permanent denial as a thrown error; refresh and report.
        }
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        return isContactsAuthorized
    }

    @discardableResult
    func requestCalendarAccess() async -> Bool {
        do {
            _ = try await EKEventStore().requestFullAccessToEvents()
        } catch {
            // Same handling as Contacts: status is the source of truth.
        }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        return isCalendarAuthorized
    }
}
