import AppIntents
import SwiftUI
import UIKit

/// Apple Shortcuts entry point: "Hey Siri, Meister Quick-Clean".
///
/// We do NOT run cleaning silently from the intent — Photos deletion needs a
/// PhotoKit confirmation sheet that has to be presented from a foreground UI.
/// Instead the intent opens the app and triggers the run there. Apple's
/// guidance for destructive intents.
struct QuickCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick-Clean ausführen"
    static var description = IntentDescription(
        "Räumt App-Cache, Duplikat-Fotos, Screenshots und Screen-Recordings in einem Schwung weg. Öffnet Meister und startet automatisch.",
        categoryName: "Cleanup"
    )

    /// Important — without this Shortcuts thinks the intent is silent and never
    /// brings the app forward, so the Photos delete-sheet never appears.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AutoCleanLauncher.shared.requestAutoStart()
        return .result()
    }
}

/// Lighter intent — exposes just the score, no side-effects. Safe for the
/// "Show Health" voice query and for widget intents that don't open the app.
struct ShowHealthScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Meister Health Score zeigen"
    static var description = IntentDescription(
        "Liest Disk, Akku und Uptime und gibt eine Zahl 0–100 zurück.",
        categoryName: "Status"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let score = HealthScoreSnapshot.read()
        let verdict: String
        switch score {
        case 80...:    verdict = "Alles im Lot."
        case 60..<80:  verdict = "OK, kleine Optimierungen möglich."
        case 40..<60:  verdict = "Speicher oder Akku schauen."
        default:       verdict = "Mehrere Aufmerksamkeitspunkte."
        }
        return .result(value: score, dialog: IntentDialog("Health Score: \(score) von 100. \(verdict)"))
    }
}

// AppShortcutsProvider conformance lives in CleanPhotosIntent.swift —
// Apple only allows one per app, so QuickCleanIntent and ShowHealthScoreIntent
// are registered there.

/// Cross-component handoff: AppIntent fires → flips a flag → ContentView
/// starts the run when it next becomes active. Singleton because intents
/// run in their own process context and we can't pass the model in.
@MainActor
final class AutoCleanLauncher: ObservableObject {
    static let shared = AutoCleanLauncher()
    @Published var pendingAutoStart: Bool = false

    func requestAutoStart() {
        pendingAutoStart = true
    }

    func consume() -> Bool {
        guard pendingAutoStart else { return false }
        pendingAutoStart = false
        return true
    }
}

/// Minimal copy of the dashboard scoring used by the Shortcuts intent.
/// We keep the math identical to IOSDashboardModel.score so the spoken
/// number matches the dashboard.
enum HealthScoreSnapshot {
    static func read() -> Int {
        // Disk
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? url.resourceValues(forKeys: keys)
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = total - free
        let diskPct = total > 0 ? Double(used) / Double(total) : 0

        // Battery — UIDevice works inside intents.
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryFloat = device.batteryLevel

        // Uptime
        let uptimeDays = Double(ProcessInfo.processInfo.systemUptime) / 86_400

        var score = 0
        // Disk: 50 pts, penalize >85% usage.
        let diskPenalty = max(0, diskPct - 0.85) / 0.15
        score += Int((1 - diskPenalty) * 50)
        // Battery: 30 pts based on level.
        if batteryFloat < 0 {
            score += 20
        } else {
            score += Int(Double(batteryFloat) * 30)
        }
        // Uptime: 20 pts max, -1 per 2 days.
        score += max(0, 20 - Int(uptimeDays) / 2)
        return min(100, max(0, score))
    }
}
