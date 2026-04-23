import Foundation

/// Scan a user-chosen folder (via `UIDocumentPickerViewController`) for large and/or
/// ancient files. Works against iCloud Drive because iOS files surface there as
/// URLs — we just read file size and modification date.
enum ICloudDriveCleaner {
    struct Finding: Identifiable {
        let id = UUID()
        let url: URL
        let size: Int64
        let modified: Date
    }

    /// Walk the directory, collecting files larger than `sizeThreshold` bytes
    /// or older than `ageThreshold`. Respects iCloud security-scoped URLs.
    static func scan(
        at folder: URL,
        sizeThreshold: Int64 = 50 * 1024 * 1024,
        ageThreshold: TimeInterval = 180 * 24 * 3600
    ) throws -> [Finding] {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else {
            return []
        }
        var findings: [Finding] = []
        let cutoff = Date().addingTimeInterval(-ageThreshold)
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate ?? .distantPast
            if size >= sizeThreshold || modified < cutoff {
                findings.append(Finding(url: url, size: size, modified: modified))
            }
        }
        return findings.sorted { $0.size > $1.size }
    }

    static func delete(_ findings: [Finding]) throws -> Int {
        var removed = 0
        for finding in findings {
            try? FileManager.default.removeItem(at: finding.url)
            removed += 1
        }
        return removed
    }
}
