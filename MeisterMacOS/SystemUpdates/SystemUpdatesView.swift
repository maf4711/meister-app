import SwiftUI
import AppKit
import MeradOSDesign4

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
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<[SystemUpdate]> {
        let result = command("/usr/sbin/softwareupdate", ["--list"])
        if let issue = result.issue(source: "macOS-Updates") { return .init(value: nil, issues: [issue]) }
        let updates = parse(result.output)
        guard !updates.isEmpty || result.output.contains("No new software available") else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "macOS-Updates")])
        }
        return .init(value: updates)
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
        if let label = pendingLabel {
            out.append(SystemUpdate(id: label, label: label, title: label, version: nil, sizeBytes: nil, isRecommended: false, requiresRestart: false))
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

}

@MainActor
final class SystemUpdatesModel: ObservableObject {
    @Published var updates: [SystemUpdate] = []
    @Published var isLoading = false
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    private let reader = SystemUpdatesReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        updates = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }

    func copyInstallCommand(for label: String) {
        let cmd = "sudo softwareupdate --install \(CommandRunner.shellQuote(label)) --restart"
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
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.updates.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Updates")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("softwareupdate --list. Install-Kommandos brauchen sudo — werden in die Zwischenablage kopiert.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
        } else if !model.issues.isEmpty {
            ContentUnavailableView("Update-Status unbekannt", systemImage: "arrow.triangle.2.circlepath")
        } else if model.updates.isEmpty {
            ContentUnavailableView("Keine Updates verfügbar",
                                   systemImage: "checkmark.circle.fill",
                                   description: Text("System ist auf aktuellem Stand."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.updates) { u in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.down.app").foregroundStyle(MD4.SemColor.brandPrimary)
                        Text(u.title)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Spacer()
                        if u.isRecommended {
                            badge("Empfohlen", MD4.SemColor.success)
                        }
                        if u.requiresRestart {
                            badge("Neustart", MD4.SemColor.warning)
                        }
                    }
                    HStack {
                        Text(u.label)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                            .textSelection(.enabled)
                        if let bytes = u.sizeBytes {
                            Text("· \(bytes.humanBytes)")
                                .font(MD4.Typo.caption)
                                .foregroundStyle(MD4.SemColor.textSecondary)
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
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
