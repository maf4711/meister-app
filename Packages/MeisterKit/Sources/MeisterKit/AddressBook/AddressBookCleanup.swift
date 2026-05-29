import Foundation

public enum AddressBookCleanupError: Error, LocalizedError {
    case contactsAppStillRunning
    case sourceMissing(URL)
    case trashUnavailable

    public var errorDescription: String? {
        switch self {
        case .contactsAppStillRunning: return "Contacts.app is still running — quit it and retry."
        case .sourceMissing(let url): return "Source path no longer exists: \(url.path)"
        case .trashUnavailable: return "Cannot locate the user Trash directory."
        }
    }
}

public enum AddressBookCleanup {
    public static func perform(moving source: AddressBookSource) async throws {
        _ = try await quitContactsApp()
        _ = try await killContactsd()
        try moveSourceToTrash(source)
        try moveChangelogToTrash()
    }

    public static func quitContactsApp() async throws -> Bool {
        let result = try await Shell.run(
            ["/usr/bin/osascript", "-e", "tell application \"Contacts\" to quit"]
        )
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return result.status == 0
    }

    @discardableResult
    public static func killContactsd() async throws -> Bool {
        // contactsd auto-restarts via launchd. A plain SIGTERM releases file handles.
        let result = try await Shell.run(["/usr/bin/pkill", "-x", "contactsd"])
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return result.status == 0 || result.status == 1 // 1 = no matching process, acceptable
    }

    public static func moveSourceToTrash(_ source: AddressBookSource) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path.path) else {
            throw AddressBookCleanupError.sourceMissing(source.path)
        }
        let stamp = timestamp()
        let destinationName = "AddressBook-Source-\(source.shortID)-\(stamp)"
        try trash(source.path, renamedTo: destinationName)
    }

    public static func moveChangelogToTrash() throws {
        let fm = FileManager.default
        let root = AddressBookScanner.root
        let candidates = ["ABAssistantChangelog.aclcddb",
                          "ABAssistantChangelog.aclcddb-shm",
                          "ABAssistantChangelog.aclcddb-wal"]
        for name in candidates {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try trash(url, renamedTo: "\(name).\(timestamp())")
            }
        }
    }

    private static func trash(_ url: URL, renamedTo newName: String) throws {
        let fm = FileManager.default
        guard let trashURL = try? fm.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: false
        ) else {
            throw AddressBookCleanupError.trashUnavailable
        }
        let destination = trashURL.appendingPathComponent(newName)
        try fm.moveItem(at: url, to: destination)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
