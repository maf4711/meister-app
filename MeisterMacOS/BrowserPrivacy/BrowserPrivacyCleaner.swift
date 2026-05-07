import Foundation
import AppKit

enum Browser: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, brave, arc, edge
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .brave:  return "Brave"
        case .arc:    return "Arc"
        case .edge:   return "Microsoft Edge"
        }
    }

    var symbol: String {
        switch self {
        case .safari: return "safari"
        case .firefox: return "flame"
        default: return "globe"
        }
    }
}

enum PrivacyTarget: String, CaseIterable, Identifiable {
    case history, cookies, downloads, cache
    var id: String { rawValue }
    var label: String {
        switch self {
        case .history:   return "History"
        case .cookies:   return "Cookies"
        case .downloads: return "Downloads-List"
        case .cache:     return "Cache"
        }
    }
}

struct BrowserPrivacyEntry: Identifiable, Hashable {
    let browser: Browser
    let target: PrivacyTarget
    let path: URL
    let bytes: Int64
    var id: String { "\(browser.rawValue):\(target.rawValue):\(path.path)" }
}

actor BrowserPrivacyCleaner {

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Resolve known privacy paths per browser × target.
    /// Returns only paths that actually exist on disk.
    func scan() async -> [BrowserPrivacyEntry] {
        var out: [BrowserPrivacyEntry] = []
        for b in Browser.allCases {
            for t in PrivacyTarget.allCases {
                for path in paths(for: b, target: t) {
                    guard FileManager.default.fileExists(atPath: path.path) else { continue }
                    let bytes = (try? size(of: path)) ?? 0
                    out.append(BrowserPrivacyEntry(browser: b, target: t, path: path, bytes: bytes))
                }
            }
        }
        return out
    }

    @MainActor
    func recycle(_ entries: [BrowserPrivacyEntry]) async -> Int64 {
        let urls = entries.map(\.path)
        let totalBefore = entries.reduce(0) { $0 + $1.bytes }
        let ok: Bool = await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { _, error in
                cont.resume(returning: error == nil)
            }
        }
        return ok ? totalBefore : 0
    }

    // MARK: - paths

    nonisolated func paths(for browser: Browser, target: PrivacyTarget) -> [URL] {
        let lib = home.appendingPathComponent("Library")
        switch (browser, target) {
        case (.safari, .history):
            return [lib.appendingPathComponent("Safari/History.db"),
                    lib.appendingPathComponent("Safari/History.db-wal"),
                    lib.appendingPathComponent("Safari/History.db-shm")]
        case (.safari, .cookies):
            return [lib.appendingPathComponent("Cookies/Cookies.binarycookies")]
        case (.safari, .downloads):
            return [lib.appendingPathComponent("Safari/Downloads.plist")]
        case (.safari, .cache):
            return [lib.appendingPathComponent("Caches/com.apple.Safari")]

        case (.chrome, .history):
            return [lib.appendingPathComponent("Application Support/Google/Chrome/Default/History"),
                    lib.appendingPathComponent("Application Support/Google/Chrome/Default/History-journal")]
        case (.chrome, .cookies):
            return [lib.appendingPathComponent("Application Support/Google/Chrome/Default/Cookies"),
                    lib.appendingPathComponent("Application Support/Google/Chrome/Default/Cookies-journal")]
        case (.chrome, .downloads):
            return [lib.appendingPathComponent("Application Support/Google/Chrome/Default/Downloads")]
        case (.chrome, .cache):
            return [lib.appendingPathComponent("Application Support/Google/Chrome/Default/Cache"),
                    lib.appendingPathComponent("Application Support/Google/Chrome/Default/Code Cache")]

        case (.firefox, .history), (.firefox, .cookies):
            // Firefox profiles live under Profiles/<random>.default-release/
            // Keep simple: scan all profiles' places.sqlite (history+bookmarks) or cookies.sqlite.
            return firefoxProfileFiles(name: target == .history ? "places.sqlite" : "cookies.sqlite")
        case (.firefox, .downloads):
            return firefoxProfileFiles(name: "downloads.sqlite")
        case (.firefox, .cache):
            return [lib.appendingPathComponent("Caches/Firefox")]

        case (.brave, .history):
            return [lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser/Default/History")]
        case (.brave, .cookies):
            return [lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser/Default/Cookies")]
        case (.brave, .downloads):
            return [lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser/Default/Downloads")]
        case (.brave, .cache):
            return [lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser/Default/Cache")]

        case (.arc, .history):
            return [lib.appendingPathComponent("Application Support/Arc/User Data/Default/History")]
        case (.arc, .cookies):
            return [lib.appendingPathComponent("Application Support/Arc/User Data/Default/Cookies")]
        case (.arc, .downloads):
            return [lib.appendingPathComponent("Application Support/Arc/User Data/Default/Downloads")]
        case (.arc, .cache):
            return [lib.appendingPathComponent("Application Support/Arc/User Data/Default/Cache")]

        case (.edge, .history):
            return [lib.appendingPathComponent("Application Support/Microsoft Edge/Default/History")]
        case (.edge, .cookies):
            return [lib.appendingPathComponent("Application Support/Microsoft Edge/Default/Cookies")]
        case (.edge, .downloads):
            return [lib.appendingPathComponent("Application Support/Microsoft Edge/Default/Downloads")]
        case (.edge, .cache):
            return [lib.appendingPathComponent("Application Support/Microsoft Edge/Default/Cache")]
        }
    }

    private nonisolated func firefoxProfileFiles(name: String) -> [URL] {
        let profiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: profiles,
                                                                          includingPropertiesForKeys: nil) else { return [] }
        return entries.map { $0.appendingPathComponent(name) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private nonisolated func size(of url: URL) throws -> Int64 {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if !isDir.boolValue {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Int64 = 0
        if let it = FileManager.default.enumerator(at: url,
                                                   includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                   options: [.skipsHiddenFiles]) {
            for case let f as URL in it {
                let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
                total += Int64(s)
            }
        }
        return total
    }
}
