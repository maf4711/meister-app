import Photos
import UIKit
@preconcurrency import Vision

/// Detects photos that are documents / receipts / whiteboards rather than memories.
/// Heuristic: text density above a threshold + strong rectangular frame.
enum DocumentDetector {
    struct Finding {
        let item: PhotoItem
        let textCharacters: Int
        let hasRectangle: Bool
    }

    /// Scan items, return photos that look like documents. Used to clean out receipts you photographed.
    static func scan(
        items: [PhotoItem],
        minTextCharacters: Int = 40,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [Finding] {
        let photos = items.filter { !$0.isVideo }
        var findings: [Finding] = []
        let total = max(1, photos.count)
        for (index, item) in photos.enumerated() {
            if let thumb = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: 800, height: 800)
            ) {
                let (text, hasRect) = await analyse(thumb)
                if text >= minTextCharacters || hasRect {
                    findings.append(Finding(item: item, textCharacters: text, hasRectangle: hasRect))
                }
            }
            progress(Double(index + 1) / Double(total))
        }
        return findings.sorted { $0.textCharacters > $1.textCharacters }
    }

    private static func analyse(_ image: UIImage) async -> (Int, Bool) {
        guard let cg = image.cgImage else { return (0, false) }
        return await withCheckedContinuation { continuation in
            let textRequest = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let chars = observations.compactMap { $0.topCandidates(1).first?.string }
                    .reduce(0) { $0 + $1.count }
                let rectRequest = VNDetectRectanglesRequest { rReq, _ in
                    let rects = (rReq.results as? [VNRectangleObservation]) ?? []
                    let strong = rects.contains { $0.confidence > 0.8 }
                    continuation.resume(returning: (chars, strong))
                }
                rectRequest.minimumAspectRatio = 0.3
                rectRequest.maximumObservations = 3
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    try? handler.perform([rectRequest])
                }
            }
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([textRequest])
            }
        }
    }
}
