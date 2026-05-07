import SwiftUI
import MeradOSDesign3

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
        .toolbarBackground(MD3.SemColor.surface, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

#Preview { ContentView() }
