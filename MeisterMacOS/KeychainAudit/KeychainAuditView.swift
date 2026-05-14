import SwiftUI
import AppKit
import MeradOSDesign4

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
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.summaries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keychain Audit")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Item-Statistik pro Keychain — Metadaten only, keine Decrypt-Prompts.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
            Image(systemName: "key.horizontal.fill").foregroundStyle(MD4.SemColor.brandPrimary)
            Text("\(model.totalItems) Items in \(model.summaries.count) Keychain\(model.summaries.count == 1 ? "" : "s")")
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Spacer()
            Button("Open Keychain Access") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func keychainCard(_ s: KeychainSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lock.shield").foregroundStyle(MD4.SemColor.brandPrimary)
                Text(s.displayName)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
                Text("\(s.totalItems) items")
                    .font(MD4.Typo.tabular(MD4.Typo.body))
                    .foregroundStyle(MD4.SemColor.textPrimary)
            }
            grid(s)
            Text(s.path)
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(s.sizeBytes.humanBytes)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                if let m = s.lastModified {
                    Text("· geändert \(m.formatted(date: .abbreviated, time: .omitted))")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
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
            Image(systemName: icon).foregroundStyle(MD4.SemColor.textSecondary).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(MD4.Typo.tabular(MD4.Typo.body))
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(label)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
        }
    }
}
