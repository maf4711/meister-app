import Foundation

/// Read-only scan for catalog bloat. Injectable home for tests.
struct BloatwareScanner: Sendable {
    let home: URL
    /// Extra app roots for tests (defaults: /Applications + ~/Applications).
    let applicationRoots: [URL]
    /// Optional brew list injector (tests). Default shells out to `brew list --cask`.
    let brewCaskProvider: @Sendable () -> [String]
    /// Optional login-item name injector.
    let loginItemProvider: @Sendable () -> [String]

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationRoots: [URL]? = nil,
        brewCaskList: (@Sendable () -> [String])? = nil,
        loginItemNames: (@Sendable () -> [String])? = nil
    ) {
        self.home = home
        self.applicationRoots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
        self.brewCaskProvider = brewCaskList ?? { Self.runBrewListCask() }
        self.loginItemProvider = loginItemNames ?? { Self.readLoginItems() }
    }

    private var fileManager: FileManager { .default }

    func scanAll() -> [BloatFinding] {
        let ignore = BloatCatalog.loadIgnoreLines(home: home, fileManager: fileManager)
        var findings: [BloatFinding] = []
        findings.append(contentsOf: scanApps(ignore: ignore))
        findings.append(contentsOf: scanAgents(ignore: ignore))
        findings.append(contentsOf: scanBrew(ignore: ignore))
        findings.append(contentsOf: scanSupport(ignore: ignore))
        findings.append(contentsOf: scanLogin(ignore: ignore))

        // Dedupe by id
        var seen = Set<String>()
        var unique: [BloatFinding] = []
        for f in findings {
            if seen.insert(f.id).inserted {
                unique.append(f)
            }
        }
        return unique.sorted {
            if $0.severity != $1.severity { return $0.severity < $1.severity }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Apps

    private func scanApps(ignore: [String]) -> [BloatFinding] {
        var out: [BloatFinding] = []
        for root in applicationRoots {
            guard fileManager.fileExists(atPath: root.path),
                  let kids = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for kid in kids where kid.pathExtension == "app" {
                let name = kid.deletingPathExtension().lastPathComponent
                guard let sev = BloatCatalog.severity(for: name, ignoreFileLines: ignore) else { continue }
                out.append(BloatFinding(
                    kind: .app,
                    severity: sev,
                    name: name,
                    path: kid.path,
                    detail: "Application bundle",
                    bytes: sizeOf(kid)
                ))
            }
        }
        return out
    }

    // MARK: - LaunchAgents

    private func scanAgents(ignore: [String]) -> [BloatFinding] {
        var out: [BloatFinding] = []
        let dirs = [
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
        ]
        for dir in dirs {
            guard fileManager.fileExists(atPath: dir.path),
                  let kids = try? fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for plist in kids where plist.pathExtension == "plist" {
                let base = plist.lastPathComponent
                if base.lowercased().contains("disabled") { continue }
                let prog = programPath(from: plist)
                if BloatCatalog.isKeep(base, ignoreFileLines: ignore) { continue }
                if let prog, BloatCatalog.isKeep(prog, ignoreFileLines: ignore) { continue }

                // Orphan: absolute program path missing → always P0 (unless KEEP above)
                if let prog, prog.hasPrefix("/"), !fileManager.fileExists(atPath: prog) {
                    out.append(BloatFinding(
                        kind: .launchAgent,
                        severity: .p0,
                        name: base,
                        path: plist.path,
                        detail: "ORPHAN: missing binary: \(prog)",
                        bytes: sizeOf(plist)
                    ))
                    continue
                }

                var sev = BloatCatalog.severity(for: base, ignoreFileLines: ignore)
                if sev == nil, let prog {
                    sev = BloatCatalog.severity(for: prog, ignoreFileLines: ignore)
                }
                guard let sev else { continue }
                out.append(BloatFinding(
                    kind: .launchAgent,
                    severity: sev,
                    name: base,
                    path: plist.path,
                    detail: "Program: \(prog ?? "unknown")",
                    bytes: sizeOf(plist)
                ))
            }
        }
        return out
    }

    private func programPath(from plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        if let p = obj["Program"] as? String, !p.isEmpty { return p }
        if let args = obj["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
            return first
        }
        return nil
    }

    // MARK: - Brew

    private func scanBrew(ignore: [String]) -> [BloatFinding] {
        brewCaskProvider().compactMap { cask in
            guard let sev = BloatCatalog.severity(for: cask, ignoreFileLines: ignore) else { return nil }
            return BloatFinding(
                kind: .brewCask,
                severity: sev,
                name: cask,
                path: "brew:cask:\(cask)",
                detail: "Homebrew cask",
                bytes: 0
            )
        }
    }

    private static func runBrewListCask() -> [String] {
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let brew else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["list", "--cask"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Application Support leftovers

    private func scanSupport(ignore: [String]) -> [BloatFinding] {
        let root = home.appendingPathComponent("Library/Application Support")
        guard fileManager.fileExists(atPath: root.path),
              let kids = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var out: [BloatFinding] = []
        for d in kids {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = d.lastPathComponent
            if BloatCatalog.supportSkip.contains(name) { continue }
            if name.hasPrefix("Apple") || name.hasPrefix("com.apple") || name.hasPrefix("iCloud") {
                continue
            }
            guard let sev = BloatCatalog.severity(for: name, ignoreFileLines: ignore) else { continue }
            // Still has matching app? Skip.
            if appExistsMatching(name: name) { continue }
            let bytes = sizeOf(d)
            out.append(BloatFinding(
                kind: .supportDir,
                severity: sev,
                name: name,
                path: d.path,
                detail: "Leftover Application Support (\(bytes.humanBytes))",
                bytes: bytes
            ))
        }
        return out
    }

    private func appExistsMatching(name: String) -> Bool {
        for root in applicationRoots {
            if fileManager.fileExists(atPath: root.appendingPathComponent("\(name).app").path) {
                return true
            }
            // fuzzy: any app containing name
            guard let kids = try? fileManager.contentsOfDirectory(atPath: root.path) else { continue }
            if kids.contains(where: { $0.localizedCaseInsensitiveContains(name) && $0.hasSuffix(".app") }) {
                return true
            }
        }
        return false
    }

    // MARK: - Login items

    private func scanLogin(ignore: [String]) -> [BloatFinding] {
        loginItemProvider().compactMap { name in
            guard let sev = BloatCatalog.severity(for: name, ignoreFileLines: ignore) else { return nil }
            return BloatFinding(
                kind: .loginItem,
                severity: sev,
                name: name,
                path: "login-item:\(name)",
                detail: "Login item",
                bytes: 0
            )
        }
    }

    private static func readLoginItems() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to get the name of every login item"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return [] }
        return text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: - size

    private func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(vals?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let vals = try? file.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(vals?.fileSize ?? 0)
        }
        return total
    }
}
