import SwiftUI
import MeradOSDesign4

struct NetConnection: Identifiable, Hashable {
    let id: String
    let processName: String
    let pid: Int?
    let user: String
    let proto: String      // TCP / UDP
    let localAddress: String
    let remoteAddress: String?
    let state: String      // ESTABLISHED / LISTEN
}

actor NetworkConnectionsReader {
    /// `lsof -i -nP -F p,c,L,n,t` produces structured field-prefixed output.
    func read() async -> [NetConnection] {
        let raw = run("/usr/sbin/lsof", ["-i", "-nP", "-F", "pcLnTt"])
        return parse(raw)
    }

    /// lsof -F output format: each line starts with a field-letter:
    /// p<pid>, c<command>, L<user>, t<protocol>, n<addr-pair>, T<state>
    nonisolated func parse(_ raw: String) -> [NetConnection] {
        var out: [NetConnection] = []
        var pid: Int?
        var command: String = ""
        var user: String = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            guard let firstChar = s.first else { continue }
            let value = String(s.dropFirst())
            switch firstChar {
            case "p":
                pid = Int(value)
            case "c":
                command = value
            case "L":
                user = value
            case "n":
                // Network address pair like "*:9000" or "127.0.0.1:443->192.168.1.5:62320"
                let (proto, local, remote, state) = parseAddress(value)
                out.append(NetConnection(
                    id: "\(pid ?? 0):\(local):\(remote ?? "")",
                    processName: command,
                    pid: pid,
                    user: user,
                    proto: proto,
                    localAddress: local,
                    remoteAddress: remote,
                    state: state
                ))
            default:
                break
            }
        }
        return out.sorted {
            // Established connections first, then sort by process
            if ($0.state == "ESTABLISHED") != ($1.state == "ESTABLISHED") {
                return $0.state == "ESTABLISHED"
            }
            return $0.processName.lowercased() < $1.processName.lowercased()
        }
    }

    private nonisolated func parseAddress(_ raw: String) -> (proto: String, local: String, remote: String?, state: String) {
        // Possible formats:
        //  TCP 127.0.0.1:443
        //  TCP 127.0.0.1:443 (LISTEN)
        //  TCP 127.0.0.1:443->192.168.1.5:62320 (ESTABLISHED)
        //  UDP *:67
        var proto = "?"
        var rest = raw
        if rest.hasPrefix("TCP ") { proto = "TCP"; rest = String(rest.dropFirst(4)) }
        else if rest.hasPrefix("UDP ") { proto = "UDP"; rest = String(rest.dropFirst(4)) }

        // Strip "(STATE)" if present
        var state = "—"
        if let r = rest.range(of: " ("), let close = rest.range(of: ")") {
            state = String(rest[r.upperBound..<close.lowerBound])
            rest = String(rest[..<r.lowerBound])
        }

        // Split on "->"
        if let arrow = rest.range(of: "->") {
            let local = String(rest[..<arrow.lowerBound])
            let remote = String(rest[arrow.upperBound...])
            return (proto, local, remote, state)
        }
        return (proto, rest, nil, state)
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
final class NetworkConnectionsModel: ObservableObject {
    @Published var connections: [NetConnection] = []
    @Published var query: String = ""
    @Published var showOnlyEstablished = false
    @Published var isLoading = false
    private let reader = NetworkConnectionsReader()

    var filtered: [NetConnection] {
        var data = connections
        if showOnlyEstablished {
            data = data.filter { $0.state == "ESTABLISHED" }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            data = data.filter {
                $0.processName.lowercased().contains(q)
                    || $0.localAddress.lowercased().contains(q)
                    || ($0.remoteAddress ?? "").lowercased().contains(q)
            }
        }
        return data
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.connections = await reader.read()
    }
}

struct NetworkConnectionsView: View {
    @StateObject private var model = NetworkConnectionsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            controls
            Divider().background(MD4.SemColor.divider)
            list
        }
        .background(MD4.SemColor.background)
        .task { if model.connections.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Network Connections")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("lsof -i — wer hat grade welche Sockets offen.")
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

    private var controls: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MD4.SemColor.textSecondary)
                TextField("Filter…", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(MD4.SemColor.surfaceRaised, in: Capsule())
            Toggle("Nur ESTABLISHED", isOn: $model.showOnlyEstablished)
                .toggleStyle(.button)
            Spacer()
            Text("\(model.filtered.count) Verbindungen")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var list: some View {
        List(model.filtered) { c in
            HStack(spacing: 10) {
                Image(systemName: c.state == "ESTABLISHED" ? "arrow.left.arrow.right.circle.fill" : "circle.dotted")
                    .foregroundStyle(c.state == "ESTABLISHED" ? MD4.SemColor.success : MD4.SemColor.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(c.processName)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text("(\(c.pid.map(String.init) ?? "?"))")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textTertiary)
                    }
                    Text(c.localAddress + (c.remoteAddress.map { " → \($0)" } ?? ""))
                        .font(MD4.Typo.tabular(MD4.Typo.caption))
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(c.proto)
                    .font(MD4.Typo.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD4.SemColor.surfaceRaised, in: Capsule())
                    .foregroundStyle(MD4.SemColor.textSecondary)
                Text(c.state)
                    .font(MD4.Typo.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((c.state == "ESTABLISHED" ? MD4.SemColor.success : MD4.SemColor.textTertiary).opacity(0.18), in: Capsule())
                    .foregroundStyle(c.state == "ESTABLISHED" ? MD4.SemColor.success : MD4.SemColor.textTertiary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}
