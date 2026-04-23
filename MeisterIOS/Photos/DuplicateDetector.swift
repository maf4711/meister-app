import Foundation
import Photos

/// Group photos that look the same using perceptual hashing.
///
/// Strategy: compute hashes in parallel (bounded concurrency) so a library of a few
/// thousand photos finishes in seconds instead of minutes. Clustering is then O(n²)
/// over the hash set but each comparison is just an XOR.
actor DuplicateDetector {
    struct Group: Identifiable {
        let id = UUID()
        var items: [PhotoItem]
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
        var reclaimableBytes: Int64 {
            items.sorted { $0.sizeBytes > $1.sizeBytes }.dropFirst().reduce(0) { $0 + $1.sizeBytes }
        }
    }

    let threshold: Int
    let maxConcurrent: Int

    init(threshold: Int = 5, maxConcurrent: Int = 6) {
        self.threshold = threshold
        self.maxConcurrent = maxConcurrent
    }

    func scan(
        items: [PhotoItem],
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [Group] {
        let photos = items.filter { !$0.isVideo }
        guard photos.count > 1 else { return [] }

        // Chunked-parallel hashing: process `maxConcurrent` photos per group, then the next.
        // Simpler than a running in-flight counter and has no race conditions.
        var hashes: [String: UInt64] = [:]
        var processed = 0
        let total = photos.count
        let chunkSize = maxConcurrent
        let chunks = stride(from: 0, to: photos.count, by: chunkSize).map {
            Array(photos[$0..<min($0 + chunkSize, photos.count)])
        }
        for chunk in chunks {
            await withTaskGroup(of: (String, UInt64?).self) { group in
                for item in chunk {
                    group.addTask {
                        let thumb = await PhotoThumbnailLoader.thumbnail(for: item.asset)
                        return (item.id, thumb.flatMap(PerceptualHash.hash))
                    }
                }
                for await (id, hash) in group {
                    if let hash { hashes[id] = hash }
                    processed += 1
                    progress(Double(processed) / Double(total))
                }
            }
        }

        return cluster(photos: photos, hashes: hashes)
    }

    private func cluster(photos: [PhotoItem], hashes: [String: UInt64]) -> [Group] {
        // Bucket by aspect ratio so portraits don't collide with panoramas.
        let buckets = Dictionary(grouping: photos) { item -> String in
            let ratio = Double(item.pixelWidth) / max(1.0, Double(item.pixelHeight))
            return String(format: "%.2f", ratio)
        }

        var groups: [Group] = []
        for (_, bucket) in buckets {
            var visited = Set<String>()
            for (i, a) in bucket.enumerated() where !visited.contains(a.id) {
                guard let ha = hashes[a.id] else { continue }
                var cluster: [PhotoItem] = [a]
                visited.insert(a.id)
                for j in (i + 1)..<bucket.count {
                    let b = bucket[j]
                    if visited.contains(b.id) { continue }
                    guard let hb = hashes[b.id] else { continue }
                    if PerceptualHash.distance(ha, hb) <= threshold {
                        cluster.append(b)
                        visited.insert(b.id)
                    }
                }
                if cluster.count > 1 { groups.append(Group(items: cluster)) }
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }
}
