import SwiftUI
import AppKit
import MeradOSDesign3

struct TaggedFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let tags: [String]
}

struct TagSummary: Identifiable, Hashable {
    let id: String
    let tag: String
    let count: Int
    let totalBytes: Int64
    let files: [TaggedFile]
}

actor TagManagerReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Use mdfind to scan ~/Documents, ~/Desktop, ~/Downloads for tagged files.
    func read() async -> [TagSummary] {
        let scopes = [
            home.appendingPathComponent("Documents").path,
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Downloads").path,
        ]
        var allTagged: [TaggedFile] = []
        for scope in scopes {
            allTagged.append(contentsOf: scan(scope: scope))
        }

        // Bucket by tag
        var bucket: [String: [TaggedFile]] = [:]
        for f in allTagged {
            for tag in f.tags {
                bucket[tag, default: []].append(f)
            }
        }

        return bucket.map { (tag, files) in
            let total = files.reduce(Int64(0)) { acc, f in
                let attrs = try? FileManager.default.attributesOfItem(atPath: f.url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return acc + Int64(size)
            }
            return TagSummary(id: tag, tag: tag, count: files.count, totalBytes: total, files: files)
        }
        .sorted { $0.count > $1.count }
    }

    private nonisolated func scan(scope: String) -> [TaggedFile] {
        let raw = run("/usr/bin/mdfind", ["-onlyin", scope, "kMDItemUserTags == '*'"])
        let paths = raw.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        return paths.compactMap { path -> TaggedFile? in
            let url = URL(fileURLWithPath: path)
            let tags = readTags(at: url)
            guard !tags.isEmpty else { return nil }
            return TaggedFile(id: path, url: url, tags: tags)
        }
    }

    /// Read finder tags from xattr blob (binary plist).
    nonisolated func readTags(at url: URL) -> [String] {
        let attrName = "com.apple.metadata:_kMDItemUserTags"
        let len = url.path.withCString { p in
            attrName.withCString { a in
                getxattr(p, a, nil, 0, 0, 0)
            }
        }
        guard len > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: len)
        let read = url.path.withCString { p in
            attrName.withCString { a in
                buf.withUnsafeMutableBufferPointer { ptr in
                    getxattr(p, a, ptr.baseAddress, len, 0, 0)
                }
            }
        }
        guard read > 0 else { return [] }
        let data = Data(buf.prefix(read))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let arr = plist as? [String] else { return [] }
        // Tag string format: "Tag Name\nN" where N is color index. Strip the suffix.
        return arr.map { s in
            if let nl = s.firstIndex(of: "\n") { return String(s[..<nl]) }
            return s
        }
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

@MainActor
final class TagManagerModel: ObservableObject {
    @Published var summaries: [TagSummary] = []
    @Published var isLoading = false
    @Published var selectedTag: String?
    private let reader = TagManagerReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.summaries = await reader.read()
        if selectedTag != nil && !summaries.contains(where: { $0.tag == selectedTag }) {
            selectedTag = nil
        }
    }
}

struct TagManagerView: View {
    @StateObject private var model = TagManagerModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            HStack(spacing: 0) {
                tagSidebar
                Divider().background(MD3.SemColor.divider)
                fileList
            }
        }
        .background(MD3.SemColor.background)
        .task { if model.summaries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tag Manager")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Finder-Tags in ~/Documents, ~/Desktop, ~/Downloads. Klick aufs Tag → Datei-Liste.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    private var tagSidebar: some View {
        List(selection: Binding(get: { model.selectedTag },
                                set: { model.selectedTag = $0 })) {
            ForEach(model.summaries) { s in
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(MD3.SemColor.brandPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.tag)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        Text("\(s.count) files · \(s.totalBytes.humanBytes)")
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                    }
                }
                .tag(s.tag as String?)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(width: 250)
    }

    @ViewBuilder
    private var fileList: some View {
        if let selected = model.selectedTag,
           let summary = model.summaries.first(where: { $0.tag == selected }) {
            List(summary.files) { f in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.url.lastPathComponent)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        Text(f.url.deletingLastPathComponent().path)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if f.tags.count > 1 {
                        Text("+\(f.tags.count - 1)")
                            .font(MD3.Typo.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(MD3.SemColor.surfaceRaised, in: Capsule())
                            .foregroundStyle(MD3.SemColor.textSecondary)
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([f.url])
                    } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("Tag wählen",
                                   systemImage: "tag",
                                   description: Text("Links ein Tag anklicken um die zugehörigen Dateien zu sehen."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
