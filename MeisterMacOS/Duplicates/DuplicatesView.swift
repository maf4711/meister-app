import SwiftUI
import AppKit
import MeradOSDesign3

@MainActor
final class DuplicatesModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var keep: [String: URL] = [:]   // group hash → URL the user wants to keep
    @Published var isScanning = false
    @Published var scanRoots: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
    ]
    @Published var minSizeMB: Double = 5
    @Published var lastReclaimed: Int64 = 0
    @Published var errorMessage: String?

    private let finder = DuplicateFinder()

    var totalWasted: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var totalReclaimable: Int64 {
        groups.reduce(0) { acc, g in
            let losers = g.files.count - 1
            return acc + g.bytes * Int64(losers)
        }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let bytes = Int64(minSizeMB * 1_048_576)
        let result = await finder.find(in: scanRoots, minSize: bytes)
        self.groups = result
        // Default: keep oldest file in each group (lowest creation date).
        var defaults: [String: URL] = [:]
        for g in result {
            let oldest = g.files.min { (lhs, rhs) -> Bool in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l < r
            }
            defaults[g.hash] = oldest ?? g.files.first
        }
        self.keep = defaults
    }

    func recycleLosers() async {
        var reclaimed: Int64 = 0
        for g in groups {
            guard let keepURL = keep[g.hash] else { continue }
            let losers = g.files.filter { $0 != keepURL }
            let result: (Bool, NSError?) = await withCheckedContinuation { cont in
                NSWorkspace.shared.recycle(losers) { _, err in
                    cont.resume(returning: (err == nil, err as NSError?))
                }
            }
            if result.0 {
                reclaimed += g.bytes * Int64(losers.count)
            } else if let e = result.1 {
                errorMessage = e.localizedDescription
            }
        }
        lastReclaimed = reclaimed
        await scan()
    }
}

struct DuplicatesView: View {
    @StateObject private var model = DuplicatesModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
            Divider().background(MD3.SemColor.divider)
            footer
        }
        .background(MD3.SemColor.background)
        .alert("Duplikate in den Papierkorb?",
               isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("In Papierkorb", role: .destructive) {
                Task { await model.recycleLosers() }
            }
        } message: {
            Text("\(model.totalReclaimable.humanBytes) frei. Die ausgewählte Datei pro Gruppe bleibt erhalten, alle anderen gehen in den Trash.")
        }
        .alert("Fehler",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate Finder")
                        .font(MD3.Typo.title2)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    Text("Identische Dateien finden — gleiche Größe + gleicher SHA256.")
                        .font(MD3.Typo.small)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
                Spacer()
                Button {
                    Task { await model.scan() }
                } label: {
                    Label(model.isScanning ? "Scanne…" : "Scan", systemImage: "magnifyingglass")
                }
                .disabled(model.isScanning)
            }
            HStack {
                Text("Min. Größe: \(Int(model.minSizeMB)) MB")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                Slider(value: $model.minSizeMB, in: 1...500, step: 1)
                    .frame(maxWidth: 240)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.groups.isEmpty {
            ProgressView("Hashes werden berechnet…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.groups.isEmpty {
            ContentUnavailableView("Keine Duplikate gefunden",
                                   systemImage: "checkmark.circle",
                                   description: Text("Erstmal scannen, oder Größenfilter senken."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.files, id: \.self) { url in
                            row(group: group, url: url)
                        }
                    } header: {
                        HStack {
                            Text("\(group.files.count) × \(group.bytes.humanBytes)")
                                .font(MD3.Typo.caption.bold())
                            Spacer()
                            Text("verschwendet: \(group.wastedBytes.humanBytes)")
                                .font(MD3.Typo.caption)
                                .foregroundStyle(MD3.SemColor.warning)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(group: DuplicateGroup, url: URL) -> some View {
        let isKept = model.keep[group.hash] == url
        return HStack(spacing: 10) {
            Image(systemName: isKept ? "lock.fill" : "trash")
                .foregroundStyle(isKept ? MD3.SemColor.success : MD3.SemColor.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(url.deletingLastPathComponent().path)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Behalten") { model.keep[group.hash] = url }
                .buttonStyle(.borderless)
                .disabled(isKept)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Im Finder anzeigen")
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaimable")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text(model.totalReclaimable.humanBytes)
                    .font(MD3.Typo.tabular(MD3.Typo.headline))
                    .foregroundStyle(MD3.SemColor.textPrimary)
            }
            Spacer()
            if model.lastReclaimed > 0 {
                Text("Letzter Lauf: \(model.lastReclaimed.humanBytes)")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button("Verlierer in Papierkorb") {
                showConfirm = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.groups.isEmpty || model.isScanning)
        }
        .padding(20)
    }
}

#Preview {
    DuplicatesView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
