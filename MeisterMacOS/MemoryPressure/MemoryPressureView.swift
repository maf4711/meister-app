import SwiftUI
import MeradOSDesign4

struct MemSample: Identifiable, Hashable {
    let id: Date
    let timestamp: Date
    let usedBytes: Int64
    let freeBytes: Int64
    let cachedBytes: Int64
    let compressedBytes: Int64
    let pressure: Pressure
    let swapUsedBytes: Int64

    enum Pressure: String {
        case normal, warning, critical
    }
}

actor MemoryPressureReader {
    static let pageSize: Int64 = Int64(NSPageSize())

    func read() async -> MemSample {
        let raw = run("/usr/bin/vm_stat")
        let stats = parse(raw)
        let pressure = currentPressure()
        let swap = parseSwap(run("/usr/sbin/sysctl", ["-n", "vm.swapusage"]))
        return MemSample(
            id: Date(),
            timestamp: Date(),
            usedBytes: (stats.active + stats.wired) * Self.pageSize,
            freeBytes: stats.free * Self.pageSize,
            cachedBytes: stats.cached * Self.pageSize,
            compressedBytes: stats.compressed * Self.pageSize,
            pressure: pressure,
            swapUsedBytes: swap
        )
    }

    nonisolated func parse(_ raw: String) -> (free: Int64, active: Int64, wired: Int64, cached: Int64, compressed: Int64) {
        var free: Int64 = 0, active: Int64 = 0, wired: Int64 = 0, cached: Int64 = 0, compressed: Int64 = 0
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let v = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            guard let n = Int64(v) else { continue }
            switch key {
            case "Pages free": free = n
            case "Pages active": active = n
            case "Pages wired down": wired = n
            case "File-backed pages", "Pages purgeable": cached += n
            case "Pages occupied by compressor": compressed = n
            default: break
            }
        }
        return (free, active, wired, cached, compressed)
    }

    /// Quick proxy for memory pressure: ratio of free pages to total physical memory.
    private nonisolated func currentPressure() -> MemSample.Pressure {
        let totalMem = Int64(ProcessInfo.processInfo.physicalMemory)
        let raw = run("/usr/bin/vm_stat")
        let stats = parse(raw)
        let availableBytes = (stats.free + stats.cached) * Self.pageSize
        let pct = Double(availableBytes) / Double(totalMem)
        switch pct {
        case 0.20...: return .normal
        case 0.10...: return .warning
        default:      return .critical
        }
    }

    nonisolated func parseSwap(_ raw: String) -> Int64 {
        // sysctl vm.swapusage prints e.g. "total = 2048.00M  used = 1024.00M  free = 1024.00M  (encrypted)"
        guard let usedRange = raw.range(of: "used = ") else { return 0 }
        let after = raw[usedRange.upperBound...]
        let v = after.split(separator: " ").first.map(String.init) ?? ""
        return parseSizeM(v)
    }

    private nonisolated func parseSizeM(_ s: String) -> Int64 {
        // "1024.00M" or "0.00M"
        let cleaned = s.trimmingCharacters(in: CharacterSet(charactersIn: "M"))
        guard let n = Double(cleaned) else { return 0 }
        return Int64(n * 1_048_576)
    }

    private nonisolated func run(_ tool: String, _ args: [String] = []) -> String {
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
final class MemoryPressureModel: ObservableObject {
    @Published var samples: [MemSample] = []
    @Published var current: MemSample?
    private let reader = MemoryPressureReader()
    private static let maxSamples = 60   // ~5 min @ 5s interval
    private var task: Task<Void, Never>?

    func start() {
        task = Task { @MainActor in
            while !Task.isCancelled {
                let s = await reader.read()
                self.current = s
                self.samples.append(s)
                if self.samples.count > Self.maxSamples {
                    self.samples.removeFirst(self.samples.count - Self.maxSamples)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct MemoryPressureView: View {
    @StateObject private var model = MemoryPressureModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory Pressure")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Live — vm_stat alle 5 Sekunden, letzte 5 Min als Sparkline.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.current {
            ScrollView {
                VStack(spacing: 16) {
                    pressureBadge(s.pressure)
                    grid(s)
                    sparkline
                }
                .padding(20)
            }
        } else {
            ProgressView("Sammle Samples…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pressureBadge(_ p: MemSample.Pressure) -> some View {
        let (color, label, icon): (Color, String, String) = {
            switch p {
            case .normal:   return (MD4.SemColor.success, "Memory Pressure: NORMAL", "checkmark.shield.fill")
            case .warning:  return (MD4.SemColor.warning, "Memory Pressure: WARNING", "exclamationmark.triangle.fill")
            case .critical: return (MD4.SemColor.error, "Memory Pressure: CRITICAL", "xmark.shield.fill")
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(label)
                .font(MD4.Typo.headline)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func grid(_ s: MemSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Used", s.usedBytes.humanBytes, "memorychip")
            tile("Free", s.freeBytes.humanBytes, "wind")
            tile("Cached", s.cachedBytes.humanBytes, "tray")
            tile("Compressed", s.compressedBytes.humanBytes, "archivebox")
            tile("Swap", s.swapUsedBytes.humanBytes, "arrow.up.arrow.down")
            tile("Total", Int64(ProcessInfo.processInfo.physicalMemory).humanBytes, "rectangle.stack.fill")
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(label.uppercased())
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                Spacer()
            }
            Text(value)
                .font(MD4.Typo.tabular(MD4.Typo.title3))
                .foregroundStyle(MD4.SemColor.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Used Memory — letzte 5 Min")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Canvas { ctx, size in
                guard model.samples.count > 1 else { return }
                let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
                let maxIdx = model.samples.count - 1
                var path = Path()
                for (idx, s) in model.samples.enumerated() {
                    let x = CGFloat(idx) / CGFloat(maxIdx) * size.width
                    let y = (1.0 - CGFloat(Double(s.usedBytes) / totalMem)) * size.height
                    if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(MD4.SemColor.brandPrimary), lineWidth: 2)
            }
            .frame(height: 80)
            .background(MD4.SemColor.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
