import SwiftUI
import AppKit
import MeradOSDesign4

struct WiFiNetwork: Identifiable, Hashable {
    let id: String       // SSID
    let ssid: String
    let security: String
    let lastJoined: Date?
}

actor WiFiPasswordsReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<[WiFiNetwork]> {
        let ports = command("/usr/sbin/networksetup", ["-listallhardwareports"])
        if let issue = ports.issue(source: "WLAN-Hardware") { return .init(value: nil, issues: [issue]) }
        guard let device = Self.wirelessDevice(in: ports.output) else {
            if ports.output.contains("Hardware Port:") { return .init(value: nil, issues: [.init(kind: .unavailable, source: "WLAN-Hardware")]) }
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "WLAN-Hardware")])
        }
        let result = command("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", device])
        if let issue = result.issue(source: "Gespeicherte WLANs") { return .init(value: nil, issues: [issue]) }
        guard result.output.contains("Preferred networks on ") else {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Gespeicherte WLANs")])
        }
        return .init(value: parse(result.output))
    }

    nonisolated static func wirelessDevice(in output: String) -> String? {
        var wireless = false
        for line in output.split(separator: "\n") {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("Hardware Port:") {
                wireless = value.contains("Wi-Fi") || value.contains("AirPort")
            } else if wireless && value.hasPrefix("Device:") {
                return value.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    nonisolated func parse(_ raw: String) -> [WiFiNetwork] {
        guard raw.contains("Preferred networks on ") else { return [] }
        var out: [WiFiNetwork] = []
        for line in raw.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("Preferred networks") || s.isEmpty { continue }
            let ssid = s.trimmingCharacters(in: .whitespaces)
            guard !ssid.isEmpty else { continue }
            out.append(WiFiNetwork(
                id: ssid,
                ssid: ssid,
                security: "—",
                lastJoined: nil
            ))
        }
        return out.sorted { $0.ssid.lowercased() < $1.ssid.lowercased() }
    }

    /// Fetch password from the System keychain. Apple shows a sudo prompt
    /// for AirPort items by default; the user must approve once per query.
    func password(for ssid: String) async -> String? {
        let result = CommandRunner.run("/usr/bin/security", ["find-generic-password", "-D", "AirPort network password", "-a", ssid, "-w"])
        guard result.succeeded else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

@MainActor
final class WiFiPasswordsModel: ObservableObject {
    @Published var networks: [WiFiNetwork] = []
    @Published var revealed: [String: String] = [:]   // ssid → password
    @Published var isLoading = false
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var lastError: String?
    private let reader = WiFiPasswordsReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        revealed.removeAll()
        let report = await reader.read()
        networks = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }

    func reveal(_ ssid: String) async {
        if let pw = await reader.password(for: ssid) {
            revealed[ssid] = pw
        } else {
            lastError = "Konnte Passwort für \(ssid) nicht aus Keychain lesen — Mac-Login-Passwort wird abgefragt, ggf. abgebrochen."
        }
    }

    func copy(_ pw: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(pw, forType: .string)
    }
}

struct WiFiPasswordsView: View {
    @StateObject private var model = WiFiPasswordsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.networks.isEmpty { await model.reload() } }
        .alert("Fehler",
               isPresented: Binding(get: { model.lastError != nil },
                                    set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wi-Fi Networks & Passwords")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Alle gespeicherten WLANs. Passwort sichtbar nach Mac-Login-Confirm pro Netz.")
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
        if model.isLoading && model.networks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.issues.isEmpty {
            ContentUnavailableView("WLAN-Liste nicht ermittelbar", systemImage: "wifi.exclamationmark")
        } else if model.networks.isEmpty {
            ContentUnavailableView("Keine WLANs gespeichert",
                                   systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.networks) { net in
                row(net)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ net: WiFiNetwork) -> some View {
        HStack {
            Image(systemName: "wifi")
                .foregroundStyle(MD4.SemColor.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(net.ssid)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                if let pw = model.revealed[net.ssid] {
                    HStack(spacing: 6) {
                        Text(pw)
                            .font(MD4.Typo.tabular(MD4.Typo.caption))
                            .foregroundStyle(MD4.SemColor.success)
                            .textSelection(.enabled)
                        Button {
                            model.copy(pw)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text("Passwort verborgen")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
            Spacer()
            if model.revealed[net.ssid] == nil {
                Button("Passwort zeigen") {
                    Task { await model.reveal(net.ssid) }
                }
            } else {
                Text("revealed")
                    .font(MD4.Typo.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD4.SemColor.success.opacity(0.2), in: Capsule())
                    .foregroundStyle(MD4.SemColor.success)
            }
        }
        .padding(.vertical, 2)
    }
}
