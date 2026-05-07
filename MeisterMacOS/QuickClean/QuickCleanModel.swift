import Foundation
import SwiftUI

/// One-click cleanup across all safe-default System Cleanup categories.
/// Combines scan + clean into a single async operation with progress.
@MainActor
final class QuickCleanModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var bytesScanned: Int64 = 0
    @Published var bytesReclaimed: Int64 = 0
    @Published var lastError: String?

    private let scanner = SystemCleanupScanner()
    private let cleaner = SystemCleanupCleaner()

    enum Phase: Equatable {
        case idle
        case scanning
        case cleaning
        case done
    }

    var isRunning: Bool {
        phase == .scanning || phase == .cleaning
    }

    /// Scan + clean safe-default categories in one go.
    func run() async {
        phase = .scanning
        bytesReclaimed = 0
        lastError = nil

        let scans = await scanner.scanAll()
        let safeWithBytes = scans
            .filter { $0.category.safeDefault && $0.bytes > 0 }
        bytesScanned = safeWithBytes.reduce(0) { $0 + $1.bytes }

        guard !safeWithBytes.isEmpty else {
            phase = .done
            return
        }

        phase = .cleaning
        do {
            let manifest = try await cleaner.clean(Set(safeWithBytes.map(\.category)))
            bytesReclaimed = manifest.totalReclaimedBytes
        } catch {
            lastError = error.localizedDescription
        }
        phase = .done
    }
}
