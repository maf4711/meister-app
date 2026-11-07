import SwiftUI
import MeradOSDesign4

struct VPNStatusInfo: Equatable {
    let isConnected: Bool
    let interfaceName: String?
    let primaryService: String?
    let dnsServers: [String]
    let externalIP: String?
    let raw: String
}

actor VPNStatusReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<VPNStatusInfo> {
        let network = command("/usr/sbin/scutil", ["--nwi"])
        if let issue = network.issue(source: "Netzwerk-Tunnel") { return .init(value: nil, issues: [issue]) }
        let nwi = network.output
        guard nwi.contains("Network interfaces:") || nwi.contains("No network information") else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Netzwerk-Tunnel")])
        }
        let dns = command("/usr/sbin/scutil", ["--dns"])
        var issues = dns.issue(source: "DNS-Server").map { [$0] } ?? []
        if dns.succeeded && !dns.output.contains("DNS configuration") {
            issues.append(.init(kind: .invalidOutput, source: "DNS-Server"))
        }
        let interfaces = nwi.split(separator: "\n").filter { $0.contains("Network interfaces:") }
            .flatMap { $0.split(separator: ":", maxSplits: 1).last?.split(whereSeparator: { $0.isWhitespace }).map(String.init) ?? [] }
        let tunnel = interfaces.first { isLikelyVPN(name: $0) }
        return .init(value: VPNStatusInfo(isConnected: tunnel != nil,
            interfaceName: tunnel ?? parsePrimaryInterface(nwi), primaryService: parsePrimaryService(nwi),
            dnsServers: dns.succeeded ? Array(parseDNS(dns.output).prefix(5)) : [], externalIP: nil, raw: nwi), issues: issues)
    }

    nonisolated func parsePrimaryInterface(_ raw: String) -> String? {
        // Look for line "Network interfaces: utun4 en0 ..."
        for line in raw.split(separator: "\n") {
            if line.contains("Network interfaces:") {
                return line.split(separator: ":", maxSplits: 1).last?
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .first.map(String.init)
            }
        }
        return nil
    }

    nonisolated func parsePrimaryService(_ raw: String) -> String? {
        for line in raw.split(separator: "\n") {
            if line.contains("REACH : flags") { return nil }
            if line.lowercased().contains("primary interface") {
                return String(line)
            }
        }
        return nil
    }

    nonisolated func parseDNS(_ raw: String) -> [String] {
        var out: [String] = []
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("nameserver["), let r = s.range(of: ":") {
                let v = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !v.isEmpty && !out.contains(String(v)) { out.append(String(v)) }
            }
        }
        return out
    }

    nonisolated func isLikelyVPN(name: String) -> Bool {
        let prefixes = ["utun", "ipsec", "tap", "tun", "ppp", "wg"]
        return prefixes.contains { name.hasPrefix($0) }
    }

}

@MainActor
final class VPNStatusModel: ObservableObject {
    @Published var info: VPNStatusInfo?
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var isLoading = false
    private let reader = VPNStatusReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        self.info = report.value
        issues = report.issues
        lastChecked = report.timestamp
    }
}

struct VPNStatusView: View {
    @StateObject private var model = VPNStatusModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.info == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("VPN Status")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Lokale Tunnel-Erkennung. Kein Nachweis für VPN-Schutz oder vollständige Verkehrsweiterleitung.")
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
        if let i = model.info {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard(i)
                    detailCard(i)
                }
                .padding(20)
            }
        } else if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Netzwerkstatus nicht verfügbar", systemImage: "network")
        }
    }

    private func statusCard(_ i: VPNStatusInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "network")
                .foregroundStyle(MD4.SemColor.textSecondary)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.isConnected ? "Tunnel erkannt" : "Kein Tunnel erkannt")
                    .font(MD4.Typo.title3)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                if let iface = i.interfaceName {
                    Text("Interface: \(iface)")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailCard(_ i: VPNStatusInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNS Server")
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            if i.dnsServers.isEmpty {
                Text("—")
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            } else {
                ForEach(i.dnsServers, id: \.self) { dns in
                    HStack {
                        Image(systemName: "globe").foregroundStyle(MD4.SemColor.brandPrimary)
                        Text(dns)
                            .font(MD4.Typo.tabular(MD4.Typo.body))
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
