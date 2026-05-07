import Foundation

struct HostsEntry: Identifiable, Hashable {
    let id: String      // line number + ip + host
    let ip: String
    let hosts: [String]
    let comment: String?
    let isCommented: Bool
}

actor HostsReader {

    static let path = "/etc/hosts"

    func read() async -> (entries: [HostsEntry], rawText: String) {
        let raw = (try? String(contentsOfFile: Self.path, encoding: .utf8)) ?? ""
        let entries = parse(raw)
        return (entries, raw)
    }

    nonisolated func parse(_ text: String) -> [HostsEntry] {
        var out: [HostsEntry] = []
        for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let isCommented = trimmed.hasPrefix("#")
            let body = isCommented
                ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                : trimmed
            // skip pure-comment headers (no IP at start)
            let parts = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = parts.first, isLikelyIP(first) else { continue }
            var inlineComment: String?
            var hosts: [String] = []
            for p in parts.dropFirst() {
                if p.hasPrefix("#") {
                    inlineComment = body.range(of: "#").map { String(body[$0.lowerBound...].dropFirst()) }
                    break
                }
                hosts.append(p)
            }
            out.append(HostsEntry(
                id: "\(idx)|\(first)|\(hosts.joined(separator: ","))",
                ip: first,
                hosts: hosts,
                comment: inlineComment?.trimmingCharacters(in: .whitespaces),
                isCommented: isCommented
            ))
        }
        return out
    }

    private nonisolated func isLikelyIP(_ s: String) -> Bool {
        // Crude IPv4/IPv6 sniff — good enough for hosts file.
        if s.contains(":") { return true }   // IPv6
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }
}
