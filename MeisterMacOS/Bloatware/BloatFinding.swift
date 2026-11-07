import Foundation

/// One catalog-matched junk item on this Mac.
struct BloatFinding: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case app
        case launchAgent = "launchagent"
        case brewCask = "brew-cask"
        case supportDir = "support-dir"
        case loginItem = "login-item"
    }

    enum Severity: String, Comparable {
        case p0 = "P0"
        case p1 = "P1"
        case p2 = "P2"

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity: Int] = [.p0: 0, .p1: 1, .p2: 2]
            return (order[lhs] ?? 9) < (order[rhs] ?? 9)
        }

        var title: String {
            switch self {
            case .p0: return "P0 — Junk"
            case .p1: return "P1 — Noise"
            case .p2: return "P2 — Check"
            }
        }
    }

    let kind: Kind
    let severity: Severity
    let name: String
    let path: String
    let detail: String
    let bytes: Int64

    var id: String { "\(kind.rawValue)|\(path)" }
}

struct BloatKillManifest: Codable {
    let timestamp: Date
    let entries: [Entry]
    let quarantinedCount: Int

    struct Entry: Codable {
        let kind: String
        let severity: String
        let name: String
        let path: String
        let quarantined: Bool
        let error: String?
    }
}
