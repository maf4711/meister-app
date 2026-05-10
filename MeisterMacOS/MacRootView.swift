import SwiftUI

@MainActor
final class NavigationState: ObservableObject {
    @Published var selection: BashModule.ID = "dashboard"
}

struct MacRootView: View {
    @EnvironmentObject private var nav: NavigationState
    @State private var commandSearchOpen = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { commandSearchOpen = true } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: [.command])
                .help("⌘K — Modul suchen")
            }
        }
        .overlay {
            if commandSearchOpen {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { commandSearchOpen = false }
                    CommandSearchView(isPresented: $commandSearchOpen,
                                      selection: $nav.selection)
                        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.snappy, value: commandSearchOpen)
    }

    private var sidebar: some View {
        List(selection: $nav.selection) {
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
        if let module = BashModule.all.first(where: { $0.id == nav.selection }) {
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
            case "xcode-switcher":
                XcodeSwitcherView()
            case "simulator-manager":
                SimulatorManagerView()
            case "docker-cleanup":
                DockerCleanupView()
            case "brew-doctor":
                BrewDoctorView()
            case "rosetta-audit":
                RosettaAuditView()
            case "quick-clean":
                QuickCleanView()
            case "auto-clean-all":
                AutoCleanAllView()
            case "extended-attributes":
                ExtendedAttributesView()
            case "symlink-inspector":
                SymlinkInspectorView()
            case "vpn-status":
                VPNStatusView()
            case "memory-pressure":
                MemoryPressureView()
            case "bluetooth-devices":
                BluetoothDevicesView()
            case "autopilot":
                AutopilotView()
            case "notification-perms":
                NotificationPermissionsView()
            case "icloud-sync":
                ICloudSyncView()
            case "wifi-passwords":
                WiFiPasswordsView()
            case "hosts-blocklist":
                HostsBlocklistView()
            case "app-permissions":
                AppPermissionsView()
            case "storage-forecast":
                StorageForecastView()
            case "slack-webhook":
                SlackWebhookView()
            case "disk-map":
                DiskMapView()
            case "process-manager":
                ProcessManagerView()
            case "network-connections":
                NetworkConnectionsView()
            case "system-updates":
                SystemUpdatesView()
            case "code-signature":
                CodeSignatureView()
            case "dns-flush":
                DNSFlushView()
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
