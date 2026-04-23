import ArgumentParser
import Foundation
import MeisterKit

@main
struct Meister: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meister",
        abstract: "Local macOS maintenance — addressbook, contacts, storage. Zero upload.",
        version: "0.1.0",
        subcommands: [Contacts.self],
        defaultSubcommand: Contacts.self
    )
}

struct Contacts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "AddressBook inspection and cleanup",
        subcommands: [Scan.self, Inspect.self, Export.self, Cleanup.self],
        defaultSubcommand: Scan.self
    )
}

// MARK: - meister contacts scan

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan AddressBook sources and report sizes, accounts, sync state"
    )

    @Flag(name: .long, help: "Machine-readable JSON output")
    var json: Bool = false

    mutating func run() async throws {
        let sources = try await AddressBookScanner.scan()
        let total = AddressBookScanner.totalSize()
        let sync = try await SyncStateInspector.inspect()

        if json {
            let payload = ScanReport(
                totalBytes: total,
                contactsEnabled: sync.contactsEnabled,
                accountID: sync.accountID,
                sources: sources.map { s in
                    ScanReport.Source(
                        id: s.id.uuidString,
                        sizeBytes: s.sizeBytes,
                        account: s.account,
                        hasDestructiveMarker: s.hasDestructiveMarker,
                        lastEvent: s.lastMigrationEvent
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }

        print("AddressBook root total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
        if let enabled = sync.contactsEnabled {
            print("iCloud Contacts sync: \(enabled ? "ENABLED" : "disabled")")
        }
        if let account = sync.accountID {
            print("iCloud account: \(account)")
        }
        print("")
        if sources.isEmpty {
            print("No non-empty sources found.")
            return
        }
        print("UUID prefix  Size       Destructive  Account")
        print("-----------  ---------  -----------  ----------------------------")
        for source in sources {
            let marker = source.hasDestructiveMarker ? "⚠ yes       " : "            "
            let uuid = source.shortID.padding(toLength: 11, withPad: " ", startingAt: 0)
            let size = source.humanSize.padding(toLength: 9, withPad: " ", startingAt: 0)
            let account = source.account ?? "unknown"
            print("\(uuid)  \(size)  \(marker) \(account)")
        }
    }
}

private struct ScanReport: Encodable {
    struct Source: Encodable {
        let id: String
        let sizeBytes: Int64
        let account: String?
        let hasDestructiveMarker: Bool
        let lastEvent: String?
    }
    let totalBytes: Int64
    let contactsEnabled: Bool?
    let accountID: String?
    let sources: [Source]
}

// MARK: - meister contacts inspect <UUID-prefix>

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show full migration.log tail and stats for a source"
    )

    @Argument(help: "UUID prefix (first 8 chars) or full UUID of the source")
    var uuid: String

    mutating func run() async throws {
        let sources = try await AddressBookScanner.scan()
        guard let source = sources.first(where: { $0.id.uuidString.hasPrefix(uuid.uppercased()) }) else {
            print("No source matched prefix '\(uuid)'. Run `meister contacts scan` first.")
            throw ExitCode.failure
        }
        print("Source:  \(source.id.uuidString)")
        print("Path:    \(source.path.path)")
        print("Size:    \(source.humanSize)")
        print("Account: \(source.account ?? "unknown")")
        print("")
        print("Last migration events:")
        print(source.lastMigrationEvent?.replacingOccurrences(of: " | ", with: "\n") ?? "(no migration.log)")
    }
}

// MARK: - meister contacts export <path>

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export all contacts to a single vCard file"
    )

    @Argument(help: "Destination .vcf path (will be overwritten if it exists)")
    var destination: String

    mutating func run() async throws {
        let url = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        try await ContactExporter.writeVCard(to: url)
        print("Wrote \(url.path)")
    }
}

// MARK: - meister contacts cleanup

struct Cleanup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quit Contacts, kill contactsd, move the largest source + changelog to Trash"
    )

    @Option(name: .long, help: "UUID prefix of the source to remove (default: largest)")
    var source: String?

    @Flag(name: .long, help: "Skip confirmation prompt")
    var yes: Bool = false

    mutating func run() async throws {
        let sources = try await AddressBookScanner.scan()
        guard !sources.isEmpty else {
            print("Nothing to clean up — no non-empty sources.")
            return
        }

        let target: AddressBookSource
        if let prefix = source?.uppercased() {
            guard let match = sources.first(where: { $0.id.uuidString.hasPrefix(prefix) }) else {
                print("No source matched '\(prefix)'.")
                throw ExitCode.failure
            }
            target = match
        } else {
            target = sources[0]
        }

        print("About to remove source \(target.shortID) (\(target.humanSize))")
        if let account = target.account { print("  account:  \(account)") }
        if let event = target.lastMigrationEvent { print("  last event: \(event)") }
        print("")
        print("This will:")
        print("  1. Quit Contacts.app")
        print("  2. Kill contactsd (auto-restarts)")
        print("  3. Move the source to ~/.Trash/AddressBook-Source-\(target.shortID)-<timestamp>")
        print("  4. Move ABAssistantChangelog files to Trash")
        print("")

        if !yes {
            print("Proceed? [y/N] ", terminator: "")
            let response = readLine()?.lowercased() ?? ""
            guard response == "y" || response == "yes" else {
                print("Aborted.")
                return
            }
        }

        try await AddressBookCleanup.perform(moving: target)
        print("Done. Reopen Contacts.app and reimport your vCard backup to finish.")
    }
}
