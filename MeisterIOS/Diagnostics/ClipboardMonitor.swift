import Observation
import UIKit

/// Watches `UIPasteboard.changeCountDidChange` notifications while the app is foreground.
/// Not an audit trail (iOS no longer exposes who read the clipboard), but makes the
/// user aware how often the pasteboard mutates — a proxy for "who is watching".
@Observable
@MainActor
final class ClipboardMonitor {
    struct Change: Identifiable {
        let id = UUID()
        let timestamp: Date
        let changeCount: Int
        let typePreview: String
    }

    private(set) var changes: [Change] = []
    private var observer: NSObjectProtocol?

    func start() {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.record() }
        }
        record()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func record() {
        let board = UIPasteboard.general
        let preview: String
        if board.hasStrings { preview = "text" }
        else if board.hasURLs { preview = "URL" }
        else if board.hasImages { preview = "image" }
        else if board.hasColors { preview = "color" }
        else { preview = "other" }
        changes.insert(Change(timestamp: .now, changeCount: board.changeCount, typePreview: preview), at: 0)
        if changes.count > 50 { changes.removeLast() }
    }
}
