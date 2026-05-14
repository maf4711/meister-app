import SwiftUI
import AppKit
import MeradOSDesign4

@MainActor
final class SSHKeysModel: ObservableObject {
    @Published var keys: [SSHKey] = []
    @Published var isLoading = false
    private let reader = SSHKeyReader()

    var riskCounts: (low: Int, medium: Int, high: Int) {
        var l = 0, m = 0, h = 0
        for k in keys {
            switch k.risk {
            case .low: l += 1
            case .medium: m += 1
            case .high: h += 1
            }
        }
        return (l, m, h)
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.keys = await reader.read()
    }
}

struct SSHKeysView: View {
    @StateObject private var model = SSHKeysModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.keys.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SSH Keys")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("~/.ssh — Typ, Bit-Länge, Fingerprint, Passphrase-Status, Risk-Score.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.keys.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.keys.isEmpty {
            ContentUnavailableView("Keine SSH-Keys gefunden",
                                   systemImage: "key.slash",
                                   description: Text("`~/.ssh` ist leer oder es existieren nur Private-Keys ohne `.pub`-Pendant."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                riskBadges
                Divider().background(MD4.SemColor.divider)
                keysList
            }
        }
    }

    private var riskBadges: some View {
        HStack(spacing: 12) {
            badge("\(model.riskCounts.high) High Risk", MD4.SemColor.error)
            badge("\(model.riskCounts.medium) Medium", MD4.SemColor.warning)
            badge("\(model.riskCounts.low) OK", MD4.SemColor.success)
            Spacer()
            Text("\(model.keys.count) Keys gesamt")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var keysList: some View {
        List(model.keys) { k in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    riskDot(k.risk)
                    Text(k.publicPath.lastPathComponent)
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                    Text(k.keyType)
                        .font(MD4.Typo.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MD4.SemColor.surfaceRaised, in: Capsule())
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    if let b = k.bits {
                        Text("\(b) bit")
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    passphraseTag(k.hasPassphrase)
                }
                if let fp = k.fingerprint {
                    Text(fp)
                        .font(MD4.Typo.tabular(MD4.Typo.caption))
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let comment = k.comment, !comment.isEmpty {
                    Text(comment)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .swipeActions {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([k.publicPath])
                } label: { Label("Reveal", systemImage: "magnifyingglass") }
                .tint(MD4.SemColor.brandPrimary)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func riskDot(_ r: SSHKey.Risk) -> some View {
        let color: Color = {
            switch r {
            case .low: return MD4.SemColor.success
            case .medium: return MD4.SemColor.warning
            case .high: return MD4.SemColor.error
            }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func passphraseTag(_ s: SSHKey.KeyState) -> some View {
        let (label, color): (String, Color) = {
            switch s {
            case .protected:    return ("passphrase", MD4.SemColor.success)
            case .unprotected:  return ("ohne passphrase", MD4.SemColor.error)
            case .noPrivate:    return ("nur public", MD4.SemColor.textTertiary)
            case .unknown:      return ("?", MD4.SemColor.textTertiary)
            }
        }()
        return Text(label)
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
