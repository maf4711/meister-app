import SwiftUI
import MeradOSDesign3

struct ContentView: View {
    var body: some View {
        TabView {
            IOSDashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            IOSAutoCleanView()
                .tabItem { Label("Alles erledigen", systemImage: "wand.and.stars.inverse") }
            PhotosCleanerView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
            ContactsCleanerView()
                .tabItem { Label("Contacts", systemImage: "person.2") }
            StorageView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            IOSHardwareView()
                .tabItem { Label("Hardware", systemImage: "gearshape.2") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .toolbarBackground(MD3.SemColor.surface, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

#Preview { ContentView() }
