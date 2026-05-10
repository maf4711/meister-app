import SwiftUI
import UIKit

/// Three-state permission status used by `PermissionGate`.
///
/// - `.notDetermined`: ask for access (system dialog appears once)
/// - `.denied` / `.restricted`: ask the user to open Settings — iOS won't
///   re-prompt after denial. Without this branch the "Grant Access" button
///   silently does nothing on the second tap, which is exactly what Justin
///   reported.
/// - `.authorized`: render `granted`
enum PermissionState: Equatable {
    case notDetermined, denied, granted
}

/// HIG-aligned access prompt.
struct PermissionGate<Granted: View>: View {
    typealias State = PermissionState

    let title: String
    let systemImage: String
    let message: String
    let state: State
    let request: () async -> Void
    @ViewBuilder let granted: () -> Granted

    @SwiftUI.State private var isRequesting = false

    /// Convenience initializer that maps a Bool to either `.granted` or
    /// `.notDetermined`. Existing call sites work unchanged but lose the
    /// "open Settings" branch — prefer the explicit `state:` form.
    init(title: String,
         systemImage: String,
         message: String,
         isGranted: Bool,
         request: @escaping () async -> Void,
         @ViewBuilder granted: @escaping () -> Granted) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.state = isGranted ? .granted : .notDetermined
        self.request = request
        self.granted = granted
    }

    init(title: String,
         systemImage: String,
         message: String,
         state: State,
         request: @escaping () async -> Void,
         @ViewBuilder granted: @escaping () -> Granted) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.state = state
        self.request = request
        self.granted = granted
    }

    var body: some View {
        switch state {
        case .granted:
            granted()
        case .notDetermined:
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                VStack(spacing: 8) {
                    Button {
                        isRequesting = true
                        Task {
                            await request()
                            isRequesting = false
                        }
                    } label: {
                        Text(isRequesting ? "Requesting Access…" : "Grant Access")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting)
                    .accessibilityHint("Opens the system authorization dialog.")

                    // Tom Build 30: "NICHTS WURDE GEFIXT" — turns out the
                    // borderless tertiary "stattdessen…" link from Build 30
                    // was too easy to overlook. Promote to a full secondary
                    // button so it has the same visual weight as Grant
                    // Access. Some iOS configurations never present the
                    // system dialog at all (Catalyst, prior cached denial)
                    // — without a prominent escape, the user appears stuck.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("In Einstellungen öffnen", systemImage: "gearshape")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Falls der iOS-Dialog nicht erscheint, hier direkt zur Permission-Seite.")
                }
            }
        case .denied:
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text("Zugriff wurde abgelehnt. iOS zeigt den System-Dialog nicht erneut — bitte in den Einstellungen freischalten:\n\nEinstellungen → Datenschutz → \(title) → Meister")
            } actions: {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Einstellungen öffnen", systemImage: "gearshape")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
