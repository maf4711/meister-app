import SwiftUI
import UIKit
import MeradOSDesign4

@MainActor
final class IOSDashboardModel: ObservableObject {
    @Published var snapshot: IOSDeviceSnapshot?
    @Published var isLoading = false
    private let reader = IOSDeviceReader()

    /// Composite "health" score for iOS — disk usage + battery + OS recency.
    var score: Int {
        guard let s = snapshot else { return 0 }
        var total = 0
        // Disk: 50 pts max — penalize >85% usage
        let diskPenalty = max(0, s.diskUsagePct - 0.85) / 0.15  // 0...1 above 85%
        total += Int((1 - diskPenalty) * 50)
        // Battery: 30 pts max — based on level if unplugged
        if s.batteryState == .charging || s.batteryState == .full {
            total += 30
        } else if s.batteryLevel < 0 {
            total += 20  // unknown
        } else {
            total += Int(Double(s.batteryLevel) * 30)
        }
        // Uptime: 20 pts max — reboots within 30 days = full points
        let days = Double(s.uptimeSeconds) / 86_400
        total += Int(max(0, 20 - days * 0.5))  // 1 pt off every 2 days uptime
        return min(100, max(0, total))
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.snapshot = await reader.read()
    }
}

struct IOSDashboardView: View {
    @StateObject private var model = IOSDashboardModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                healthRing
                grid
            }
            .padding(20)
        }
        .background(MD4.SemColor.background)
        .task { if model.snapshot == nil { await model.reload() } }
        .refreshable { await model.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meister")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(MD4.SemColor.textPrimary)
            if let s = model.snapshot {
                HStack(spacing: 6) {
                    Image(systemName: s.runtimeKind.icon)
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                    Text(s.runtimeKind.label)
                        .font(MD4.Typo.caption.bold())
                    Text("·")
                        .foregroundStyle(MD4.SemColor.textTertiary)
                    Text("\(s.modelName) · \(s.osName) \(s.osVersion)")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
        }
    }

    private var healthRing: some View {
        VStack(spacing: 12) {
            HealthRing(progress: Double(model.score) / 100,
                       size: 160, lineWidth: 12,
                       isComputing: model.isLoading)
                .overlay {
                    VStack(spacing: 0) {
                        NumberFlow(model.score, font: .system(size: 48, weight: .light))
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("/ 100")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                }
            Text(model.snapshot.map { _ in scoreVerdict() } ?? "Berechne…")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let s = model.snapshot {
                tile("Disk", icon: "internaldrive.fill",
                     primary: "\(Int(s.diskUsagePct * 100))%",
                     secondary: "\(s.freeDiskBytes.humanBytes) frei von \(s.totalDiskBytes.humanBytes)")
                tile("App-Storage", icon: "app",
                     primary: s.appUsedBytes.humanBytes,
                     secondary: "Documents + Library + Caches + tmp")
                tile("RAM", icon: "memorychip",
                     primary: Int64(s.physicalMemoryBytes).humanBytes,
                     secondary: "\(s.processorCount) Cores")
                if s.hasBattery {
                    tile("Battery", icon: batteryIcon(s),
                         primary: s.batteryLevel < 0 ? "—" : "\(Int((s.batteryLevel * 100).rounded()))%",
                         secondary: s.batteryState.label)
                } else {
                    tile("Power", icon: "powerplug.fill",
                         primary: "Netzstrom",
                         secondary: "Mac hat keinen Akku")
                }
                tile("Uptime", icon: "clock",
                     primary: formatUptime(s.uptimeSeconds),
                     secondary: "seit letztem Neustart")
                tile("OS", icon: "info.circle",
                     primary: "\(s.osName) \(s.osVersion)",
                     secondary: s.modelName)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private func tile(_ title: String, icon: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(title.uppercased())
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                Spacer()
            }
            Text(primary)
                .font(MD4.Typo.tabular(MD4.Typo.title3))
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text(secondary)
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func batteryIcon(_ s: IOSDeviceSnapshot) -> String {
        if s.batteryState == .charging { return "battery.100.bolt" }
        if s.batteryLevel < 0 { return "battery.0" }
        let pct = Int((s.batteryLevel * 100).rounded())
        switch pct {
        case 75...:  return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default:      return "battery.0"
        }
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h" }
        return "\(seconds / 60)m"
    }

    private func scoreVerdict() -> String {
        switch model.score {
        case 80...:    return "Alles im Lot"
        case 60..<80:  return "OK, kleine Optimierungen möglich"
        case 40..<60:  return "Speicher oder Akku schauen"
        default:       return "Mehrere Aufmerksamkeitspunkte"
        }
    }
}

#Preview {
    IOSDashboardView()
}
