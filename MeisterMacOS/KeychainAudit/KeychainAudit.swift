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
    let sizeBytes: Int64?
    let lastModified: Date?
}

actor KeychainAuditReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    func read() async -> DiagnosticReport<[KeychainSummary]> {
        let list = command("/usr/bin/security", ["list-keychains", "-d", "user"])
        if let issue = list.issue(source: "Schlüsselbundliste") { return .init(value: nil, issues: [issue]) }
        let paths = parseKeychainList(list.output)
        if paths.isEmpty && !list.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(value: nil, issues: [.init(kind: .invalidOutput, source: "Schlüsselbundliste")])
        }
        var values: [KeychainSummary] = []
        var issues: [DiagnosticIssue] = []
        for path in paths {
            let result = command("/usr/bin/security", ["dump-keychain", path])
            if let issue = result.issue(source: "Schlüsselbund-Metadaten") { issues.append(issue); continue }
            if !result.output.isEmpty && !result.output.contains("keychain:") && !result.output.contains("class:") {
                issues.append(.init(kind: .invalidOutput, source: "Schlüsselbund-Metadaten")); continue
            }
            values.append(summarize(path: path, dump: result.output))
        }
        return .init(value: values.isEmpty && !issues.isEmpty ? nil : values, issues: issues)
    }

    nonisolated func parseKeychainList(_ raw: String) -> [String] {
        // Format: "    /Users/x/Library/Keychains/login.keychain-db"
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")) }
            .filter { $0.hasSuffix(".keychain-db") || $0.hasSuffix(".keychain") }
    }

    nonisolated private func summarize(path: String, dump: String) -> KeychainSummary {
        let url = URL(fileURLWithPath: path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value
        let modified = attrs?[.modificationDate] as? Date

        // dump-keychain (no -d / no -i flag) shows metadata only — no decrypt prompt.
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

}
