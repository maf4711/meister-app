import SwiftUI
import MeradOSDesign3

/// Spotlight-style fuzzy search over all BashModules. Triggered by Cmd-K.
struct CommandSearchView: View {
    @Binding var isPresented: Bool
    @Binding var selection: BashModule.ID
    @State private var query: String = ""
    @State private var highlight: Int = 0
    @FocusState private var focused: Bool

    private var results: [BashModule] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return Array(BashModule.all.prefix(8))
        }
        return BashModule.all
            .compactMap { module -> (BashModule, Int)? in
                let s = score(query: q, module: module)
                return s > 0 ? (module, s) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MD3.SemColor.textSecondary)
                TextField("Modul suchen…", text: $query)
                    .textFieldStyle(.plain)
                    .font(MD3.Typo.title3)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                    .focused($focused)
                    .onSubmit { commit() }
                Text("⌘K")
                    .font(MD3.Typo.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD3.SemColor.surfaceRaised, in: Capsule())
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider().background(MD3.SemColor.divider)

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
        .squircle(MD3.Radii.lg)
        .overlay(
            ContinuousSquircle(cornerRadius: MD3.Radii.lg)
                .stroke(MD3.SemColor.divider, lineWidth: 0.5)
        )
        .onKeyPress(.upArrow) { highlight = max(0, highlight - 1); return .handled }
        .onKeyPress(.downArrow) { highlight = min(results.count - 1, highlight + 1); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onAppear { focused = true; highlight = 0 }
        .onChange(of: query) { _, _ in highlight = 0 }
    }

    private func row(module: BashModule, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.symbol)
                .frame(width: 24)
                .foregroundStyle(isHighlighted ? MD3.SemColor.brandPrimary : MD3.SemColor.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(module.group.rawValue)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            if isHighlighted {
                Text("↵")
                    .foregroundStyle(MD3.SemColor.textTertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(isHighlighted ? MD3.SemColor.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func commit() {
        guard !results.isEmpty else { return }
        let target = results[min(highlight, results.count - 1)]
        selection = target.id
        isPresented = false
    }

    /// Simple subsequence-aware fuzzy score: title prefix match > title contains > group contains.
    private func score(query: String, module: BashModule) -> Int {
        let title = module.title.lowercased()
        let group = module.group.rawValue.lowercased()
        if title == query { return 1000 }
        if title.hasPrefix(query) { return 500 + (100 - min(99, title.count - query.count)) }
        if title.contains(query) { return 200 }
        if group.contains(query) { return 100 }
        // Subsequence: every char in query appears in title in order
        var ti = title.startIndex
        for q in query {
            guard let found = title[ti...].firstIndex(of: q) else { return 0 }
            ti = title.index(after: found)
        }
        return 50
    }
}
