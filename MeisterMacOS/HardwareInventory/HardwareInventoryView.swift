import SwiftUI
import MeradOSDesign4

struct HardwareSection: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let rows: [(String, String)]
    var asLines: [String] { rows.map { "\($0.0): \($0.1)" } }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HardwareSection, rhs: HardwareSection) -> Bool { lhs.id == rhs.id }
}

actor HardwareInventoryReader {
    func read() async -> [HardwareSection] {
        var out: [HardwareSection] = []
        if let dict = sp("SPHardwareDataType") {
            out.append(parseHardware(dict))
        }
        if let dict = sp("SPMemoryDataType") {
            out.append(parseMemory(dict))
        }
        if let dict = sp("SPStorageDataType") {
            out.append(contentsOf: parseStorage(dict))
        }
        if let dict = sp("SPDisplaysDataType") {
            out.append(contentsOf: parseDisplays(dict))
        }
        if let dict = sp("SPNetworkDataType") {
            out.append(parseNetwork(dict))
        }
        if let dict = sp("SPSoftwareDataType") {
            out.append(parseSoftware(dict))
        }
        return out
    }

    private nonisolated func sp(_ type: String) -> [String: Any]? {
        let raw = run("/usr/sbin/system_profiler", ["-json", type])
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any] else { return nil }
        return dict
    }

    private nonisolated func parseHardware(_ root: [String: Any]) -> HardwareSection {
        let items = (root["SPHardwareDataType"] as? [[String: Any]]) ?? []
        let item = items.first ?? [:]
        return HardwareSection(
            id: "hw",
            title: "System",
            icon: "cpu",
            rows: [
                ("Model",        item["machine_model"] as? String ?? "—"),
                ("Chip",         item["chip_type"] as? String ?? item["cpu_type"] as? String ?? "—"),
                ("Cores",        "\(item["number_processors"] as? String ?? "—")"),
                ("Memory",       item["physical_memory"] as? String ?? "—"),
                ("Serial",       item["serial_number"] as? String ?? "—"),
                ("UUID",         item["platform_UUID"] as? String ?? "—"),
                ("Boot Mode",    item["boot_mode"] as? String ?? "—"),
            ]
        )
    }

    private nonisolated func parseMemory(_ root: [String: Any]) -> HardwareSection {
        let items = (root["SPMemoryDataType"] as? [[String: Any]]) ?? []
        let item = items.first ?? [:]
        return HardwareSection(
            id: "mem",
            title: "Memory",
            icon: "memorychip",
            rows: [
                ("Type",    item["dimm_type"] as? String ?? "Unified"),
                ("Size",    item["dimm_size"] as? String ?? item["SPMemoryDataType"] as? String ?? "—"),
                ("ECC",     item["global_ecc_state"] as? String ?? "—"),
                ("Upgrade", item["is_memory_upgradeable"] as? String ?? "Soldered"),
            ]
        )
    }

    private nonisolated func parseStorage(_ root: [String: Any]) -> [HardwareSection] {
        let items = (root["SPStorageDataType"] as? [[String: Any]]) ?? []
        return items.enumerated().map { idx, vol in
            let total = vol["size_in_bytes"] as? Int64 ??
                Int64((vol["size_in_bytes"] as? NSNumber)?.int64Value ?? 0)
            let free  = vol["free_space_in_bytes"] as? Int64 ??
                Int64((vol["free_space_in_bytes"] as? NSNumber)?.int64Value ?? 0)
            return HardwareSection(
                id: "stor-\(idx)",
                title: "Volume: \((vol["_name"] as? String ?? "—"))",
                icon: "externaldrive",
                rows: [
                    ("Mount",     vol["mount_point"] as? String ?? "—"),
                    ("Format",    vol["file_system"] as? String ?? "—"),
                    ("Size",      total.humanBytes),
                    ("Free",      free.humanBytes),
                    ("Used",      (total - free).humanBytes),
                    ("Boot",      vol["bootable_volume"] as? String ?? "—"),
                ]
            )
        }
    }

    private nonisolated func parseDisplays(_ root: [String: Any]) -> [HardwareSection] {
        let gpus = (root["SPDisplaysDataType"] as? [[String: Any]]) ?? []
        var out: [HardwareSection] = []
        for (idx, gpu) in gpus.enumerated() {
            var rows: [(String, String)] = [
                ("GPU",     gpu["sppci_model"] as? String ?? "—"),
                ("Cores",   gpu["sppci_cores"] as? String ?? "—"),
                ("Vendor",  gpu["spdisplays_vendor"] as? String ?? "—"),
            ]
            if let displays = gpu["spdisplays_ndrvs"] as? [[String: Any]] {
                for (j, d) in displays.enumerated() {
                    rows.append(("Display \(j + 1)",
                                 "\(d["_name"] as? String ?? "—") · \(d["_spdisplays_resolution"] as? String ?? "—")"))
                }
            }
            out.append(HardwareSection(
                id: "gpu-\(idx)",
                title: "Graphics",
                icon: "display",
                rows: rows
            ))
        }
        return out
    }

    private nonisolated func parseNetwork(_ root: [String: Any]) -> HardwareSection {
        let items = (root["SPNetworkDataType"] as? [[String: Any]]) ?? []
        let active = items.filter { ($0["ip_address"] as? [String])?.isEmpty == false }
        let rows: [(String, String)] = active.prefix(6).map { iface in
            let name = iface["_name"] as? String ?? "—"
            let ips = (iface["ip_address"] as? [String])?.joined(separator: ", ") ?? "—"
            return (name, ips)
        }
        return HardwareSection(
            id: "net",
            title: "Network",
            icon: "network",
            rows: rows.isEmpty ? [("(no active interface)", "")] : rows
        )
    }

    private nonisolated func parseSoftware(_ root: [String: Any]) -> HardwareSection {
        let items = (root["SPSoftwareDataType"] as? [[String: Any]]) ?? []
        let item = items.first ?? [:]
        return HardwareSection(
            id: "sw",
            title: "Software",
            icon: "info.circle",
            rows: [
                ("OS Version",   item["os_version"] as? String ?? "—"),
                ("Kernel",       item["kernel_version"] as? String ?? "—"),
                ("Uptime",       item["uptime"] as? String ?? "—"),
                ("Boot Volume",  item["boot_volume"] as? String ?? "—"),
                ("Computer",     item["local_host_name"] as? String ?? "—"),
            ]
        )
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
final class HardwareInventoryModel: ObservableObject {
    @Published var sections: [HardwareSection] = []
    @Published var isLoading = false
    private let reader = HardwareInventoryReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.sections = await reader.read()
    }
}

struct HardwareInventoryView: View {
    @StateObject private var model = HardwareInventoryModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.sections.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hardware Inventory")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("system_profiler-Daten in lesbar. CPU, Memory, Storage, GPU, Network, OS.")
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
        if model.isLoading && model.sections.isEmpty {
            ProgressView("Reading hardware…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(model.sections) { sect in
                        sectionCard(sect)
                    }
                }
                .padding(20)
            }
        }
    }

    private func sectionCard(_ s: HardwareSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: s.icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(s.title)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top) {
                    Text(pair.0)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text(pair.1)
                        .font(MD4.Typo.tabular(MD4.Typo.small))
                        .foregroundStyle(MD4.SemColor.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    HardwareInventoryView()
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}
