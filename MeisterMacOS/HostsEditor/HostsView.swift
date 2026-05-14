import SwiftUI
import MeradOSDesign4

@MainActor
final class HostsModel: ObservableObject {
    @Published var entries: [HostsEntry] = []
    @Published var raw: String = ""
    @Published var isLoading = false

    private let reader = HostsReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let (e, r) = await reader.read()
        self.entries = e
        self.raw = r
    }
}

struct HostsView: View {
    @StateObject private var model = HostsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.entries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("/etc/hosts")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Read-only Anzeige. Edit via `sudo vi /etc/hosts` — schreibender Zugriff später.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty {
            ContentUnavailableView(
                "Keine aktiven Einträge",
                systemImage: "doc.text",
                description: Text("Hosts-Datei enthält nur Standardeinträge.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.entries) { entry in
                    row(entry)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ entry: HostsEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.ip)
                    .font(MD4.Typo.tabular(MD4.Typo.body))
                    .foregroundStyle(entry.isCommented ? MD4.SemColor.textTertiary : MD4.SemColor.textPrimary)
                if entry.isCommented {
                    Text("auskommentiert")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                }
            }
            .frame(width: 140, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.hosts.joined(separator: ", "))
                    .font(MD4.Typo.body)
                    .foregroundStyle(entry.isCommented ? MD4.SemColor.textTertiary : MD4.SemColor.textPrimary)
                if let c = entry.comment {
                    Text("# \(c)")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HostsView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
