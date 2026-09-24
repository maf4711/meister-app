import Foundation
import SwiftUI

/// A bounded, user-facing explanation; raw command output may contain secrets.
struct DiagnosticIssue: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case missingTool, permissionDenied, executionFailed, invalidOutput, unavailable, timedOut
    }

    let kind: Kind
    let source: String
    var id: Self { self }

    var message: String {
        switch kind {
        case .missingTool: return "Benötigtes Programm nicht gefunden."
        case .permissionDenied: return "Zugriff verweigert. Prüfe die benötigten Berechtigungen."
        case .executionFailed: return "Die Prüfung konnte nicht erfolgreich ausgeführt werden."
        case .invalidOutput: return "Die Antwort konnte nicht vollständig ausgewertet werden."
        case .unavailable: return "Diese Information ist auf diesem Mac nicht verfügbar."
        case .timedOut: return "Die Prüfung hat das Zeitlimit überschritten."
        }
    }
}

struct DiagnosticReport<Value> {
    let value: Value?
    let issues: [DiagnosticIssue]
    let timestamp: Date

    var isComplete: Bool { value != nil && issues.isEmpty }

    init(value: Value?, issues: [DiagnosticIssue] = [], timestamp: Date = Date()) {
        self.value = value
        var seen = Set<DiagnosticIssue>()
        self.issues = issues.filter { seen.insert($0).inserted }
        self.timestamp = timestamp
    }
}

extension DiagnosticReport: Sendable where Value: Sendable {}

struct DiagnosticIssuesView: View {
    let issues: [DiagnosticIssue]
    let timestamp: Date?

    var body: some View {
        if !issues.isEmpty || timestamp != nil {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(issues) { issue in
                    Label {
                        Text("\(issue.source): \(issue.message)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if let timestamp {
                    Text("Zuletzt geprüft: \(timestamp.formatted(date: .abbreviated, time: .standard))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
