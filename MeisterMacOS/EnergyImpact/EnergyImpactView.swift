import SwiftUI
import MeradOSDesign3

struct EnergyHog: Identifiable, Hashable {
    let id: Int       // pid
    let name: String
    let energyImpact: Double  // higher = worse
    let cpuPercent: Double
}

actor EnergyImpactReader {
    /// Sample `top -l 1 -stats pid,command,cpu,power` and parse top energy users.
    func read() async -> [EnergyHog] {
        let raw = run("/usr/bin/top", ["-l", "1", "-stats", "pid,command,cpu,power", "-n", "20", "-o", "power"])
        return parse(raw)
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
                  let power = Double(parts[parts.count - 1]) else { continue }
            // Command may contain spaces — rejoin everything between PID and last 2 columns.
            let cmd = parts[1..<(parts.count - 2)].joined(separator: " ")
            out.append(EnergyHog(id: pid, name: cmd, energyImpact: power, cpuPercent: cpu))
        }
        return out.sorted { $0.energyImpact > $1.energyImpact }
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
final class EnergyImpactModel: ObservableObject {
    @Published var hogs: [EnergyHog] = []
    @Published var isLoading = false
    private let reader = EnergyImpactReader()
    private var timer: Timer?

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        self.hogs = await reader.read()
    }
}

struct EnergyImpactView: View {
    @StateObject private var model = EnergyImpactModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            list
        }
        .background(MD3.SemColor.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Energy Impact")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Welche Prozesse fressen grade Akku/CPU. Live, alle 5 Sekunden.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
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
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                bar(value: min(h.energyImpact / 100, 1))
                    .frame(width: 80, height: 6)
                Text(String(format: "%.0f", h.energyImpact))
                    .font(MD3.Typo.tabular(MD3.Typo.caption))
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .frame(width: 36, alignment: .trailing)
                Text(String(format: "%.0f%%", h.cpuPercent))
                    .font(MD3.Typo.tabular(MD3.Typo.caption))
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func bar(value: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(MD3.SemColor.surfaceRaised)
            Capsule().fill(barColor(value))
                .scaleEffect(x: CGFloat(max(0.02, value)), y: 1, anchor: .leading)
        }
    }

    private func barColor(_ v: Double) -> Color {
        switch v {
        case 0..<0.33: return MD3.SemColor.success
        case 0.33..<0.66: return MD3.SemColor.warning
        default: return MD3.SemColor.error
        }
    }
}
