import SwiftUI
import MeradOSDesign4

@MainActor
final class SlackWebhookModel: ObservableObject {
    @Published var webhookURL: String = ""
    @Published var isSending = false
    @Published var lastResult: String?

    var isConfigured: Bool {
        WebhookSecretStore.validURL(webhookURL) != nil
    }

    func load() {
        do {
            webhookURL = try WebhookSecretStore.load()
            if let legacy = UserDefaults.standard.string(forKey: "meister.slack.webhook") {
                if webhookURL.isEmpty {
                    try WebhookSecretStore.save(legacy)
                    webhookURL = legacy
                }
                UserDefaults.standard.removeObject(forKey: "meister.slack.webhook")
            }
        } catch { lastResult = error.localizedDescription }
    }

    func save() {
        guard webhookURL.isEmpty || isConfigured else { lastResult = "Gültige Slack-HTTPS-URL erforderlich"; return }
        do {
            try WebhookSecretStore.save(webhookURL)
            lastResult = "Im Schlüsselbund gespeichert"
        } catch { lastResult = error.localizedDescription }
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
        guard !isSending else { return }
        guard let url = WebhookSecretStore.validURL(webhookURL) else {
            lastResult = "Ungültige Webhook-URL"
            return
        }
        isSending = true
        defer { isSending = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let session = URLSession(configuration: .ephemeral, delegate: WebhookSessionDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (_, resp) = try await session.data(for: request)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                lastResult = "OK · \(http.statusCode)"
            } else if let http = resp as? HTTPURLResponse {
                lastResult = "HTTP \(http.statusCode)"
            }
        } catch {
            lastResult = "Senden fehlgeschlagen. Netzwerkverbindung und Webhook prüfen."
        }
    }
}

struct SlackWebhookView: View {
    @StateObject private var model = SlackWebhookModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slack Webhook")
                .font(MD4.Typo.title2)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text("Optionaler Versand per Test-Button. Keine automatische Verbindung zum Autopilot.")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
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
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            SecureField("https://hooks.slack.com/services/T.../B.../...", text: $model.webhookURL)
                .textFieldStyle(.roundedBorder)
                .font(MD4.Typo.tabular(MD4.Typo.body))
            HStack {
                if model.isConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MD4.SemColor.success)
                    Text("Konfiguriert")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.success)
                } else {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(MD4.SemColor.warning)
                    Text("Gültige Slack-HTTPS-URL erforderlich")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.warning)
                }
                Spacer()
                Button("Im Schlüsselbund speichern") { model.save() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Webhook anlegen")
                .font(MD4.Typo.caption.bold())
                .foregroundStyle(MD4.SemColor.brandPrimary)
                .textCase(.uppercase)
            Text("In Slack: Apps → Incoming Webhooks → Add to Slack → Channel auswählen → URL kopieren.")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Link("api.slack.com/messaging/webhooks",
                 destination: URL(string: "https://api.slack.com/messaging/webhooks")!)
                .font(MD4.Typo.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.brandPrimary.opacity(0.08),
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
                        .font(MD4.Typo.caption)
                        .foregroundStyle(result.hasPrefix("OK") ? MD4.SemColor.success : MD4.SemColor.error)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
