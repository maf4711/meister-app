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
            module.destination
        } else {
            ContentUnavailableView(
                "Select a module",
                systemImage: "sidebar.left"
            )
        }
    }
}
