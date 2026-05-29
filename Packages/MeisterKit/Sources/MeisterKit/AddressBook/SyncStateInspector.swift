import Foundation

public struct SyncState: Sendable {
    public let accountID: String?
    public let contactsEnabled: Bool?
}

public enum SyncStateInspector {
    public static func inspect() async throws -> SyncState {
        let result = try await Shell.run(
            ["/usr/bin/defaults", "read", "MobileMeAccounts", "Accounts"]
        )
        guard result.status == 0 else {
            return SyncState(accountID: nil, contactsEnabled: nil)
        }
        return parse(result.stdout)
    }

    public static func parse(_ defaultsOutput: String) -> SyncState {
        let lines = defaultsOutput.components(separatedBy: "\n")
        var accountID: String? = nil
        var contactsEnabled: Bool? = nil
        var lastEnabled: Bool? = nil

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("AccountID"), accountID == nil {
                if let equalIdx = line.firstIndex(of: "=") {
                    let value = line[line.index(after: equalIdx)...]
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ;\""))
                    accountID = value
                }
            }
            if line.hasPrefix("Enabled") {
                if let equalIdx = line.firstIndex(of: "=") {
                    let value = line[line.index(after: equalIdx)...]
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
                    lastEnabled = (value == "1")
                }
            }
            if line.contains("Name = CONTACTS") {
                contactsEnabled = lastEnabled
            }
        }
        return SyncState(accountID: accountID, contactsEnabled: contactsEnabled)
    }
}
