import SwiftUI
import MeradOSDesign3

@MainActor
final class SlackWebhookModel: ObservableObject {
    @AppStorage("meister.slack.webhook") var webhookURL: String = ""
    @Published var isSending = false
    @Published var lastResult: String?

    var isConfigured: Bool {
        URL(string: webhookURL)?.scheme?.hasPrefix("http") == true
    }

    func sendTest() async {
        await send(text: ":sparkles: Meister: Test-Nachricht. Dein Webhook funktioniert.")
    }

    /// Send a structured cleanup-report. Called by Autopilot's post-clean hook.
    func sendReport(reclaimedBytes: Int64, durationSeconds: Double, errors: [String] = []) async {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let bytes = formatter.string(fromByteCount: reclaimedBytes)
        var text = ":wand: Meister Autopilot: \(bytes) reclaimed in \(String(format: "%.1f", durationSeconds))s."
        if !errors.isEmpty {
            text += "\nErrors: " + errors.prefix(5).joined(separator: " | ")
        }
        await send(text: text)
    }

    private func send(text: String) async {
        guard let url = URL(string: webhookURL) else {
            lastResult = "Ungültige Webhook-URL"
            return
        }
        isSending = true
        defer { isSending = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                lastResult = "OK · \(http.statusCode)"
            } else if let http = resp as? HTTPURLResponse {
                lastResult = "HTTP \(http.statusCode)"
            }
        } catch {
            lastResult = error.localizedDescription
        }
    }
}

struct SlackWebhookView: View {
    @StateObject private var model = SlackWebhookModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slack Webhook")
                .font(MD3.Typo.title2)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text("Autopilot postet nach jedem Cleanup eine Zusammenfassung. Browser-Test-Button.")
                .font(MD3.Typo.small)
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                webhookInput
                howToCard
                testPanel
            }
            .padding(20)
        }
    }

    private var webhookInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incoming Webhook URL")
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textPrimary)
            TextField("https://hooks.slack.com/services/T.../B.../...", text: $model.webhookURL)
                .textFieldStyle(.roundedBorder)
                .font(MD3.Typo.tabular(MD3.Typo.body))
            HStack {
                if model.isConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MD3.SemColor.success)
                    Text("Konfiguriert")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.success)
                } else {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(MD3.SemColor.warning)
                    Text("Keine URL gesetzt — Autopilot kann keine Reports senden")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.warning)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Webhook anlegen")
                .font(MD3.Typo.caption.bold())
                .foregroundStyle(MD3.SemColor.brandPrimary)
                .textCase(.uppercase)
            Text("In Slack: Apps → Incoming Webhooks → Add to Slack → Channel auswählen → URL kopieren.")
                .font(MD3.Typo.small)
                .foregroundStyle(MD3.SemColor.textSecondary)
            Link("api.slack.com/messaging/webhooks",
                 destination: URL(string: "https://api.slack.com/messaging/webhooks")!)
                .font(MD3.Typo.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.brandPrimary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    Task { await model.sendTest() }
                } label: {
                    if model.isSending {
                        HStack { ProgressView().controlSize(.small); Text("Sende…") }
                    } else {
                        Label("Test-Nachricht senden", systemImage: "paperplane")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isConfigured || model.isSending)
                Spacer()
                if let result = model.lastResult {
                    Text(result)
                        .font(MD3.Typo.caption)
                        .foregroundStyle(result.hasPrefix("OK") ? MD3.SemColor.success : MD3.SemColor.error)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
