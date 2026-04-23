import Foundation

struct StorageInfo {
    let total: Int64
    let free: Int64
    var used: Int64 { total - free }
    var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum StorageReader {
    static func read() -> StorageInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            return StorageInfo(total: total, free: free)
        }
        return StorageInfo(total: 0, free: 0)
    }

    /// Estimate cached data for this app's own sandbox (what we can actually clean).
    static func appCacheBytes() -> Int64 {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        return directorySize(caches) + directorySize(tmp)
    }

    static func purgeAppCache() throws {
        let fm = FileManager.default
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil).forEach { try? fm.removeItem(at: $0) }
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        try fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil).forEach { try? fm.removeItem(at: $0) }
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
