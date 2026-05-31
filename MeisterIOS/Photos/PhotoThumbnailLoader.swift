import Photos
import UIKit

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
