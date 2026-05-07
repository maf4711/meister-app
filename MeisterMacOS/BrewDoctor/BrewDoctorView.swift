import SwiftUI
import MeradOSDesign3

struct BrewIssue: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let level: Level

    enum Level { case warning, error, info }
}

actor BrewDoctorReader {
    private static let candidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    func brewPath() -> String? {
        Self.candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func runDoctor() async -> [BrewIssue] {
        guard let brew = brewPath() else { return [] }
        let raw = run(brew, ["doctor"])
        return parseDoctor(raw)
    }

    func runOutdated() async -> [String] {
        guard let brew = brewPath() else { return [] }
        let raw = run(brew, ["outdated", "--quiet"])
        return raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Parse `brew doctor` text output into structured issues.
    /// Format: `Warning: ...` / `Error: ...` followed by indented detail lines.
    nonisolated func parseDoctor(_ raw: String) -> [BrewIssue] {
        var out: [BrewIssue] = []
        var currentTitle: String?
        var currentLevel: BrewIssue.Level = .warning
        var detailLines: [String] = []

        func flush() {
            if let title = currentTitle {
                out.append(BrewIssue(
                    id: "\(out.count):\(title)",
                    title: title,
                    detail: detailLines.isEmpty ? nil : detailLines.joined(separator: "\n"),
                    level: currentLevel
                ))
            }
            currentTitle = nil
            detailLines = []
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("Warning:") {
                flush()
                currentTitle = String(s.dropFirst("Warning:".count)).trimmingCharacters(in: .whitespaces)
                currentLevel = .warning
            } else if s.hasPrefix("Error:") {
                flush()
                currentTitle = String(s.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
                currentLevel = .error
            } else if currentTitle != nil {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { detailLines.append(trimmed) }
            }
        }
        flush()
        return out
    }

    func cleanup() async -> Bool {
        guard let brew = brewPath() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["cleanup"]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
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
final class BrewDoctorModel: ObservableObject {
    @Published var brewPath: String?
    @Published var issues: [BrewIssue] = []
    @Published var outdated: [String] = []
    @Published var isLoading = false
    @Published var lastAction: String?
    private let reader = BrewDoctorReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.brewPath = await reader.brewPath()
        async let i = reader.runDoctor()
        async let o = reader.runOutdated()
        self.issues = await i
        self.outdated = await o
    }

    func cleanup() async {
        let ok = await reader.cleanup()
        lastAction = ok ? "brew cleanup ✓" : "cleanup fehlgeschlagen"
        await reload()
    }
}

struct BrewDoctorView: View {
    @StateObject private var model = BrewDoctorModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.brewPath == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brew Doctor")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("brew doctor + brew outdated. Cleanup-Button räumt alte Versionen.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            if model.brewPath != nil {
                Button { Task { await model.cleanup() } } label: {
                    Label("brew cleanup", systemImage: "trash")
                }
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
        if model.brewPath == nil {
            ContentUnavailableView("Homebrew nicht gefunden",
                                   systemImage: "mug.fill",
                                   description: Text("Erwartet unter /opt/homebrew/bin/brew oder /usr/local/bin/brew."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    if !model.issues.isEmpty {
                        issuesSection
                    }
                    if !model.outdated.isEmpty {
                        outdatedSection
                    }
                    if let action = model.lastAction {
                        Text(action)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.success)
                    }
                }
                .padding(20)
            }
        }
    }

    private var statusCard: some View {
        HStack {
            Image(systemName: model.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.issues.isEmpty ? MD3.SemColor.success : MD3.SemColor.warning)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.issues.isEmpty ? "Brew is healthy" : "\(model.issues.count) Hinweis\(model.issues.count == 1 ? "" : "e")")
                    .font(MD3.Typo.headline)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("\(model.outdated.count) Pakete outdated · \(model.brewPath ?? "—")")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Doctor Output")
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textPrimary)
            ForEach(model.issues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: issue.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.level == .error ? MD3.SemColor.error : MD3.SemColor.warning)
                        Text(issue.title)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                    }
                    if let d = issue.detail {
                        Text(d)
                            .font(MD3.Typo.small)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                            .padding(.leading, 24)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MD3.SemColor.surfaceRaised.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var outdatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outdated Packages")
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textPrimary)
            ForEach(model.outdated, id: \.self) { name in
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(MD3.SemColor.warning)
                    Text(name)
                        .font(MD3.Typo.body)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}
