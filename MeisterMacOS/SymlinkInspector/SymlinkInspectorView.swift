import SwiftUI
import AppKit
import MeradOSDesign4

struct BrokenSymlink: Identifiable, Hashable {
    let id: String
    let url: URL
    let target: String
    let parent: URL
}

actor SymlinkScanner {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Walk Documents/Desktop/Downloads/Library and report symlinks whose
    /// destination doesn't exist.
    func scan() async -> [BrokenSymlink] {
        let scopes: [URL] = [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Developer"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        var broken: [BrokenSymlink] = []
        for scope in scopes {
            broken.append(contentsOf: walk(scope))
        }
        return broken
    }

    private nonisolated func walk(_ root: URL) -> [BrokenSymlink] {
        let fm = FileManager.default
        var out: [BrokenSymlink] = []
        guard let it = fm.enumerator(at: root,
                                      includingPropertiesForKeys: [.isSymbolicLinkKey],
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                      errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in it {
            guard let isLink = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
                  isLink else { continue }
            // Resolve the link
            let target = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "?"
            let resolvedURL: URL = {
                if target.hasPrefix("/") {
                    return URL(fileURLWithPath: target)
                }
                return url.deletingLastPathComponent().appendingPathComponent(target)
            }()
            if !fm.fileExists(atPath: resolvedURL.path) {
                out.append(BrokenSymlink(
                    id: url.path,
                    url: url,
                    target: target,
                    parent: url.deletingLastPathComponent()
                ))
            }
        }
        return out
    }

    @MainActor
    func recycle(_ urls: [URL]) async -> Int {
        await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { recycled, _ in
                cont.resume(returning: recycled.count)
            }
        }
    }
}

@MainActor
final class SymlinkInspectorModel: ObservableObject {
    @Published var broken: [BrokenSymlink] = []
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var lastRecycled: Int?
    private let scanner = SymlinkScanner()

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        self.broken = await scanner.scan()
        self.selected = Set(broken.map(\.id))
    }

    func recycleSelected() async {
        let urls = broken.filter { selected.contains($0.id) }.map(\.url)
        let count = await scanner.recycle(urls)
        lastRecycled = count
        await scan()
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }
}

struct SymlinkInspectorView: View {
    @StateObject private var model = SymlinkInspectorModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
            if !model.broken.isEmpty {
                Divider().background(MD4.SemColor.divider)
                footer
            }
        }
        .background(MD4.SemColor.background)
        .task { if model.broken.isEmpty { await model.scan() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Symlink Inspector")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Symlinks deren Ziel nicht mehr existiert. Recycle löscht den Link, nie das Ziel.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.scan() } } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.broken.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.broken.isEmpty {
            ContentUnavailableView("Keine kaputten Symlinks",
                                   systemImage: "link.circle",
                                   description: Text("Documents, Desktop, Downloads und Developer sind sauber."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.broken) { link in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { model.selected.contains(link.id) },
                        set: { _ in model.toggle(link.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    Image(systemName: "link.badge.exclamationmark")
                        .foregroundStyle(MD4.SemColor.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.url.lastPathComponent)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("→ \(link.target)")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.error)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(link.parent.path)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([link.url])
                    } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(model.selected.count) ausgewählt")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Spacer()
            if let last = model.lastRecycled {
                Text("Letzter Lauf: \(last) Links recycled")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button("In Papierkorb") {
                Task { await model.recycleSelected() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty)
        }
        .padding(20)
    }
}
