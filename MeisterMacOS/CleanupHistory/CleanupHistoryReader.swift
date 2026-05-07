import Foundation

/// Unified entry across cleanup + uninstall manifests.
struct HistoryEntry: Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let kind: Kind
    let title: String         // app name for uninstalls, count summary for cleanups
    let bytes: Int64
    let manifestPath: URL

    enum Kind: String {
        case cleanup, uninstall
    }
}

actor CleanupHistoryReader {
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private var supportRoot: URL {
        home.appendingPathComponent("Library/Application Support/Meister", isDirectory: true)
    }

    /// Load all manifests, newest first.
    func load() async -> [HistoryEntry] {
        let cleanups = supportRoot.appendingPathComponent("cleanups", isDirectory: true)
        let uninstalls = supportRoot.appendingPathComponent("uninstalls", isDirectory: true)
        var out: [HistoryEntry] = []
        out.append(contentsOf: read(directory: cleanups, kind: .cleanup))
        out.append(contentsOf: read(directory: uninstalls, kind: .uninstall))
        return out.sorted { $0.timestamp > $1.timestamp }
    }

    nonisolated private func read(directory: URL, kind: HistoryEntry.Kind) -> [HistoryEntry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url -> HistoryEntry? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let dict = any as? [String: Any] else { return nil }
            let bytes = (dict["totalReclaimedBytes"] as? Int64) ??
                Int64((dict["totalReclaimedBytes"] as? NSNumber)?.int64Value ?? 0)
            let timestamp = parseDate(dict["timestamp"] as? String) ??
                            parseDate(url.deletingPathExtension().lastPathComponent) ??
                            Date()
            let title: String
            switch kind {
            case .cleanup:
                let entries = (dict["entries"] as? [[String: Any]]) ?? []
                let categories = Set(entries.compactMap { $0["category"] as? String })
                title = "\(entries.count) item\(entries.count == 1 ? "" : "s") · \(categories.count) categor\(categories.count == 1 ? "y" : "ies")"
            case .uninstall:
                let appName = (dict["appName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                title = appName
            }
            return HistoryEntry(
                id: url.path,
                timestamp: timestamp,
                kind: kind,
                title: title,
                bytes: bytes,
                manifestPath: url
            )
        }
    }

    nonisolated private func parseDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let formatters: [DateFormatter] = {
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd'T'HH-mm-ssXXXXX"
            iso.locale = Locale(identifier: "en_US_POSIX")
            let alt = DateFormatter()
            alt.dateFormat = "yyyy-MM-dd-HHmmss"
            alt.locale = Locale(identifier: "en_US_POSIX")
            return [iso, alt]
        }()
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        // ISO8601 with colons (in case it slipped through)
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        return isoFmt.date(from: s)
    }
}
