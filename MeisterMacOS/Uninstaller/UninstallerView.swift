import SwiftUI
import AppKit
import MeradOSDesign4

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published var leftovers: [LeftoverItem] = []
    @Published var selectedLeftovers: Set<LeftoverItem.ID> = []
    @Published var isLoadingApps = false
    @Published var isScanningLeftovers = false
    @Published var isUninstalling = false
    @Published var errorMessage: String?
    @Published var lastManifest: UninstallManifest?

    private let scanner = UninstallerScanner()
    private let cleaner = UninstallerCleaner()

    var totalSelectedBytes: Int64 {
        let leftoverBytes = leftovers
            .filter { selectedLeftovers.contains($0.id) }
            .reduce(0) { $0 + $1.bytes }
        return (selectedApp?.bundleSize ?? 0) + leftoverBytes
    }

    func loadApps() async {
        isLoadingApps = true
        defer { isLoadingApps = false }
        self.apps = InstalledAppDiscovery.discoverAll()
    }

    func selectApp(_ app: InstalledApp) async {
        self.selectedApp = app
        self.leftovers = []
        self.selectedLeftovers = []
        isScanningLeftovers = true
        defer { isScanningLeftovers = false }
        // Off main for the FS scan.
        let found = await Task.detached(priority: .userInitiated) {
            UninstallerScanner().leftovers(for: app)
        }.value
        self.leftovers = found
        self.selectedLeftovers = Set(found.map(\.id))  // pre-select all
    }

    func toggle(_ leftover: LeftoverItem) {
        if selectedLeftovers.contains(leftover.id) {
            selectedLeftovers.remove(leftover.id)
        } else {
            selectedLeftovers.insert(leftover.id)
        }
    }

    func uninstall() async {
        guard let app = selectedApp else { return }
        let chosen = leftovers.filter { selectedLeftovers.contains($0.id) }
        isUninstalling = true
        defer { isUninstalling = false }
        do {
            let manifest = try await cleaner.uninstall(app, leftovers: chosen)
            self.lastManifest = manifest
            // App is gone — refresh list and clear selection.
            await loadApps()
            self.selectedApp = nil
            self.leftovers = []
            self.selectedLeftovers = []
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct UninstallerView: View {
    @StateObject private var model = UninstallerModel()
    @State private var showConfirm = false
    @State private var search = ""

    var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter { $0.displayName.lowercased().contains(search.lowercased()) }
    }

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 280, idealWidth: 320)
            detail
                .frame(minWidth: 360)
        }
        .background(MD4.SemColor.background)
        .task { if model.apps.isEmpty { await model.loadApps() } }
        .alert("Uninstall \(model.selectedApp?.displayName ?? "")?",
               isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await model.uninstall() }
            }
        } message: {
            Text("\(model.totalSelectedBytes.humanBytes) total. App + \(model.selectedLeftovers.count) leftover items go to ~/.Trash and can be restored.")
        }
        .alert("Error",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: app list pane

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MD4.SemColor.textTertiary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(MD4.SemColor.divider)

            List(filteredApps, selection: Binding(
                get: { model.selectedApp?.id },
                set: { newID in
                    if let id = newID,
                       let app = filteredApps.first(where: { $0.id == id }) {
                        Task { await model.selectApp(app) }
                    }
                }
            )) { app in
                appRow(app).tag(app.id)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(MD4.SemColor.surface)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            appIcon(for: app)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(app.version ?? app.bundleID ?? "")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(app.bundleSize.humanBytes)
                .font(MD4.Typo.tabular(MD4.Typo.caption))
                .foregroundStyle(MD4.SemColor.textTertiary)
        }
    }

    private func appIcon(for app: InstalledApp) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
        return Image(nsImage: icon).resizable().interpolation(.high)
    }

    // MARK: detail pane

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                detailHeader(for: app)
                Divider().background(MD4.SemColor.divider)
                if model.isScanningLeftovers {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Scanning leftovers…")
                            .font(MD4.Typo.small)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.leftovers.isEmpty {
                    ContentUnavailableView("No leftovers found",
                                           systemImage: "checkmark.seal",
                                           description: Text("Only the app bundle will be removed."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    leftoverList
                }
                Divider().background(MD4.SemColor.divider)
                footer
            }
            .background(MD4.SemColor.background)
        } else {
            ContentUnavailableView("Pick an app",
                                   systemImage: "trash",
                                   description: Text("Select an app to scan for leftover files."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MD4.SemColor.background)
        }
    }

    private func detailHeader(for app: InstalledApp) -> some View {
        HStack(alignment: .center, spacing: 14) {
            appIcon(for: app)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("\(app.version ?? "?") · \(app.bundleSize.humanBytes)")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                if let id = app.bundleID {
                    Text(id)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    private var leftoverList: some View {
        List {
            ForEach(LeftoverItem.Source.allCases, id: \.self) { source in
                let group = model.leftovers.filter { $0.source == source }
                if !group.isEmpty {
                    Section(source.rawValue) {
                        ForEach(group) { item in leftoverRow(item) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func leftoverRow(_ item: LeftoverItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selectedLeftovers.contains(item.id) },
                set: { _ in model.toggle(item) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(item.url.deletingLastPathComponent().path)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.bytes.humanBytes)
                .font(MD4.Typo.tabular(MD4.Typo.caption))
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Will reclaim")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text(model.totalSelectedBytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.headline))
                    .foregroundStyle(MD4.SemColor.textPrimary)
            }
            Spacer()
            Button {
                showConfirm = true
            } label: {
                if model.isUninstalling {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Uninstalling…")
                    }
                } else {
                    Text("Uninstall")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.isUninstalling || model.isScanningLeftovers)
        }
        .padding(20)
    }
}

#Preview {
    UninstallerView()
        .frame(width: 920, height: 600)
        .preferredColorScheme(.dark)
}
