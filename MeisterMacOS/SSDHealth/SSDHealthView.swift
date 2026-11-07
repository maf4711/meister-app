import SwiftUI
import MeradOSDesign4

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
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<[SSDInfo]> {
        let result = command("/usr/sbin/diskutil", ["list", "-plist", "physical"])
        if let issue = result.issue(source: "Datenträgerliste") { return .init(value: nil, issues: [issue]) }
        guard let listData = result.output.data(using: .utf8),
              let listDict = (try? PropertyListSerialization.propertyList(from: listData, format: nil)) as? [String: Any],
              let disks = listDict["AllDisksAndPartitions"] as? [[String: Any]] else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Datenträgerliste")])
        }
        var values: [SSDInfo] = []
        var issues: [DiagnosticIssue] = []
        for entry in disks {
            guard let id = entry["DeviceIdentifier"] as? String else {
                issues.append(.init(kind: .invalidOutput, source: "Datenträgerliste")); continue
            }
            let result = command("/usr/sbin/diskutil", ["info", "-plist", id])
            if let issue = result.issue(source: "Datenträgerdetails") { issues.append(issue); continue }
            guard let value = inspect(devID: id, raw: result.output) else {
                issues.append(.init(kind: .invalidOutput, source: "Datenträgerdetails")); continue
            }
            values.append(value)
        }
        return .init(value: values.isEmpty && !issues.isEmpty ? nil : values, issues: issues)
    }

    private nonisolated func inspect(devID: String, raw: String) -> SSDInfo? {
        guard let data = raw.data(using: .utf8),
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let d = any as? [String: Any], d["DeviceIdentifier"] as? String == devID,
              d["TotalSize"] is NSNumber else { return nil }

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
            case "Not Supported", "NotSupported", "Unsupported": return .notSupported
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

}

@MainActor
final class SSDHealthModel: ObservableObject {
    @Published var disks: [SSDInfo] = []
    @Published var isLoading = false
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    private let reader = SSDHealthReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        disks = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }
}

struct SSDHealthView: View {
    @StateObject private var model = SSDHealthModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.disks.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Health")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("S.M.A.R.T.-Status pro Disk via diskutil. Verified = OK, Failing = sofort Backup + Disk-Tausch.")
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
        if model.isLoading && model.disks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.disks.isEmpty {
            ContentUnavailableView(model.issues.isEmpty ? "Keine Disks gefunden" : "Datenträger nicht vollständig ermittelbar",
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
                    .foregroundStyle(MD4.SemColor.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name)
                        .font(MD4.Typo.headline)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Text("\(d.id) · \(d.media) · \(d.protocolName)")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
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
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func smartBadge(_ s: SSDInfo.SMARTStatus) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch s {
            case .verified:     return ("Verified", MD4.SemColor.success, "checkmark.shield.fill")
            case .failing:      return ("Failing — Backup + Tausch", MD4.SemColor.error, "exclamationmark.triangle.fill")
            case .notSupported: return ("kein S.M.A.R.T.", MD4.SemColor.textTertiary, "questionmark.circle")
            case .unknown:      return ("unbekannt", MD4.SemColor.textTertiary, "questionmark.circle")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(MD4.Typo.caption.bold())
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Text(value)
                .font(MD4.Typo.tabular(MD4.Typo.body))
                .foregroundStyle(MD4.SemColor.textPrimary)
        }
        .padding(.trailing, 16)
    }
}
