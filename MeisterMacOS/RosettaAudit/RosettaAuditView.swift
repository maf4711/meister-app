import SwiftUI
import AppKit
import MeradOSDesign4

struct AppArchInfo: Identifiable, Hashable {
    let id: String
    let url: URL
    let displayName: String
    let architectures: [String]    // e.g. ["x86_64", "arm64"]
    let bundleSize: Int64

    var arch: ArchClass {
        let hasArm = architectures.contains(where: { $0.hasPrefix("arm64") })
        let hasX86 = architectures.contains(where: { $0.hasPrefix("x86_64") || $0 == "i386" })
        if hasArm && hasX86 { return .universal }
        if hasArm { return .arm }
        if hasX86 { return .intel }
        return .unknown
    }

    enum ArchClass: String {
        case arm = "Apple Silicon"
        case intel = "Intel (Rosetta)"
        case universal = "Universal"
        case unknown = "?"
    }
}

actor RosettaAuditReader {
    func read() async -> [AppArchInfo] {
        let appsDirs = ["/Applications", "/Applications/Utilities"]
        var out: [AppArchInfo] = []
        for dir in appsDirs {
            out.append(contentsOf: scanDir(dir))
        }
        return out.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    private nonisolated func scanDir(_ path: String) -> [AppArchInfo] {
        let url = URL(fileURLWithPath: path)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url,
                                                                          includingPropertiesForKeys: nil)
        else { return [] }
        return entries.compactMap { app -> AppArchInfo? in
            guard app.pathExtension == "app" else { return nil }
            return inspect(app)
        }
    }

    private nonisolated func inspect(_ appURL: URL) -> AppArchInfo? {
        // Find executable inside .app via Info.plist's CFBundleExecutable.
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = any as? [String: Any],
              let exe = dict["CFBundleExecutable"] as? String else { return nil }
        let exeURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(exe)
        guard FileManager.default.fileExists(atPath: exeURL.path) else { return nil }

        let archs = lipoArchs(at: exeURL)
        let size = bundleSize(at: appURL)
        return AppArchInfo(
            id: appURL.path,
            url: appURL,
            displayName: appURL.deletingPathExtension().lastPathComponent,
            architectures: archs,
            bundleSize: size
        )
    }

    /// Parses `lipo -archs <binary>` which prints a single line of space-separated archs.
    nonisolated func lipoArchs(at exe: URL) -> [String] {
        let raw = run("/usr/bin/lipo", ["-archs", exe.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private nonisolated func bundleSize(at url: URL) -> Int64 {
        guard let it = FileManager.default.enumerator(at: url,
                                                      includingPropertiesForKeys: [.fileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in it {
            let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
            total += Int64(s)
        }
        return total
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
final class RosettaAuditModel: ObservableObject {
    @Published var apps: [AppArchInfo] = []
    @Published var isLoading = false
    @Published var filter: AppArchInfo.ArchClass? = nil
    private let reader = RosettaAuditReader()

    var filtered: [AppArchInfo] {
        guard let f = filter else { return apps }
        return apps.filter { $0.arch == f }
    }

    var stats: (total: Int, arm: Int, intel: Int, universal: Int) {
        var arm = 0, intel = 0, universal = 0
        for a in apps {
            switch a.arch {
            case .arm: arm += 1
            case .intel: intel += 1
            case .universal: universal += 1
            case .unknown: break
            }
        }
        return (apps.count, arm, intel, universal)
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.apps = await reader.read()
    }
}

struct RosettaAuditView: View {
    @StateObject private var model = RosettaAuditModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            statsAndFilter
            Divider().background(MD4.SemColor.divider)
            list
        }
        .background(MD4.SemColor.background)
        .task { if model.apps.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rosetta Audit")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Welche Apps in /Applications sind noch x86? lipo -archs pro Bundle.")
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

    private var statsAndFilter: some View {
        let stats = model.stats
        return HStack(spacing: 8) {
            chip("Alle (\(stats.total))", nil)
            chip("Apple Silicon (\(stats.arm))", .arm)
            chip("Universal (\(stats.universal))", .universal)
            chip("Intel-only (\(stats.intel))", .intel, urgent: stats.intel > 0)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func chip(_ label: String, _ filter: AppArchInfo.ArchClass?, urgent: Bool = false) -> some View {
        let active = model.filter == filter
        let color: Color = urgent && !active ? MD4.SemColor.warning : (active ? MD4.SemColor.brandPrimary : MD4.SemColor.textSecondary)
        return Button(label) { model.filter = filter }
            .font(MD4.Typo.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? MD4.SemColor.brandPrimary.opacity(0.2) : Color.clear, in: Capsule())
            .foregroundStyle(color)
            .buttonStyle(.plain)
    }

    private var list: some View {
        Group {
            if model.isLoading && model.apps.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filtered.isEmpty {
                ContentUnavailableView("Keine Apps gefunden",
                                       systemImage: "app.dashed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.filtered) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(MD4.Typo.body)
                                .foregroundStyle(MD4.SemColor.textPrimary)
                            Text(app.architectures.joined(separator: " · "))
                                .font(MD4.Typo.caption)
                                .foregroundStyle(MD4.SemColor.textSecondary)
                        }
                        Spacer()
                        Text(app.bundleSize.humanBytes)
                            .font(MD4.Typo.tabular(MD4.Typo.caption))
                            .foregroundStyle(MD4.SemColor.textSecondary)
                        archBadge(app.arch)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func archBadge(_ arch: AppArchInfo.ArchClass) -> some View {
        let color: Color = {
            switch arch {
            case .arm: return MD4.SemColor.success
            case .universal: return MD4.SemColor.brandPrimary
            case .intel: return MD4.SemColor.warning
            case .unknown: return MD4.SemColor.textTertiary
            }
        }()
        return Text(arch.rawValue)
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
