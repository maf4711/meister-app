import Foundation

struct HealthRecommendation: Identifiable {
    let id: String
    let priority: Int
    let title: String
    let detail: String
    let moduleID: String

    static func ranked(for observation: HealthObservation) -> [HealthRecommendation] {
        var result: [HealthRecommendation] = []
        for check in observation.security where ["filevault", "firewall", "gatekeeper", "sip"].contains(check.id) {
            let priority: Int
            switch check.state {
            case .bad: priority = 100
            case .warn: priority = 90
            case .unknown: priority = 50
            case .ok: continue
            }
            result.append(.init(id: check.id, priority: priority, title: "\(check.title) prüfen",
                                detail: check.detail ?? "Status in der Sicherheitsübersicht prüfen.", moduleID: "security-status"))
        }
        if let disk = observation.disk, disk.availableFraction < 0.15 {
            result.append(.init(id: "disk", priority: disk.availableFraction < 0.05 ? 95 : 70,
                                title: "Speicherplatz prüfen",
                                detail: "\(disk.available.humanBytes) verfügbar. Große Dateien vor dem Aufräumen prüfen.", moduleID: "large-old-files"))
        }
        if observation.backup.destination != nil, let last = observation.backup.lastBackupDate {
            let days = max(0, Int(observation.timestamp.timeIntervalSince(last) / 86_400))
            if days > 7 {
                result.append(.init(id: "backup", priority: 80, title: "Backup ist \(days) Tage alt",
                                    detail: "Erreichbarkeit des eingerichteten Backup-Ziels prüfen.", moduleID: "time-machine"))
            }
        }
        return result.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: HealthSnapshot?
    @Published var reclaimableBytes: Int64 = 0
    @Published var allSecurityOK = false
    @Published var securityIssueCount = 0
    @Published var lastBackup: Date?
    @Published var snapshotCount = 0
    @Published var recommendations: [HealthRecommendation] = []
    @Published var isLoading = false
    private let reader = HealthScoreReader()

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let observation = await reader.observe()
        guard !Task.isCancelled else { return }
        snapshot = HealthScoreReader.evaluate(observation)
        reclaimableBytes = observation.scans.reduce(0) { $0 + $1.bytes }
        lastBackup = observation.backup.lastBackupDate
        snapshotCount = observation.snapshots.count
        let checks = observation.security.filter { ["filevault", "firewall", "gatekeeper", "sip"].contains($0.id) }
        securityIssueCount = checks.filter { if case .ok = $0.state { return false }; return true }.count
        allSecurityOK = checks.count == 4 && securityIssueCount == 0
        recommendations = HealthRecommendation.ranked(for: observation)
    }
}
