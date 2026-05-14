import SwiftUI
import AppKit
import MeradOSDesign4

@MainActor
final class SecurityStatusModel: ObservableObject {
    @Published var checks: [SecurityCheck] = []
    @Published var isLoading = false
    private let reader = SecurityStatusReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.checks = await reader.readAll()
    }
}

struct SecurityStatusView: View {
    @StateObject private var model = SecurityStatusModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.checks.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Security Status")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("FileVault, Firewall, Gatekeeper, SIP, XProtect, Quarantine — read-only.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.checks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.checks) { check in
                    row(check)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ check: SecurityCheck) -> some View {
        let (color, label, icon) = stateInfo(check.state)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(check.title)
                        .font(MD4.Typo.headline)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                    Text(label)
                        .font(MD4.Typo.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.2), in: Capsule())
                        .foregroundStyle(color)
                }
                if let detail = check.detail, !detail.isEmpty {
                    Text(detail)
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .lineLimit(3)
                }
                if let action = check.action {
                    Button(action.label) {
                        NSWorkspace.shared.open(action.url)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(MD4.SemColor.brandPrimary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func stateInfo(_ s: SecurityState) -> (Color, String, String) {
        switch s {
        case .ok(let l):     return (MD4.SemColor.success, l, "checkmark.shield.fill")
        case .warn(let l):   return (MD4.SemColor.warning, l, "exclamationmark.triangle.fill")
        case .bad(let l):    return (MD4.SemColor.error,   l, "xmark.shield.fill")
        case .unknown(let l):return (MD4.SemColor.textSecondary, l, "questionmark.circle")
        }
    }
}

#Preview {
    SecurityStatusView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
