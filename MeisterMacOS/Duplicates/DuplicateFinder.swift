import Foundation
import CryptoKit

struct DuplicateGroup: Identifiable, Hashable {
    let hash: String
    let bytes: Int64
    let files: [URL]
    var id: String { hash }
    var wastedBytes: Int64 { bytes * Int64(max(0, files.count - 1)) }
}

actor DuplicateFinder {
    /// Minimum file size to consider — below this, hashing cost exceeds reclaim value.
    static let minSize: Int64 = 1_048_576  // 1 MB
    /// Hard cap per file we'll hash to avoid OOM on multi-GB videos.
    static let hashChunk: Int = 256 * 1024  // 256 KB chunks

    /// Find duplicates under the given root URLs.
    /// Two-stage: bucket by size, then SHA256 only same-size files.
    func find(in roots: [URL], minSize: Int64 = DuplicateFinder.minSize) async -> [DuplicateGroup] {
        var sizeBuckets: [Int64: [URL]] = [:]

        for root in roots {
            for url in enumerate(root) {
                guard let bytes = try? size(of: url), bytes >= minSize else { continue }
                sizeBuckets[bytes, default: []].append(url)
            }
        }

        var groups: [DuplicateGroup] = []
        for (bytes, candidates) in sizeBuckets where candidates.count >= 2 {
            let hashed = await hashAll(candidates)
            let byHash = Dictionary(grouping: hashed) { $0.hash }
            for (hash, entries) in byHash where entries.count >= 2 {
                groups.append(DuplicateGroup(
                    hash: hash,
                    bytes: bytes,
                    files: entries.map(\.url)
                ))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - helpers

    private nonisolated func enumerate(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return [url]
        }
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: opts,
            errorHandler: { _, _ in true }
        ) else { return [] }
        var out: [URL] = []
        for case let f as URL in enumerator {
            if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                out.append(f)
            }
        }
        return out
    }

    private nonisolated func size(of url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
    }

    private struct HashedFile {
        let url: URL
        let hash: String
    }

    private func hashAll(_ urls: [URL]) async -> [HashedFile] {
        await withTaskGroup(of: HashedFile?.self) { group in
            for url in urls {
                group.addTask { Self.sha256(of: url).map { HashedFile(url: url, hash: $0) } }
            }
            var out: [HashedFile] = []
            for await h in group { if let h = h { out.append(h) } }
            return out
        }
    }

    static func sha256(of url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buf = [UInt8](repeating: 0, count: hashChunk)
        while stream.hasBytesAvailable {
            let read = buf.withUnsafeMutableBufferPointer { ptr -> Int in
                stream.read(ptr.baseAddress!, maxLength: ptr.count)
            }
            if read <= 0 { break }
            hasher.update(data: Data(buf.prefix(read)))
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
