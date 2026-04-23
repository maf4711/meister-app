import Foundation
import Photos

enum ScreenshotDetector {
    /// All screenshots (iOS marks them via PHAssetMediaSubtype.photoScreenshot).
    static func screenshots(in items: [PhotoItem]) -> [PhotoItem] {
        items.filter { $0.isScreenshot }
    }

    /// Screen recordings (videos shot via iOS's screen recorder).
    /// No official flag — use duration < 10min + recorded via the stock app.
    static func screenRecordings(in items: [PhotoItem]) -> [PhotoItem] {
        items.filter { item in
            guard item.isVideo else { return false }
            let resources = PHAssetResource.assetResources(for: item.asset)
            return resources.contains { $0.originalFilename.hasPrefix("RPReplay") }
        }
    }
}
