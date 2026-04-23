import Foundation

public enum AddressBookScanner {
    public static let root: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AddressBook", isDirectory: true)
    }()

    public static var sourcesDirectory: URL {
        root.appendingPathComponent("Sources", isDirectory: true)
    }

    public static func scan() async throws -> [AddressBookSource] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [AddressBookSource] = []
        for entry in entries {
            guard let uuid = UUID(uuidString: entry.lastPathComponent) else { continue }
            let size = directorySize(at: entry)
            if size == 0 { continue }

            let log = try? String(contentsOf: entry.appendingPathComponent("migration.log"), encoding: .utf8)
            let account = extractAccount(from: log)
            let lastEvent = extractLastEvent(from: log)
            let destructive = lastEvent?.contains("Removed People:") == true ||
                              lastEvent?.contains("UPLOAD TO") == true

            result.append(AddressBookSource(
                id: uuid,
                path: entry,
                sizeBytes: size,
                account: account,
                lastMigrationEvent: lastEvent,
                hasDestructiveMarker: destructive,
                contactCount: nil
            ))
        }
        return result.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public static func totalSize() -> Int64 {
        directorySize(at: root)
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func extractAccount(from log: String?) -> String? {
        guard let log else { return nil }
        // migration.log UPLOAD lines look like:
        // UPLOAD TO https://foellmer%40mac.com@p102-contacts.icloud.com/...
        let pattern = #"https://([^@:]+)(?::[^@]*)?@"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(log.startIndex..<log.endIndex, in: log)
        guard let match = regex.firstMatch(in: log, range: range),
              let emailRange = Range(match.range(at: 1), in: log) else {
            return nil
        }
        let percent = String(log[emailRange])
        return percent.removingPercentEncoding ?? percent
    }

    private static func extractLastEvent(from log: String?) -> String? {
        guard let log else { return nil }
        let lines = log
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(12).joined(separator: " | ")
    }
}
