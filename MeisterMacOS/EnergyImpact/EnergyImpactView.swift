import SwiftUI
import MeradOSDesign4

struct EnergyHog: Identifiable, Hashable {
    let id: Int       // pid
    let name: String
    let energyImpact: Double  // higher = worse
    let cpuPercent: Double
}

actor EnergyImpactReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<[EnergyHog]> {
        let result = command("/usr/bin/top", ["-l", "1", "-stats", "pid,command,cpu,power", "-n", "20", "-o", "power"])
        if let issue = result.issue(source: "Energieverbrauch") { return .init(value: nil, issues: [issue]) }
        let rows = parse(result.output)
        guard !rows.isEmpty else { return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Energieverbrauch")]) }
        return .init(value: rows)
    }

    nonisolated func parse(_ raw: String) -> [EnergyHog] {
        var lines = raw.split(separator: "\n").map(String.init)
        // Drop everything until the header row that starts with "PID".
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        lines = Array(lines[(headerIdx + 1)...])

        var out: [EnergyHog] = []
        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[parts.count - 2]),
                  let power = Double(parts[parts.count - 1]),
                  pid > 0, cpu.isFinite, cpu >= 0, power.isFinite, power >= 0 else { continue }
            // Command may contain spaces — rejoin everything between PID and last 2 columns.
            let cmd = parts[1..<(parts.count - 2)].joined(separator: " ")
            out.append(EnergyHog(id: pid, name: cmd, energyImpact: power, cpuPercent: cpu))
        }
        return out.sorted { $0.energyImpact > $1.energyImpact }
    }

}

@MainActor
final class EnergyImpactModel: ObservableObject {
    @Published var hogs: [EnergyHog] = []
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var isLoading = false
    private let reader = EnergyImpactReader()
    private var refreshTask: Task<Void, Never>?

    func start() {
        stop()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        guard !Task.isCancelled else { return }
        self.hogs = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }
}

struct EnergyImpactView: View {
    @StateObject private var model = EnergyImpactModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            Divider().background(MD4.SemColor.divider)
            list
        }
        .background(MD4.SemColor.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Energy Impact")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Welche Prozesse fressen grade Akku/CPU. Live, alle 5 Sekunden.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(20)
    }

    private var list: some View {
        List(model.hogs) { h in
            HStack {
                Text(h.name)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                bar(value: min(h.energyImpact / 100, 1))
                    .frame(width: 80, height: 6)
                Text(String(format: "%.0f", h.energyImpact))
                    .font(MD4.Typo.tabular(MD4.Typo.caption))
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .frame(width: 36, alignment: .trailing)
                Text(String(format: "%.0f%%", h.cpuPercent))
                    .font(MD4.Typo.tabular(MD4.Typo.caption))
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func bar(value: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(MD4.SemColor.surfaceRaised)
            Capsule().fill(barColor(value))
                .scaleEffect(x: CGFloat(max(0.02, value)), y: 1, anchor: .leading)
        }
    }

    private func barColor(_ v: Double) -> Color {
        switch v {
        case 0..<0.33: return MD4.SemColor.success
        case 0.33..<0.66: return MD4.SemColor.warning
        default: return MD4.SemColor.error
        }
    }
}
