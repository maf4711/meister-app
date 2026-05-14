import SwiftUI
import MeradOSDesign4

struct BluetoothDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let connected: Bool
    let batteryPercent: Int?
    let kind: String?           // mouse, keyboard, headphones, ...
}

actor BluetoothDevicesReader {
    func read() async -> [BluetoothDevice] {
        let raw = run("/usr/sbin/system_profiler", ["-json", "SPBluetoothDataType"])
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let bt = dict["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var out: [BluetoothDevice] = []
        for top in bt {
            // Two top-level shapes: connected vs not_connected
            if let connected = top["device_connected"] as? [[String: [String: Any]]] {
                for entry in connected { out.append(contentsOf: parseDeviceMap(entry, connected: true)) }
            }
            if let notConnected = top["device_not_connected"] as? [[String: [String: Any]]] {
                for entry in notConnected { out.append(contentsOf: parseDeviceMap(entry, connected: false)) }
            }
        }
        return out.sorted { $0.connected && !$1.connected }
    }

    private nonisolated func parseDeviceMap(_ map: [String: [String: Any]], connected: Bool) -> [BluetoothDevice] {
        return map.map { (name, attrs) in
            let address = attrs["device_address"] as? String ?? "—"
            let battery = (attrs["device_batteryLevelMain"] as? String)
                .flatMap { $0.hasSuffix("%") ? Int($0.dropLast()) : Int($0) }
            let kind = attrs["device_minorType"] as? String ?? attrs["device_majorType"] as? String
            return BluetoothDevice(
                id: address,
                name: name,
                address: address,
                connected: connected,
                batteryPercent: battery,
                kind: kind
            )
        }
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
final class BluetoothDevicesModel: ObservableObject {
    @Published var devices: [BluetoothDevice] = []
    @Published var isLoading = false
    private let reader = BluetoothDevicesReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.devices = await reader.read()
    }
}

struct BluetoothDevicesView: View {
    @StateObject private var model = BluetoothDevicesModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.devices.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bluetooth Devices")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Gepairt + Battery-Level wo verfügbar (Magic Keyboard, Maus, Trackpad, AirPods).")
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
        if model.isLoading && model.devices.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.devices.isEmpty {
            ContentUnavailableView("Keine Bluetooth-Geräte gepairt",
                                   systemImage: "antenna.radiowaves.left.and.right.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.devices) { d in
                HStack {
                    Image(systemName: d.connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(d.connected ? MD4.SemColor.success : MD4.SemColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("\(d.kind ?? "—") · \(d.address)")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    Spacer()
                    if let b = d.batteryPercent {
                        batteryBadge(percent: b)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func batteryBadge(percent: Int) -> some View {
        let color: Color = percent < 20 ? MD4.SemColor.error : (percent < 40 ? MD4.SemColor.warning : MD4.SemColor.success)
        return HStack(spacing: 4) {
            Image(systemName: percent < 20 ? "battery.25" : (percent < 60 ? "battery.50" : "battery.100"))
            Text("\(percent)%")
                .font(MD4.Typo.tabular(MD4.Typo.caption.bold()))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }
}
