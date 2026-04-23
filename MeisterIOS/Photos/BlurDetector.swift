import CoreImage
import Photos
import UIKit
import Vision

/// Flags blurry photos using the Laplacian variance of a grayscale thumbnail.
/// Runs in parallel so a few thousand photos finish in seconds.
enum BlurDetector {
    static func scan(
        items: [PhotoItem],
        threshold: Double = 0.002,
        maxConcurrent: Int = 6,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [(PhotoItem, Double)] {
        let photos = items.filter { !$0.isVideo }
        guard !photos.isEmpty else { return [] }

        var results: [(PhotoItem, Double)] = []
        var processed = 0
        let total = photos.count
        let chunks = stride(from: 0, to: photos.count, by: maxConcurrent).map {
            Array(photos[$0..<min($0 + maxConcurrent, photos.count)])
        }
        for chunk in chunks {
            await withTaskGroup(of: (PhotoItem, Double?).self) { group in
                for item in chunk {
                    group.addTask {
                        let thumb = await PhotoThumbnailLoader.thumbnail(
                            for: item.asset,
                            size: CGSize(width: 256, height: 256)
                        )
                        return (item, thumb.flatMap(laplacianVariance))
                    }
                }
                for await (item, score) in group {
                    if let score, score < threshold { results.append((item, score)) }
                    processed += 1
                    progress(Double(processed) / Double(total))
                }
            }
        }
        return results.sorted { $0.1 < $1.1 }
    }

    /// Approximate Laplacian variance through Core Image edge detection.
    static func laplacianVariance(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        let edges = ci
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let out = ctx.createCGImage(edges, from: edges.extent) else { return nil }
        let w = out.width, h = out.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        let bitmap = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        bitmap?.draw(out, in: CGRect(x: 0, y: 0, width: w, height: h))

        let count = pixels.count
        guard count > 0 else { return nil }
        let mean = Double(pixels.reduce(0) { Int($0) + Int($1) }) / Double(count) / 255.0
        var variance = 0.0
        for p in pixels {
            let v = Double(p) / 255.0 - mean
            variance += v * v
        }
        return variance / Double(count)
    }
}
