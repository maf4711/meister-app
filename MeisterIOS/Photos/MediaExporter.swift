import AVFoundation
import Photos
import UIKit

/// Space-saving exports that preserve quality but shrink file size:
///   - HEIC images → JPEG (for sharing) or JPEG → HEIC (for storage, iOS-native)
///   - Videos → HEVC at lower bitrate
enum MediaExporter {
    enum ExportError: Error {
        case unsupportedAsset
        case exportFailed(String)
    }

    // MARK: - Video

    /// Re-encode a video to HEVC. Returns the new asset's local identifier.
    static func compressVideo(
        _ asset: PHAsset,
        preset: String = AVAssetExportPresetHEVC1920x1080
    ) async throws -> String {
        guard asset.mediaType == .video else { throw ExportError.unsupportedAsset }
        let avAsset = try await fetchAVAsset(asset)
        guard let exporter = AVAssetExportSession(asset: avAsset, presetName: preset) else {
            throw ExportError.exportFailed("unable to create export session")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        guard exporter.status == .completed else {
            throw ExportError.exportFailed(exporter.error?.localizedDescription ?? "unknown")
        }

        return try await saveVideoAndReplace(original: asset, at: outputURL)
    }

    private static func fetchAVAsset(_ asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: ExportError.exportFailed("cannot fetch source video"))
                }
            }
        }
    }

    private static func saveVideoAndReplace(original: PHAsset, at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                placeholder = request?.placeholderForCreatedAsset
                PHAssetChangeRequest.deleteAssets([original] as NSArray)
            }, completionHandler: { ok, error in
                if ok, let id = placeholder?.localIdentifier {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: ExportError.exportFailed(error?.localizedDescription ?? "save failed"))
                }
            })
        }
    }

    // MARK: - Image

    /// Export a HEIC image to JPEG at the chosen quality. Returns the file URL in the temp dir;
    /// callers can share it via `ShareLink`.
    static func exportAsJPEG(_ asset: PHAsset, quality: CGFloat = 0.9) async throws -> URL {
        guard asset.mediaType == .image else { throw ExportError.unsupportedAsset }
        let image = try await fetchFullImage(asset)
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw ExportError.exportFailed("jpeg encoding failed")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }

    private static func fetchFullImage(_ asset: PHAsset) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ExportError.exportFailed("cannot fetch image"))
                }
            }
        }
    }
}
