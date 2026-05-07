import Foundation
import AppKit

struct CleanupManifest: Codable {
    let timestamp: Date
    let entries: [Entry]
    let totalReclaimedBytes: Int64

    struct Entry: Codable {
        let category: String
        let path: String
        let bytes: Int64
        let recycled: Bool
        let error: String?
    }
}

enum CleanupError: Error, LocalizedError {
    case manifestWriteFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .manifestWriteFailed(let url, let err):
            return "Failed to write manifest at \(url.path): \(err.localizedDescription)"
        }
    }
}

@MainActor
final class SystemCleanupCleaner {
    private let fileManager: FileManager
    private let home: URL

    init(fileManager: FileManager = .default,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.home = home
    }

    /// Clean the given categories. Each top-level item under each category path
    /// is moved to ~/.Trash via NSWorkspace.recycle. Trash itself is emptied
    /// directly (you can't recycle the trash). Writes a manifest of what was
    /// moved to ~/Library/Application Support/Meister/cleanups/<ISO8601>.json.
    func clean(_ categories: Set<SystemCleanupCategory>) async throws -> CleanupManifest {
        var entries: [CleanupManifest.Entry] = []
        var total: Int64 = 0

        for category in categories {
            for root in category.paths(home: home) {
                guard fileManager.fileExists(atPath: root.path) else { continue }

                if category == .trash {
                    for item in directoryItems(at: root) {
                        let bytes = sizeOf(item)
                        do {
                            try fileManager.removeItem(at: item)
                            total += bytes
                            entries.append(.init(category: category.rawValue,
                                                 path: item.path,
                                                 bytes: bytes,
                                                 recycled: false,
                                                 error: nil))
                        } catch {
                            entries.append(.init(category: category.rawValue,
                                                 path: item.path,
                                                 bytes: bytes,
                                                 recycled: false,
                                                 error: error.localizedDescription))
                        }
                    }
                    continue
                }

                if category.preserveContainer {
                    for item in directoryItems(at: root) {
                        let bytes = sizeOf(item)
                        let (ok, err) = await recycle(item)
                        if ok { total += bytes }
                        entries.append(.init(category: category.rawValue,
                                             path: item.path,
                                             bytes: bytes,
                                             recycled: ok,
                                             error: err))
                    }
                } else {
                    let bytes = sizeOf(root)
                    let (ok, err) = await recycle(root)
                    if ok { total += bytes }
                    entries.append(.init(category: category.rawValue,
                                         path: root.path,
                                         bytes: bytes,
                                         recycled: ok,
                                         error: err))
                }
            }
        }

        let manifest = CleanupManifest(
            timestamp: Date(),
            entries: entries,
            totalReclaimedBytes: total
        )
        try writeManifest(manifest)
        return manifest
    }

    // MARK: helpers

    private func directoryItems(at url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            return Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url,
                                                   includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                   options: [.skipsHiddenFiles]) {
            for case let f as URL in enumerator {
                let size = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    private func recycle(_ url: URL) async -> (Bool, String?) {
        await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error = error {
                    cont.resume(returning: (false, error.localizedDescription))
                } else {
                    cont.resume(returning: (true, nil))
                }
            }
        }
    }

    private func writeManifest(_ manifest: CleanupManifest) throws {
        let support = home
            .appendingPathComponent("Library/Application Support/Meister/cleanups", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: manifest.timestamp).replacingOccurrences(of: ":", with: "-")
        let url = support.appendingPathComponent("\(stamp).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(manifest)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CleanupError.manifestWriteFailed(url, error)
        }
    }
}
