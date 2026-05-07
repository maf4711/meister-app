import SwiftUI

struct MacRootView: View {
    @State private var selection: BashModule.ID = "dashboard"

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(BashModule.grouped(), id: \.0) { group, modules in
                Section(group.rawValue) {
                    ForEach(modules) { module in
                        Label(module.title, systemImage: module.symbol)
                            .tag(module.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let module = BashModule.all.first(where: { $0.id == selection }) {
            switch module.id {
            case "dashboard":
                DashboardView()
            case "addressbook":
                AddressBookCleanupView()
            case "system-cleanup":
                SystemCleanupView()
            case "uninstaller":
                UninstallerView()
            case "large-old-files":
                LargeFilesView()
            case "duplicates":
                DuplicatesView()
            case "security-status":
                SecurityStatusView()
            case "browser-privacy":
                BrowserPrivacyView()
            case "login-items":
                LoginItemsView()
            case "hosts-file":
                HostsView()
            case "time-machine":
                TimeMachineView()
            case "health-score":
                HealthScoreView()
            case "energy-impact":
                EnergyImpactView()
            case "usb-devices":
                USBDevicesView()
            case "cleanup-history":
                CleanupHistoryView()
            case "hardware-inventory":
                HardwareInventoryView()
            case "default-apps":
                DefaultAppsView()
            case "keychain-audit":
                KeychainAuditView()
            case "ssh-keys":
                SSHKeysView()
            case "ssd-health":
                SSDHealthView()
            case "tag-manager":
                TagManagerView()
            case "undo-cleanup":
                UndoCleanupView()
            default:
                BashOutputView(module: module)
            }
        } else {
            ContentUnavailableView(
                "Select a module",
                systemImage: "sidebar.left"
            )
        }
    }
}
