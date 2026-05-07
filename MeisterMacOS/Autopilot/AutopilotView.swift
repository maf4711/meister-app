import SwiftUI
import AppKit
import MeradOSDesign3

struct AutopilotState: Equatable {
    let isInstalled: Bool
    let plistPath: String
    let lastRun: Date?
}

actor AutopilotReader {
    static let label = "com.merados.meister.autopilot"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var lastRunMarker: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Meister/autopilot.last")
    }

    func read() async -> AutopilotState {
        let installed = FileManager.default.fileExists(atPath: Self.plistURL.path)
        let last: Date? = {
            guard let data = try? Data(contentsOf: Self.lastRunMarker),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            let f = ISO8601DateFormatter()
            return f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines))
        }()
        return AutopilotState(isInstalled: installed,
                              plistPath: Self.plistURL.path,
                              lastRun: last)
    }

    /// Generate the plist that runs `/usr/bin/open meister://run/quick-clean` daily at 03:30.
    nonisolated func plistContents() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-jg</string>
                <string>meister://run/quick-clean</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key><integer>3</integer>
                <key>Minute</key><integer>30</integer>
            </dict>
            <key>RunAtLoad</key><false/>
        </dict>
        </plist>
        """
    }

    func install() async throws {
        let url = Self.plistURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try plistContents().write(to: url, atomically: true, encoding: .utf8)
        // Bootstrap into launchd; ignore errors if already loaded.
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", url.path])
    }

    func uninstall() async {
        let url = Self.plistURL
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Self.label)"])
        try? FileManager.default.removeItem(at: url)
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
final class AutopilotModel: ObservableObject {
    @Published var state: AutopilotState?
    @Published var isWorking = false
    @Published var error: String?
    private let reader = AutopilotReader()

    func reload() async {
        self.state = await reader.read()
    }

    func install() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await reader.install()
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }

    func uninstall() async {
        isWorking = true
        defer { isWorking = false }
        await reader.uninstall()
        await reload()
    }
}

struct AutopilotView: View {
    @StateObject private var model = AutopilotModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { await model.reload() }
        .alert("Fehler",
               isPresented: Binding(get: { model.error != nil },
                                    set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Autopilot")
                .font(MD3.Typo.title2)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text("Tägliche Quick-Clean um 03:30 via LaunchAgent. Apple-Shortcuts-kompatibel.")
                .font(MD3.Typo.small)
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.state {
            VStack(spacing: 16) {
                statusCard(s)
                actionCard(s)
                Spacer()
            }
            .padding(20)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusCard(_ s: AutopilotState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.isInstalled ? "clock.badge.checkmark" : "clock.badge.questionmark")
                .foregroundStyle(s.isInstalled ? MD3.SemColor.success : MD3.SemColor.textSecondary)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.isInstalled ? "Autopilot installiert" : "Autopilot nicht aktiv")
                    .font(MD3.Typo.title3)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                if let last = s.lastRun {
                    Text("Letzter Lauf: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                } else {
                    Text("Noch kein Lauf protokolliert")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
                Text(s.plistPath)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionCard(_ s: AutopilotState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup")
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text("Schedule: täglich um 03:30 — `open meister://run/quick-clean`")
                .font(MD3.Typo.small)
                .foregroundStyle(MD3.SemColor.textSecondary)
            HStack {
                if s.isInstalled {
                    Button(role: .destructive) {
                        Task { await model.uninstall() }
                    } label: {
                        Label("Autopilot deaktivieren", systemImage: "trash")
                    }
                } else {
                    Button {
                        Task { await model.install() }
                    } label: {
                        Label("Autopilot aktivieren", systemImage: "play.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Spacer()
                if let url = URL(string: "file://\(s.plistPath)"),
                   FileManager.default.fileExists(atPath: s.plistPath) {
                    Button("Plist im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .disabled(model.isWorking)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
