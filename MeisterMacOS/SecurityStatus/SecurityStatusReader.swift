import Foundation

enum SecurityState {
    case ok(String)        // green
    case warn(String)      // yellow
    case bad(String)       // red
    case unknown(String)   // gray
}

struct SecurityCheck: Identifiable, Hashable {
    let id: String
    let title: String
    let state: SecurityState
    let detail: String?
    let action: SecurityAction?

    static func == (lhs: SecurityCheck, rhs: SecurityCheck) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SecurityAction: Hashable {
    let label: String
    let url: URL  // x-apple.systempreferences:// deep link
}

actor SecurityStatusReader {

    func readCore() async -> [SecurityCheck] {
        async let fv = fileVault()
        async let fw = firewall()
        async let gk = gatekeeper()
        async let sip = systemIntegrityProtection()
        return await [fv, fw, gk, sip]
    }

    func readAll() async -> [SecurityCheck] {
        async let fv = fileVault()
        async let fw = firewall()
        async let gk = gatekeeper()
        async let sip = systemIntegrityProtection()
        async let xp  = xprotectVersion()
        async let qa  = quarantineFlagsCount()
        return await [fv, fw, gk, sip, xp, qa]
    }

    // MARK: - individual checks

    private func fileVault() async -> SecurityCheck {
        let out = run("/usr/bin/fdesetup", ["status"])
        let state = Self.parseState(out, enabled: "filevault is on", disabled: "filevault is off", critical: true)
        let needsAction: Bool = { switch state { case .warn, .bad: return true; default: return false } }()
        return SecurityCheck(
            id: "filevault",
            title: "FileVault",
            state: state,
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: !needsAction ? nil : .init(
                label: "FileVault einschalten",
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault")!
            )
        )
    }

    private func firewall() async -> SecurityCheck {
        let out = run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        let state = Self.parseState(out, enabled: "enabled", disabled: "disabled", critical: false)
        let needsAction: Bool = { switch state { case .warn, .bad: return true; default: return false } }()
        return SecurityCheck(
            id: "firewall",
            title: "Firewall",
            state: state,
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: !needsAction ? nil : .init(
                label: "Firewall öffnen",
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Firewall")!
            )
        )
    }

    private func gatekeeper() async -> SecurityCheck {
        let out = run("/usr/sbin/spctl", ["--status"])
        let state = Self.parseState(out, enabled: "assessments enabled", disabled: "assessments disabled", critical: true)
        return SecurityCheck(
            id: "gatekeeper",
            title: "Gatekeeper",
            state: state,
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: nil
        )
    }

    private func systemIntegrityProtection() async -> SecurityCheck {
        let out = run("/usr/bin/csrutil", ["status"])
        let state = Self.parseState(out, enabled: "enabled", disabled: "disabled", critical: false)
        return SecurityCheck(
            id: "sip",
            title: "System Integrity Protection",
            state: state,
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: nil
        )
    }

    private func xprotectVersion() async -> SecurityCheck {
        let plist = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist"
        var version = "unbekannt"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
           let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = any as? [String: Any],
           let v = dict["Version"] as? Int {
            version = "v\(v)"
        }
        return SecurityCheck(
            id: "xprotect",
            title: "XProtect (Apple AntiMalware)",
            state: version == "unbekannt" ? .unknown("Nicht ermittelt") : .ok(version),
            detail: nil,
            action: nil
        )
    }

    /// Count files in ~/Downloads and ~/Desktop with a quarantine xattr.
    private func quarantineFlagsCount() async -> SecurityCheck {
        let count = countQuarantineFiles()
        let state: SecurityState = count == 0
            ? .ok("0 Dateien")
            : .ok("\(count) Datei\(count == 1 ? "" : "en") mit Herkunftsmarkierung")
        return SecurityCheck(
            id: "quarantine",
            title: "Quarantine-Flags in ~/Downloads + ~/Desktop",
            state: state,
            detail: count == 0 ? nil : "Herkunftsmarkierungen sind Teil des macOS-Schutzes und kein Nachweis für Schadsoftware.",
            action: nil
        )
    }

    private nonisolated func countQuarantineFiles() -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scan = [home.appendingPathComponent("Downloads"),
                    home.appendingPathComponent("Desktop")]
        var count = 0
        for dir in scan {
            guard let it = FileManager.default.enumerator(at: dir,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let f as URL in it {
                if hasQuarantine(f) { count += 1 }
            }
        }
        return count
    }

    private nonisolated func hasQuarantine(_ url: URL) -> Bool {
        // getxattr length probe — returns -1 if attr missing.
        let path = url.path
        let attr = "com.apple.quarantine"
        let res = path.withCString { p in
            attr.withCString { a in
                getxattr(p, a, nil, 0, 0, 0)
            }
        }
        return res > 0
    }

    nonisolated static func parseState(_ output: String, enabled: String, disabled: String,
                                       critical: Bool) -> SecurityState {
        let value = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains(enabled) { return .ok("Aktiv") }
        if value.contains(disabled) { return critical ? .bad("Deaktiviert") : .warn("Deaktiviert") }
        return .unknown("Status nicht ermittelbar")
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let result = CommandRunner.run(tool, args)
        return result.output
    }
}
