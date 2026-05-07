import Foundation

struct HealthSignal: Identifiable, Hashable {
    let id: String
    let title: String
    let weight: Int            // contribution to score, 0-30
    let earned: Int            // points earned, 0...weight
    let detail: String
    var lostPoints: Int { weight - earned }
}

struct HealthSnapshot {
    let score: Int             // 0-100
    let signals: [HealthSignal]
    let timestamp: Date
}

actor HealthScoreReader {

    private let security = SecurityStatusReader()
    private let cleanup = SystemCleanupScanner()
    private let tm = TimeMachineReader()

    /// Aggregate signals into a 0-100 score.
    /// Weights chosen so that a fully-protected, recently-backed-up,
    /// uncluttered Mac is 100. Each missing thing eats points.
    func snapshot() async -> HealthSnapshot {
        async let secChecks = security.readAll()
        async let cleanupScans = cleanup.scanAll()
        async let tmStatus = tm.status()
        async let snaps = tm.snapshots()
        let sec = await secChecks
        let scans = await cleanupScans
        let backup = await tmStatus
        let snapList = await snaps

        var signals: [HealthSignal] = []

        // FileVault — 20 pts
        let fv = sec.first { $0.id == "filevault" }
        signals.append(.init(
            id: "filevault", title: "FileVault Disk-Encryption", weight: 20,
            earned: stateOK(fv?.state) ? 20 : 0,
            detail: stateLabel(fv?.state)
        ))

        // Firewall — 10 pts
        let fw = sec.first { $0.id == "firewall" }
        signals.append(.init(
            id: "firewall", title: "Firewall", weight: 10,
            earned: stateOK(fw?.state) ? 10 : 0,
            detail: stateLabel(fw?.state)
        ))

        // Gatekeeper — 10 pts
        let gk = sec.first { $0.id == "gatekeeper" }
        signals.append(.init(
            id: "gatekeeper", title: "Gatekeeper", weight: 10,
            earned: stateOK(gk?.state) ? 10 : 0,
            detail: stateLabel(gk?.state)
        ))

        // SIP — 10 pts
        let sip = sec.first { $0.id == "sip" }
        signals.append(.init(
            id: "sip", title: "System Integrity Protection", weight: 10,
            earned: stateOK(sip?.state) ? 10 : 0,
            detail: stateLabel(sip?.state)
        ))

        // Backup recency — 20 pts
        let bytesPerDay: Int = {
            if let last = backup.lastBackupDate {
                return Int(Date().timeIntervalSince(last) / 86_400)
            }
            return 999
        }()
        let backupEarned: Int
        let backupDetail: String
        switch bytesPerDay {
        case 0...2:    backupEarned = 20; backupDetail = "Backup ≤2 Tage alt"
        case 3...7:    backupEarned = 14; backupDetail = "Backup ≤1 Woche alt"
        case 8...30:   backupEarned = 8;  backupDetail = "Backup ≤1 Monat alt"
        case 31...90:  backupEarned = 3;  backupDetail = "Backup älter als 1 Monat"
        default:       backupEarned = 0;  backupDetail = "Kein/sehr altes Backup gefunden"
        }
        signals.append(.init(
            id: "backup", title: "Time-Machine-Backup", weight: 20,
            earned: backupEarned, detail: backupDetail
        ))

        // Cleanup-Druck — 15 pts (umgekehrt: viel reclaimable = wenig Punkte)
        let totalCleanable = scans.reduce(Int64(0)) { $0 + $1.bytes }
        let gb = Double(totalCleanable) / 1_073_741_824
        let cleanEarned: Int
        let cleanDetail: String
        switch gb {
        case ..<1:    cleanEarned = 15; cleanDetail = "<1 GB recyclebar"
        case 1..<5:   cleanEarned = 12; cleanDetail = "\(String(format: "%.1f", gb)) GB recyclebar"
        case 5..<20:  cleanEarned = 7;  cleanDetail = "\(String(format: "%.1f", gb)) GB Cleanup-Druck"
        case 20..<50: cleanEarned = 3;  cleanDetail = "\(String(format: "%.1f", gb)) GB — System-Cleanup ist überfällig"
        default:      cleanEarned = 0;  cleanDetail = "\(String(format: "%.1f", gb)) GB — kritischer Cleanup-Stau"
        }
        signals.append(.init(
            id: "cleanup", title: "System-Cleanup-Druck", weight: 15,
            earned: cleanEarned, detail: cleanDetail
        ))

        // Lokale Snapshots — 10 pts (zu viele = SSD-Last)
        let snapEarned: Int
        let snapDetail: String
        switch snapList.count {
        case 0...8:   snapEarned = 10; snapDetail = "\(snapList.count) lokale Snapshots — gesund"
        case 9...20:  snapEarned = 6;  snapDetail = "\(snapList.count) Snapshots — ok"
        case 21...50: snapEarned = 2;  snapDetail = "\(snapList.count) Snapshots — purgen"
        default:      snapEarned = 0;  snapDetail = "\(snapList.count) Snapshots — fressen Disk-Space"
        }
        signals.append(.init(
            id: "snapshots", title: "Lokale APFS-Snapshots", weight: 10,
            earned: snapEarned, detail: snapDetail
        ))

        // Quarantine-Flags — 5 pts
        let qa = sec.first { $0.id == "quarantine" }
        signals.append(.init(
            id: "quarantine", title: "Downloads ohne Gatekeeper-Check", weight: 5,
            earned: stateOK(qa?.state) ? 5 : 2,
            detail: stateLabel(qa?.state)
        ))

        let total = signals.reduce(0) { $0 + $1.earned }
        return HealthSnapshot(score: total, signals: signals, timestamp: Date())
    }

    private nonisolated func stateOK(_ s: SecurityState?) -> Bool {
        if case .ok = s { return true }
        return false
    }

    private nonisolated func stateLabel(_ s: SecurityState?) -> String {
        switch s {
        case .ok(let l), .warn(let l), .bad(let l), .unknown(let l): return l
        case .none: return "—"
        }
    }
}
