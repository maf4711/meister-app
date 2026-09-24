import SwiftUI
import MeradOSDesign4

struct DockerUsage: Equatable {
    let images: Stat
    let containers: Stat
    let volumes: Stat
    let buildCache: Stat

    struct Stat: Equatable {
        let total: Int
        let active: Int
        let sizeBytes: Int64
        let reclaimableBytes: Int64
    }

    static let empty = DockerUsage(
        images: .init(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
        containers: .init(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
        volumes: .init(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
        buildCache: .init(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
    )

    var totalReclaimable: Int64 {
        images.reclaimableBytes + containers.reclaimableBytes
            + volumes.reclaimableBytes + buildCache.reclaimableBytes
    }
}

actor DockerCleanupReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<DockerUsage> {
        let result = command(pickDocker(), ["system", "df", "--format", "json"])
        if let issue = result.issue(source: "Docker") { return .init(value: nil, issues: [issue]) }
        let raw = result.output

        // `docker system df --format json` returns one JSON line per type.
        var images = DockerUsage.Stat(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        var containers = images
        var volumes = images
        var cache = images

        var parsedTypes = Set<String>()
        var malformed = false
        for line in raw.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let dict = any as? [String: Any] else { malformed = true; continue }
            let type = (dict["Type"] as? String) ?? ""
            guard ["Images", "Containers", "Local Volumes", "Build Cache"].contains(type),
                  dict["TotalCount"] != nil, dict["Active"] != nil,
                  dict["Size"] is String, dict["Reclaimable"] is String,
                  !parsedTypes.contains(type), let stat = parseStat(dict) else { malformed = true; continue }
            parsedTypes.insert(type)
            switch type {
            case "Images":     images = stat
            case "Containers": containers = stat
            case "Local Volumes": volumes = stat
            case "Build Cache": cache = stat
            default: break
            }
        }
        let issues: [DiagnosticIssue] = malformed || parsedTypes.count != 4
            ? [.init(kind: .invalidOutput, source: "Docker-Speicherbelegung")] : []
        guard !parsedTypes.isEmpty else { return .init(value: nil, issues: issues) }
        return .init(value: DockerUsage(images: images, containers: containers, volumes: volumes, buildCache: cache), issues: issues)
    }

    func prune() async -> Bool {
        CommandRunner.run(pickDocker(), ["system", "prune", "-af", "--volumes"], timeout: 300).succeeded
    }

    private nonisolated func pickDocker() -> String {
        let arm = "/opt/homebrew/bin/docker"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        return "/usr/local/bin/docker"
    }

    private nonisolated func parseStat(_ dict: [String: Any]) -> DockerUsage.Stat? {
        func count(_ key: String) -> Int? {
            let value = dict[key] as? Int ?? (dict[key] as? String).flatMap(Int.init)
            guard let value, value >= 0 else { return nil }
            return value
        }
        guard let total = count("TotalCount"), let active = count("Active"), active <= total,
              let sizeText = dict["Size"] as? String, let size = parsedSize(sizeText),
              let reclaimText = dict["Reclaimable"] as? String,
              let reclaim = parsedSize(reclaimText.split(separator: " ").first.map(String.init) ?? "") else { return nil }
        return .init(total: total, active: active, sizeBytes: size, reclaimableBytes: reclaim)
    }

    /// Parse strings like "1.23GB", "5MB", "150kB"
    nonisolated func parseSize(_ s: String) -> Int64 { parsedSize(s) ?? 0 }

    private nonisolated func parsedSize(_ s: String) -> Int64? {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
        let suffixes: [(String, Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("kB", 1024), ("B", 1),
        ]
        for (suffix, mul) in suffixes {
            if cleaned.hasSuffix(suffix) {
                let numPart = String(cleaned.dropLast(suffix.count))
                if let n = Double(numPart), n.isFinite, n >= 0, n * mul < Double(Int64.max) { return Int64(n * mul) }
            }
        }
        return nil
    }

    /// Reclaimable strings look like "850MB (78%)" — strip the % part.
    nonisolated func parseReclaimable(_ s: String) -> Int64 {
        let head = s.split(separator: " ").first.map(String.init) ?? s
        return parseSize(head)
    }

}

@MainActor
final class DockerCleanupModel: ObservableObject {
    @Published var usage: DockerUsage? = nil
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var isPruning = false
    @Published var actionMessage: String?
    @Published var isLoading = false
    private let reader: DockerCleanupReader
    init(reader: DockerCleanupReader = DockerCleanupReader()) { self.reader = reader }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        usage = report.value
        issues = report.issues
        lastChecked = report.timestamp
    }

    func prune() async {
        guard usage != nil, issues.isEmpty, !isPruning, !isLoading else { return }
        isPruning = true
        defer { isPruning = false }
        let ok = await reader.prune()
        actionMessage = ok ? "Bereinigung abgeschlossen. Speicherbelegung wird neu ermittelt." : "Bereinigung fehlgeschlagen. Docker-Dienst und Berechtigungen prüfen."
        await reload()
    }
}

struct DockerCleanupView: View {
    @StateObject private var model = DockerCleanupModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            if let message = model.actionMessage { Text(message).font(.caption).padding() }
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.usage == nil { await model.reload() } }
        .alert("Docker komplett aufräumen?", isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Prune (af + volumes)", role: .destructive) {
                Task { await model.prune() }
            }
        } message: {
            Text("`docker system prune -af --volumes` — entfernt alle ungenutzten Images, gestoppte Container, dangling volumes und den Build-Cache. \(model.usage?.totalReclaimable.humanBytes ?? "?") sind laut letzter Messung potenziell bereinigbar.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Docker Cleanup")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("docker system df + system prune. Reclaimt typischerweise GB.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Group {
                Button { Task { await model.reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading || model.isPruning)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.usage == nil && !model.issues.isEmpty {
            ContentUnavailableView("Docker-Diagnose nicht verfügbar", systemImage: "shippingbox",
                                   description: Text("Installation, laufenden Docker-Dienst und Zugriffsrechte prüfen. Anschließend erneut aktualisieren."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let u = model.usage {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statTile("Images", u.images, icon: "shippingbox")
                    statTile("Containers", u.containers, icon: "tray.full")
                    statTile("Volumes", u.volumes, icon: "externaldrive.connected.to.line.below")
                    statTile("Build Cache", u.buildCache, icon: "hammer")
                }
                pruneButton(reclaimable: u.totalReclaimable)

                Spacer()
            }
            .padding(20)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statTile(_ label: String, _ s: DockerUsage.Stat, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(label)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
                Text("\(s.active) aktiv / \(s.total)")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            HStack {
                Text(s.sizeBytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.title3))
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
                if s.reclaimableBytes > 0 {
                    Text("\(s.reclaimableBytes.humanBytes) reclaimable")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.warning)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pruneButton(reclaimable: Int64) -> some View {
        Button {
            showConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("System Prune — bis zu \(reclaimable.humanBytes)")
                    .font(MD4.Typo.headline)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(MD4.SemColor.brandPrimary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(reclaimable == 0 || !model.issues.isEmpty || model.isPruning || model.isLoading)
    }
}
