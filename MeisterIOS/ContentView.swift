import SwiftUI
import MeradOSDesign2

struct ContentView: View {
    var body: some View {
        TabView {
            PhotosCleanerView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
            ContactsCleanerView()
                .tabItem { Label("Contacts", systemImage: "person.2") }
            StorageView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            CalendarCleanerView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .toolbarBackground(Color.meradSurface, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

#Preview { ContentView() }
