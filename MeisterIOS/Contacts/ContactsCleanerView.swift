import Contacts
import ContactsUI
import Observation
import SwiftUI
import UIKit

/// State + domain logic for the Contacts cleaner.
@Observable
@MainActor
final class ContactsViewModel {
    var contacts: [ContactItem] = []
    var duplicateGroups: [ContactGroup] = []
    var lowQualityContacts: [ContactItem] = []
    var emptyContacts: [ContactItem] = []

    var isScanning = false
    var scanProgress: Double = 0
    var currentPhase: String = ""
    var latestBackupURL: URL?
    var errorMessage: String?

    /// Increments on destructive completion so the view can play a haptic.
    var mutationCount = 0

    func scan() async {
        isScanning = true
        scanProgress = 0
        currentPhase = "Reading contacts"
        defer { isScanning = false }
        do {
            let loaded = try await Task.detached { try ContactScanner.fetchAll() }.value
            contacts = loaded
            currentPhase = "Reading contacts — \(loaded.count) entries"
            scanProgress = 0.15

            duplicateGroups = await ContactDeduplicator.dedupe(loaded) { [weak self] value, phase in
                Task { @MainActor in
                    guard let self else { return }
                    self.scanProgress = 0.15 + value * 0.7
                    self.currentPhase = phase
                }
            }

            currentPhase = "Scoring quality"
            scanProgress = 0.9
            lowQualityContacts = loaded
                .filter { $0.quality < 0.5 && !$0.isEmpty }
                .sorted { $0.quality < $1.quality }
            emptyContacts = loaded.filter(\.isEmpty)
            scanProgress = 1
            currentPhase = "Complete"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backup() async {
        do {
            latestBackupURL = try ContactBackup.exportAll()
            mutationCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(_ group: ContactGroup) async {
        do {
            try ContactScanner.merge(group: group)
            mutationCount += 1
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEmpty() async {
        do {
            try ContactScanner.delete(emptyContacts)
            mutationCount += 1
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContactsCleanerView: View {
    @State private var model = ContactsViewModel()
    @State private var permissions = PermissionManager.shared
    @State private var isConfirmingEmptyDeletion = false

    var body: some View {
        NavigationStack {
            PermissionGate(
                title: "Contacts Access",
                systemImage: "person.2",
                message: "Meister finds duplicate contacts and merges them locally. Nothing is uploaded.",
                state: permissions.contactsGateState,
                request: { await permissions.requestContactsAccess() }
            ) {
                content
            }
            .navigationTitle("Contacts")
            .refreshable { await model.scan() }
            .task { permissions.refresh() }
            .task(id: permissions.contactsStatus) {
                if permissions.isContactsAuthorized && model.contacts.isEmpty && !model.isScanning {
                    await model.scan()
                }
            }
            .haptic(.success, trigger: model.mutationCount)
            .alert(
                "Couldn't Finish",
                isPresented: .constant(model.errorMessage != nil),
                presenting: model.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { message in
                Text(message)
            }
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(model.currentPhase), \(Int(model.scanProgress * 100)) percent")
                }
            }

            Section("Summary") {
                summaryRow("Total Contacts", value: "\(model.contacts.count)")
                summaryRow("Duplicate Groups", value: "\(model.duplicateGroups.count)")
                summaryRow("Low-Quality", value: "\(model.lowQualityContacts.count)")
                summaryRow("Empty", value: "\(model.emptyContacts.count)")
            }

            Section("Backup") {
                Button {
                    Task { await model.backup() }
                } label: {
                    Label("Back Up to vCard", systemImage: "square.and.arrow.down.on.square")
                }
                .accessibilityHint("Exports all contacts to a vCard file stored inside the app's Documents folder.")
                if let url = model.latestBackupURL {
                    Text("Saved: \(url.lastPathComponent)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Duplicate Groups") {
                if model.duplicateGroups.isEmpty {
                    Text("No duplicates found.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.duplicateGroups) { group in
                        NavigationLink {
                            ContactGroupDetailView(
                                group: group,
                                onMerge: { group in Task { await model.merge(group) } }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).fontWeight(.medium)
                                Text("^[\(group.items.count) entries](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !model.emptyContacts.isEmpty {
                Section("Empty Contacts") {
                    Button(role: .destructive) {
                        isConfirmingEmptyDeletion = true
                    } label: {
                        Label("Delete \(model.emptyContacts.count) Empty Contacts", systemImage: "trash")
                    }
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
            "Delete \(model.emptyContacts.count) Empty Contacts?",
            isPresented: $isConfirmingEmptyDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteEmpty() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Contacts with no name, phone, or email will be permanently removed from this device and iCloud.")
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows a single group of duplicate contacts with an explanation of which entry wins.
struct ContactGroupDetailView: View {
    let group: ContactGroup
    let onMerge: (ContactGroup) -> Void

    @State private var isConfirmingMerge = false
    @State private var previewContact: CNContact?

    var body: some View {
        List {
            ForEach(group.items) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fullName.isEmpty ? "No Name" : item.fullName)
                            .fontWeight(.medium)
                        if !item.phones.isEmpty {
                            Text(item.phones.joined(separator: ", "))
                                .font(.caption)
                        }
                        if !item.emails.isEmpty {
                            Text(item.emails.joined(separator: ", "))
                                .font(.caption)
                        }
                        Text("Quality: \(Int((item.quality * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Tom: "Bei den Duplikat Kontakten solltest du auch eine
                    // öffnen-Vorschau einbauen, damit man bei den Dubletten
                    // besser sieht was bei dem Kontakt alles gespeichert ist".
                    // Native CNContactViewController shows every field
                    // (address, birthday, notes, related names, IM accounts,
                    // social profiles) without us re-rendering them.
                    Button {
                        previewContact = item.cn
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Vollständigen Kontakt anzeigen")
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingMerge = true
                } label: {
                    Label("Merge into Primary", systemImage: "arrow.triangle.merge")
                }
            } footer: {
                Text("The contact with the highest quality score is kept. Phones and emails from the others are copied onto it before deletion.")
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Merge \(group.items.count) Contacts?",
            isPresented: $isConfirmingMerge,
            titleVisibility: .visible
        ) {
            Button("Merge", role: .destructive) { onMerge(group) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action can't be undone, but you can restore from the latest vCard backup.")
        }
        .sheet(item: $previewContact) { contact in
            ContactPreviewSheet(contact: contact)
        }
    }
}

/// SwiftUI wrapper around CNContactViewController. Read-only, no editing —
/// the goal is just to inspect what's stored, especially when comparing
/// duplicates side-by-side before a merge.
///
/// Tom Build 33: tapping the magnifying glass crashed the app. Cause:
/// `ContactScanner.keys` only fetches name/phone/email/thumbnail to keep the
/// dedup scan fast, but `CNContactViewController(for:)` reads ~30 fields
/// (postal addresses, dates, social profiles, IM accounts, related names…)
/// and force-unwraps any that weren't part of the original fetch — instant
/// crash. Fix: re-fetch the single contact by identifier with the view
/// controller's own descriptor on demand.
struct ContactPreviewSheet: UIViewControllerRepresentable {
    let contact: CNContact
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let fullContact = Self.refetch(contact) ?? contact
        let vc = CNContactViewController(for: fullContact)
        vc.allowsEditing = false
        vc.allowsActions = false
        vc.contactStore = CNContactStore()
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismiss)
        )
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    private static func refetch(_ contact: CNContact) -> CNContact? {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactViewController.descriptorForRequiredKeys(),
        ]
        return try? store.unifiedContact(withIdentifier: contact.identifier, keysToFetch: keys)
    }

    final class Coordinator: NSObject {
        let onDismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.onDismiss = dismiss }
        @objc func dismiss() { onDismiss() }
    }
}
