import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: HealthSnapshot?
    @Published var reclaimableBytes: Int64 = 0
    @Published var allSecurityOK: Bool = false
    @Published var securityIssueCount: Int = 0
    @Published var lastBackup: Date?
    @Published var snapshotCount: Int = 0
    @Published var recommendation: String = "Berechne Empfehlung…"
    @Published var recommendationDetail: String = ""
    @Published var isLoading = false

    private let scoreReader = HealthScoreReader()
    private let cleanupScanner = SystemCleanupScanner()
    private let secReader = SecurityStatusReader()
    private let tmReader = TimeMachineReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        async let snapshotF = scoreReader.snapshot()
        async let scansF = cleanupScanner.scanAll()
        async let secF = secReader.readAll()
        async let tmStatusF = tmReader.status()
        async let snapsF = tmReader.snapshots()

        let snap = await snapshotF
        let scans = await scansF
        let sec = await secF
        let tm = await tmStatusF
        let snaps = await snapsF

        self.snapshot = snap
        self.reclaimableBytes = scans.reduce(0) { $0 + $1.bytes }
        self.lastBackup = tm.lastBackupDate
        self.snapshotCount = snaps.count

        let issues = sec.filter {
            switch $0.state {
            case .ok: return false
            default:  return true
            }
        }
        self.allSecurityOK = issues.isEmpty
        self.securityIssueCount = issues.count

        // Generate a smart recommendation from the highest-impact signal.
        let (rec, detail) = pickRecommendation(snap: snap, scans: scans, securityIssues: issues, lastBackup: tm.lastBackupDate, snapshots: snaps.count)
        self.recommendation = rec
        self.recommendationDetail = detail
    }

    private func pickRecommendation(snap: HealthSnapshot,
                                    scans: [CategoryScan],
                                    securityIssues: [SecurityCheck],
                                    lastBackup: Date?,
                                    snapshots: Int) -> (String, String) {
        // Rank candidate recommendations by impact, return the strongest one.
        struct Candidate { let weight: Int; let title: String; let detail: String }
        var pool: [Candidate] = []

        // Security wins above everything if FileVault or SIP is off.
        if let fv = securityIssues.first(where: { $0.id == "filevault" }),
           case .bad = fv.state {
            pool.append(.init(weight: 100,
                              title: "Schalte FileVault ein",
                              detail: "Disk ist unverschlüsselt. Bei Diebstahl liest jeder mit USB-Stick alles."))
        }
        if let sip = securityIssues.first(where: { $0.id == "sip" }),
           case .warn = sip.state {
            pool.append(.init(weight: 90,
                              title: "System Integrity Protection ist aus",
                              detail: "Aktivieren via macOS Recovery (`csrutil enable`)."))
        }

        // Cleanup pressure
        let totalCleanable = scans.reduce(Int64(0)) { $0 + $1.bytes }
        let gb = Double(totalCleanable) / 1_073_741_824
        if gb >= 5 {
            let topCat = scans.first { $0.bytes > 0 }
            pool.append(.init(weight: 70 + Int(min(20, gb)),
                              title: "\(String(format: "%.1f", gb)) GB Cache-Druck",
                              detail: "Größter Posten: \(topCat?.category.title ?? "—") (\(topCat?.bytes.humanBytes ?? "—")). Ein System-Cleanup-Lauf reicht."))
        }

        // Backup recency
        if let lb = lastBackup {
            let days = Int(Date().timeIntervalSince(lb) / 86_400)
            if days > 7 {
                pool.append(.init(weight: 60 + min(30, days),
                                  title: "Backup ist \(days) Tage alt",
                                  detail: "Time Machine sollte täglich laufen. Externe Disk anschließen oder Network-Target prüfen."))
            }
        } else {
            pool.append(.init(weight: 85,
                              title: "Kein Time-Machine-Backup gefunden",
                              detail: "Erste TM-Disk einrichten — bei Disk-Tod sonst alles weg."))
        }

        // Snapshot bloat
        if snapshots > 25 {
            pool.append(.init(weight: 40 + snapshots,
                              title: "\(snapshots) lokale Snapshots fressen Disk-Space",
                              detail: "APFS hält bis zu 24h alte Snapshots. Mehr deutet auf Backup-Disk-Probleme hin."))
        }

        // Default
        if pool.isEmpty {
            pool.append(.init(weight: 1,
                              title: "Mac läuft sauber",
                              detail: "Keine dringenden Maßnahmen. Score \(snap.score)/100."))
        }

        let best = pool.max { $0.weight < $1.weight }!
        return (best.title, best.detail)
    }
}
