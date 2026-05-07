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
        let on = out.lowercased().contains("filevault is on")
        return SecurityCheck(
            id: "filevault",
            title: "FileVault",
            state: on ? .ok("Aktiv") : .bad("Aus — Disk unverschlüsselt"),
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: on ? nil : .init(
                label: "FileVault einschalten",
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault")!
            )
        )
    }

    private func firewall() async -> SecurityCheck {
        let out = run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        let on = out.lowercased().contains("enabled")
        return SecurityCheck(
            id: "firewall",
            title: "Firewall",
            state: on ? .ok("Aktiv") : .warn("Aus"),
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: on ? nil : .init(
                label: "Firewall öffnen",
                url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Firewall")!
            )
        )
    }

    private func gatekeeper() async -> SecurityCheck {
        let out = run("/usr/sbin/spctl", ["--status"])
        let on = out.lowercased().contains("assessments enabled")
        return SecurityCheck(
            id: "gatekeeper",
            title: "Gatekeeper",
            state: on ? .ok("Aktiv") : .bad("Aus — beliebige Apps können starten"),
            detail: out.trimmingCharacters(in: .whitespacesAndNewlines),
            action: nil
        )
    }

    private func systemIntegrityProtection() async -> SecurityCheck {
        let out = run("/usr/bin/csrutil", ["status"])
        let on = out.lowercased().contains("enabled")
        return SecurityCheck(
            id: "sip",
            title: "System Integrity Protection",
            state: on ? .ok("Aktiv") : .warn("Aus — System ungeschützt"),
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
            state: .ok(version),
            detail: nil,
            action: nil
        )
    }

    /// Count files in ~/Downloads and ~/Desktop with a quarantine xattr.
    private func quarantineFlagsCount() async -> SecurityCheck {
        let count = countQuarantineFiles()
        let state: SecurityState = count == 0
            ? .ok("0 Dateien")
            : .warn("\(count) Datei\(count == 1 ? "" : "en")")
        return SecurityCheck(
            id: "quarantine",
            title: "Quarantine-Flags in ~/Downloads + ~/Desktop",
            state: state,
            detail: count == 0 ? nil : "Aus dem Web heruntergeladen, noch nicht von Gatekeeper geprüft.",
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

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
