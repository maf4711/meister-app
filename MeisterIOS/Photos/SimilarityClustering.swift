import CoreImage
import Photos
import UIKit
import Vision

/// Finds visually similar photos using Vision's `VNFeaturePrintObservation` — far smarter
/// than pHash: works across crops, rotations, lighting changes.
///
/// Complexity: O(n²) feature comparisons + O(n × thumbnail-decode) for extraction.
/// On-device, ~500 photos take 10–20 s.
/// Minimal seam over a photo for pure keeper/reclaimable math — lets the logic be
/// unit-tested without constructing a PHAsset (see issue #26).
protocol SizedPhoto {
    var id: String { get }
    var sizeBytes: Int64 { get }
}

extension PhotoItem: SizedPhoto {}

actor SimilarityClustering {
    struct Cluster: Identifiable {
        let id = UUID()
        let items: [PhotoItem]
        /// The frame to KEEP — the best shot (sharpness + face quality), not just
        /// the largest file. Resolved from `BestShotSelector`; falls back to the
        /// largest-bytes heuristic when no best shot is supplied.
        let keeperID: String?

        init(items: [PhotoItem], keeperID: String? = nil) {
            self.items = items
            self.keeperID = keeperID ?? SimilarityClustering.fallbackKeeperID(items)
        }

        /// Copies the user can delete — everything except the keeper.
        var deletable: [PhotoItem] { items.filter { $0.id != keeperID } }

        var reclaimableBytes: Int64 {
            SimilarityClustering.reclaimableBytes(items, keeperID: keeperID ?? "")
        }
    }

    /// Vision distance threshold — lower = stricter. 0.5 is a sane default for near-duplicates.
    let distanceThreshold: Float

    init(distanceThreshold: Float = 0.5) { self.distanceThreshold = distanceThreshold }

    func cluster(
        _ items: [PhotoItem],
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [Cluster] {
        let photos = items.filter { !$0.isVideo }
        guard photos.count > 1 else { return [] }

        var fingerprints: [String: VNFeaturePrintObservation] = [:]
        let total = photos.count
        for (index, item) in photos.enumerated() {
            if let thumb = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: 299, height: 299)
            ), let observation = await featurePrint(for: thumb) {
                fingerprints[item.id] = observation
            }
            progress(Double(index + 1) / Double(total))
        }

        // Group by feature-print distance. Photos without a fingerprint can't be
        // compared, so they're dropped from the index space (they could only ever
        // be singletons anyway, which are filtered out).
        let fpPhotos = photos.filter { fingerprints[$0.id] != nil }
        let observations = fpPhotos.map { fingerprints[$0.id]! }
        let indexClusters = Self.groupIndices(count: fpPhotos.count, threshold: distanceThreshold) { i, j in
            var distance: Float = 0
            do {
                try observations[i].computeDistance(&distance, to: observations[j])
                return distance
            } catch {
                return .greatestFiniteMagnitude
            }
        }
        var result: [Cluster] = []
        for idxs in indexClusters {
            let clusterItems = idxs.map { fpPhotos[$0] }
            // Keep the best shot (sharpness + face quality), not the largest file.
            let keeper = await BestShotSelector.pickBest(in: clusterItems)?.id
            result.append(Cluster(items: clusterItems, keeperID: keeper))
        }
        return result.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Pure, deterministic **complete-link** (diameter-capped) clustering over an
    /// injected distance function. Two clusters merge only when EVERY cross-pair is
    /// within `threshold`, so a finished cluster's diameter is always < `threshold`.
    /// This prevents single-link chaining, where A~B and B~C (but A far from C)
    /// would wrongly drag the dissimilar C into the group and offer it for deletion.
    ///
    /// Returns clusters of size > 1, each index list sorted ascending, groups sorted
    /// by their smallest index. Extracted so the grouping logic is unit-testable
    /// without PHAsset/Vision. The `distance` closure (Vision `computeDistance`) is
    /// expensive, so it's evaluated exactly C(count, 2) times and cached.
    static func groupIndices(
        count: Int,
        threshold: Float,
        distance: (Int, Int) -> Float
    ) -> [[Int]] {
        guard count > 1 else { return [] }

        // Cache the pairwise distances once — `distance` may be expensive (Vision).
        var dist = [Float](repeating: 0, count: count * count)
        for i in 0..<count {
            for j in (i + 1)..<count {
                let d = distance(i, j)
                dist[i * count + j] = d
                dist[j * count + i] = d
            }
        }

        // Complete-link agglomerative merge on the cached matrix. A merge of two
        // clusters is valid iff their max cross-pair distance is < threshold; by
        // induction every cluster therefore stays within the diameter cap.
        var clusters: [[Int]] = (0..<count).map { [$0] }
        func completeLink(_ a: [Int], _ b: [Int]) -> Float {
            var m: Float = 0
            for x in a { for y in b { let v = dist[x * count + y]; if v > m { m = v } } }
            return m
        }

        while true {
            var bestI = -1, bestJ = -1
            var bestDist = Float.greatestFiniteMagnitude
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let cl = completeLink(clusters[i], clusters[j])
                    guard cl < threshold else { continue }
                    // Deterministic: smallest linkage first, tie-broken by representative.
                    if cl < bestDist
                        || (cl == bestDist
                            && (clusters[i][0], clusters[j][0]) < (clusters[bestI][0], clusters[bestJ][0])) {
                        bestDist = cl; bestI = i; bestJ = j
                    }
                }
            }
            if bestI < 0 { break }
            let merged = (clusters[bestI] + clusters[bestJ]).sorted()
            clusters.remove(at: bestJ)   // j > i — remove the higher index first
            clusters.remove(at: bestI)
            clusters.append(merged)
        }

        return clusters
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }

    /// Bytes freed by keeping `keeperID` and deleting the rest. If the keeper is
    /// not present (e.g. already deleted), every item counts as reclaimable.
    static func reclaimableBytes<T: SizedPhoto>(_ items: [T], keeperID: String) -> Int64 {
        items.filter { $0.id != keeperID }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Fallback keeper when no best-shot is known: the largest file, tie-broken to
    /// the smallest id so the choice is deterministic regardless of input order.
    static func fallbackKeeperID<T: SizedPhoto>(_ items: [T]) -> String? {
        items.max { a, b in
            a.sizeBytes != b.sizeBytes ? a.sizeBytes < b.sizeBytes : a.id > b.id
        }?.id
    }

    private func featurePrint(for image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, _ in
                continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
