import SwiftUI
import AppKit
import MeradOSDesign4

struct AppPermission: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let displayName: String?
    let service: TCCService
    let allowed: Bool
}

enum TCCService: String, CaseIterable, Identifiable {
    case camera        = "kTCCServiceCamera"
    case microphone    = "kTCCServiceMicrophone"
    case screenCapture = "kTCCServiceScreenCapture"
    case fda           = "kTCCServiceSystemPolicyAllFiles"
    case docFolder     = "kTCCServiceSystemPolicyDocumentsFolder"
    case desktop       = "kTCCServiceSystemPolicyDesktopFolder"
    case downloads     = "kTCCServiceSystemPolicyDownloadsFolder"
    case accessibility = "kTCCServiceAccessibility"
    case automation    = "kTCCServiceAppleEvents"
    case contacts      = "kTCCServiceAddressBook"
    case calendars     = "kTCCServiceCalendar"
    case reminders     = "kTCCServiceReminders"
    case photos        = "kTCCServicePhotos"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .camera: return "Kamera"
        case .microphone: return "Mikrofon"
        case .screenCapture: return "Bildschirmaufnahme"
        case .fda: return "Festplattenvollzugriff"
        case .docFolder: return "Dokumente"
        case .desktop: return "Schreibtisch"
        case .downloads: return "Downloads"
        case .accessibility: return "Bedienungshilfen"
        case .automation: return "Automatisierung (AppleEvents)"
        case .contacts: return "Kontakte"
        case .calendars: return "Kalender"
        case .reminders: return "Erinnerungen"
        case .photos: return "Fotos"
        }
    }
    var icon: String {
        switch self {
        case .camera: return "camera"
        case .microphone: return "mic"
        case .screenCapture: return "rectangle.dashed.badge.record"
        case .fda: return "externaldrive.fill"
        case .docFolder, .desktop, .downloads: return "folder"
        case .accessibility: return "figure.walk.circle"
        case .automation: return "applescript"
        case .contacts: return "person.2"
        case .calendars: return "calendar"
        case .reminders: return "list.bullet"
        case .photos: return "photo"
        }
    }
}

actor AppPermissionsReader {
    private let command: @Sendable (String, [String]) -> CommandRunner.Result
    init(command: @escaping @Sendable (String, [String]) -> CommandRunner.Result = { CommandRunner.run($0, $1) }) {
        self.command = command
    }

    /// Inspect only the user's TCC database, read-only. Missing access is not an empty audit.
    func read() async -> DiagnosticReport<[AppPermission]> {
        let userDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        let result = command("/usr/bin/sqlite3", ["-readonly", userDB.path, "SELECT service, client, auth_value FROM access;"])
        if let issue = result.issue(source: "App-Berechtigungen") { return .init(value: nil, issues: [issue]) }
        let malformed = result.output.split(separator: "\n").contains { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            return fields.count != 3 || Int(fields.last ?? "") == nil
        }
        let values = parse(result.output)
        return .init(value: malformed && values.isEmpty ? nil : values,
                     issues: malformed ? [.init(kind: .invalidOutput, source: "App-Berechtigungen")] : [])
    }

    nonisolated func parse(_ raw: String) -> [AppPermission] {
        var out: [AppPermission] = []
        for line in raw.split(separator: "\n") {
            let parts = String(line).split(separator: "|").map(String.init)
            guard parts.count >= 3 else { continue }
            guard let svc = TCCService(rawValue: parts[0]) else { continue }
            // auth_value: 0 = denied, 1 = unknown, 2 = allowed, 3 = limited
            let allowed = (Int(parts[2]) ?? 0) >= 2
            let bid = parts[1]
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            out.append(AppPermission(
                id: "\(svc.rawValue)|\(bid)",
                bundleID: bid,
                displayName: url?.deletingPathExtension().lastPathComponent,
                service: svc,
                allowed: allowed
            ))
        }
        return out.sorted {
            if $0.service == $1.service {
                return ($0.displayName ?? $0.bundleID) < ($1.displayName ?? $1.bundleID)
            }
            return $0.service.rawValue < $1.service.rawValue
        }
    }

}

@MainActor
final class AppPermissionsModel: ObservableObject {
    @Published var issues: [DiagnosticIssue] = []
    @Published var lastChecked: Date?
    @Published var items: [AppPermission] = []
    @Published var isLoading = false
    private let reader = AppPermissionsReader()

    var groupedByService: [(TCCService, [AppPermission])] {
        let dict = Dictionary(grouping: items) { $0.service }
        return TCCService.allCases.compactMap { svc in
            guard let entries = dict[svc] else { return nil }
            return (svc, entries)
        }
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = await reader.read()
        items = report.value ?? []
        issues = report.issues
        lastChecked = report.timestamp
    }
}

struct AppPermissionsView: View {
    @StateObject private var model = AppPermissionsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            DiagnosticIssuesView(issues: model.issues, timestamp: model.lastChecked)
            content
        }
        .background(MD4.SemColor.background)
        .task { await model.reload() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("App Permissions")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Lokale Benutzer-TCC-Datenbank: gespeicherte Kamera-, Mikrofon- und weitere Zugriffsentscheidungen.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading || model.lastChecked == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.issues.contains(where: { $0.kind == .permissionDenied }) {
            fdaPrompt
        } else if model.items.isEmpty {
            ContentUnavailableView(model.issues.isEmpty ? "Keine unterstützten Einträge" : "Berechtigungen nicht ermittelbar", systemImage: "lock.shield")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.groupedByService, id: \.0) { svc, items in
                        serviceSection(svc, items)
                    }
                }
                .padding(20)
            }
        }
    }

    private var fdaPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(MD4.SemColor.warning)
            Text("Full Disk Access erforderlich")
                .font(MD4.Typo.title3)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Text("Der Zugriff wurde verweigert. Festplattenvollzugriff für Meister in den Datenschutzeinstellungen prüfen und erneut laden.")
                .font(MD4.Typo.body)
                .foregroundStyle(MD4.SemColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("System Settings öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func serviceSection(_ svc: TCCService, _ items: [AppPermission]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: svc.icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(svc.label)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(MD4.Typo.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MD4.SemColor.surfaceRaised, in: Capsule())
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            ForEach(items) { p in
                HStack {
                    Image(systemName: p.allowed ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(p.allowed ? MD4.SemColor.success : MD4.SemColor.textTertiary)
                    Text(p.displayName ?? p.bundleID)
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Text(p.bundleID)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
