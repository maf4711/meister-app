import Foundation
import Photos
import UIKit

/// A lightweight wrapper around a PHAsset used by the UI layer.
struct PhotoItem: Identifiable, Hashable {
    let id: String           // PHAsset.localIdentifier
    let asset: PHAsset
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let sizeBytes: Int64
    let mediaSubtypes: PHAssetMediaSubtype
    let isVideo: Bool
    let duration: TimeInterval
    let isFavorite: Bool
    let isEdited: Bool

    // Explicit init so `isFavorite`/`isEdited` can default to false — keeps existing
    // call sites and test fixtures (which predate these fields) compiling.
    init(
        id: String, asset: PHAsset, pixelWidth: Int, pixelHeight: Int,
        creationDate: Date?, sizeBytes: Int64, mediaSubtypes: PHAssetMediaSubtype,
        isVideo: Bool, duration: TimeInterval,
        isFavorite: Bool = false, isEdited: Bool = false
    ) {
        self.id = id; self.asset = asset
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.creationDate = creationDate; self.sizeBytes = sizeBytes
        self.mediaSubtypes = mediaSubtypes; self.isVideo = isVideo; self.duration = duration
        self.isFavorite = isFavorite; self.isEdited = isEdited
    }

    var isScreenshot: Bool { mediaSubtypes.contains(.photoScreenshot) }
    var isBurst: Bool { asset.representsBurst }
    /// Favorite or edited photos must never be offered for auto-deletion.
    var isProtected: Bool { isFavorite || isEdited }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum PhotoScanner {
    /// Default cap — the most recent 500 assets. Scans a few thousand photos on an iPhone 17
    /// in under 20 s; raise/lower via the `limit` parameter for power users.
    static let defaultLimit = 500

    /// Pixel-based size so fetchAll never touches PHAssetResource (that blocked
    /// TF "Scan funktioniert nicht" on "Reading library" for iCloud libraries).
    static func estimateBytes(
        pixelWidth: Int, pixelHeight: Int, isVideo: Bool, duration: TimeInterval
    ) -> Int64 {
        if isVideo {
            return Int64(max(duration, 1) * 1_500_000)
        }
        let pixels = Int64(max(pixelWidth, 1)) * Int64(max(pixelHeight, 1))
        return pixels * 3 / 4
    }

    /// Fetch up to `limit` assets (photos + videos) the user has authorized, most recent first.
    /// Lightweight: PHAsset fields only — no iCloud resource queries.
    static func fetchAll(
        limit: Int = defaultLimit,
        progress: ((Int, Int) -> Void)? = nil
    ) -> [PhotoItem] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.includeHiddenAssets = false
        opts.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: opts)
        let total = result.count
        var items: [PhotoItem] = []
        items.reserveCapacity(total)
        result.enumerateObjects { asset, idx, _ in
            let isVideo = asset.mediaType == .video
            items.append(PhotoItem(
                id: asset.localIdentifier,
                asset: asset,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                sizeBytes: estimateBytes(
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isVideo: isVideo,
                    duration: asset.duration
                ),
                mediaSubtypes: asset.mediaSubtypes,
                isVideo: isVideo,
                duration: asset.duration,
                isFavorite: asset.isFavorite,
                isEdited: false
            ))
            if idx == 0 || idx == total - 1 || idx % 25 == 0 {
                progress?(idx + 1, total)
            }
        }
        return items
    }

    /// Delete assets through the standard "Recently Deleted" flow.
    /// Apple shows its own confirmation sheet — we never silently destroy.
    static func delete(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}

extension PHAsset {
    /// True if the user has edited this asset. Detected by the presence of an
    /// `.adjustmentData` resource — free to query, no editing session needed.
    /// Edited photos are protected from auto-deletion.
    var hasEdits: Bool {
        PHAssetResource.assetResources(for: self).contains { $0.type == .adjustmentData }
    }

    /// Best-effort size estimate without downloading originals.
    /// Uses PHAssetResource which is free to query.
    var estimatedSize: Int64 {
        let resources = PHAssetResource.assetResources(for: self)
        let primary = resources.first { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto } ?? resources.first
        guard let resource = primary else { return 0 }
        return (resource.value(forKey: "fileSize") as? Int64) ?? 0
    }
}
