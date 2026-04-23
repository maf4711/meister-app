import CoreImage
import Photos
import UIKit

/// 64-bit perceptual hash (aHash variant: 8×8 downsample + mean threshold).
/// Good enough for burst/near-duplicate detection; cheap to compute on-device.
enum PerceptualHash {
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Compute pHash from a thumbnail-sized UIImage.
    static func hash(_ image: UIImage) -> UInt64? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        // Resize to 8x8 grayscale
        let resized = ci
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: 8.0 / CGFloat(cg.width),
                kCIInputAspectRatioKey: 1.0
            ])
        let rect = CGRect(x: 0, y: 0, width: 8, height: 8)
        guard let bitmap = ciContext.createCGImage(resized, from: rect) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64)
        let ctx = CGContext(
            data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        ctx?.draw(bitmap, in: rect)
        let mean = pixels.reduce(0) { Int($0) + Int($1) } / 64
        var bits: UInt64 = 0
        for i in 0..<64 where Int(pixels[i]) > mean { bits |= (1 << i) }
        return bits
    }

    /// Hamming distance — number of differing bits (0 = identical, 64 = inverse).
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

enum PhotoThumbnailLoader {
    /// Fetch a thumbnail suitable for hashing. Cheap — uses the in-app image manager.
    /// Guarantees a single continuation resume (needed because `.opportunistic` can
    /// call back twice), and caps the wait so one stalled asset can't freeze a scan.
    static func thumbnail(for asset: PHAsset, size: CGSize = .init(width: 128, height: 128)) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.resizeMode = .fast
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            let resumeBox = ResumeBox(continuation: continuation)
            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                resumeBox.resume(with: image)
            }

            // 3-second hard cap so an iCloud-only asset doesn't freeze the pipeline.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                PHImageManager.default().cancelImageRequest(requestID)
                resumeBox.resume(with: nil)
            }
        }
    }

    /// Guards against PhotoKit calling the completion block more than once, which
    /// would crash with `SWIFT TASK CONTINUATION MISUSE`.
    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let continuation: CheckedContinuation<UIImage?, Never>

        init(continuation: CheckedContinuation<UIImage?, Never>) {
            self.continuation = continuation
        }

        func resume(with image: UIImage?) {
            lock.lock(); defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: image)
        }
    }
}
