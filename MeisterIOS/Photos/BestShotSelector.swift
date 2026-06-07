import Photos
import UIKit
@preconcurrency import Vision

/// Picks the best shot from a set of near-duplicates using a simple quality proxy:
/// sharpness (Laplacian variance) + face quality from Vision when faces are present.
enum BestShotSelector {
    static func pickBest(in group: [PhotoItem]) async -> PhotoItem? {
        var scored: [(PhotoItem, Double)] = []
        for item in group {
            guard let thumb = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: 512, height: 512)
            ) else { continue }
            let sharpness = BlurDetector.laplacianVariance(thumb) ?? 0
            let faceQuality = await faceQuality(for: thumb)
            scored.append((item, sharpness + faceQuality * 0.5))
        }
        return scored.max { $0.1 < $1.1 }?.0
    }

    private static func faceQuality(for image: UIImage) async -> Double {
        guard let cg = image.cgImage else { return 0 }
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceCaptureQualityRequest { req, _ in
                let faces = (req.results as? [VNFaceObservation]) ?? []
                let best = faces.compactMap { $0.faceCaptureQuality.map(Double.init) }.max() ?? 0
                continuation.resume(returning: best)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            }
        }
    }
}
