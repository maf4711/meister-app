import Foundation

struct LargeFileItem: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
    let lastUsed: Date?
    let lastModified: Date?
    var id: String { url.path }

    /// The newer of (lastUsed, lastModified). Nil if both are nil.
    var freshness: Date? {
        switch (lastUsed, lastModified) {
        case (let u?, let m?): return max(u, m)
        case (let u?, nil):    return u
        case (nil, let m?):    return m
        default:               return nil
        }
    }
}

@MainActor
final class LargeFilesScanner: NSObject, ObservableObject {
    @Published var items: [LargeFileItem] = []
    @Published var isScanning = false

    private var query: NSMetadataQuery?

    /// Default scope — user content directories. Library/system stay out by
    /// default; cleaning those is the System Cleanup module's job.
    nonisolated static var defaultScope: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Pictures"),
        ]
    }

    /// Scan for files larger than `minBytes`. If `olderThanDays` is non-nil,
    /// also require the file to not have been used or modified within that
    /// window. Uses Spotlight (NSMetadataQuery) so the index does the heavy
    /// lifting — instantaneous on indexed volumes.
    func scan(minBytes: Int64,
              olderThanDays: Int?,
              scope: [URL] = LargeFilesScanner.defaultScope) {
        cancel()
        let q = NSMetadataQuery()
        q.searchScopes = scope
        q.predicate = makePredicate(minBytes: minBytes, olderThanDays: olderThanDays)
        q.valueListAttributes = [
            NSMetadataItemFSSizeKey,
            NSMetadataItemLastUsedDateKey,
            NSMetadataItemFSContentChangeDateKey,
            NSMetadataItemContentTypeKey,
        ]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSSizeKey, ascending: false)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryFinished(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )

        self.query = q
        self.isScanning = true
        q.start()
    }

    func cancel() {
        if let q = query {
            q.stop()
            NotificationCenter.default.removeObserver(self, name: nil, object: q)
        }
        query = nil
        isScanning = false
    }

    @objc private func queryFinished(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        q.disableUpdates()
        var collected: [LargeFileItem] = []
        for case let result as NSMetadataItem in (q.results) {
            guard
                let path = result.value(forAttribute: NSMetadataItemPathKey) as? String,
                let size = (result.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
            else { continue }
            // Skip files inside user Library — those belong to System Cleanup.
            if path.contains("/Library/") { continue }
            collected.append(LargeFileItem(
                url: URL(fileURLWithPath: path),
                bytes: size,
                lastUsed: result.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                lastModified: result.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            ))
        }
        self.items = collected
        self.isScanning = false
        NotificationCenter.default.removeObserver(self, name: nil, object: q)
        self.query = nil
    }

    private func makePredicate(minBytes: Int64, olderThanDays: Int?) -> NSPredicate {
        var clauses: [NSPredicate] = [
            NSPredicate(format: "%K >= %lld", NSMetadataItemFSSizeKey, minBytes),
            NSPredicate(format: "%K != %@", NSMetadataItemContentTypeKey, "public.folder" as NSString),
        ]
        if let days = olderThanDays, days > 0 {
            let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86_400)
            // Use lastUsedDate when available; fall back to content-change date.
            let usedOld = NSPredicate(format: "%K < %@", NSMetadataItemLastUsedDateKey, cutoff as NSDate)
            let usedMissing = NSPredicate(format: "%K == nil", NSMetadataItemLastUsedDateKey)
            let modOld = NSPredicate(format: "%K < %@", NSMetadataItemFSContentChangeDateKey, cutoff as NSDate)
            let dormant = NSCompoundPredicate(orPredicateWithSubpredicates: [
                usedOld,
                NSCompoundPredicate(andPredicateWithSubpredicates: [usedMissing, modOld]),
            ])
            clauses.append(dormant)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
    }
}
