import SwiftUI
import MeradOSDesign3

struct SSDInfo: Identifiable, Hashable {
    let id: String           // device node, e.g. /dev/disk0
    let name: String
    let media: String        // SSD / HDD / Other
    let protocolName: String // PCIe, SATA, USB, Thunderbolt
    let smart: SMARTStatus
    let totalBytes: Int64
    let isInternal: Bool
    let removable: Bool

    enum SMARTStatus: String {
        case verified, failing, notSupported, unknown
    }
}

actor SSDHealthReader {
    func read() async -> [SSDInfo] {
        // Get list of all whole-disk identifiers via diskutil list -plist
        let listRaw = run("/usr/sbin/diskutil", ["list", "-plist", "physical"])
        guard let listData = listRaw.data(using: .utf8),
              let listAny = try? PropertyListSerialization.propertyList(from: listData, format: nil),
              let listDict = listAny as? [String: Any],
              let disks = listDict["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }

        return disks.compactMap { entry -> SSDInfo? in
            guard let id = entry["DeviceIdentifier"] as? String else { return nil }
            return inspect(devID: id)
        }
    }

    private nonisolated func inspect(devID: String) -> SSDInfo? {
        let raw = run("/usr/sbin/diskutil", ["info", "-plist", devID])
        guard let data = raw.data(using: .utf8),
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let d = any as? [String: Any] else { return nil }

        let name = d["IORegistryEntryName"] as? String
                ?? d["MediaName"] as? String
                ?? devID
        let media: String = {
            if (d["SolidState"] as? Bool) == true { return "SSD" }
            if let m = d["MediaType"] as? String { return m }
            return "—"
        }()
        let proto = d["BusProtocol"] as? String ?? "—"
        let smartRaw = (d["SMARTStatus"] as? String) ?? "Unsupported"
        let smart: SSDInfo.SMARTStatus = {
            switch smartRaw {
            case "Verified": return .verified
            case "Failing":  return .failing
            case "Not Supported", "NotSupported": return .notSupported
            default: return .unknown
            }
        }()
        let total = (d["TotalSize"] as? Int64) ??
            Int64((d["TotalSize"] as? NSNumber)?.int64Value ?? 0)
        let isInternal = (d["Internal"] as? Bool) ?? false
        let removable = (d["Removable"] as? Bool) ?? false

        return SSDInfo(
            id: devID,
            name: name,
            media: media,
            protocolName: proto,
            smart: smart,
            totalBytes: total,
            isInternal: isInternal,
            removable: removable
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
final class SSDHealthModel: ObservableObject {
    @Published var disks: [SSDInfo] = []
    @Published var isLoading = false
    private let reader = SSDHealthReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.disks = await reader.read()
    }
}

struct SSDHealthView: View {
    @StateObject private var model = SSDHealthModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.disks.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Health")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("S.M.A.R.T.-Status pro Disk via diskutil. Verified = OK, Failing = sofort Backup + Disk-Tausch.")
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
        if model.isLoading && model.disks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.disks.isEmpty {
            ContentUnavailableView("Keine Disks gefunden",
                                   systemImage: "externaldrive.badge.questionmark")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(model.disks) { disk in
                        diskCard(disk)
                    }
                }
                .padding(20)
            }
        }
    }

    private func diskCard(_ d: SSDInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: d.isInternal ? "internaldrive" : "externaldrive")
                    .foregroundStyle(MD3.SemColor.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name)
                        .font(MD3.Typo.headline)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    Text("\(d.id) · \(d.media) · \(d.protocolName)")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
                Spacer()
                smartBadge(d.smart)
            }
            HStack {
                stat("Größe", d.totalBytes.humanBytes)
                stat("Position", d.isInternal ? "intern" : (d.removable ? "wechselbar" : "extern"))
                stat("Bus", d.protocolName)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func smartBadge(_ s: SSDInfo.SMARTStatus) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch s {
            case .verified:     return ("Verified", MD3.SemColor.success, "checkmark.shield.fill")
            case .failing:      return ("Failing — Backup + Tausch", MD3.SemColor.error, "exclamationmark.triangle.fill")
            case .notSupported: return ("kein S.M.A.R.T.", MD3.SemColor.textTertiary, "questionmark.circle")
            case .unknown:      return ("unbekannt", MD3.SemColor.textTertiary, "questionmark.circle")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(MD3.Typo.caption.bold())
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
            Text(value)
                .font(MD3.Typo.tabular(MD3.Typo.body))
                .foregroundStyle(MD3.SemColor.textPrimary)
        }
        .padding(.trailing, 16)
    }
}
