import SwiftUI
import MeradOSDesign4

struct USBDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let speed: String
    let location: String
}

actor USBDevicesReader {
    func read() async -> [USBDevice] {
        let raw = run("/usr/sbin/system_profiler", ["-json", "SPUSBDataType"])
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let items = dict["SPUSBDataType"] as? [[String: Any]] else { return [] }

        var out: [USBDevice] = []
        for top in items { collect(node: top, into: &out, location: top["_name"] as? String ?? "—") }
        return out
    }

    private nonisolated func collect(node: [String: Any], into out: inout [USBDevice], location: String) {
        if let children = node["_items"] as? [[String: Any]] {
            for child in children { collect(node: child, into: &out, location: location) }
        }
        guard let name = node["_name"] as? String, !name.isEmpty else { return }
        // Filter out hub roots — they don't have product_id.
        guard node["product_id"] != nil || node["serial_num"] != nil else { return }
        out.append(USBDevice(
            id: "\(name)|\(node["serial_num"] as? String ?? UUID().uuidString)",
            name: name,
            manufacturer: node["manufacturer"] as? String ?? "—",
            speed: (node["device_speed"] as? String) ?? "—",
            location: location
        ))
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
final class USBDevicesModel: ObservableObject {
    @Published var devices: [USBDevice] = []
    @Published var isLoading = false
    private let reader = USBDevicesReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.devices = await reader.read()
    }
}

struct USBDevicesView: View {
    @StateObject private var model = USBDevicesModel()

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
                Text("USB Devices")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Was hängt grade dran und mit welcher Geschwindigkeit.")
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
            ContentUnavailableView("Keine USB-Geräte angeschlossen",
                                   systemImage: "cable.connector",
                                   description: Text("Stick, Tastatur, Maus oder externe Disk anschließen."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.devices) { d in
                HStack(spacing: 12) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("\(d.manufacturer) · \(d.location)")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    Spacer()
                    Text(d.speed)
                        .font(MD4.Typo.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MD4.SemColor.surfaceRaised, in: Capsule())
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
