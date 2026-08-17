import Foundation

/// Severity catalog for macOS bloat (mirrors kill-bloatware skill).
/// KEEP always wins over P0/P1 patterns.
enum BloatCatalog {
    /// Substrings matched case-insensitively against names / labels / paths.
    static let keepPatterns: [String] = [
        "com.apple.", "com.merados.", "com.heald.", "com.meister.", "com.dev.",
        "homebrew.", "iterm", "ghostty", "claude", "codex", "collaborator",
        "docker", "lulu", "little snitch", "clamxav", "malwarebytes",
        "1password", "bitwarden", "github", "goland", "bbedit", "xcode",
        "raycast", "signal", "ledger", "bitcoin", "home assistant", "home-assistant",
        "aqara", "eve", "deco",
    ]

    static let p0Patterns: [String] = [
        "cleanmymac", "ccleaner", "mackeeper", "mac cleaner", "mac-cleaner",
        "advanced mac cleaner", "dr.cleaner", "dr cleaner", "disk doctor",
        "adware doctor", "search marquis", "searchawesome", "vsearch",
        "genieo", "installcore", "bundlore", "shlayer",
        "avast", "avghub", "avasthub", "mcafee", "norton", "trend micro", "trendmicro",
    ]

    static let p1Patterns: [String] = [
        "google.keystone", "keystone", "googleupdater", "google.googleupdater",
        "microsoft.autoupdate", "microsoft-auto-update", "microsoft autoupdate", "autoupdate",
        "ai.perplexity", "perplexity", "dropbox", "onedrive",
        "spotify", "zoomopener", "us.zoom.updater",
        "creative cloud", "adobe", "akamai",
    ]

    /// Application Support basenames that are normal system/vendor and never leftovers.
    static let supportSkip: Set<String> = [
        "AddressBook", "CrashReporter", "Dock", "FaceTime", "FileProvider",
        "Knowledge", "Microsoft", "MobileSync", "SyncServices", "Caches",
        "networkserviceproxy", "ControlCenter", "DifferentialPrivacy", "CloudDocs",
    ]

    static func isKeep(_ raw: String, ignoreFileLines: [String] = []) -> Bool {
        let low = raw.lowercased()
        for line in ignoreFileLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if low.contains(t.lowercased()) { return true }
        }
        return keepPatterns.contains { low.contains($0) }
    }

    static func severity(for raw: String, ignoreFileLines: [String] = []) -> BloatFinding.Severity? {
        if isKeep(raw, ignoreFileLines: ignoreFileLines) { return nil }
        let low = raw.lowercased()
        for p in p0Patterns where low.contains(p) { return .p0 }
        for p in p1Patterns where low.contains(p) { return .p1 }
        return nil
    }

    static func loadIgnoreLines(home: URL, fileManager: FileManager = .default) -> [String] {
        let url = home.appendingPathComponent(".kill-bloatware-ignore")
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return data.components(separatedBy: .newlines)
    }
}
