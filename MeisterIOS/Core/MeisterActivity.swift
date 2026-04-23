import ActivityKit
import Foundation

/// Lightweight Live Activity surfaced in the Dynamic Island and Lock Screen
/// while Meister is running a long scan.
struct ScanActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: String
        public var progress: Double
    }

    public var scanTitle: String
}

@MainActor
enum ScanActivityCoordinator {
    private static var activity: Activity<ScanActivityAttributes>?

    static func start(title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ScanActivityAttributes(scanTitle: title)
        let state = ScanActivityAttributes.ContentState(phase: "Starting…", progress: 0)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 30))
            )
        } catch {
            activity = nil
        }
    }

    static func update(phase: String, progress: Double) async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ScanActivityAttributes.ContentState(phase: phase, progress: progress),
            staleDate: Date().addingTimeInterval(60 * 30)
        )
        await activity.update(content)
    }

    static func finish(phase: String = "Complete") async {
        guard let activity else { return }
        let content = ActivityContent(
            state: ScanActivityAttributes.ContentState(phase: phase, progress: 1),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .default)
        Self.activity = nil
    }
}
