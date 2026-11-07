import XCTest
import Contacts
import EventKit
import Photos
@testable import MeisterIOS

// Grounded entirely in MeisterIOS/Core/PermissionManager.swift.
//
// IMPORTANT grounding notes (why this file is invariant-based, not
// case-by-case):
//   * `photosStatus`, `contactsStatus`, `calendarStatus` are `private(set)`,
//     so a `@testable` test can READ them but cannot drive them to arbitrary
//     values. The only mutators are `refresh()` (reads the live system
//     status) and the `request…` methods (need on-device authorization).
//   * Therefore the pure enum switches (`photosGateState`,
//     `contactsGateState`, `calendarGateState`) cannot be fed synthetic
//     inputs from a test. Instead we assert the *invariants* those switches
//     guarantee against whatever the runtime's current status is. On an
//     unauthorized CI runner that status is `.notDetermined`; the assertions
//     hold for every possible status because they re-derive the documented
//     mapping rather than hard-coding one outcome.
//   * `PermissionState` is compared via a `switch` over its three literally
//     observed cases (`.granted`, `.denied`, `.notDetermined`) so the test
//     does not depend on an unconfirmed `Equatable` conformance.
//
// Skipped on purpose: the `request…Access()` async methods invoke
// PHPhotoLibrary / CNContactStore / EKEventStore authorization APIs, which
// require an interactive on-device prompt and are non-deterministic in CI —
// per the protocol these are not unit-testable here.
@MainActor
final class PermissionManagerTests: XCTestCase {

    // MARK: - Local mirror of the observed PermissionState cases.

    /// Re-expresses a `PermissionState` as one of its three observed cases
    /// without relying on `Equatable`. Mirrors the cases literally present in
    /// the source (`.granted`, `.denied`, `.notDetermined`).
    private func isGranted(_ state: PermissionState) -> Bool {
        switch state {
        case .granted: return true
        case .denied, .notDetermined: return false
        }
    }

    private func isDenied(_ state: PermissionState) -> Bool {
        switch state {
        case .denied: return true
        case .granted, .notDetermined: return false
        }
    }

    private func isNotDetermined(_ state: PermissionState) -> Bool {
        switch state {
        case .notDetermined: return true
        case .granted, .denied: return false
        }
    }

    /// Exactly one of the three cases must hold (the switch is total).
    private func assertExactlyOneCase(_ state: PermissionState,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let flags = [isGranted(state), isDenied(state), isNotDetermined(state)]
        XCTAssertEqual(flags.filter { $0 }.count, 1,
                       "PermissionState must resolve to exactly one observed case",
                       file: file, line: line)
    }

    // MARK: - Singleton identity.

    func testSharedIsNonNil() {
        XCTAssertNotNil(PermissionManager.shared)
    }

    func testSharedIsStableSingleton() {
        XCTAssertTrue(PermissionManager.shared === PermissionManager.shared)
    }

    func testSharedIdentityAcrossLocalBindings() {
        let a = PermissionManager.shared
        let b = PermissionManager.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - refresh() does not crash and is idempotent.

    func testRefreshDoesNotCrash() {
        PermissionManager.shared.refresh()
        // Reaching here without trapping is the assertion.
        XCTAssertNotNil(PermissionManager.shared)
    }

    func testRefreshIsIdempotentForPhotosStatus() {
        let m = PermissionManager.shared
        m.refresh()
        let first = m.photosStatus
        m.refresh()
        XCTAssertEqual(first, m.photosStatus,
                       "Re-reading the system photos status must be stable across back-to-back refreshes")
    }

    func testRefreshIsIdempotentForContactsStatus() {
        let m = PermissionManager.shared
        m.refresh()
        let first = m.contactsStatus
        m.refresh()
        XCTAssertEqual(first, m.contactsStatus,
                       "Re-reading the system contacts status must be stable across back-to-back refreshes")
    }

    func testRefreshIsIdempotentForCalendarStatus() {
        let m = PermissionManager.shared
        m.refresh()
        let first = m.calendarStatus
        m.refresh()
        XCTAssertEqual(first, m.calendarStatus,
                       "Re-reading the system calendar status must be stable across back-to-back refreshes")
    }

    func testRepeatedRefreshConverges() {
        let m = PermissionManager.shared
        m.refresh()
        let photos = m.photosStatus
        let contacts = m.contactsStatus
        let calendar = m.calendarStatus
        for _ in 0..<5 { m.refresh() }
        XCTAssertEqual(photos, m.photosStatus)
        XCTAssertEqual(contacts, m.contactsStatus)
        XCTAssertEqual(calendar, m.calendarStatus)
    }

    // MARK: - photosGateState mapping invariant (exercises the photos switch).

    func testPhotosGateStateResolvesToExactlyOneCase() {
        PermissionManager.shared.refresh()
        assertExactlyOneCase(PermissionManager.shared.photosGateState)
    }

    /// Source: `case .authorized, .limited: return .granted` AND
    /// `isPhotosAuthorized = (.authorized || .limited)`. The two derivations
    /// of "granted-ness" must agree for whatever the live status is.
    func testPhotosAuthorizedAgreesWithGateGranted() {
        let m = PermissionManager.shared
        m.refresh()
        XCTAssertEqual(m.isPhotosAuthorized, isGranted(m.photosGateState),
                       "isPhotosAuthorized must equal (photosGateState == .granted)")
    }

    /// Source: `.denied, .restricted` map to `.denied`; those statuses are
    /// never authorized.
    func testPhotosDeniedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isDenied(m.photosGateState) {
            XCTAssertFalse(m.isPhotosAuthorized)
        }
    }

