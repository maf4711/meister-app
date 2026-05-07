import Foundation

struct KeychainSummary: Identifiable, Hashable {
    let id: String
    let path: String
    let displayName: String
    let totalItems: Int
    let internetPasswords: Int
    let genericPasswords: Int
    let certificates: Int
    let keys: Int
    let sizeBytes: Int64
    let lastModified: Date?
}

actor KeychainAuditReader {
    func read() async -> [KeychainSummary] {
        // 1. List user keychains
        let listOut = run("/usr/bin/security", ["list-keychains", "-d", "user"])
        let paths = parseKeychainList(listOut)

        var out: [KeychainSummary] = []
        for path in paths {
            out.append(summarize(path: path))
        }
        return out
    }

    nonisolated func parseKeychainList(_ raw: String) -> [String] {
        // Format: "    /Users/x/Library/Keychains/login.keychain-db"
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")) }
            .filter { $0.hasSuffix(".keychain-db") || $0.hasSuffix(".keychain") }
    }

    nonisolated private func summarize(path: String) -> KeychainSummary {
        let url = URL(fileURLWithPath: path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        let modified = attrs?[.modificationDate] as? Date

        // dump-keychain (no -d / no -i flag) shows metadata only — no decrypt prompt.
        let dump = run("/usr/bin/security", ["dump-keychain", path])
        let counts = countItems(in: dump)

        return KeychainSummary(
            id: path,
            path: path,
            displayName: url.deletingPathExtension().lastPathComponent,
            totalItems: counts.total,
            internetPasswords: counts.internet,
            genericPasswords: counts.generic,
            certificates: counts.cert,
            keys: counts.key,
            sizeBytes: bytes,
            lastModified: modified
        )
    }

    nonisolated func countItems(in dump: String) -> (total: Int, internet: Int, generic: Int, cert: Int, key: Int) {
        var total = 0, internetP = 0, genericP = 0, cert = 0, key = 0
        for line in dump.split(separator: "\n") {
            let s = String(line)
            // dump-keychain marks each item with `class: "<type>"`
            if let r = s.range(of: "class: ") {
                let val = String(s[r.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
                total += 1
                switch val {
                case "inet": internetP += 1
                case "genp": genericP += 1
                case "cert": cert += 1
                case "keys", "publ", "priv": key += 1
                default: break
                }
            }
        }
        return (total, internetP, genericP, cert, key)
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
