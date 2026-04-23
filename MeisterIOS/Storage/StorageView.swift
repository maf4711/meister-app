import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class StorageViewModel {
    var info: StorageInfo = StorageReader.read()
    var cacheBytes: Int64 = 0
    var isRefreshing = false
    var purgeCount = 0

    func refresh() async {
        isRefreshing = true
        info = StorageReader.read()
        cacheBytes = await Task.detached { StorageReader.appCacheBytes() }.value
        isRefreshing = false
    }

    func clearCache() async {
        try? StorageReader.purgeAppCache()
        purgeCount += 1
        await refresh()
    }
}

struct StorageView: View {
    @State private var model = StorageViewModel()
    @State private var isConfirmingClear = false
    @State private var reportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("Device Storage") {
                    storageHeader
                        .padding(.vertical, 8)
                }

                Section("Tools") {
                    NavigationLink {
                        ICloudCleanerView()
                    } label: {
                        Label("iCloud Drive Cleaner", systemImage: "icloud")
                    }
                    NavigationLink {
                        TrashView()
                    } label: {
                        Label("Trash (30 Days)", systemImage: "trash")
                    }
                    Button {
                        exportReport()
                    } label: {
                        Label("Export PDF Report", systemImage: "doc.richtext")
                    }
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("Share Last Report", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    HStack {
                        Text("App Cache")
                        Spacer()
                        Text(ByteSize.formatted(model.cacheBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear App Cache", systemImage: "trash")
                    }
                    .disabled(model.cacheBytes == 0)
                } header: {
                    Text("App Data")
                } footer: {
                    Text("Only removes data inside Meister's own sandbox. Your photos and contacts are untouched.")
                }
            }
            .navigationTitle("Storage")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .haptic(.destruction, trigger: model.purgeCount)
            .confirmationDialog(
                "Clear App Cache?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) { Task { await model.clearCache() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Temporary files inside Meister are removed. Scans rerun the next time you open a tab.")
            }
        }
    }

    private var storageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ByteSize.formatted(model.info.used))
                        .font(.largeTitle.bold())
                    Text("of \(ByteSize.formatted(model.info.total)) used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.info.usedRatio, format: .percent.precision(.fractionLength(0)))
                    .font(.title.monospacedDigit())
                    .foregroundStyle(gaugeTint)
            }
            Gauge(value: model.info.usedRatio) { EmptyView() }
                .tint(gaugeTint)
            Text("Free: \(ByteSize.formatted(model.info.free))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage: \(ByteSize.formatted(model.info.used)) used, \(ByteSize.formatted(model.info.free)) free")
    }

    private func exportReport() {
        let info = model.info
        let report = CleanupReport(
            generatedAt: .now,
            deviceInfo: UIDevice.current.model,
            sections: [
                CleanupReport.Section(title: "Device Storage", rows: [
                    ("Used", ByteSize.formatted(info.used)),
                    ("Free", ByteSize.formatted(info.free)),
                    ("Total", ByteSize.formatted(info.total)),
                    ("Utilization", "\(Int(info.usedRatio * 100))%"),
                ]),
                CleanupReport.Section(title: "Meister Data", rows: [
                    ("App Cache", ByteSize.formatted(model.cacheBytes)),
                ]),
            ]
        )
        reportURL = try? report.renderPDF()
    }

    private var gaugeTint: Color {
        switch model.info.usedRatio {
        case ..<0.75: .green
        case ..<0.9:  .orange
        default:      .red
        }
    }
}
