import SwiftUI
import MeradOSDesign4

struct SimDevice: Identifiable, Hashable {
    let id: String        // UDID
    let name: String
    let runtime: String   // e.g. iOS 17.5
    let state: String     // Booted / Shutdown
    let dataSize: Int64?  // optional, computed lazy
}

actor SimulatorManagerReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    /// `xcrun simctl list devices --json` returns `{ devices: { runtime: [device, ...] } }`.
    func read() async -> DiagnosticReport<[SimDevice]> {
        let result = command("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        if let issue = result.issue(source: "Simulatoren") { return .init(value: nil, issues: [issue]) }
        let raw = result.output
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let devices = dict["devices"] as? [String: [[String: Any]]] else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Simulatoren")])
        }

        var issues: [DiagnosticIssue] = []
        var out: [SimDevice] = []
        for (runtimeKey, items) in devices {
            // runtimeKey looks like "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
            let pretty = runtimeKey
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            for item in items {
                guard let udid = item["udid"] as? String,
                      let name = item["name"] as? String,
                      let state = item["state"] as? String else { issues.append(.init(kind: .invalidOutput, source: "Simulatoren")); continue }
                let dataPath = item["dataPath"] as? String
                let size: Int64? = dataPath.flatMap { directorySize(atPath: $0) }
                out.append(SimDevice(
                    id: udid,
                    name: name,
                    runtime: pretty,
                    state: state,
                    dataSize: size
                ))
            }
        }
        return .init(value: out.isEmpty && !issues.isEmpty ? nil : out.sorted { ($0.runtime, $0.name) > ($1.runtime, $1.name) }, issues: issues)
    }

    func erase(udid: String) async -> Bool {
        guard UUID(uuidString: udid) != nil else { return false }
        return CommandRunner.run("/usr/bin/xcrun", ["simctl", "erase", udid], timeout: 300).succeeded
    }

    func delete(udid: String) async -> Bool {
        guard UUID(uuidString: udid) != nil else { return false }
        return CommandRunner.run("/usr/bin/xcrun", ["simctl", "delete", udid], timeout: 300).succeeded
    }

    private nonisolated func directorySize(atPath path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        guard let it = FileManager.default.enumerator(at: url,
                                                      includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                      options: [.skipsHiddenFiles]) else { return nil }
        var total: Int64 = 0
        for case let f as URL in it {
            let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
            total += Int64(s)
        }
        return total
    }

}

@MainActor
final class SimulatorManagerModel: ObservableObject {
    @Published var devices: [SimDevice] = []
    @Published var isLoading = false
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var actionStatus: String?
    private let reader = SimulatorManagerReader()

    var totalDataBytes: Int64 {
        devices.compactMap(\.dataSize).reduce(0, +)
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        devices = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }

    func erase(_ d: SimDevice) async {
        let ok = await reader.erase(udid: d.id)
        actionStatus = ok ? "\(d.name) erased" : "erase failed"
        await reload()
    }

    func delete(_ d: SimDevice) async {
        let ok = await reader.delete(udid: d.id)
        actionStatus = ok ? "\(d.name) deleted" : "delete failed"
        await reload()
    }
}

struct SimulatorManagerView: View {
    @StateObject private var model = SimulatorManagerModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.devices.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Simulator Manager")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("xcrun simctl — pro Sim erase oder delete. Gesamt: \(model.totalDataBytes.humanBytes) Sim-Daten.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            if let status = model.actionStatus {
                Text(status)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.devices.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.devices.isEmpty && !model.issues.isEmpty {
            ContentUnavailableView("Simulatoren nicht ermittelbar", systemImage: "iphone")
        } else if model.devices.isEmpty {
            ContentUnavailableView("Keine Simulatoren installiert",
                                   systemImage: "iphone.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.devices) { d in
                HStack {
                    Image(systemName: d.state == "Booted" ? "iphone.gen2.circle.fill" : "iphone.gen2")
                        .foregroundStyle(d.state == "Booted" ? MD4.SemColor.success : MD4.SemColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("\(d.runtime) · \(d.state)")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    Spacer()
                    if let size = d.dataSize {
                        Text(size.humanBytes)
                            .font(MD4.Typo.tabular(MD4.Typo.caption))
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    Button("Erase") { Task { await model.erase(d) } }
                        .buttonStyle(.borderless)
                    Button("Delete", role: .destructive) { Task { await model.delete(d) } }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
