import Foundation

/// On-disk 30-day recovery trash for destructive actions. Stores a small JSON
/// descriptor plus the actual payload (vCard data for contacts, ICS for events)
/// so the user can undo within the window.
///
/// Photos are intentionally not included: iOS's own "Recently Deleted" album
/// already keeps them for 30 days.
struct TrashEntry: Codable, Identifiable {
    enum Kind: String, Codable { case contact, calendarEvent }
    let id: UUID
    let kind: Kind
    let summary: String
    let createdAt: Date
    let payloadFile: String
}

@MainActor
final class TrashStore {
    static let shared = TrashStore()

    private let directory: URL
    private let manifest: URL
    private let retention: TimeInterval = 30 * 24 * 3600

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base
        manifest = base.appendingPathComponent("manifest.json")
    }

    // MARK: - Manifest

    func entries() -> [TrashEntry] {
        purgeExpired()
        guard let data = try? Data(contentsOf: manifest) else { return [] }
        return ((try? JSONDecoder().decode([TrashEntry].self, from: data)) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    func store(kind: TrashEntry.Kind, summary: String, payload: Data) {
        let id = UUID()
        let fileName = "\(id.uuidString).\(kind == .contact ? "vcf" : "ics")"
        let fileURL = directory.appendingPathComponent(fileName)
        try? payload.write(to: fileURL)
        var existing = entries()
        existing.append(TrashEntry(
            id: id,
            kind: kind,
            summary: summary,
            createdAt: .now,
            payloadFile: fileName
        ))
        persist(existing)
    }

    func payload(for entry: TrashEntry) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(entry.payloadFile))
    }

    func remove(_ entry: TrashEntry) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.payloadFile))
        persist(entries().filter { $0.id != entry.id })
    }

    /// Drop entries older than the retention window. Called automatically before reads.
    func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-retention)
        guard let data = try? Data(contentsOf: manifest),
              var all = try? JSONDecoder().decode([TrashEntry].self, from: data) else { return }
        let survivors = all.filter { $0.createdAt > cutoff }
        if survivors.count == all.count { return }
        let expired = all.filter { $0.createdAt <= cutoff }
        for entry in expired {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.payloadFile))
        }
        all = survivors
        persist(all)
    }

    private func persist(_ entries: [TrashEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifest)
    }
}
