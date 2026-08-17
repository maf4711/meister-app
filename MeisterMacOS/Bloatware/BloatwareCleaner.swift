import Foundation
import AppKit

/// Quarantines selected bloat findings under ~/.meister/bloatware-quarantine/YYYYMMDD.
/// Never touches KEEP items (caller filters). System LaunchAgents under /Library skipped.
@MainActor
final class BloatwareCleaner {
    private let fileManager: FileManager
    private let home: URL

    init(fileManager: FileManager = .default,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.home = home
    }

    func quarantineRoot() -> URL {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        let stamp = fmt.string(from: Date())
        return home
            .appendingPathComponent(".meister/bloatware-quarantine/\(stamp)", isDirectory: true)
    }

    func kill(_ findings: [BloatFinding]) async throws -> BloatKillManifest {
        let qRoot = quarantineRoot()
        try fileManager.createDirectory(at: qRoot, withIntermediateDirectories: true)

        var entries: [BloatKillManifest.Entry] = []
        var okCount = 0

        for f in findings {
            let (ok, err) = await killOne(f, quarantine: qRoot)
            if ok { okCount += 1 }
            entries.append(.init(
                kind: f.kind.rawValue,
                severity: f.severity.rawValue,
                name: f.name,
                path: f.path,
                quarantined: ok,
                error: err
            ))
        }

        let manifest = BloatKillManifest(
            timestamp: Date(),
            entries: entries,
            quarantinedCount: okCount
        )
        try writeManifest(manifest)
        return manifest
    }

    private func killOne(_ f: BloatFinding, quarantine: URL) async -> (Bool, String?) {
        switch f.kind {
        case .launchAgent:
            if f.path.hasPrefix("/Library/") {
                return (false, "system LaunchAgent — needs admin")
            }
            bootout(plist: f.path)
            return moveAside(URL(fileURLWithPath: f.path), into: quarantine)

        case .app:
            let url = URL(fileURLWithPath: f.path)
            // Prefer Trash (reversible via Finder)
            let recycled = await recycle(url)
            if recycled.0 { return recycled }
            let apps = quarantine.appendingPathComponent("Apps", isDirectory: true)
            try? fileManager.createDirectory(at: apps, withIntermediateDirectories: true)
            return moveAside(url, into: apps)

        case .brewCask:
            return uninstallBrewCask(f.name)

        case .supportDir:
            let support = quarantine.appendingPathComponent("Support", isDirectory: true)
            try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            return moveAside(URL(fileURLWithPath: f.path), into: support)

        case .loginItem:
            return removeLoginItem(f.name)
        }
    }

    private func bootout(plist: String) {
        let uid = getuid()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(uid)", plist]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let u = Process()
            u.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            u.arguments = ["unload", plist]
            u.standardOutput = Pipe()
            u.standardError = Pipe()
            try? u.run()
            u.waitUntilExit()
        }
    }

    private func moveAside(_ src: URL, into dir: URL) -> (Bool, String?) {
        guard fileManager.fileExists(atPath: src.path) else {
            return (false, "path gone")
        }
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        var final = dest
        if fileManager.fileExists(atPath: final.path) {
            final = dir.appendingPathComponent("\(src.lastPathComponent).\(UUID().uuidString.prefix(8))")
        }
        do {
            try fileManager.moveItem(at: src, to: final)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func recycle(_ url: URL) async -> (Bool, String?) {
        await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle([url]) { _, error in
                cont.resume(returning: (error == nil, error?.localizedDescription))
            }
        }
    }

    private func uninstallBrewCask(_ name: String) -> (Bool, String?) {
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            fileManager.isExecutableFile(atPath: $0)
        }
        guard let brew else { return (false, "brew not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["uninstall", "--cask", name]
        let err = Pipe()
        p.standardOutput = Pipe()
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        if p.terminationStatus == 0 { return (true, nil) }
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        return (false, msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "brew failed")
    }

    private func removeLoginItem(_ name: String) -> (Bool, String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = [
            "-e",
            "tell application \"System Events\" to delete login item \"\(name.replacingOccurrences(of: "\"", with: "\\\""))\""
        ]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        return p.terminationStatus == 0 ? (true, nil) : (false, "osascript failed")
    }

    private func writeManifest(_ manifest: BloatKillManifest) throws {
        let dir = home.appendingPathComponent(
            "Library/Application Support/Meister/bloatware", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: manifest.timestamp).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }
}
