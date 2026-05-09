import SwiftUI
import AppKit
import MeradOSDesign3

struct SystemUpdate: Identifiable, Hashable {
    let id: String
    let label: String
    let title: String
    let version: String?
    let sizeBytes: Int64?
    let isRecommended: Bool
    let requiresRestart: Bool
}

actor SystemUpdatesReader {
    func read() async -> [SystemUpdate] {
        let raw = run("/usr/sbin/softwareupdate", ["--list"])
        return parse(raw)
    }

    nonisolated func parse(_ raw: String) -> [SystemUpdate] {
        var out: [SystemUpdate] = []
        var pendingLabel: String?
        var pendingTitle = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            // softwareupdate uses asterisk lines: "* Label: macOS Sonoma 14.5"
            if let r = s.range(of: "* Label: ") {
                if let lbl = pendingLabel {
                    out.append(SystemUpdate(id: lbl, label: lbl, title: pendingTitle, version: nil, sizeBytes: nil, isRecommended: false, requiresRestart: false))
                }
                pendingLabel = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                pendingTitle = ""
            } else if pendingLabel != nil {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("Software") {
                    pendingTitle = trimmed
                    let recommended = trimmed.lowercased().contains("recommended")
                    let restart = trimmed.lowercased().contains("restart")
                    let version = parseVersion(from: trimmed)
                    let size = parseSize(from: trimmed)
                    out.append(SystemUpdate(
                        id: pendingLabel!,
                        label: pendingLabel!,
                        title: trimmed,
                        version: version,
                        sizeBytes: size,
                        isRecommended: recommended,
                        requiresRestart: restart
                    ))
                    pendingLabel = nil
                    pendingTitle = ""
                }
            }
        }
        return out
    }

    private nonisolated func parseVersion(from line: String) -> String? {
        // "Title: macOS Sonoma 14.5 ... [Version: 14.5]"
        if let r = line.range(of: "Version: ") {
            let after = line[r.upperBound...]
            return after.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "]" }).first.map(String.init)
        }
        return nil
    }

    private nonisolated func parseSize(from line: String) -> Int64? {
        // "[Size: 12345K]"
        guard let r = line.range(of: "Size: ") else { return nil }
        let after = line[r.upperBound...]
        let token = after.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "]" }).first.map(String.init) ?? ""
        // Tokens like "12345K", "1.2G"
        if token.hasSuffix("K"), let n = Double(token.dropLast()) { return Int64(n * 1024) }
        if token.hasSuffix("M"), let n = Double(token.dropLast()) { return Int64(n * 1_048_576) }
        if token.hasSuffix("G"), let n = Double(token.dropLast()) { return Int64(n * 1_073_741_824) }
        return nil
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
final class SystemUpdatesModel: ObservableObject {
    @Published var updates: [SystemUpdate] = []
    @Published var isLoading = false
    private let reader = SystemUpdatesReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.updates = await reader.read()
    }

    func copyInstallCommand(for label: String) {
        let cmd = "sudo softwareupdate --install \"\(label)\" --restart"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
    }
}

struct SystemUpdatesView: View {
    @StateObject private var model = SystemUpdatesModel()
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.updates.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Updates")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("softwareupdate --list. Install-Kommandos brauchen sudo — werden in die Zwischenablage kopiert.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button("System-Settings öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
            }
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.updates.isEmpty {
            ProgressView("Frage Apple-Server…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.updates.isEmpty {
            ContentUnavailableView("Keine Updates verfügbar",
                                   systemImage: "checkmark.circle.fill",
                                   description: Text("System ist auf aktuellem Stand."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.updates) { u in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.down.app").foregroundStyle(MD3.SemColor.brandPrimary)
                        Text(u.title)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        Spacer()
                        if u.isRecommended {
                            badge("Empfohlen", MD3.SemColor.success)
                        }
                        if u.requiresRestart {
                            badge("Neustart", MD3.SemColor.warning)
                        }
                    }
                    HStack {
                        Text(u.label)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                            .textSelection(.enabled)
                        if let bytes = u.sizeBytes {
                            Text("· \(bytes.humanBytes)")
                                .font(MD3.Typo.caption)
                                .foregroundStyle(MD3.SemColor.textSecondary)
                        }
                        Spacer()
                        Button {
                            model.copyInstallCommand(for: u.label)
                            copied = u.label
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if copied == u.label { copied = nil }
                            }
                        } label: {
                            Label(copied == u.label ? "Kopiert!" : "sudo-Cmd", systemImage: copied == u.label ? "checkmark" : "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(MD3.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
