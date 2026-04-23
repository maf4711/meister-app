import SwiftUI

/// Centralizes the sensory-feedback vocabulary used across the app, so screens
/// trigger the same haptic for the same class of event (success, deletion, …).
///
/// Backed by the SwiftUI ``sensoryFeedback(_:trigger:)`` modifier introduced in iOS 17.
enum HapticEvent {
    /// A destructive action completed (delete, merge that dropped contacts, clear cache).
    case destruction
    /// A non-destructive success (scan finished, backup written).
    case success
    /// A gentle tick for selection changes.
    case selection
    /// A warning prior to a destructive action.
    case warning

    var feedback: SensoryFeedback {
        switch self {
        case .destruction: .impact(weight: .medium)
        case .success:     .success
        case .selection:   .selection
        case .warning:     .warning
        }
    }
}

extension View {
    /// Play a haptic whenever `trigger` changes.
    func haptic<T: Equatable>(_ event: HapticEvent, trigger: T) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger)
    }
}
