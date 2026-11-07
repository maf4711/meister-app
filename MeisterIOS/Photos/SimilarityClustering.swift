import CoreImage
import Photos
import UIKit
@preconcurrency import Vision

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

/// Seam for deletion-candidate logic — id + whether the photo is protected
/// (favorite/edited). Lets the safety rules be unit-tested without a PHAsset.
protocol DuplicateCandidate {
    var id: String { get }
    var isProtected: Bool { get }
}

extension PhotoItem: DuplicateCandidate {}

/// Capture time for the copy-window split. Pure so TestFlight false-dupes
/// (same couple, different days) can be unit-tested without PHAsset.
protocol CaptureTimed {
    var id: String { get }
    var creationDate: Date? { get }
}

extension PhotoItem: CaptureTimed {}

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

        /// Copies the user can delete: everything except the keeper AND except any
        /// favorite/edited photo (never auto-deleted). Empty when there is no valid
        /// keeper in the set — a fail-safe so a whole group is never offered for
        /// deletion. See `SimilarityClustering.deletableIDs`.
        var deletable: [PhotoItem] {
            let ids = Set(SimilarityClustering.deletableIDs(items, keeperID: keeperID))
            return items.filter { ids.contains($0.id) }
        }

        /// Bytes actually freed if the user deletes the candidates — i.e. the
        /// `deletable` set, which already excludes the keeper and protected photos.
        var reclaimableBytes: Int64 { deletable.reduce(0) { $0 + $1.sizeBytes } }
    }

    /// Outcome of a clustering run: the duplicate clusters plus the ids of photos
    /// whose fingerprint could not be computed (iCloud-only, decode failure, …) so
    /// the UI can tell the user "N photos couldn't be analyzed" instead of silently
    /// pretending they're unique.
    struct ClusterResult {
        let clusters: [Cluster]
        let failedIDs: [String]
    }

    /// Vision distance threshold — lower = stricter. 0.35 is copies/bursts;
    /// 0.5 was grouping lookalike portraits from different days (TF Apr 21).
    let distanceThreshold: Float

    /// Two frames are copies only if captured within this window.
    static let captureWindow: TimeInterval = 60

    /// Pin the feature-print algorithm revision so results are stable across OS
    /// updates (a new default revision would silently shift distances/threshold).
    static let featurePrintRevision = VNGenerateImageFeaturePrintRequest.currentRevision

    init(distanceThreshold: Float = 0.35) { self.distanceThreshold = distanceThreshold }

    func cluster(
        _ items: [PhotoItem],
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> ClusterResult {
        // Exclude videos and burst stacks. Bursts are intentional multi-frame
        // captures, not accidental duplicates — offering all-but-one for deletion
        // would destroy the stack the user deliberately shot.
        let photos = items.filter { Self.isEligibleForDedup(isVideo: $0.isVideo, isBurst: $0.isBurst) }
        guard photos.count > 1 else { return ClusterResult(clusters: [], failedIDs: []) }

        var fingerprints: [String: VNFeaturePrintObservation] = [:]
        let total = photos.count
        var processed = 0
        let chunkSize = 6
        let chunks = stride(from: 0, to: photos.count, by: chunkSize).map {
            Array(photos[$0..<min($0 + chunkSize, photos.count)])
        }
        for chunk in chunks {
            await withTaskGroup(of: (String, VNFeaturePrintObservation?).self) { group in
                for item in chunk {
                    group.addTask {
                        let size = Self.fittedSize(
                            pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight, maxDimension: 299
                        )
                        guard let thumb = await PhotoThumbnailLoader.thumbnail(
                            for: item.asset, size: size, contentMode: .aspectFit
                        ) else { return (item.id, nil) }
                        return (item.id, await Self.featurePrint(for: thumb))
                    }
                }
                for await (id, observation) in group {
                    if let observation { fingerprints[id] = observation }
                    processed += 1
                    progress(Double(processed) / Double(total))
                }
            }
        }

        let failed = Self.failedIDs(allIDs: photos.map(\.id), fingerprintedIDs: Set(fingerprints.keys))

        // Group by feature-print distance. Photos without a fingerprint can't be
        // compared, so they're dropped from the index space (they're reported as
        // failed above rather than silently treated as unique).
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
            // Vision groups lookalikes; only same-moment frames are copies.
            for timed in Self.splitByCaptureWindow(clusterItems, window: Self.captureWindow) {
                let keeper = await BestShotSelector.pickBest(in: timed)?.id
                result.append(Cluster(items: timed, keeperID: keeper))
            }
        }
        return ClusterResult(
            clusters: result.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            failedIDs: failed
        )
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

    /// Fallback keeper when no best-shot is known: the largest file, tie-broken to
    /// the smallest id so the choice is deterministic regardless of input order.
    static func fallbackKeeperID<T: SizedPhoto>(_ items: [T]) -> String? {
        items.max { a, b in
            a.sizeBytes != b.sizeBytes ? a.sizeBytes < b.sizeBytes : a.id > b.id
        }?.id
    }

    /// Ids in `allIDs` that did not get a fingerprint — reported to the UI so failed
    /// photos aren't silently treated as unique. Preserves the input order.
    static func failedIDs(allIDs: [String], fingerprintedIDs: Set<String>) -> [String] {
        allIDs.filter { !fingerprintedIDs.contains($0) }
    }

    /// Split a Vision cluster into groups whose capture times all lie within
    /// `window`. Drops singletons. TF: couple photos from Mar 20 / Apr 2 / Apr 19
    /// must not be one "9 copies" list.
    static func splitByCaptureWindow<T: CaptureTimed>(
        _ items: [T],
        window: TimeInterval = captureWindow
    ) -> [[T]] {
        let dated = items.filter { $0.creationDate != nil }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        guard dated.count > 1 else { return [] }
        var groups: [[T]] = []
        var current: [T] = [dated[0]]
        for item in dated.dropFirst() {
            let prev = current.last!.creationDate!
            let next = item.creationDate!
            if next.timeIntervalSince(prev) <= window {
                current.append(item)
            } else {
                if current.count > 1 { groups.append(current) }
                current = [item]
            }
        }
        if current.count > 1 { groups.append(current) }
        return groups
    }

    /// Whether a photo may take part in duplicate detection. Videos aren't photos;
    /// bursts are intentional multi-frame captures, not accidental duplicates, so
    /// they're excluded to keep `cluster()` from ever offering a burst frame for
    /// deletion. Pure so the data-loss-relevant exclusion is unit-tested.
    static func isEligibleForDedup(isVideo: Bool, isBurst: Bool) -> Bool {
        !isVideo && !isBurst
    }

    /// Ids safe to offer for deletion: everything except the keeper and except
    /// protected (favorite/edited) photos. Returns [] when `keeperID` is nil or not
    /// present in `items` — a fail-safe guaranteeing a whole group is never deletable.
    static func deletableIDs<T: DuplicateCandidate>(_ items: [T], keeperID: String?) -> [String] {
        guard let keeperID, items.contains(where: { $0.id == keeperID }) else { return [] }
        return items.filter { $0.id != keeperID && !$0.isProtected }.map(\.id)
    }

    /// The keeper to use after an in-session deletion: keep the chosen best-shot
    /// keeper if it survived; return nil (let the Cluster re-derive one) only when
    /// the keeper itself was deleted. Prevents the keeper silently flipping to the
    /// largest-file fallback for groups whose keeper was untouched.
    static func preservedKeeperID(current: String?, survivingIDs: Set<String>) -> String? {
        guard let current, survivingIDs.contains(current) else { return nil }
        return current
    }

    /// Aspect-preserving size that fits `(pixelWidth, pixelHeight)` inside a
    /// `maxDimension` box without upscaling. Avoids the square-squash that distorts
    /// the image before fingerprinting. Falls back to a square for unknown sizes.
    static func fittedSize(pixelWidth: Int, pixelHeight: Int, maxDimension: CGFloat) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return CGSize(width: maxDimension, height: maxDimension)
        }
        let w = CGFloat(pixelWidth), h = CGFloat(pixelHeight)
        let scale = maxDimension / max(w, h)
        guard scale < 1 else { return CGSize(width: w, height: h) }  // never upscale
        return CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
    }

    private static func featurePrint(for image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        // `cgImage` drops UIImage.imageOrientation, so a portrait shot taken in
        // landscape orientation would fingerprint rotated. Pass the orientation
        // explicitly so visually-equal photos match regardless of EXIF rotation.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, _ in
                continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            }
            request.revision = Self.featurePrintRevision
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}

extension CGImagePropertyOrientation {
    /// Map UIKit's image orientation to the ImageIO orientation Vision expects.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
