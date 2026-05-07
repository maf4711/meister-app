import Foundation

struct CategoryScan: Hashable, Identifiable {
    let category: SystemCleanupCategory
    let bytes: Int64
    let itemCount: Int
    var id: String { category.id }
}

actor SystemCleanupScanner {
    private let fileManager: FileManager
    private let home: URL

    init(fileManager: FileManager = .default,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.home = home
    }

    /// Scan all categories concurrently.
    func scanAll() async -> [CategoryScan] {
        await withTaskGroup(of: CategoryScan.self) { group in
            for cat in SystemCleanupCategory.allCases {
                group.addTask { [self] in await self.scan(cat) }
            }
            var results: [CategoryScan] = []
            for await scan in group { results.append(scan) }
            return results.sorted { $0.bytes > $1.bytes }
        }
    }

    func scan(_ category: SystemCleanupCategory) async -> CategoryScan {
        var totalBytes: Int64 = 0
        var totalItems = 0

        for root in category.paths(home: home) {
            let (bytes, items) = directorySize(at: root)
            totalBytes += bytes
            totalItems += items
        }
        return CategoryScan(category: category, bytes: totalBytes, itemCount: totalItems)
    }

    /// Recursive byte sum of a directory. Returns (0, 0) if path is missing.
    /// Skips symlinks to avoid loops + double-counting.
    private nonisolated func directorySize(at url: URL) -> (Int64, Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return (0, 0)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: opts,
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        var bytes: Int64 = 0
        var items = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile != true { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            bytes += size
            items += 1
        }
        return (bytes, items)
    }
}

extension Int64 {
    /// Human-readable bytes via ByteCountFormatter (locale-aware).
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
