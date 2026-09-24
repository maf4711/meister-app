import SwiftUI
import MeradOSDesign4

struct StorageForecast: Equatable {
    let totalBytes: Int64
    let freeBytes: Int64
    let cleanupHistoryDays: Int
    let avgGrowthBytesPerDay: Int64       // negative = growing
    let daysUntilFull: Int?               // nil = not growing, or already full
}

struct StorageSample: Codable {
    let date: Date
    let total: Int64
    let free: Int64
}

actor StorageForecastReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func compute() async throws -> StorageForecast {
        guard let disk = DiskCapacity.read() else {
            throw CocoaError(.fileReadUnknown)
        }
        let url = home.appendingPathComponent("Library/Application Support/Meister/storage-samples.json")
        var samples: [StorageSample] = []
        if FileManager.default.fileExists(atPath: url.path) {
            samples = try JSONDecoder().decode([StorageSample].self, from: Data(contentsOf: url))
        }
        let now = Date()
        samples = samples.filter { now.timeIntervalSince($0.date) <= 90 * 86_400 && $0.total == disk.total }
        // Keep one observation per hour so frequent refreshes do not bias the trend.
        if samples.last.map({ now.timeIntervalSince($0.date) >= 3600 }) ?? true {
            samples.append(.init(date: now, total: disk.total, free: disk.available))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: url, options: .atomic)
        }
        return Self.forecast(samples: samples, disk: disk)
    }

    nonisolated static func forecast(samples: [StorageSample], disk: DiskCapacity) -> StorageForecast {
        let samples = samples.filter { $0.total == disk.total }.sorted { $0.date < $1.date }
        let span = samples.first.flatMap { first in samples.last.map { $0.date.timeIntervalSince(first.date) } } ?? 0
        let days = max(0, Int(span / 86_400))
        var growth: Int64 = 0
        // At least seven days and three observations before making a projection.
        if days >= 7, samples.count >= 3, let first = samples.first, let last = samples.last {
            growth = Int64(Double(last.free - first.free) / (span / 86_400))
        }
        let daysUntilFull = growth < 0 ? Int(Double(disk.available) / Double(-growth)) : nil
        return StorageForecast(totalBytes: disk.total, freeBytes: disk.available,
                               cleanupHistoryDays: days, avgGrowthBytesPerDay: growth, daysUntilFull: daysUntilFull)
    }
}

@MainActor
final class StorageForecastModel: ObservableObject {
    @Published var forecast: StorageForecast?
    @Published var isLoading = false
    @Published var error: String?
    private let reader = StorageForecastReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do { self.forecast = try await reader.compute() }
        catch { self.error = error.localizedDescription }
    }
}

struct StorageForecastView: View {
    @StateObject private var model = StorageForecastModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.forecast == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage Forecast")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Trend aus gemessenen Speicherständen auf dem Datenvolume. Messung bei jedem Aufruf.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
        if let error = model.error {
            ContentUnavailableView("Messung fehlgeschlagen", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let f = model.forecast {
            ScrollView {
                VStack(spacing: 16) {
                    headlineCard(f)
                    if f.cleanupHistoryDays < 7 {
                        ContentUnavailableView("Zu wenig Daten",
                                               systemImage: "chart.line.uptrend.xyaxis",
                                               description: Text("Nur \(f.cleanupHistoryDays) Tag(e) Messhistorie. Mindestens 7 Tage und 3 Messungen für eine Prognose."))
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
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
                .textCase(.uppercase)
            Text(f.freeBytes.humanBytes)
                .font(MD4.Typo.tabular(.system(size: 42, weight: .light)))
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text("von \(f.totalBytes.humanBytes) gesamt")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            if let days = f.daysUntilFull {
                HStack {
                    Image(systemName: forecastIcon(days)).foregroundStyle(forecastColor(days))
                    Text("Disk voll in ca. \(days) Tag\(days == 1 ? "" : "en")")
                        .font(MD4.Typo.headline)
                        .foregroundStyle(forecastColor(days))
                }
                .padding(.top, 8)
            } else {
                Text("Keine belastbare Vorhersage für einen vollen Datenträger.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.success)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statGrid(_ f: StorageForecast) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Messhistorie",
                 "\(f.cleanupHistoryDays) Tage",
                 "clock.arrow.2.circlepath")
            tile("Änderung Freispeicher / Tag",
                 f.avgGrowthBytesPerDay.humanBytes,
                 "arrow.up.arrow.down")
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private func forecastIcon(_ days: Int) -> String {
        switch days {
        case ..<7: return "exclamationmark.triangle.fill"
        case ..<30: return "exclamationmark.circle"
        default: return "checkmark.circle"
        }
    }

    private func forecastColor(_ days: Int) -> Color {
        switch days {
        case ..<7: return MD4.SemColor.error
        case ..<30: return MD4.SemColor.warning
        default: return MD4.SemColor.success
        }
    }
}
