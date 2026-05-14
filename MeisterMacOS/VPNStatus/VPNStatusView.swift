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
    func read() async -> VPNStatusInfo {
        // scutil --nwi prints active network interfaces; VPN tunnels show as utun*/ipsec*/tap*
        let nwi = run("/usr/sbin/scutil", ["--nwi"])
        let primary = parsePrimaryInterface(nwi)
        let isVPN = primary.map { isLikelyVPN(name: $0) } ?? false

        // DNS servers
        let dnsRaw = run("/usr/sbin/scutil", ["--dns"])
        let dns = parseDNS(dnsRaw)

        // External IP — best-effort, doesn't make a network call
        let externalIP: String? = nil

        return VPNStatusInfo(
            isConnected: isVPN,
            interfaceName: primary,
            primaryService: parsePrimaryService(nwi),
            dnsServers: Array(dns.prefix(5)),
            externalIP: externalIP,
            raw: nwi
        )
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
                out.append(String(v))
            }
        }
        return out
    }

    nonisolated func isLikelyVPN(name: String) -> Bool {
        let prefixes = ["utun", "ipsec", "tap", "tun", "ppp", "wg"]
        return prefixes.contains { name.hasPrefix($0) }
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
final class VPNStatusModel: ObservableObject {
    @Published var info: VPNStatusInfo?
    @Published var isLoading = false
    private let reader = VPNStatusReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.info = await reader.read()
    }
}

struct VPNStatusView: View {
    @StateObject private var model = VPNStatusModel()

    var body: some View {
        VStack(spacing: 0) {
            header
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
                Text("scutil --nwi + --dns. Primärinterface, DNS-Server, Tunnel-Detection.")
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
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusCard(_ i: VPNStatusInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: i.isConnected ? "lock.shield.fill" : "lock.open")
                .foregroundStyle(i.isConnected ? MD4.SemColor.success : MD4.SemColor.textSecondary)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.isConnected ? "VPN aktiv" : "Kein VPN")
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
