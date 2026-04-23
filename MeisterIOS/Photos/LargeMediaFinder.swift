import Foundation

enum LargeMediaFinder {
    /// Top-N largest media by estimated size.
    static func top(_ n: Int, in items: [PhotoItem]) -> [PhotoItem] {
        items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(n).map { $0 }
    }
    static func largerThan(_ bytes: Int64, in items: [PhotoItem]) -> [PhotoItem] {
        items.filter { $0.sizeBytes > bytes }.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
