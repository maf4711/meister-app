import SwiftUI
import MeradOSDesign3

struct SimDevice: Identifiable, Hashable {
    let id: String        // UDID
    let name: String
    let runtime: String   // e.g. iOS 17.5
    let state: String     // Booted / Shutdown
    let dataSize: Int64?  // optional, computed lazy
}

actor SimulatorManagerReader {
    /// `xcrun simctl list devices --json` returns `{ devices: { runtime: [device, ...] } }`.
    func read() async -> [SimDevice] {
        let raw = run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let devices = dict["devices"] as? [String: [[String: Any]]] else { return [] }

        var out: [SimDevice] = []
        for (runtimeKey, items) in devices {
            // runtimeKey looks like "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
            let pretty = runtimeKey
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            for item in items {
                guard let udid = item["udid"] as? String,
                      let name = item["name"] as? String,
                      let state = item["state"] as? String else { continue }
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
        return out.sorted { ($0.runtime, $0.name) > ($1.runtime, $1.name) }
    }

    func erase(udid: String) async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl", "erase", udid]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    func delete(udid: String) async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl", "delete", udid]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
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

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
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
final class SimulatorManagerModel: ObservableObject {
    @Published var devices: [SimDevice] = []
    @Published var isLoading = false
    @Published var actionStatus: String?
    private let reader = SimulatorManagerReader()

    var totalDataBytes: Int64 {
        devices.compactMap(\.dataSize).reduce(0, +)
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.devices = await reader.read()
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
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.devices.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Simulator Manager")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("xcrun simctl — pro Sim erase oder delete. Gesamt: \(model.totalDataBytes.humanBytes) Sim-Daten.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            if let status = model.actionStatus {
                Text(status)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.success)
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
        } else if model.devices.isEmpty {
            ContentUnavailableView("Keine Simulatoren installiert",
                                   systemImage: "iphone.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.devices) { d in
                HStack {
                    Image(systemName: d.state == "Booted" ? "iphone.gen2.circle.fill" : "iphone.gen2")
                        .foregroundStyle(d.state == "Booted" ? MD3.SemColor.success : MD3.SemColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        Text("\(d.runtime) · \(d.state)")
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                    }
                    Spacer()
                    if let size = d.dataSize {
                        Text(size.humanBytes)
                            .font(MD3.Typo.tabular(MD3.Typo.caption))
                            .foregroundStyle(MD3.SemColor.textSecondary)
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
