import SwiftUI
import MeradOSDesign4

struct ContentView: View {
    /// Selection so the Shortcuts intent can deeplink into the Quick-Clean tab.
    @State private var selection: Tab = .dashboard
    @StateObject private var launcher = AutoCleanLauncher.shared

    enum Tab: Hashable {
        case dashboard, autoClean, photos, contacts, storage, hardware, diagnostics
    }

    var body: some View {
        TabView(selection: $selection) {
            IOSDashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)
            IOSAutoCleanView()
                .tabItem { Label("Alles erledigen", systemImage: "wand.and.stars.inverse") }
                .tag(Tab.autoClean)
            PhotosCleanerView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.photos)
            ContactsCleanerView()
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(Tab.contacts)
            StorageView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(Tab.storage)
            IOSHardwareView()
                .tabItem { Label("Hardware", systemImage: "gearshape.2") }
                .tag(Tab.hardware)
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                .tag(Tab.diagnostics)
        }
        .toolbarBackground(MD4.SemColor.surface, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: launcher.pendingAutoStart) { _, pending in
            // Shortcuts/Siri triggered Quick-Clean: jump to the right tab.
            // The actual run is started by IOSAutoCleanView once it sees the flag.
            if pending { selection = .autoClean }
        }
    }
}

#Preview { ContentView() }
