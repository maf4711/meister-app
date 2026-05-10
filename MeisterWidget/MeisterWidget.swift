import SwiftUI
import WidgetKit

struct StorageSnapshot: TimelineEntry {
    let date: Date
    let usedRatio: Double
    let usedString: String
    let totalString: String
}

struct StorageProvider: TimelineProvider {
    private let fmt = ByteCountFormatter()
    init() { fmt.countStyle = .file }

    func placeholder(in context: Context) -> StorageSnapshot {
        .init(date: .now, usedRatio: 0.42, usedString: "128 GB", totalString: "256 GB")
    }
    func getSnapshot(in context: Context, completion: @escaping (StorageSnapshot) -> Void) {
        completion(readSnapshot())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageSnapshot>) -> Void) {
        let entry = readSnapshot()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
    }

    private func readSnapshot() -> StorageSnapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let values = try? url.resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = total - free
        return StorageSnapshot(
            date: .now,
            usedRatio: total > 0 ? Double(used) / Double(total) : 0,
            usedString: fmt.string(fromByteCount: used),
            totalString: fmt.string(fromByteCount: total)
        )
    }
}

struct StorageWidgetEntryView: View {
    var entry: StorageProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(.orange)
                Text("Meister").font(.caption.bold())
                Spacer()
            }
            Text(entry.usedString).font(.title3.bold()).monospacedDigit()
            Text("of \(entry.totalString)").font(.caption2).foregroundStyle(.secondary)
            Gauge(value: entry.usedRatio) { EmptyView() } currentValueLabel: {
                Text("\(Int(entry.usedRatio * 100))%").font(.caption.bold())
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(entry.usedRatio > 0.9 ? .red : (entry.usedRatio > 0.75 ? .orange : .green))
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MeisterStorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeisterStorageWidget", provider: StorageProvider()) { entry in
            StorageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Storage")
        .description("iPhone disk usage at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

import ActivityKit

@main
struct MeisterWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeisterStorageWidget()
        MeisterHealthScoreWidget()
        MeisterScanLiveActivity()
    }
}

// MARK: - Health Score widget
// Self-contained quick score: 50 pts disk + 30 pts battery + 20 pts uptime.
// Same weighting as IOSDashboardModel.score but using only the data
// available to a widget extension (no PhotoKit / heavy scans).

struct HealthSnapshot: TimelineEntry {
    let date: Date
    let score: Int
    let diskPct: Int
    let batteryPct: Int
    let uptimeDays: Int
}

struct HealthProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthSnapshot {
        .init(date: .now, score: 84, diskPct: 65, batteryPct: 78, uptimeDays: 3)
    }
    func getSnapshot(in context: Context, completion: @escaping (HealthSnapshot) -> Void) {
        completion(read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthSnapshot>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(60 * 30))))
    }

    private func read() -> HealthSnapshot {
        // Disk
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? url.resourceValues(forKeys: keys)
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = total - free
        let diskPct = total > 0 ? Int(((Double(used) / Double(total)) * 100).rounded()) : 0

        // Battery — UIDevice in widget extension is allowed and works the same.
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryFloat = device.batteryLevel
        let batteryPct = batteryFloat < 0 ? -1 : Int((batteryFloat * 100).rounded())

        // Uptime
        let uptimeDays = Int(ProcessInfo.processInfo.systemUptime / 86_400)

        // Score (matches IOSDashboardModel weighting)
        var score = 0
        // Disk: 50 pts, penalize >85% usage
        let diskPenalty = max(0.0, (Double(diskPct) - 85.0) / 15.0)
        score += Int((1 - diskPenalty) * 50)
        // Battery: 30 pts based on level
        if batteryPct < 0 {
            score += 20
        } else {
            score += Int(Double(batteryPct) / 100.0 * 30)
        }
        // Uptime: 20 pts max, -1 per 2 days
        score += max(0, 20 - uptimeDays / 2)
        score = min(100, max(0, score))

        return HealthSnapshot(
            date: .now,
            score: score,
            diskPct: diskPct,
            batteryPct: batteryPct,
            uptimeDays: uptimeDays
        )
    }
}

struct HealthScoreWidgetEntryView: View {
    var entry: HealthProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var ringColor: Color {
        switch entry.score {
        case 80...:    return .green
        case 50..<80:  return .orange
        default:       return .red
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle().stroke(.tertiary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(entry.score) / 100)
                    .stroke(ringColor, style: .init(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(entry.score)").font(.caption2.bold().monospacedDigit())
            }
            .containerBackground(.fill.tertiary, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(ringColor)
                    Text("Health").font(.caption.bold())
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.score)").font(.system(size: 36, weight: .light).monospacedDigit())
                        .foregroundStyle(ringColor)
                    Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    statChip("Disk", "\(entry.diskPct)%")
                    if entry.batteryPct >= 0 {
                        statChip("Akku", "\(entry.batteryPct)%")
                    }
                }
            }
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold().monospacedDigit())
        }
    }
}

struct MeisterHealthScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeisterHealthScoreWidget", provider: HealthProvider()) { entry in
            HealthScoreWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Health Score")
        .description("Sicherheit, Backup, Cleanup-Druck — eine Zahl 0-100.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct MeisterScanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScanActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkles.square.filled.on.square")
                        .foregroundStyle(.orange)
                    Text(context.attributes.scanTitle).font(.headline)
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(context.state.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: context.state.progress).tint(.orange)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.scanTitle, systemImage: "sparkles.square.filled.on.square")
                        .font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%").font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        Text(context.state.phase).font(.caption2)
                        ProgressView(value: context.state.progress).tint(.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles.square.filled.on.square").foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%").font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "sparkles.square.filled.on.square").foregroundStyle(.orange)
            }
        }
    }
}
