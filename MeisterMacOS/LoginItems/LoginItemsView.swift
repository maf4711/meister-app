import SwiftUI
import AppKit
import MeradOSDesign3

@MainActor
final class LoginItemsModel: ObservableObject {
    @Published var items: [LoginItem] = []
    @Published var isLoading = false
    @Published var filter: LoginItemKind? = nil

    private let reader = LoginItemsReader()

    var filtered: [LoginItem] {
        guard let f = filter else { return items }
        return items.filter { $0.kind == f }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.items = await reader.readAll()
    }
}

struct LoginItemsView: View {
    @StateObject private var model = LoginItemsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            kindFilter
            Divider().background(MD3.SemColor.divider)
            list
        }
        .background(MD3.SemColor.background)
        .task { if model.items.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Login Items & Launch Agents")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Was startet bei Login + im Hintergrund. Read-only — Removal in Settings → Login Items.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    private var kindFilter: some View {
        HStack(spacing: 8) {
            chip("Alle", nil)
            chip("Login Items", .loginItem)
            chip("User Agents", .launchAgentUser)
            chip("System Agents", .launchAgentSystem)
            chip("Daemons", .launchDaemon)
            Spacer()
            Text("\(model.filtered.count) Einträge")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func chip(_ label: String, _ kind: LoginItemKind?) -> some View {
        let active = model.filter == kind
        return Button(label) { model.filter = kind }
            .font(MD3.Typo.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? MD3.SemColor.brandPrimary.opacity(0.2) : Color.clear,
                        in: Capsule())
            .foregroundStyle(active ? MD3.SemColor.brandPrimary : MD3.SemColor.textSecondary)
            .buttonStyle(.plain)
    }

    private var list: some View {
        List {
            ForEach(model.filtered) { item in
                row(item)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: LoginItem) -> some View {
        HStack {
            Image(systemName: kindIcon(item.kind))
                .foregroundStyle(item.enabled ? MD3.SemColor.brandPrimary : MD3.SemColor.textTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                if let path = item.path {
                    Text(path)
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let team = item.teamID {
                Text(team)
                    .font(MD3.Typo.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD3.SemColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Text(item.enabled ? "an" : "aus")
                .font(MD3.Typo.caption.bold())
                .foregroundStyle(item.enabled ? MD3.SemColor.success : MD3.SemColor.textTertiary)
            if let path = item.path {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Im Finder anzeigen")
            }
        }
        .padding(.vertical, 2)
    }

    private func kindIcon(_ k: LoginItemKind) -> String {
        switch k {
        case .loginItem:         return "person.crop.circle"
        case .launchAgentUser:   return "person.fill"
        case .launchAgentSystem: return "gear"
        case .launchDaemon:      return "bolt.shield"
        }
    }
}

#Preview {
    LoginItemsView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
