import CoreImage
import Photos
import UIKit
import Vision

/// Finds visually similar photos using Vision's `VNFeaturePrintObservation` — far smarter
/// than pHash: works across crops, rotations, lighting changes.
///
/// Complexity: O(n²) feature comparisons + O(n × thumbnail-decode) for extraction.
/// On-device, ~500 photos take 10–20 s.
actor SimilarityClustering {
    struct Cluster: Identifiable {
        let id = UUID()
        let items: [PhotoItem]
        var reclaimableBytes: Int64 {
            items.sorted { $0.sizeBytes > $1.sizeBytes }.dropFirst().reduce(0) { $0 + $1.sizeBytes }
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
        return indexClusters
            .map { Cluster(items: $0.map { fpPhotos[$0] }) }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Pure, deterministic single-link union-find over an injected distance function.
    /// Returns clusters of size > 1, each index list sorted ascending, groups sorted
    /// by their smallest index. Extracted so the grouping logic is unit-testable
    /// without PHAsset/Vision. Indices `i, j` pair iff `distance(i, j) < threshold`.
    static func groupIndices(
        count: Int,
        threshold: Float,
        distance: (Int, Int) -> Float
    ) -> [[Int]] {
        guard count > 1 else { return [] }
        var parent = Array(0..<count)
        func find(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = find(parent[i]); return parent[i] }() }
        func union(_ i: Int, _ j: Int) {
            let (ri, rj) = (find(i), find(j))
            if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
        }
        for i in 0..<count {
            for j in (i + 1)..<count where distance(i, j) < threshold {
                union(i, j)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<count { groups[find(i), default: []].append(i) }
        return groups.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
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
