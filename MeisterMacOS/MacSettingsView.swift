import SwiftUI

struct MacSettingsView: View {
    @AppStorage("Meister.backupDirectory") private var backupDirectory: String = ""
    @AppStorage("Meister.confirmDestructiveOperations") private var confirmDestructive: Bool = true

    var body: some View {
        Form {
            Section("Backups") {
                HStack {
                    TextField("Default backup directory", text: $backupDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { pickDirectory() }
                }
                Text("vCard exports and .abbu archives are written here during maintenance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                Toggle("Confirm destructive operations", isOn: $confirmDestructive)
                Text("Always shows a preview before moving AddressBook sources, killing daemons, or deleting files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            backupDirectory = url.path
        }
    }
}
