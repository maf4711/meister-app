import Foundation
import AppKit

struct UninstallManifest: Codable {
    let timestamp: Date
    let app: AppRef
    let entries: [Entry]
    let totalReclaimedBytes: Int64

    struct AppRef: Codable {
        let bundleID: String?
        let displayName: String
        let version: String?
        let bundlePath: String
    }
    struct Entry: Codable {
        let source: String
        let path: String
        let bytes: Int64
        let recycled: Bool
        let error: String?
    }
}

@MainActor
final class UninstallerCleaner {
    private let fileManager: FileManager
    private let home: URL

    init(fileManager: FileManager = .default,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.home = home
    }

    /// Recycles the bundle and all selected leftovers. System-level
    /// LaunchDaemons in /Library/LaunchDaemons are skipped (admin needed).
    func uninstall(_ app: InstalledApp,
                   leftovers: [LeftoverItem]) async throws -> UninstallManifest {
        var entries: [UninstallManifest.Entry] = []
        var total: Int64 = 0

        // 1. The app bundle itself.
        let (bundleOK, bundleErr) = await recycle(app.bundleURL)
        if bundleOK { total += app.bundleSize }
        entries.append(.init(source: "Application",
                             path: app.bundleURL.path,
                             bytes: app.bundleSize,
                             recycled: bundleOK,
                             error: bundleErr))

        // 2. Every selected leftover. Skip /Library/LaunchDaemons — needs admin.
        for item in leftovers {
            if item.source == .launchDaemons,
               item.url.path.hasPrefix("/Library/LaunchDaemons") {
                entries.append(.init(source: item.source.rawValue,
                                     path: item.url.path,
                                     bytes: item.bytes,
                                     recycled: false,
                                     error: "system path — needs admin to remove"))
                continue
            }
            let (ok, err) = await recycle(item.url)
            if ok { total += item.bytes }
            entries.append(.init(source: item.source.rawValue,
                                 path: item.url.path,
                                 bytes: item.bytes,
                                 recycled: ok,
                                 error: err))
        }

        let manifest = UninstallManifest(
            timestamp: Date(),
            app: .init(bundleID: app.bundleID,
                       displayName: app.displayName,
                       version: app.version,
                       bundlePath: app.bundleURL.path),
            entries: entries,
            totalReclaimedBytes: total
        )
        try writeManifest(manifest)
        return manifest
    }

    private func recycle(_ url: URL) async -> (Bool, String?) {
        await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle([url]) { _, error in
                cont.resume(returning: (error == nil, error?.localizedDescription))
            }
        }
    }

    private func writeManifest(_ manifest: UninstallManifest) throws {
        let dir = home.appendingPathComponent(
            "Library/Application Support/Meister/uninstalls", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: manifest.timestamp).replacingOccurrences(of: ":", with: "-")
        let safeName = manifest.app.displayName.replacingOccurrences(of: "/", with: "_")
        let url = dir.appendingPathComponent("\(stamp)-\(safeName).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}
