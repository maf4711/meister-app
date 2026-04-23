import SwiftUI

/// HIG-aligned access prompt. Shows a full-screen introduction with a single
/// primary action and falls through to `granted` once authorization is given.
struct PermissionGate<Granted: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let isGranted: Bool
    let request: () async -> Void
    @ViewBuilder let granted: () -> Granted

    @State private var isRequesting = false

    var body: some View {
        if isGranted {
            granted()
        } else {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
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
            }
        }
    }
}
