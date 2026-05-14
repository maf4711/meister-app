import SwiftUI
import AppKit
import MeradOSDesign4

struct NotifAppPerm: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let displayName: String
    let allowedAlert: Bool
    let allowedBanner: Bool
    let allowedSound: Bool
    let allowedBadge: Bool
    let allowedLockScreen: Bool
}

actor NotificationPermissionsReader {
    /// NotificationCenter stores per-app prefs in
    /// ~/Library/Preferences/.../com.apple.ncprefs.plist (binary plist).
    /// Read via `defaults read` — no SQLite needed for the basics.
    func read() async -> [NotifAppPerm] {
        let raw = run("/usr/bin/defaults", ["read", "com.apple.ncprefs"])
        return parse(raw)
    }

    /// Parse defaults output into permissions per bundle id.
    /// Format inside the plist: `apps = ( { "bundle-id" = "..."; flags = N; ... }, ... )`
    /// flags is a bitmask: 0x01 = badges, 0x02 = sound, 0x04 = banner, 0x08 = alert,
    /// 0x40 = lock screen, 0x4000 = show on lock.
    nonisolated func parse(_ raw: String) -> [NotifAppPerm] {
        var out: [NotifAppPerm] = []
        var depth = 0
        var current: [String: String] = [:]
        var insideAppsBlock = false

        for line in raw.split(separator: "\n") {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s.contains("apps = (") { insideAppsBlock = true; continue }
            guard insideAppsBlock else { continue }

            if s == "{" {
                depth += 1
                current = [:]
                continue
            }
            if s.hasPrefix("}") {
                depth -= 1
                if let bid = current["bundle-id"], let flagsStr = current["flags"], let flags = Int(flagsStr) {
                    let name = appName(forBundleID: bid) ?? bid
                    out.append(NotifAppPerm(
                        id: bid,
                        bundleID: bid,
                        displayName: name,
                        allowedAlert: (flags & 0x08) != 0,
                        allowedBanner: (flags & 0x04) != 0,
                        allowedSound: (flags & 0x02) != 0,
                        allowedBadge: (flags & 0x01) != 0,
                        allowedLockScreen: (flags & 0x40) != 0
                    ))
                }
                current = [:]
                continue
            }
            // Parse key = value;
            let parts = s.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \";,")) }
            if parts.count == 2 {
                current[parts[0]] = parts[1]
            }
        }
        return out.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    private nonisolated func appName(forBundleID bid: String) -> String? {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        return url?.deletingPathExtension().lastPathComponent
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

@MainActor
final class NotificationPermissionsModel: ObservableObject {
    @Published var entries: [NotifAppPerm] = []
    @Published var isLoading = false
    private let reader = NotificationPermissionsReader()

    var totalAllowed: Int {
        entries.filter { $0.allowedAlert || $0.allowedBanner }.count
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.entries = await reader.read()
    }
}

struct NotificationPermissionsView: View {
    @StateObject private var model = NotificationPermissionsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.entries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notification Permissions")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Welche Apps dürfen wann Notifications schicken. \(model.entries.count) Apps registriert, \(model.totalAllowed) erlaubt.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button("In Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            ContentUnavailableView("Keine Daten",
                                   systemImage: "bell.slash",
                                   description: Text("`defaults read com.apple.ncprefs` lieferte nichts. Apple hat das Format evtl. geändert."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.entries) { e in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 26)
                            .foregroundStyle(MD4.SemColor.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.displayName)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text(e.bundleID)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        flag("Alert", e.allowedAlert)
                        flag("Banner", e.allowedBanner)
                        flag("Sound", e.allowedSound)
                        flag("Badge", e.allowedBadge)
                        flag("Lock", e.allowedLockScreen)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func flag(_ label: String, _ on: Bool) -> some View {
        Text(label)
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((on ? MD4.SemColor.brandPrimary : MD4.SemColor.surfaceRaised).opacity(on ? 0.2 : 1),
                        in: Capsule())
            .foregroundStyle(on ? MD4.SemColor.brandPrimary : MD4.SemColor.textTertiary)
    }
}
