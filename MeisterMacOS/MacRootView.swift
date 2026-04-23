import SwiftUI

struct MacRootView: View {
    @State private var selection: Section = .addressBook

    enum Section: String, CaseIterable, Identifiable {
        case addressBook = "AddressBook"
        case contacts = "Contacts"
        case storage = "Storage"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .addressBook: return "AddressBook Cleanup"
            case .contacts: return "Contact Dedup"
            case .storage: return "Storage"
            }
        }
        var symbol: String {
            switch self {
            case .addressBook: return "externaldrive.badge.exclamationmark"
            case .contacts: return "person.2.crop.square.stack"
            case .storage: return "internaldrive"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selection {
            case .addressBook: AddressBookCleanupView()
            case .contacts: ContactDedupPlaceholder()
            case .storage: StoragePlaceholder()
            }
        }
    }
}

private struct ContactDedupPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Coming from iOS target",
            systemImage: "person.2.crop.square.stack",
            description: Text("The deduplicator, backup, and merge logic ships with the iOS app. Mac target will gain a GUI over the same engine in a later phase.")
        )
    }
}

private struct StoragePlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Not implemented",
            systemImage: "internaldrive",
            description: Text("System storage breakdown is macOS-specific and will reuse parts of iOS Diagnostics.")
        )
    }
}
