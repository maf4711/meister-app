import SwiftUI
import MeradOSDesign3

struct StorageForecast: Equatable {
    let totalBytes: Int64
    let freeBytes: Int64
    let cleanupHistoryDays: Int
    let avgGrowthBytesPerDay: Int64       // negative = growing
    let daysUntilFull: Int?               // nil = not growing, or already full
}

actor StorageForecastReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func compute() async -> StorageForecast {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0

        let history = readCleanupManifests()
        let (growth, days) = estimateGrowth(history: history, currentFree: free)
        let daysUntilFull: Int? = {
            guard growth < 0 else { return nil }   // not growing or shrinking
            return Int(Double(free) / Double(-growth))
        }()

        return StorageForecast(
            totalBytes: total,
            freeBytes: free,
            cleanupHistoryDays: days,
            avgGrowthBytesPerDay: growth,
            daysUntilFull: daysUntilFull
        )
    }

    /// Read cleanup manifests to find points where reclaimable bytes were
    /// captured. Use the deltas between successive captures to project growth.
    private nonisolated func readCleanupManifests() -> [(Date, Int64)] {
        let dir = home.appendingPathComponent("Library/Application Support/Meister/cleanups", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let items: [(Date, Int64)] = urls.compactMap { u -> (Date, Int64)? in
            guard u.pathExtension == "json",
                  let data = try? Data(contentsOf: u),
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let dict = any as? [String: Any] else { return nil }
            let bytes = (dict["totalReclaimedBytes"] as? Int64) ??
                Int64((dict["totalReclaimedBytes"] as? NSNumber)?.int64Value ?? 0)
            let mtime = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return (mtime, bytes)
        }
        return items.sorted { $0.0 < $1.0 }
    }

    /// Heuristic: average bytes-reclaimed-per-day over manifest history is a
    /// proxy for daily junk accumulation. Negative growth = disk filling.
    private nonisolated func estimateGrowth(history: [(Date, Int64)], currentFree: Int64) -> (Int64, Int) {
        guard let first = history.first, let last = history.last, history.count >= 2 else {
            return (0, 0)
        }
        let span = max(1, Int(last.0.timeIntervalSince(first.0) / 86_400))
        let totalReclaimed = history.reduce(Int64(0)) { $0 + $1.1 }
        // If we reclaimed N bytes over D days, junk is accumulating at ~N/D per day.
        // That means the disk is "growing" (free shrinking) at the same rate.
        let growthPerDay = -totalReclaimed / Int64(span)
        return (growthPerDay, span)
    }
}

@MainActor
final class StorageForecastModel: ObservableObject {
    @Published var forecast: StorageForecast?
    @Published var isLoading = false
    private let reader = StorageForecastReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.forecast = await reader.compute()
    }
}

struct StorageForecastView: View {
    @StateObject private var model = StorageForecastModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.forecast == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage Forecast")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Wann ist die Disk voll? Schätzung aus Cleanup-Historie + aktuellem Freispeicher.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let f = model.forecast {
            ScrollView {
                VStack(spacing: 16) {
                    headlineCard(f)
                    if f.cleanupHistoryDays < 7 {
                        ContentUnavailableView("Zu wenig Daten",
                                               systemImage: "chart.line.uptrend.xyaxis",
                                               description: Text("Nur \(f.cleanupHistoryDays) Tag(e) Cleanup-Historie. Mindestens 7 Tage für eine sinnvolle Prognose."))
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        statGrid(f)
                    }
                }
                .padding(20)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headlineCard(_ f: StorageForecast) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aktuell frei")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
                .textCase(.uppercase)
            Text(f.freeBytes.humanBytes)
                .font(MD3.Typo.tabular(.system(size: 42, weight: .light)))
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text("von \(f.totalBytes.humanBytes) gesamt")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
            if let days = f.daysUntilFull {
                HStack {
                    Image(systemName: forecastIcon(days)).foregroundStyle(forecastColor(days))
                    Text("Disk voll in ca. \(days) Tag\(days == 1 ? "" : "en")")
                        .font(MD3.Typo.headline)
                        .foregroundStyle(forecastColor(days))
                }
                .padding(.top, 8)
            } else {
                Text("Keine Wachstumsdaten — Cleanups halten den Speicherstand stabil.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.success)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statGrid(_ f: StorageForecast) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Cleanup-Historie",
                 "\(f.cleanupHistoryDays) Tage",
                 "clock.arrow.2.circlepath")
            tile("Wachstum / Tag",
                 abs(f.avgGrowthBytesPerDay).humanBytes,
                 "arrow.up.arrow.down")
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD3.SemColor.brandPrimary)
                Text(label.uppercased())
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                Spacer()
            }
            Text(value)
                .font(MD3.Typo.tabular(MD3.Typo.title3))
                .foregroundStyle(MD3.SemColor.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func forecastIcon(_ days: Int) -> String {
        switch days {
        case ..<7: return "exclamationmark.triangle.fill"
        case ..<30: return "exclamationmark.circle"
        default: return "checkmark.circle"
        }
    }

    private func forecastColor(_ days: Int) -> Color {
        switch days {
        case ..<7: return MD3.SemColor.error
        case ..<30: return MD3.SemColor.warning
        default: return MD3.SemColor.success
        }
    }
}
