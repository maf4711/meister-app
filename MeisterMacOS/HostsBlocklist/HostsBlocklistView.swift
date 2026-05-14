import SwiftUI
import AppKit
import MeradOSDesign4

struct BlocklistSource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let description: String
}

struct BlocklistFetched: Equatable {
    let source: BlocklistSource
    let fetchedAt: Date
    let entryCount: Int
    let merged: String
}

actor HostsBlocklistReader {
    static let sources: [BlocklistSource] = [
        .init(id: "stevenblack",
              name: "StevenBlack/hosts (Ads + Malware)",
              url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!,
              description: "Standard-Blocklist gegen Ads, Malware, Tracker"),
        .init(id: "stevenblack-fakenews",
              name: "StevenBlack + Fakenews",
              url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts")!,
              description: "Erweitert um bekannte Fake-News-Domains"),
        .init(id: "blackhole",
              name: "blackhole-stuff (KAD/iCloud-friendly)",
              url: URL(string: "https://raw.githubusercontent.com/Hexxa/blackhole-stuff/master/hosts")!,
              description: "Lightweight, kompatibel mit iCloud Sync"),
    ]

    func fetch(_ source: BlocklistSource) async throws -> BlocklistFetched {
        let (data, _) = try await URLSession.shared.data(from: source.url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Hosts", code: -1)
        }
        // Count actual hosts entries (lines starting with 0.0.0.0 or 127.0.0.1)
        let count = text.split(separator: "\n").filter { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            return s.hasPrefix("0.0.0.0 ") || s.hasPrefix("127.0.0.1 ")
        }.count
        return BlocklistFetched(
            source: source,
            fetchedAt: Date(),
            entryCount: count,
            merged: text
        )
    }

    /// Write merged blocklist to a temp file. The user runs sudo cp manually.
    func writeStaged(_ fetched: BlocklistFetched) throws -> URL {
        let tmpDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Meister/staged-hosts", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let url = tmpDir.appendingPathComponent("hosts-\(fetched.source.id)-\(Int(Date().timeIntervalSince1970))")
        try fetched.merged.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@MainActor
final class HostsBlocklistModel: ObservableObject {
    @Published var fetched: [String: BlocklistFetched] = [:]   // source.id → fetched
    @Published var loading: Set<String> = []
    @Published var stagedPath: URL?
    @Published var error: String?
    private let reader = HostsBlocklistReader()

    var sources: [BlocklistSource] { HostsBlocklistReader.sources }

    func fetch(_ source: BlocklistSource) async {
        loading.insert(source.id)
        defer { loading.remove(source.id) }
        do {
            self.fetched[source.id] = try await reader.fetch(source)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stage(_ source: BlocklistSource) async {
        guard let f = fetched[source.id] else { return }
        do {
            self.stagedPath = try await reader.writeStaged(f)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func copyInstallCommand() {
        guard let staged = stagedPath else { return }
        let cmd = "sudo cp /etc/hosts /etc/hosts.meister-backup-$(date +%s) && sudo cp \(staged.path.replacingOccurrences(of: " ", with: "\\ ")) /etc/hosts && sudo dscacheutil -flushcache"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
    }
}

struct HostsBlocklistView: View {
    @StateObject private var model = HostsBlocklistModel()
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
            if model.stagedPath != nil {
                Divider().background(MD4.SemColor.divider)
                installPanel
            }
        }
        .background(MD4.SemColor.background)
        .alert("Fehler",
               isPresented: Binding(get: { model.error != nil },
                                    set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hosts Blocklist")
                .font(MD4.Typo.title2)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text("Curated Ad-Block-Lists laden, in /etc/hosts mergen. Backup wird automatisch gemacht.")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(model.sources) { source in
                    sourceCard(source)
                }
            }
            .padding(20)
        }
    }

    private func sourceCard(_ source: BlocklistSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(MD4.Typo.headline)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Text(source.description)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
                Spacer()
                if model.loading.contains(source.id) {
                    ProgressView().controlSize(.small)
                } else if let f = model.fetched[source.id] {
                    Text("\(f.entryCount) entries")
                        .font(MD4.Typo.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MD4.SemColor.success.opacity(0.18), in: Capsule())
                        .foregroundStyle(MD4.SemColor.success)
                }
            }
            HStack {
                if model.fetched[source.id] == nil {
                    Button("Liste laden") {
                        Task { await model.fetch(source) }
                    }
                } else {
                    Button("Erneut laden") {
                        Task { await model.fetch(source) }
                    }
                    Button("Stage zum Install") {
                        Task { await model.stage(source) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Link(source.url.absoluteString, destination: source.url)
                    .font(MD4.Typo.caption)
            }
            .disabled(model.loading.contains(source.id))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var installPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Install-Kommando in Zwischenablage")
                .font(MD4.Typo.caption.bold())
                .foregroundStyle(MD4.SemColor.brandPrimary)
                .textCase(.uppercase)
            Text("Backup von /etc/hosts wird automatisch angelegt, dann DNS-Cache geflushed.")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            HStack {
                Button {
                    model.copyInstallCommand()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Kopiert!" : "sudo-Kommando kopieren", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
                if let path = model.stagedPath {
                    Text(path.lastPathComponent)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.brandPrimary.opacity(0.08))
    }
}
