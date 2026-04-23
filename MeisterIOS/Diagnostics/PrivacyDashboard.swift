import Foundation

/// Heuristic privacy status indicators. Apple exposes very little programmatically —
/// for VPN we scan local interfaces (utun/ipsec/ppp), for Private Relay we hit a
/// Cloudflare endpoint that echoes a special header only present when relay is active.
enum PrivacyDashboard {
    struct Indicator: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let state: State
        let detail: String
    }

    enum State { case on, off, unknown }

    /// VPN detection: scan network interfaces for typical VPN prefixes.
    static func vpnActive() -> Bool {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return false }
        defer { freeifaddrs(addresses) }
        var interface: UnsafeMutablePointer<ifaddrs>? = first
        while interface != nil {
            if let cName = interface?.pointee.ifa_name {
                let name = String(cString: cName)
                if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tap") {
                    return true
                }
            }
            interface = interface?.pointee.ifa_next
        }
        return false
    }

    /// Ask Cloudflare's trace endpoint — the `warp=` line reports relay state.
    static func privateRelayActive() async -> State {
        guard let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace") else { return .unknown }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else { return .unknown }
            for line in text.split(separator: "\n") {
                if line.hasPrefix("warp=") {
                    return line.contains("=on") ? .on : .off
                }
            }
            return .unknown
        } catch {
            return .unknown
        }
    }

    static func snapshot() async -> [Indicator] {
        let vpn = vpnActive()
        let relay = await privateRelayActive()

        return [
            Indicator(
                title: "VPN",
                systemImage: "lock.shield",
                state: vpn ? .on : .off,
                detail: vpn ? "Interface detected" : "No VPN interface active"
            ),
            Indicator(
                title: "iCloud Private Relay",
                systemImage: "cloud",
                state: relay,
                detail: relayDetail(relay)
            ),
            Indicator(
                title: "Face ID / Touch ID",
                systemImage: "faceid",
                state: .unknown,
                detail: "Managed by iOS — Settings → Face ID & Passcode"
            ),
        ]
    }

    private static func relayDetail(_ state: State) -> String {
        switch state {
        case .on: "Active — Safari traffic is double-hopped via Cloudflare"
        case .off: "Not active"
        case .unknown: "Unable to determine"
        }
    }
}
