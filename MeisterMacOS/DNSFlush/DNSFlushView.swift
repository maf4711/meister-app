import SwiftUI
import MeradOSDesign4

@MainActor
final class DNSFlushModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var lastFlushed: Date?

    enum Phase: Equatable { case idle, flushing, done, error(String) }

    func flush() async {
        phase = .flushing
        let result = await Task.detached { Self.runFlush() }.value
        if result.success {
            phase = .done
            lastFlushed = Date()
        } else {
            phase = .error(result.output)
        }
    }

    private nonisolated static func runFlush() -> (success: Bool, output: String) {
        // Two commands required since macOS 10.10:
        // 1. dscacheutil -flushcache   (User-level resolver cache)
        // 2. killall -HUP mDNSResponder (mDNS service cache)
        // Both require no special privileges on modern macOS.
        let cache = run("/usr/bin/dscacheutil", ["-flushcache"])
        let mdns  = run("/usr/bin/killall",     ["-HUP", "mDNSResponder"])
        let ok = (cache.status == 0) && (mdns.status == 0)
        let output = [cache.output, mdns.output].filter { !$0.isEmpty }.joined(separator: "\n")
        return (ok, output)
    }

    private nonisolated static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return (-1, error.localizedDescription) }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }
}

struct DNSFlushView: View {
    @StateObject private var model = DNSFlushModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DNS-Cache löschen")
                .font(MD4.Typo.title2)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text("dscacheutil -flushcache + killall -HUP mDNSResponder. Behebt DNS-Fehler, falsche Weiterleitungen und Hostsfile-Änderungen, die nicht greifen.")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(spacing: 20) {
            Spacer()
            flushButton
            phaseInfo
            if let last = model.lastFlushed {
                Text("Letzter Flush: \(last.formatted(date: .omitted, time: .shortened))")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            usageCard
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    private var flushButton: some View {
        Button {
            Task { await model.flush() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 24))
                    .rotationEffect(.degrees(model.phase == .flushing ? 360 : 0))
                    .animation(model.phase == .flushing
                               ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                               : .default, value: model.phase == .flushing)
                Text(model.phase == .flushing ? "Flusht…" : "DNS-Cache löschen")
                    .font(MD4.Typo.headline)
            }
            .padding(.horizontal, 32).padding(.vertical, 16)
            .frame(minWidth: 280)
            .foregroundStyle(.white)
            .background(MD4.SemColor.brandPrimary,
                        in: ContinuousSquircle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .flushing)
    }

    @ViewBuilder
    private var phaseInfo: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .flushing:
            Text("dscacheutil + mDNSResponder…")
                .font(MD4.Typo.small)
                .foregroundStyle(MD4.SemColor.textSecondary)
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MD4.SemColor.success)
                Text("Cache geleert. DNS-Auflösung startet sauber.")
                    .foregroundStyle(MD4.SemColor.success)
            }
            .font(MD4.Typo.body)
        case .error(let msg):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MD4.SemColor.warning)
                    Text("Fehler — wahrscheinlich braucht killall mehr Rechte.")
                        .foregroundStyle(MD4.SemColor.warning)
                }
                if !msg.isEmpty {
                    Text(msg)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
            .font(MD4.Typo.body)
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wann sinnvoll?")
                .font(MD4.Typo.caption.bold())
                .foregroundStyle(MD4.SemColor.brandPrimary)
                .textCase(.uppercase)
            ForEach([
                "Hosts-Datei geändert und Änderungen greifen nicht",
                "Websites leiten falsch weiter",
                "DNS-Leak-Test empfiehlt es",
                "Nach Netzwerk-Wechsel bei persistenten Fehlern",
            ], id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Text("·").foregroundStyle(MD4.SemColor.textTertiary)
                    Text(tip).font(MD4.Typo.small).foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 500, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
