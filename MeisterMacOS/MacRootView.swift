import SwiftUI

struct MacRootView: View {
    @State private var selection: BashModule.ID = BashModule.all.first?.id ?? ""

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
            if module.id == "addressbook" {
                // Native Swift — does not shell out
                AddressBookCleanupView()
            } else {
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
