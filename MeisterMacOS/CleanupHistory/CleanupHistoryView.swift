import SwiftUI
import AppKit
import MeradOSDesign4

@MainActor
final class CleanupHistoryModel: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    @Published var isLoading = false
    private let reader = CleanupHistoryReader()

    var totalReclaimed: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    var last30Bytes: Int64 {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return entries.filter { $0.timestamp >= cutoff }.reduce(0) { $0 + $1.bytes }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.entries = await reader.load()
    }
}

struct CleanupHistoryView: View {
    @StateObject private var model = CleanupHistoryModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            statsCards
            Divider().background(MD4.SemColor.divider)
            list
        }
        .background(MD4.SemColor.background)
        .task { if model.entries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cleanup History")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Was wurde wann reclaimed — gelesen aus den Manifests.")
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

    private var statsCards: some View {
        HStack(spacing: 16) {
            statTile(label: "Gesamt reclaimed",
                     value: model.totalReclaimed.humanBytes,
                     icon: "sparkles")
            statTile(label: "Letzte 30 Tage",
                     value: model.last30Bytes.humanBytes,
                     icon: "calendar")
            statTile(label: "Cleanups",
                     value: "\(model.entries.count)",
                     icon: "tray.full")
        }
        .padding(20)
    }

    private func statTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(label)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(MD4.Typo.tabular(MD4.Typo.title3))
                .foregroundStyle(MD4.SemColor.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var list: some View {
        Group {
            if model.entries.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "Noch keine Cleanups gelaufen",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sobald du System Cleanup, Uninstaller oder Duplikate-Finder benutzt hast, taucht die History hier auf.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.kind == .cleanup ? "sparkles" : "trash.square")
                            .foregroundStyle(MD4.SemColor.brandPrimary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(MD4.Typo.body)
                                .foregroundStyle(MD4.SemColor.textPrimary)
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(MD4.Typo.caption)
                                .foregroundStyle(MD4.SemColor.textSecondary)
                        }
                        Spacer()
                        Text(entry.bytes.humanBytes)
                            .font(MD4.Typo.tabular(MD4.Typo.body))
                            .foregroundStyle(MD4.SemColor.success)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.manifestPath])
                        } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .help("Manifest im Finder anzeigen")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

#Preview {
    CleanupHistoryView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
