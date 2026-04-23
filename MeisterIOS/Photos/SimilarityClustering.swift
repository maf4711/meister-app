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

        // Union-find grouping by feature-print distance.
        var parent = Array(0..<photos.count)
        func find(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = find(parent[i]); return parent[i] }() }
        func union(_ i: Int, _ j: Int) {
            let (ri, rj) = (find(i), find(j)); if ri != rj { parent[ri] = rj }
        }

        for i in 0..<photos.count {
            guard let a = fingerprints[photos[i].id] else { continue }
            for j in (i + 1)..<photos.count {
                guard let b = fingerprints[photos[j].id] else { continue }
                var distance: Float = 0
                do {
                    try a.computeDistance(&distance, to: b)
                    if distance < distanceThreshold { union(i, j) }
                } catch {
                    continue
                }
            }
        }
        var clusters: [Int: [PhotoItem]] = [:]
        for i in 0..<photos.count {
            clusters[find(i), default: []].append(photos[i])
        }
        return clusters.values
            .filter { $0.count > 1 }
            .map { Cluster(items: $0) }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
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
