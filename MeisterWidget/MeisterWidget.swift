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
        MeisterScanLiveActivity()
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
