import EventKit
import Observation
import SwiftUI

/// State and logic for the Calendar cleaner tab.
@Observable
@MainActor
final class CalendarViewModel {
    var finding: CalendarFinding?
    var isScanning = false
    var scanProgress: Double = 0
    var currentPhase: String = ""
    var errorMessage: String?
    var mutationCount = 0

    func scan() async {
        isScanning = true
        scanProgress = 0
        currentPhase = "Reading calendars"
        errorMessage = nil
        defer { isScanning = false }
        do {
            scanProgress = 0.2
            currentPhase = "Finding old events"
            finding = try await CalendarScanner.scan()
            scanProgress = 1
            currentPhase = "Complete"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteOldEvents() async {
        guard let finding else { return }
        do {
            try CalendarScanner.delete(events: finding.oldEvents)
            mutationCount += 1
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCompletedReminders() async {
        guard let finding else { return }
        do {
            try CalendarScanner.delete(reminders: finding.completedReminders)
            mutationCount += 1
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CalendarCleanerView: View {
    @State private var model = CalendarViewModel()
    @State private var permissions = PermissionManager.shared
    @State private var isConfirmingEventDeletion = false
    @State private var isConfirmingReminderDeletion = false

    var body: some View {
        NavigationStack {
            PermissionGate(
                title: "Calendar Access",
                systemImage: "calendar",
                message: "Meister helps archive old events and remove empty calendars. Changes stay on this device and sync through iCloud like any Calendar edit.",
                isGranted: permissions.isCalendarAuthorized,
                request: { await permissions.requestCalendarAccess() }
            ) {
                content
            }
            .navigationTitle("Calendar")
            .refreshable { await model.scan() }
            .task { permissions.refresh() }
            .task(id: permissions.calendarStatus) {
                if permissions.isCalendarAuthorized && model.finding == nil && !model.isScanning {
                    await model.scan()
                }
            }
            .haptic(.success, trigger: model.mutationCount)
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if model.isScanning {
                Section("Scanning") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.currentPhase).font(.subheadline)
                        ProgressView(value: model.scanProgress).tint(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let finding = model.finding {
                Section {
                    detailRow(count: finding.oldEvents.count, unit: "event")
                    if !finding.oldEvents.isEmpty {
                        Button(role: .destructive) {
                            isConfirmingEventDeletion = true
                        } label: {
                            Label("Delete Old Events", systemImage: "trash")
                        }
                    }
                } header: { Text("Old Events") } footer: {
                    Text("Events older than two years.")
                }

                Section {
                    if finding.emptyCalendars.isEmpty {
                        Text("No empty calendars.").foregroundStyle(.secondary)
                    } else {
                        ForEach(finding.emptyCalendars, id: \.calendarIdentifier) { calendar in
                            Label(calendar.title, systemImage: "square")
                        }
                    }
                } header: { Text("Empty Calendars") } footer: {
                    Text("Empty calendars can be removed from Settings > Calendar > Accounts.")
                }

                Section {
                    detailRow(count: finding.completedReminders.count, unit: "reminder")
                    if !finding.completedReminders.isEmpty {
                        Button(role: .destructive) {
                            isConfirmingReminderDeletion = true
                        } label: {
                            Label("Delete Completed Reminders", systemImage: "trash")
                        }
                    }
                } header: { Text("Completed Reminders") } footer: {
                    Text("Reminders completed more than two years ago.")
                }
            }

            Section {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
        }
        .confirmationDialog(
            "Delete Old Events?",
            isPresented: $isConfirmingEventDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await model.deleteOldEvents() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Events older than two years will be removed. This action syncs to your other devices.")
        }
        .confirmationDialog(
            "Delete Completed Reminders?",
            isPresented: $isConfirmingReminderDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await model.deleteCompletedReminders() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reminders completed more than two years ago will be removed.")
        }
    }

    private func detailRow(count: Int, unit: String) -> some View {
        HStack {
            Text("Found")
            Spacer()
            Text("^[\(count) \(unit)](inflect: true)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
