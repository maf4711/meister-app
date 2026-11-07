// Frozen pre-optimization working-tree source, including existing streaming changes.
import Foundation
import CryptoKit

struct ReferenceDuplicateGroup: Identifiable, Hashable {
    let hash: String
    let bytes: Int64
    let files: [URL]
    var id: String { hash }
    var wastedBytes: Int64 { bytes * Int64(max(0, files.count - 1)) }
}

actor ReferenceDuplicateFinder {
    /// Minimum file size to consider — below this, hashing cost exceeds reclaim value.
    static let minSize: Int64 = 1_048_576  // 1 MB
    /// Fixed read buffer size keeps hashing memory bounded for multi-GB videos.
    static let hashChunk: Int = 256 * 1024  // 256 KB chunks

    /// Find duplicates under the given root URLs.
    /// Two-stage: bucket by size, then SHA256 only same-size files.
    func find(in roots: [URL], minSize: Int64 = ReferenceDuplicateFinder.minSize) async -> [ReferenceDuplicateGroup] {
        var seen = Set<URL>()
        var sizeBuckets: [Int64: [URL]] = [:]

        for root in roots {
            guard !Task.isCancelled else { return [] }
            enumerate(root) { url, bytes in
                guard bytes >= minSize,
                      seen.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted else { return }
                sizeBuckets[bytes, default: []].append(url)
            }
        }

        var groups: [ReferenceDuplicateGroup] = []
        for (bytes, candidates) in sizeBuckets where candidates.count >= 2 {
            guard !Task.isCancelled else { return [] }
            let hashed = await hashAll(candidates)
            guard !Task.isCancelled else { return [] }
            let byHash = Dictionary(grouping: hashed) { $0.hash }
            for (hash, entries) in byHash where entries.count >= 2 {
                groups.append(ReferenceDuplicateGroup(
                    hash: hash,
                    bytes: bytes,
                    files: entries.map(\.url)
                ))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - helpers

    /// Consume entries as they are discovered; prefetch metadata once per file.
    private nonisolated func enumerate(_ root: URL, visit: (URL, Int64) -> Void) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        func consume(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = values.fileSize else { return }
            visit(url, Int64(bytes))
        }
        guard let values = try? root.resourceValues(forKeys: keys),
              values.isSymbolicLink != true else { return }
        guard values.isDirectory == true else {
            consume(root)
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }
        while !Task.isCancelled, let url = enumerator.nextObject() as? URL {
            consume(url)
        }
    }

    private struct HashedFile {
        let url: URL
        let hash: String
    }

    private func hashAll(_ urls: [URL]) async -> [HashedFile] {
        await withTaskGroup(of: HashedFile?.self) { group in
            var iterator = urls.makeIterator()
            for _ in 0..<4 {
                if let url = iterator.next() {
                    group.addTask { Self.sha256(of: url).map { HashedFile(url: url, hash: $0) } }
                }
            }
            var out: [HashedFile] = []
            for await h in group {
                if let h { out.append(h) }
                if !Task.isCancelled, let url = iterator.next() {
                    group.addTask { Self.sha256(of: url).map { HashedFile(url: url, hash: $0) } }
                }
            }
            return out
        }
    }

    static func sha256(of url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buf = [UInt8](repeating: 0, count: hashChunk)
        while true {
            if Task.isCancelled { return nil }
            let read = buf.withUnsafeMutableBufferPointer { ptr -> Int in
                stream.read(ptr.baseAddress!, maxLength: ptr.count)
            }
            if read < 0 { return nil }
            if read == 0 { break }
            buf.withUnsafeBytes { bytes in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: bytes[..<read]))
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
