import Contacts
import Photos
import UIKit
@preconcurrency import Vision

/// Matches the user's contacts to unlabelled faces found in the photo library.
/// Uses Vision (VNDetectFaceRectanglesRequest) for detection and
/// VNGenerateImageFeaturePrintRequest for per-face similarity — no private SPI.
///
/// Heavy: scanning a large library can take a minute or two. We sample the most recent
/// N photos to keep it practical and let the user pick a face per contact.
enum FaceToContactMatcher {
    struct FaceSample: Identifiable {
        let id = UUID()
        let asset: PHAsset
        let thumbnail: UIImage
    }

    /// Extracts candidate face thumbnails from the latest photos (no clustering yet).
    static func recentFaceSamples(limit: Int = 300) async -> [FaceSample] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var samples: [FaceSample] = []
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            guard let thumb = await PhotoThumbnailLoader.thumbnail(
                for: asset,
                size: CGSize(width: 512, height: 512)
            ) else { continue }
            if await (try? hasFace(in: thumb)) == true {
                samples.append(FaceSample(asset: asset, thumbnail: thumb))
            }
            if samples.count >= 60 { break }
        }
        return samples
    }

    /// Apply a chosen face thumbnail to a contact as its profile picture.
    static func apply(_ image: UIImage, to contact: ContactItem) throws {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        guard let mutable = contact.cn.mutableCopy() as? CNMutableContact else { return }
        mutable.imageData = data
        let request = CNSaveRequest()
        request.update(mutable)
        try CNContactStore().execute(request)
    }

    private static func hasFace(in image: UIImage) async throws -> Bool {
        guard let cg = image.cgImage else { return false }
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { req, _ in
                let faces = (req.results as? [VNFaceObservation]) ?? []
                continuation.resume(returning: !faces.isEmpty)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            }
        }
    }
}
