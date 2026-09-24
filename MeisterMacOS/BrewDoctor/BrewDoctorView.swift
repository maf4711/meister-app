import SwiftUI
import MeradOSDesign4

struct BrewIssue: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let level: Level

    enum Level { case warning, error, info }
}

actor BrewDoctorReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    private let locate: @Sendable () -> String?
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) },
         locate: @escaping @Sendable () -> String? = {
             ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
         }) {
        self.command = command
        self.locate = locate
    }
    func brewPath() -> String? { locate() }

    func runDoctor() async -> DiagnosticReport<[BrewIssue]> {
        guard let brew = brewPath() else { return .init(value: nil, issues: [.init(kind: .missingTool, source: "Homebrew")]) }
        let result = command(brew, ["doctor"])
        let findings = parseDoctor(result.output)
        if let issue = result.issue(source: "Brew Doctor") {
            // Doctor uses exit 1 for ordinary findings, not just execution errors.
            if result.status == 1 && result.failureKind == nil && issue.kind == .executionFailed && !findings.isEmpty {
                return .init(value: findings)
            }
            return .init(value: findings.isEmpty ? nil : findings, issues: [issue])
        }
        guard !findings.isEmpty || result.output.contains("Your system is ready to brew") else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Brew Doctor")])
        }
        return .init(value: findings)
    }

    func runOutdated() async -> DiagnosticReport<[String]> {
        guard let brew = brewPath() else { return .init(value: nil, issues: [.init(kind: .missingTool, source: "Homebrew")]) }
        let result = command(brew, ["outdated", "--quiet"])
        if let issue = result.issue(source: "Homebrew-Paketstand") { return .init(value: nil, issues: [issue]) }
        let names = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let valid = names.allSatisfy { $0.range(of: "^[A-Za-z0-9@+._/-]+$", options: .regularExpression) != nil }
        return valid ? .init(value: names) : .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Homebrew-Paketstand")])
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
        return CommandRunner.run(brew, ["cleanup"], timeout: 300).succeeded
    }

}

@MainActor
final class BrewDoctorModel: ObservableObject {
    @Published var brewPath: String?
    @Published var issues: [BrewIssue] = []
    @Published var outdated: [String] = []
    @Published var isLoading = false
    @Published var lastAction: String?
    @Published var diagnosticIssues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var isCleaning = false
    @Published var outdatedKnown = false
    private let reader = BrewDoctorReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        self.brewPath = await reader.brewPath()
        async let i = reader.runDoctor()
        async let o = reader.runOutdated()
        let doctor = await i
        let packages = await o
        issues = doctor.value ?? []
        outdated = packages.value ?? []
        outdatedKnown = packages.isComplete
        diagnosticIssues = DiagnosticReport(value: true, issues: doctor.issues + packages.issues).issues
        lastChecked = max(doctor.timestamp, packages.timestamp)
    }

    func cleanup() async {
        guard !isCleaning, !isLoading else { return }
        isCleaning = true
        defer { isCleaning = false }
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
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.diagnosticIssues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.brewPath == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brew Doctor")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("brew doctor + brew outdated. Cleanup-Button räumt alte Versionen.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            if model.brewPath != nil {
                Button { Task { await model.cleanup() } } label: {
                    Label("brew cleanup", systemImage: "trash")
                }
                .disabled(model.isLoading || model.isCleaning || !model.diagnosticIssues.isEmpty)
            }
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading || model.isCleaning)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.lastChecked == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.brewPath == nil {
            ContentUnavailableView("Homebrew nicht gefunden",
                                   systemImage: "mug.fill",
                                   description: Text("Erwartet unter /opt/homebrew/bin/brew oder /usr/local/bin/brew."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.diagnosticIssues.isEmpty {
                        Text("Homebrew-Diagnose unvollständig").font(.headline)
                    } else {
                        statusCard
                    }
                    if !model.issues.isEmpty {
                        issuesSection
                    }
                    if !model.outdated.isEmpty {
                        outdatedSection
                    }
                    if let action = model.lastAction {
                        Text(action)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.success)
                    }
                }
                .padding(20)
            }
        }
    }

    private var statusCard: some View {
        HStack {
            Image(systemName: model.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.issues.isEmpty ? MD4.SemColor.success : MD4.SemColor.warning)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.issues.isEmpty ? "Brew is healthy" : "\(model.issues.count) Hinweis\(model.issues.count == 1 ? "" : "e")")
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(model.outdatedKnown ? "\(model.outdated.count) Pakete outdated · \(model.brewPath ?? "—")" : "Paketstand unbekannt")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Doctor Output")
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            ForEach(model.issues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: issue.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.level == .error ? MD4.SemColor.error : MD4.SemColor.warning)
                        Text(issue.title)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                    }
                    if let d = issue.detail {
                        Text(d)
                            .font(MD4.Typo.small)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                            .padding(.leading, 24)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MD4.SemColor.surfaceRaised.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var outdatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outdated Packages")
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            ForEach(model.outdated, id: \.self) { name in
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(MD4.SemColor.warning)
                    Text(name)
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}
