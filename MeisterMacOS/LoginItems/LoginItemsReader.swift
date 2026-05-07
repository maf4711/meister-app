import Foundation

enum LoginItemKind: String {
    case loginItem      // Service Management / sfltool
    case launchAgentUser
    case launchAgentSystem
    case launchDaemon
}

struct LoginItem: Identifiable, Hashable {
    let id: String
    let label: String
    let path: String?
    let kind: LoginItemKind
    let teamID: String?
    let enabled: Bool
}

actor LoginItemsReader {

    func readAll() async -> [LoginItem] {
        async let loginItems = backgroundTaskManagementItems()
        async let userAgents = launchPlists(in: "~/Library/LaunchAgents", kind: .launchAgentUser)
        async let sysAgents  = launchPlists(in: "/Library/LaunchAgents",  kind: .launchAgentSystem)
        async let daemons    = launchPlists(in: "/Library/LaunchDaemons", kind: .launchDaemon)
        let all = await loginItems + userAgents + sysAgents + daemons
        return all.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    /// `sfltool dumpbtm` — Background Task Management (macOS 13+).
    private func backgroundTaskManagementItems() async -> [LoginItem] {
        let raw = run("/usr/bin/sfltool", ["dumpbtm"])
        return parseSfltool(raw)
    }

    /// Parse `sfltool dumpbtm` plain-text output into LoginItem rows.
    nonisolated func parseSfltool(_ raw: String) -> [LoginItem] {
        var out: [LoginItem] = []
        var currentLabel: String?
        var currentPath: String?
        var currentTeam: String?
        var currentDisposition: String?

        func flush() {
            if let label = currentLabel {
                let enabled = (currentDisposition ?? "").lowercased().contains("enabled")
                out.append(LoginItem(
                    id: "btm:\(label):\(currentPath ?? "")",
                    label: label,
                    path: currentPath,
                    kind: .loginItem,
                    teamID: currentTeam,
                    enabled: enabled
                ))
            }
            currentLabel = nil
            currentPath = nil
            currentTeam = nil
            currentDisposition = nil
        }

        for line in raw.split(separator: "\n").map(String.init) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("UUID:") || stripped.hasPrefix("Item-") {
                flush()
            } else if let r = stripped.range(of: "Name:") {
                currentLabel = String(stripped[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if stripped.hasPrefix("Executable Path:") {
                currentPath = String(stripped.dropFirst("Executable Path:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if stripped.hasPrefix("Team Identifier:") {
                currentTeam = String(stripped.dropFirst("Team Identifier:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if stripped.hasPrefix("Disposition:") {
                currentDisposition = String(stripped.dropFirst("Disposition:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return out
    }

    /// List `.plist` files in a launch directory and parse their `Label` + `ProgramArguments`.
    private func launchPlists(in pathString: String, kind: LoginItemKind) async -> [LoginItem] {
        let expanded = (pathString as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return [] }

        let entries = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { plistURL -> LoginItem? in
            guard plistURL.pathExtension == "plist",
                  let data = try? Data(contentsOf: plistURL),
                  let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = any as? [String: Any] else { return nil }
            let label = (dict["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
            let program = (dict["Program"] as? String)
                ?? (dict["ProgramArguments"] as? [String])?.first
            let disabled = (dict["Disabled"] as? Bool) ?? false
            return LoginItem(
                id: "\(kind.rawValue):\(label):\(plistURL.path)",
                label: label,
                path: program ?? plistURL.path,
                kind: kind,
                teamID: nil,
                enabled: !disabled
            )
        }
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
