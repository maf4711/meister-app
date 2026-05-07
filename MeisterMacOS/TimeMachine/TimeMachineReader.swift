import Foundation

struct TimeMachineStatus: Equatable {
    let isRunning: Bool
    let isOnAC: Bool
    let lastBackupDate: Date?
    let destination: String?
    let raw: String
}

struct LocalSnapshot: Identifiable, Hashable {
    let name: String                // e.g. com.apple.TimeMachine.2026-05-07-100000.local
    let creationDate: Date?
    let bytes: Int64?               // APFS doesn't surface this cheaply — left optional
    var id: String { name }
}

actor TimeMachineReader {

    func status() async -> TimeMachineStatus {
        let raw = run("/usr/bin/tmutil", ["status"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let dict = parsePlistish(raw)
        let running = (dict["Running"] ?? "0") == "1"
        let dest = run("/usr/bin/tmutil", ["destinationinfo"])
            .components(separatedBy: "\n")
            .first { $0.contains("Name") }?
            .split(separator: ":", maxSplits: 1).last
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        // Last backup time via `tmutil latestbackup` (returns path containing date) or `defaults read`.
        let lastBackup = lastBackupDate()

        return TimeMachineStatus(
            isRunning: running,
            isOnAC: ProcessInfo.processInfo.thermalState != .critical,
            lastBackupDate: lastBackup,
            destination: dest,
            raw: raw
        )
    }

    func snapshots() async -> [LocalSnapshot] {
        let out = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        let lines = out.split(separator: "\n").map(String.init)
        let parser = TMDateParser()
        return lines.compactMap { line -> LocalSnapshot? in
            guard line.hasPrefix("com.apple.TimeMachine.") else { return nil }
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = parser.dateFromTMSnapshot(name)
            return LocalSnapshot(name: name, creationDate: date, bytes: nil)
        }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    /// Delete a snapshot by name. Returns true on success.
    func deleteSnapshot(_ name: String) async -> Bool {
        // tmutil deletelocalsnapshots takes the timestamp portion, not the full name.
        // Format: com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local → 2026-05-07-100000
        let trimmed = name
            .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
            .replacingOccurrences(of: ".local", with: "")
        let out = run("/usr/bin/tmutil", ["deletelocalsnapshots", trimmed])
        return out.lowercased().contains("deleted")
    }

    // MARK: - helpers

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `tmutil status` outputs a non-strict plist. Crude key=value extractor good enough for booleans.
    private nonisolated func parsePlistish(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\";"))
            let v = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\";"))
            out[k] = v
        }
        return out
    }

    private nonisolated func lastBackupDate() -> Date? {
        let path = run("/usr/bin/tmutil", ["latestbackup"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        // path ends with /YYYY-MM-DD-HHMMSS.backup
        let last = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".backup", with: "")
        return TMDateParser().dateFromTimestamp(last)
    }
}

/// Tiny date parser for the `YYYY-MM-DD-HHMMSS` shape that TM uses.
struct TMDateParser: Sendable {
    let formatter: DateFormatter

    init() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        self.formatter = f
    }

    func dateFromTimestamp(_ s: String) -> Date? {
        formatter.date(from: s)
    }

    func dateFromTMSnapshot(_ name: String) -> Date? {
        // com.apple.TimeMachine.2026-05-07-100000.local
        guard let dot1 = name.range(of: "TimeMachine."),
              let dotLocal = name.range(of: ".local") else { return nil }
        let stamp = name[dot1.upperBound..<dotLocal.lowerBound]
        return formatter.date(from: String(stamp))
    }
}