    func testPhotosNotDeterminedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isNotDetermined(m.photosGateState) {
            XCTAssertFalse(m.isPhotosAuthorized)
        }
    }

    /// Full mapping check against the raw system status, re-deriving the
    /// switch in the test so any drift in the source switch is caught.
    func testPhotosGateMatchesRawStatusMapping() {
        let m = PermissionManager.shared
        m.refresh()
        let expectedGranted: Bool
        switch m.photosStatus {
        case .authorized, .limited: expectedGranted = true
        default: expectedGranted = false
        }
        XCTAssertEqual(isGranted(m.photosGateState), expectedGranted)
    }

    // MARK: - contactsGateState mapping invariant (exercises the contacts switch).

    func testContactsGateStateResolvesToExactlyOneCase() {
        PermissionManager.shared.refresh()
        assertExactlyOneCase(PermissionManager.shared.contactsGateState)
    }

    /// Source: `case .authorized: return .granted` AND
    /// `isContactsAuthorized = (status == .authorized)`.
    func testContactsAuthorizedAgreesWithGateGranted() {
        let m = PermissionManager.shared
        m.refresh()
        XCTAssertEqual(m.isContactsAuthorized, isGranted(m.contactsGateState),
                       "isContactsAuthorized must equal (contactsGateState == .granted)")
    }

    func testContactsDeniedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isDenied(m.contactsGateState) {
            XCTAssertFalse(m.isContactsAuthorized)
        }
    }

    func testContactsNotDeterminedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isNotDetermined(m.contactsGateState) {
            XCTAssertFalse(m.isContactsAuthorized)
        }
    }

    func testContactsGateMatchesRawStatusMapping() {
        let m = PermissionManager.shared
        m.refresh()
        let expectedGranted: Bool
        switch m.contactsStatus {
        case .authorized: expectedGranted = true
        default: expectedGranted = false
        }
        XCTAssertEqual(isGranted(m.contactsGateState), expectedGranted)
    }

    // MARK: - calendarGateState mapping invariant (exercises the EK switch).

    func testCalendarGateStateResolvesToExactlyOneCase() {
        PermissionManager.shared.refresh()
        assertExactlyOneCase(PermissionManager.shared.calendarGateState)
    }

    /// Source: `case .fullAccess, .writeOnly, .authorized: return .granted`
    /// AND `isCalendarAuthorized = (.fullAccess || .writeOnly || .authorized)`.
    /// This is the branch the focus highlighted: EK `.writeOnly` is treated as
    /// granted (NOT `.limited` — that case does not exist in this source).
    func testCalendarAuthorizedAgreesWithGateGranted() {
        let m = PermissionManager.shared
        m.refresh()
        XCTAssertEqual(m.isCalendarAuthorized, isGranted(m.calendarGateState),
                       "isCalendarAuthorized must equal (calendarGateState == .granted)")
    }

    func testCalendarDeniedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isDenied(m.calendarGateState) {
            XCTAssertFalse(m.isCalendarAuthorized)
        }
    }

    func testCalendarNotDeterminedGateImpliesNotAuthorized() {
        let m = PermissionManager.shared
        m.refresh()
        if isNotDetermined(m.calendarGateState) {
            XCTAssertFalse(m.isCalendarAuthorized)
        }
    }

    /// Re-derives the EK mapping from the raw status, explicitly covering the
    /// `.writeOnly` -> granted edge the focus called out.
    func testCalendarGateMatchesRawStatusMapping() {
        let m = PermissionManager.shared
        m.refresh()
        let expectedGranted: Bool
        switch m.calendarStatus {
        case .fullAccess, .writeOnly, .authorized: expectedGranted = true
        default: expectedGranted = false
        }
        XCTAssertEqual(isGranted(m.calendarGateState), expectedGranted)
    }

    // MARK: - Cross-cutting invariants.

    /// After a refresh, no gate may be simultaneously authorized AND report a
    /// non-granted gate state for any of the three frameworks.
    func testNoFrameworkIsAuthorizedWithoutGrantedGate() {
        let m = PermissionManager.shared
        m.refresh()
        if m.isPhotosAuthorized { XCTAssertTrue(isGranted(m.photosGateState)) }
        if m.isContactsAuthorized { XCTAssertTrue(isGranted(m.contactsGateState)) }
        if m.isCalendarAuthorized { XCTAssertTrue(isGranted(m.calendarGateState)) }
    }

    /// Gate state must be deterministic for a fixed underlying status: reading
    /// the computed property twice without an intervening refresh yields the
    /// same case.
    func testGateStatesAreDeterministicWithoutRefresh() {
        let m = PermissionManager.shared
        m.refresh()
        XCTAssertEqual(isGranted(m.photosGateState), isGranted(m.photosGateState))
        XCTAssertEqual(isGranted(m.contactsGateState), isGranted(m.contactsGateState))
        XCTAssertEqual(isGranted(m.calendarGateState), isGranted(m.calendarGateState))
    }
}
