import SwiftUI
import MeradOSDesign3

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
    func read() async -> DockerUsage? {
        let raw = run("/usr/local/bin/docker", ["system", "df", "--format", "json"])
            .nonEmpty
            ?? run("/opt/homebrew/bin/docker", ["system", "df", "--format", "json"])
            .nonEmpty
        guard let raw = raw else { return nil }

        // `docker system df --format json` returns one JSON line per type.
        var images = DockerUsage.Stat(total: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        var containers = images
        var volumes = images
        var cache = images

        for line in raw.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let dict = any as? [String: Any] else { continue }
            let type = (dict["Type"] as? String) ?? ""
            let stat = parseStat(dict)
            switch type {
            case "Images":     images = stat
            case "Containers": containers = stat
            case "Local Volumes": volumes = stat
            case "Build Cache": cache = stat
            default: break
            }
        }
        return DockerUsage(images: images, containers: containers, volumes: volumes, buildCache: cache)
    }

    func prune() async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pickDocker())
        p.arguments = ["system", "prune", "-af", "--volumes"]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    private nonisolated func pickDocker() -> String {
        let arm = "/opt/homebrew/bin/docker"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        return "/usr/local/bin/docker"
    }

    private nonisolated func parseStat(_ dict: [String: Any]) -> DockerUsage.Stat {
        let total = Int(dict["TotalCount"] as? Int ?? Int((dict["TotalCount"] as? String) ?? "0") ?? 0)
        let active = Int(dict["Active"] as? Int ?? Int((dict["Active"] as? String) ?? "0") ?? 0)
        let size = parseSize(dict["Size"] as? String ?? "0B")
        let reclaim = parseReclaimable(dict["Reclaimable"] as? String ?? "0B")
        return .init(total: total, active: active, sizeBytes: size, reclaimableBytes: reclaim)
    }

    /// Parse strings like "1.23GB", "5MB", "150kB"
    nonisolated func parseSize(_ s: String) -> Int64 {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
        let suffixes: [(String, Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("kB", 1024), ("B", 1),
        ]
        for (suffix, mul) in suffixes {
            if cleaned.hasSuffix(suffix) {
                let numPart = String(cleaned.dropLast(suffix.count))
                if let n = Double(numPart) { return Int64(n * mul) }
            }
        }
        return 0
    }

    /// Reclaimable strings look like "850MB (78%)" — strip the % part.
    nonisolated func parseReclaimable(_ s: String) -> Int64 {
        let head = s.split(separator: " ").first.map(String.init) ?? s
        return parseSize(head)
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: tool) else { return "" }
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

private extension String {
    var nonEmpty: String? { self.isEmpty ? nil : self }
}

@MainActor
final class DockerCleanupModel: ObservableObject {
    @Published var usage: DockerUsage? = nil
    @Published var dockerInstalled = true
    @Published var isLoading = false
    @Published var lastReclaimed: Int64?
    private let reader = DockerCleanupReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        if let u = await reader.read() {
            self.usage = u
            self.dockerInstalled = true
        } else {
            self.dockerInstalled = false
        }
    }

    func prune() async {
        guard let before = usage?.totalReclaimable else { return }
        let ok = await reader.prune()
        if ok { lastReclaimed = before }
        await reload()
    }
}

struct DockerCleanupView: View {
    @StateObject private var model = DockerCleanupModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.usage == nil { await model.reload() } }
        .alert("Docker komplett aufräumen?", isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Prune (af + volumes)", role: .destructive) {
                Task { await model.prune() }
            }
        } message: {
            Text("`docker system prune -af --volumes` — entfernt alle ungenutzten Images, gestoppte Container, dangling volumes und den Build-Cache. \(model.usage?.totalReclaimable.humanBytes ?? "?") werden frei.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Docker Cleanup")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("docker system df + system prune. Reclaimt typischerweise GB.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            if model.dockerInstalled {
                Button { Task { await model.reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if !model.dockerInstalled {
            ContentUnavailableView("Docker nicht gefunden",
                                   systemImage: "shippingbox",
                                   description: Text("`docker` ist weder unter /usr/local/bin/ noch /opt/homebrew/bin/ installiert. Erst Docker Desktop installieren."))
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
                if let last = model.lastReclaimed {
                    Text("Letzter Lauf: \(last.humanBytes) reclaimed")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.success)
                }
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
                Image(systemName: icon).foregroundStyle(MD3.SemColor.brandPrimary)
                Text(label)
                    .font(MD3.Typo.headline)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Spacer()
                Text("\(s.active) aktiv / \(s.total)")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            HStack {
                Text(s.sizeBytes.humanBytes)
                    .font(MD3.Typo.tabular(MD3.Typo.title3))
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Spacer()
                if s.reclaimableBytes > 0 {
                    Text("\(s.reclaimableBytes.humanBytes) reclaimable")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.warning)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pruneButton(reclaimable: Int64) -> some View {
        Button {
            showConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("System Prune — \(reclaimable.humanBytes) frei")
                    .font(MD3.Typo.headline)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(MD3.SemColor.brandPrimary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(reclaimable == 0)
    }
}
