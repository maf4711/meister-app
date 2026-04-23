import Foundation
import SwiftUI
import MeisterKit

@MainActor
final class AddressBookCleanupModel: ObservableObject {
    @Published var sources: [AddressBookSource] = []
    @Published var isScanning: Bool = false
    @Published var confirmCleanup: Bool = false
    @Published var cleanupPreview: String? = nil

    var largestSource: AddressBookSource? {
        sources.max(by: { $0.sizeBytes < $1.sizeBytes })
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            sources = try await AddressBookScanner.scan()
        } catch {
            sources = []
        }
    }

    func exportVCard() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.vCard]
        panel.nameFieldStringValue = "contacts-backup-\(ISO8601DateFormatter.dateOnly.string(from: Date())).vcf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await ContactExporter.writeVCard(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func requestCleanup() {
        guard let largest = largestSource else { return }
        cleanupPreview = """
        This will:
        1. Quit Contacts.app
        2. Kill the contactsd helper (will auto-restart)
        3. Move source \(largest.shortID) (\(largest.humanSize)) to Trash with timestamp
        4. Move the ABAssistantChangelog files to Trash
        5. Reopen Contacts.app so macOS recreates the source fresh

        You will then need to reimport your vCard backup manually via Finder double-click.
        """
        confirmCleanup = true
    }

    func runCleanup() async {
        guard let largest = largestSource else { return }
        do {
            try await AddressBookCleanup.perform(moving: largest)
            await scan()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
