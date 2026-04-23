import SwiftUI

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
        .toolbarBackground(Color.MeradOS.surface, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

#Preview { ContentView() }
