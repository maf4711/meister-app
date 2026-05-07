import SwiftUI
import AppKit
import MeradOSDesign3

struct XcodeInstall: Identifiable, Hashable {
    let id: String        // path
    let path: URL
    let displayName: String
    let version: String?
    let build: String?
    var isActive: Bool = false
}

actor XcodeSwitcherReader {
    /// Find all Xcode-style apps via mdfind, parse Info.plist for version.
    func read() async -> (installs: [XcodeInstall], activePath: String?) {
        let active = active()
        let raw = run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'"])
        let paths = raw.split(separator: "\n").map { String($0) }
        let installs: [XcodeInstall] = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            let plist = url.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = any as? [String: Any] else { return nil }
            let version = dict["CFBundleShortVersionString"] as? String
            let build = dict["DTXcodeBuild"] as? String ?? dict["CFBundleVersion"] as? String
            return XcodeInstall(
                id: path,
                path: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                version: version,
                build: build,
                isActive: active.flatMap { path.hasPrefix($0) } ?? false
            )
        }
        return (installs.sorted { ($0.version ?? "") > ($1.version ?? "") }, active)
    }

    nonisolated func active() -> String? {
        let raw = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Activates the given Xcode. xcode-select -s requires sudo, so we prepare
    /// the command and ask the user to run it in Terminal.
    nonisolated func activateCommand(for install: XcodeInstall) -> String {
        "sudo xcode-select -s \(install.path.path.replacingOccurrences(of: " ", with: "\\ "))/Contents/Developer"
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
final class XcodeSwitcherModel: ObservableObject {
    @Published var installs: [XcodeInstall] = []
    @Published var activePath: String?
    @Published var isLoading = false
    private let reader = XcodeSwitcherReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let (i, a) = await reader.read()
        self.installs = i
        self.activePath = a
    }

    func copyActivateCommand(for install: XcodeInstall) {
        let cmd = reader.activateCommand(for: install)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
    }
}

struct XcodeSwitcherView: View {
    @StateObject private var model = XcodeSwitcherModel()
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.installs.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Xcode Version Switcher")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Alle installierten Xcodes. Aktivierung via xcode-select braucht sudo — Befehl wird in die Zwischenablage kopiert.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
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
        if model.isLoading && model.installs.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.installs.isEmpty {
            ContentUnavailableView("Kein Xcode gefunden",
                                   systemImage: "hammer",
                                   description: Text("Spotlight findet keine Xcode-Installation. Über Mac App Store oder developer.apple.com installieren."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.installs) { x in
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(x.isActive ? MD3.SemColor.success : MD3.SemColor.brandPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(x.displayName)
                                .font(MD3.Typo.body)
                                .foregroundStyle(MD3.SemColor.textPrimary)
                            if x.isActive {
                                Text("aktiv")
                                    .font(MD3.Typo.caption.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(MD3.SemColor.success.opacity(0.18), in: Capsule())
                                    .foregroundStyle(MD3.SemColor.success)
                            }
                        }
                        Text("v\(x.version ?? "—") \(x.build.map { "(\($0))" } ?? "")")
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                        Text(x.path.path)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        model.copyActivateCommand(for: x)
                        copied = x.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copied == x.id { copied = nil }
                        }
                    } label: {
                        Label(copied == x.id ? "Kopiert!" : "Aktivieren", systemImage: copied == x.id ? "checkmark" : "doc.on.clipboard")
                    }
                    .disabled(x.isActive)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
