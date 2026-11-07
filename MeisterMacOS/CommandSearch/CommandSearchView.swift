import SwiftUI
import MeradOSDesign4

/// Spotlight-style fuzzy search over all BashModules. Triggered by Cmd-K.
struct CommandSearchView: View {
    @Binding var isPresented: Bool
    @Binding var selection: BashModule.ID
    @State private var query: String = ""
    @State private var highlight: Int = 0
    @FocusState private var focused: Bool

    private var results: [BashModule] {
        BashModule.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MD4.SemColor.textSecondary)
                TextField("Modul suchen…", text: $query)
                    .textFieldStyle(.plain)
                    .font(MD4.Typo.title3)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                    .focused($focused)
                    .onSubmit { commit() }
                Text("⌘K")
                    .font(MD4.Typo.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD4.SemColor.surfaceRaised, in: Capsule())
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider().background(MD4.SemColor.divider)

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(results.enumerated()), id: \.offset) { idx, module in
                        Button { highlight = idx; commit() } label: {
                            row(module: module, isHighlighted: idx == highlight)
                        }
                        .buttonStyle(.plain)
                        .id(idx)
                    }
                }
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 360)
                .onChange(of: highlight) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(width: 560)
        .background(.thinMaterial)
        .squircle(MD4.Radii.lg)
        .overlay(
            ContinuousSquircle(cornerRadius: MD4.Radii.lg)
                .stroke(MD4.SemColor.divider, lineWidth: 0.5)
        )
        .onKeyPress(.upArrow) { highlight = max(0, highlight - 1); return .handled }
        .onKeyPress(.downArrow) { highlight = max(0, min(results.count - 1, highlight + 1)); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onAppear { focused = true; highlight = 0 }
        .onChange(of: query) { _, _ in highlight = 0 }
    }

    private func row(module: BashModule, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.symbol)
                .frame(width: 24)
                .foregroundStyle(isHighlighted ? MD4.SemColor.brandPrimary : MD4.SemColor.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(module.group.rawValue)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            if isHighlighted {
                Text("↵")
                    .foregroundStyle(MD4.SemColor.textTertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(isHighlighted ? MD4.SemColor.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func commit() {
        guard !results.isEmpty else { return }
        let target = results[max(0, min(highlight, results.count - 1))]
        selection = target.id
        isPresented = false
    }

}
