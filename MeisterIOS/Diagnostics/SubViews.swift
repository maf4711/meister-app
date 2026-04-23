import SwiftUI

struct HardwareTestsView: View {
    @State private var results: [HardwareTest: HardwareResult] = [:]
    @State private var running: HardwareTest?

    var body: some View {
        List(HardwareTest.allCases) { test in
            Button {
                running = test
                Task {
                    results[test] = await HardwareTestRunner.run(test)
                    running = nil
                }
            } label: {
                HStack {
                    Image(systemName: test.systemImage).frame(width: 28).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(test.title).foregroundStyle(.primary)
                        if let result = results[test] {
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if running == test {
                        ProgressView()
                    } else if let result = results[test] {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            }
            .disabled(running != nil)
        }
        .navigationTitle("Hardware Tests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyAuditView: View {
    @State private var permissions = PermissionManager.shared

    var body: some View {
        List(PrivacyAudit.snapshot(permissions), id: \.service) { grant in
            HStack {
                Image(systemName: grant.systemImage).frame(width: 28).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(grant.service)
                    Text(grant.state).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Privacy Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task { permissions.refresh() }
    }
}

struct ClipboardMonitorView: View {
    @State private var monitor = ClipboardMonitor()

    var body: some View {
        List {
            if monitor.changes.isEmpty {
                Text("No clipboard changes recorded yet.").foregroundStyle(.secondary)
            }
            ForEach(monitor.changes) { change in
                HStack {
                    Image(systemName: "doc.on.clipboard").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(change.typePreview.capitalized)
                        Text(change.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("#\(change.changeCount)").font(.caption.monospacedDigit())
                }
            }
        }
        .navigationTitle("Clipboard Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

struct WiFiHistoryView: View {
    @State private var monitor = WiFiSignalMonitor()

    var body: some View {
        List {
            if monitor.samples.isEmpty {
                Text("Waiting for network changes…").foregroundStyle(.secondary)
            }
            ForEach(monitor.samples.reversed()) { sample in
                HStack {
                    Image(systemName: statusIcon(sample)).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(statusLabel(sample))
                        Text(sample.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Network History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusIcon(_ sample: WiFiSignalMonitor.Sample) -> String {
        sample.status == .satisfied ? "wifi" : "wifi.slash"
    }

    private func statusLabel(_ sample: WiFiSignalMonitor.Sample) -> String {
        var parts: [String] = [sample.interface.map { String(describing: $0) } ?? "offline"]
        if sample.isExpensive { parts.append("expensive") }
        if sample.isConstrained { parts.append("constrained") }
        return parts.joined(separator: " · ")
    }
}
