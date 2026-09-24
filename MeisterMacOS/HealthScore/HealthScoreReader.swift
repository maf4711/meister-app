import Foundation

struct HealthSignal: Identifiable, Hashable {
    let id: String
    let title: String
    let weight: Int
    let earned: Int
    let detail: String
    var lostPoints: Int { weight - earned }
}

struct HealthSnapshot {
    let score: Int
    let signals: [HealthSignal]
    let timestamp: Date
    var hasMeasurements: Bool { signals.contains { $0.weight > 0 } }
    var hasUnknowns: Bool { signals.contains { $0.weight == 0 } }
}

struct DiskCapacity {
    let total: Int64
    let available: Int64
    var availableFraction: Double { Double(available) / Double(max(1, total)) }

    static func read() -> DiskCapacity? {
        let path = FileManager.default.fileExists(atPath: "/System/Volumes/Data")
            ? "/System/Volumes/Data" : "/"
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskCapacity(total: Int64(total), available: max(0, available))
    }
}

/// A single observation is shared by the score and dashboard recommendations.
struct HealthObservation {
    let security: [SecurityCheck]
    let scans: [CategoryScan]
    let backup: TimeMachineStatus
    let snapshots: [LocalSnapshot]
    let disk: DiskCapacity?
    let timestamp: Date
}

actor HealthScoreReader {
    private let security = SecurityStatusReader()
    private let cleanup = SystemCleanupScanner()
    private let tm = TimeMachineReader()

    func observe(includeDetails: Bool = true) async -> HealthObservation {
        async let checks = security.readCore()
        async let scans: [CategoryScan] = includeDetails ? cleanup.scanAll() : []
        async let backup = tm.status()
        async let snapshots: [LocalSnapshot] = includeDetails ? tm.snapshots() : []
        return await HealthObservation(security: checks, scans: scans, backup: backup,
                                       snapshots: snapshots, disk: DiskCapacity.read(), timestamp: Date())
    }

    func snapshot() async -> HealthSnapshot {
        Self.evaluate(await observe(includeDetails: false))
    }

    /// Unknown observations are excluded, never silently classified as failures.
    static func evaluate(_ observation: HealthObservation) -> HealthSnapshot {
        var signals: [HealthSignal] = []
        for (id, title, weight) in [("filevault", "FileVault", 20), ("firewall", "Firewall", 10),
                                     ("gatekeeper", "Gatekeeper", 10), ("sip", "System Integrity Protection", 10)] {
            let state = observation.security.first { $0.id == id }?.state
            let earned: Int
            let measuredWeight: Int
            let detail: String
            switch state {
            case .ok(let label): earned = weight; measuredWeight = weight; detail = label
            case .warn(let label), .bad(let label): earned = 0; measuredWeight = weight; detail = label
            case .unknown(let label): earned = 0; measuredWeight = 0; detail = label
            case nil: earned = 0; measuredWeight = 0; detail = "Nicht ermittelt"
            }
            signals.append(.init(id: id, title: title, weight: measuredWeight, earned: earned, detail: detail))
        }
        // No destination means no backup reminders or score penalty (user preference).
        if observation.backup.destination != nil {
            if let last = observation.backup.lastBackupDate {
                let days = max(0, Int(observation.timestamp.timeIntervalSince(last) / 86_400))
                let earned = days <= 2 ? 20 : days <= 7 ? 14 : days <= 30 ? 8 : 0
                signals.append(.init(id: "backup", title: "Time-Machine-Backup", weight: 20,
                                     earned: earned, detail: "Letztes Backup vor \(days) Tagen"))
            } else {
                signals.append(.init(id: "backup", title: "Time-Machine-Backup", weight: 0,
                                     earned: 0, detail: "Backup-Alter nicht ermittelbar"))
            }
        }
        if let disk = observation.disk {
            let earned = disk.availableFraction >= 0.15 ? 30 : disk.availableFraction >= 0.05 ? 15 : 0
            signals.append(.init(id: "disk", title: "Verfügbarer Speicher", weight: 30, earned: earned,
                                 detail: "\(disk.available.humanBytes) verfügbar auf dem Datenvolume"))
        } else {
            signals.append(.init(id: "disk", title: "Verfügbarer Speicher", weight: 0, earned: 0,
                                 detail: "Speicherplatz nicht ermittelbar"))
        }
        // Cache size, quarantine flags and snapshot count alone are not health failures.
        let weight = signals.reduce(0) { $0 + $1.weight }
        let earned = signals.reduce(0) { $0 + $1.earned }
        let score = weight > 0 ? Int((Double(earned) / Double(weight) * 100).rounded()) : 0
        return HealthSnapshot(score: score, signals: signals, timestamp: observation.timestamp)
    }
}
