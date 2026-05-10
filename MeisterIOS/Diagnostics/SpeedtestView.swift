import Charts
import SwiftUI

struct SpeedtestProView: View {
    @State private var current: SpeedtestPro.Result?
    @State private var history: [SpeedtestPro.Result] = SpeedtestPro.loadHistory()
    @State private var isRunning = false
    @State private var phase: String = ""
    @State private var progress: Double = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        metric("Ping", current.map { String(format: "%.0f ms", $0.pingMs) } ?? "—")
                        metric("Jitter", current.map { String(format: "%.1f ms", $0.jitterMs) } ?? "—")
                    }
                    HStack(spacing: 24) {
                        metric("Download", current.map { String(format: "%.1f Mbps", $0.downloadMbps) } ?? "—")
                        metric("Upload", current.map { String(format: "%.1f Mbps", $0.uploadMbps) } ?? "—")
                    }
                    if isRunning {
                        ProgressView(value: progress) { Text(phase).font(.caption) }
                            .tint(.orange)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Latest Run")
            }

            Section("History") {
                if history.isEmpty {
                    Text("No tests yet.").foregroundStyle(.secondary)
                } else {
                    Chart(history) { result in
                        LineMark(
                            x: .value("When", result.timestamp),
                            y: .value("Mbps", result.downloadMbps)
                        )
                        .foregroundStyle(Color.orange)
                    }
                    .frame(height: 160)
                    .chartYAxisLabel("Download Mbps")
                    ForEach(history.reversed()) { result in
                        HStack {
                            Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            Spacer()
                            Text(String(format: "↓ %.0f Mbps", result.downloadMbps))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Button {
                    run()
                } label: {
                    Label(isRunning ? "Running…" : "Run Speedtest", systemImage: "speedometer")
                        .fontWeight(.semibold)
                }
                .disabled(isRunning)
            }
        }
        .navigationTitle("Speedtest Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit()).bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run() {
        // Tom Build 33: speedtest still crashing. Root cause this round —
        // the Task here had no isolation, so isRunning/current/history (all
        // @State) were being mutated off the main actor. iOS 18's strict
        // SwiftUI threading turns that into a runtime crash on first
        // mutation. Pin the Task to MainActor and the off-main work to a
        // detached child task that calls back through the @Sendable
        // progress closure (already MainActor-hopped internally).
        Task { @MainActor in
            isRunning = true
            defer { isRunning = false }
            let result = await Task.detached {
                await SpeedtestPro().run { p, v in
                    Task { @MainActor in phase = p; progress = v }
                }
            }.value
            current = result
            history = SpeedtestPro.loadHistory()
        }
    }
}

struct DNSBenchmarkView: View {
    @State private var results: [DNSBenchmark.ProviderResult] = []
    @State private var isRunning = false

    var body: some View {
        List {
            if results.isEmpty && !isRunning {
                Text("Tap Run to compare DNS providers.").foregroundStyle(.secondary)
            }
            if isRunning { Section { ProgressView("Querying resolvers…") } }
            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { result in
                        HStack {
                            Image(systemName: "network").foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(result.name)
                                if result.failures > 0 {
                                    Text("\(result.failures) failures").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(result.averageMs > 0 ? String(format: "%.0f ms", result.averageMs) : "—")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            Section {
                Button { run() } label: {
                    Label(isRunning ? "Running…" : "Run Benchmark", systemImage: "play.fill")
                }
                .disabled(isRunning)
            }
        }
        .navigationTitle("DNS Benchmark")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        Task {
            isRunning = true
            let engine = DNSBenchmark()
            results = await engine.run()
            isRunning = false
        }
    }
}

struct PrivacyDashboardView: View {
    @State private var indicators: [PrivacyDashboard.Indicator] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading { ProgressView("Checking…") }
            ForEach(indicators) { indicator in
                HStack {
                    Image(systemName: indicator.systemImage).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(indicator.title)
                        Text(indicator.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    stateBadge(for: indicator.state)
                }
            }
        }
        .navigationTitle("Privacy Status")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func stateBadge(for state: PrivacyDashboard.State) -> some View {
        let (text, tint): (String, Color) = switch state {
        case .on: ("On", .green)
        case .off: ("Off", .red)
        case .unknown: ("—", .secondary)
        }
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2), in: .capsule)
            .foregroundStyle(tint)
    }

    @MainActor
    private func load() async {
        loading = true
        indicators = await PrivacyDashboard.snapshot()
        loading = false
    }
}
