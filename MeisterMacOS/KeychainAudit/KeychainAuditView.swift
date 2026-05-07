import SwiftUI
import AppKit
import MeradOSDesign3

@MainActor
final class KeychainAuditModel: ObservableObject {
    @Published var summaries: [KeychainSummary] = []
    @Published var isLoading = false
    private let reader = KeychainAuditReader()

    var totalItems: Int { summaries.reduce(0) { $0 + $1.totalItems } }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.summaries = await reader.read()
    }
}

struct KeychainAuditView: View {
    @StateObject private var model = KeychainAuditModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.summaries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keychain Audit")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Item-Statistik pro Keychain — Metadaten only, keine Decrypt-Prompts.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.summaries.isEmpty {
            ProgressView("Reading keychains…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    summaryHeader
                    ForEach(model.summaries) { s in
                        keychainCard(s)
                    }
                }
                .padding(20)
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            Image(systemName: "key.horizontal.fill").foregroundStyle(MD3.SemColor.brandPrimary)
            Text("\(model.totalItems) Items in \(model.summaries.count) Keychain\(model.summaries.count == 1 ? "" : "s")")
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Spacer()
            Button("Open Keychain Access") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func keychainCard(_ s: KeychainSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lock.shield").foregroundStyle(MD3.SemColor.brandPrimary)
                Text(s.displayName)
                    .font(MD3.Typo.headline)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Spacer()
                Text("\(s.totalItems) items")
                    .font(MD3.Typo.tabular(MD3.Typo.body))
                    .foregroundStyle(MD3.SemColor.textPrimary)
            }
            grid(s)
            Text(s.path)
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(s.sizeBytes.humanBytes)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                if let m = s.lastModified {
                    Text("· geändert \(m.formatted(date: .abbreviated, time: .omitted))")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func grid(_ s: KeychainSummary) -> some View {
        HStack(spacing: 16) {
            cell("Internet", "\(s.internetPasswords)", "globe")
            cell("Generic", "\(s.genericPasswords)", "text.badge.checkmark")
            cell("Certs", "\(s.certificates)", "checkmark.seal")
            cell("Keys", "\(s.keys)", "key")
        }
    }

    private func cell(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(MD3.SemColor.textSecondary).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(MD3.Typo.tabular(MD3.Typo.body))
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(label)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
    }
}
