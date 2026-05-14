import SwiftUI
import AppKit
import MeradOSDesign4

struct RestorableEntry: Identifiable, Hashable {
    let id: String              // original path
    let originalURL: URL
    let trashURL: URL
    let bytes: Int64
    let category: String
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: trashURL.path)
    }
}

actor UndoCleanupReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Find the most recent cleanup manifest and resolve which of its entries
    /// can still be restored from ~/.Trash.
    func loadLatest() async -> (manifest: URL?, entries: [RestorableEntry]) {
        let dir = home.appendingPathComponent("Library/Application Support/Meister/cleanups", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return (nil, []) }
        guard let urls = try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return (nil, []) }
        let jsons = urls.filter { $0.pathExtension == "json" }
        guard let latest = jsons.max(by: { left, right in
            let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }) else { return (nil, []) }

        return (latest, parseManifest(at: latest))
    }

    nonisolated func parseManifest(at url: URL) -> [RestorableEntry] {
        guard let data = try? Data(contentsOf: url),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let entries = dict["entries"] as? [[String: Any]] else { return [] }
        let trash = home.appendingPathComponent(".Trash")
        return entries.compactMap { e -> RestorableEntry? in
            guard let path = e["path"] as? String,
                  let recycled = e["recycled"] as? Bool, recycled else { return nil }
            let original = URL(fileURLWithPath: path)
            let trashItem = trash.appendingPathComponent(original.lastPathComponent)
            let bytes = (e["bytes"] as? Int64) ??
                Int64((e["bytes"] as? NSNumber)?.int64Value ?? 0)
            let category = (e["category"] as? String) ?? "—"
            return RestorableEntry(
                id: path,
                originalURL: original,
                trashURL: trashItem,
                bytes: bytes,
                category: category
            )
        }
    }

    @MainActor
    func restore(_ entries: [RestorableEntry]) async -> (restored: Int, failed: Int) {
        let fm = FileManager.default
        var ok = 0, fail = 0
        for e in entries {
            guard fm.fileExists(atPath: e.trashURL.path) else { fail += 1; continue }
            // Ensure parent dir exists.
            let parent = e.originalURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            do {
                try fm.moveItem(at: e.trashURL, to: e.originalURL)
                ok += 1
            } catch {
                fail += 1
            }
        }
        return (ok, fail)
    }
}

@MainActor
final class UndoCleanupModel: ObservableObject {
    @Published var manifestPath: URL?
    @Published var entries: [RestorableEntry] = []
    @Published var selected: Set<String> = []
    @Published var isLoading = false
    @Published var lastResult: (restored: Int, failed: Int)?
    private let reader = UndoCleanupReader()

    var totalBytes: Int64 {
        entries.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var availableCount: Int { entries.filter(\.isAvailable).count }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let (m, e) = await reader.loadLatest()
        self.manifestPath = m
        self.entries = e
        self.selected = Set(e.filter(\.isAvailable).map(\.id))
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }

    func restore() async {
        let toRestore = entries.filter { selected.contains($0.id) && $0.isAvailable }
        guard !toRestore.isEmpty else { return }
        let result = await reader.restore(toRestore)
        self.lastResult = result
        await reload()
    }
}

struct UndoCleanupView: View {
    @StateObject private var model = UndoCleanupModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
            Divider().background(MD4.SemColor.divider)
            footer
        }
        .background(MD4.SemColor.background)
        .task { if model.entries.isEmpty { await model.reload() } }
        .alert("Items aus dem Trash zurückholen?",
               isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Wiederherstellen") {
                Task { await model.restore() }
            }
        } message: {
            Text("\(model.totalBytes.humanBytes) ausgewählt. Items werden aus ~/.Trash zurück an ihre ursprünglichen Pfade verschoben.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Undo Last Cleanup")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Letzten System-Cleanup-Lauf rückgängig machen — Items aus ~/.Trash an ihre alten Pfade verschieben.")
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
        if model.isLoading && model.entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            ContentUnavailableView("Kein Cleanup zum Rückgängig-Machen",
                                   systemImage: "arrow.uturn.backward",
                                   description: Text("Noch kein System-Cleanup-Lauf gefunden — oder alle Items wurden bereits aus dem Trash entfernt."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let m = model.manifestPath {
                    Text("Manifest: \(m.lastPathComponent) · \(model.entries.count) Einträge · \(model.availableCount) noch im Trash")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                }
                List {
                    ForEach(model.entries) { e in
                        row(e)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func row(_ e: RestorableEntry) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(e.id) },
                set: { _ in model.toggle(e.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!e.isAvailable)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.originalURL.lastPathComponent)
                    .font(MD4.Typo.body)
                    .foregroundStyle(e.isAvailable ? MD4.SemColor.textPrimary : MD4.SemColor.textTertiary)
                Text(e.originalURL.deletingLastPathComponent().path)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(e.category)
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Text(e.bytes.humanBytes)
                .font(MD4.Typo.tabular(MD4.Typo.caption))
                .foregroundStyle(MD4.SemColor.textSecondary)
            if !e.isAvailable {
                Text("nicht im Trash")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.error)
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wiederherstellen")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text(model.totalBytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.headline))
                    .foregroundStyle(MD4.SemColor.textPrimary)
            }
            Spacer()
            if let result = model.lastResult {
                Text("Letzter Lauf: \(result.restored) ok, \(result.failed) failed")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(result.failed == 0 ? MD4.SemColor.success : MD4.SemColor.warning)
                    .padding(.trailing, 12)
            }
            Button("Wiederherstellen") {
                showConfirm = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty || model.isLoading)
        }
        .padding(20)
    }
}
