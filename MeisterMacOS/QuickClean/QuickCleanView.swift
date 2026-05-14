import SwiftUI
import MeradOSDesign4

struct QuickCleanView: View {
    @StateObject private var model = QuickCleanModel()
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .sparkleBurst(trigger: celebrate, color: MD4.SemColor.success)
        .onChange(of: model.bytesReclaimed) { _, new in
            if new > 0 { celebrate.toggle() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Clean")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("One-Click — alle Safe-Default-Caches in den Trash. Reversibel.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 24) {
            heroButton
            phaseLabel
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var heroButton: some View {
        Button {
            Task { await model.run() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.isRunning ? "sparkles" : "wand.and.stars")
                    .font(.system(size: 28))
                    .symbolEffect(.pulse, isActive: model.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(buttonLabel)
                        .font(MD4.Typo.headline)
                    Text(buttonSubtitle)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 18)
            .frame(minWidth: 320)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [MD4.SemColor.brandPrimary, MD4.SemColor.brandStrong],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: ContinuousSquircle(cornerRadius: 18)
            )
            .shadow(color: MD4.SemColor.brandPrimary.opacity(0.45), radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(model.isRunning)
    }

    private var phaseLabel: some View {
        VStack(spacing: 4) {
            switch model.phase {
            case .idle:
                EmptyView()
            case .scanning:
                Text("Scanne…")
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            case .cleaning:
                Text("Räume \(model.bytesScanned.humanBytes) auf…")
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            case .done:
                if let err = model.lastError {
                    Text("Fehler: \(err)")
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.error)
                } else {
                    Text("Reclaimed \(model.bytesReclaimed.humanBytes)")
                        .font(MD4.Typo.title3)
                        .foregroundStyle(MD4.SemColor.success)
                    Text("Items liegen im ~/.Trash. Mit Undo Last Cleanup zurückholbar.")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
        }
    }

    private var buttonLabel: String {
        switch model.phase {
        case .idle: return "Quick Clean starten"
        case .scanning: return "Scanne…"
        case .cleaning: return "Räume auf…"
        case .done: return "Nochmal laufen lassen"
        }
    }

    private var buttonSubtitle: String {
        switch model.phase {
        case .idle, .done: return "Caches, Logs, Browser, Dev-Tools — alles in einem Lauf"
        case .scanning: return "Größen werden ermittelt"
        case .cleaning: return "Items werden in den Trash verschoben"
        }
    }
}

#Preview {
    QuickCleanView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
