import Foundation
import AppKit

/// A user-installable app discovered under /Applications or ~/Applications.
/// Excludes system apps in /System/Applications (those are SIP-protected).
struct InstalledApp: Identifiable, Hashable {
    let bundleURL: URL
    let bundleID: String?
    let displayName: String
    let version: String?
    let iconPath: String?
    let bundleSize: Int64

    var id: String { bundleURL.path }

    /// Search tokens used to locate leftovers across ~/Library.
    /// Always includes the bundle ID (if present). Also includes the display
    /// name (matches apps that store data under their pretty name, e.g.
    /// "~/Library/Application Support/Sublime Text").
    var searchTokens: [String] {
        var tokens: [String] = []
        if let id = bundleID, !id.isEmpty { tokens.append(id) }
        tokens.append(displayName)
        return tokens
    }
}

@MainActor
enum InstalledAppDiscovery {
    /// Returns all .app bundles directly under /Applications and ~/Applications.
    /// Skips system apps. Does not recurse into subdirectories beyond one level.
    static func discoverAll(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [InstalledApp] {
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let kids = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for kid in kids where kid.pathExtension == "app" {
                if let app = makeApp(at: kid) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    private static func makeApp(at url: URL) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let plist = (try? Data(contentsOf: plistURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let bundleID = plist?["CFBundleIdentifier"] as? String
        let name = (plist?["CFBundleDisplayName"] as? String)
            ?? (plist?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (plist?["CFBundleShortVersionString"] as? String)
            ?? (plist?["CFBundleVersion"] as? String)
        let size = (try? sizeOf(url)) ?? 0
        return InstalledApp(
            bundleURL: url,
            bundleID: bundleID,
            displayName: name,
            version: version,
            iconPath: plist?["CFBundleIconFile"] as? String,
            bundleSize: size
        )
    }

    private static func sizeOf(_ url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in enumerator {
            let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
            total += Int64(s)
        }
        return total
    }
}
