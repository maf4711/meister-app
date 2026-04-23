import Observation
import Photos
import SwiftUI

/// State and logic for the Photos cleaner tab.
@Observable
@MainActor
final class PhotosViewModel {
    var library: [PhotoItem] = []
    var duplicateGroups: [DuplicateDetector.Group] = []
    var screenshots: [PhotoItem] = []
    var screenRecordings: [PhotoItem] = []
    var blurryPhotos: [(PhotoItem, Double)] = []
    var largeMedia: [PhotoItem] = []

    var isScanning = false
    var scanProgress: Double = 0
    var currentPhase: String = ""

    /// Bumped each time a destructive action completes — used to trigger haptics.
    var destructionCount = 0

    func scan() async {
        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        currentPhase = "Reading library"
        let fetched = await Task.detached(priority: .userInitiated) { PhotoScanner.fetchAll() }.value
        library = fetched
        currentPhase = "Reading library — \(fetched.count) items"
        scanProgress = 0.05

        // Cheap metadata scans finish almost instantly.
        screenshots = ScreenshotDetector.screenshots(in: fetched)
        screenRecordings = ScreenshotDetector.screenRecordings(in: fetched)
        largeMedia = LargeMediaFinder.largerThan(100 * 1024 * 1024, in: fetched)
        scanProgress = 0.1
        currentPhase = "Detecting duplicates — 0/\(fetched.count)"

        let detector = DuplicateDetector(threshold: 5)
        duplicateGroups = await detector.scan(items: fetched) { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.scanProgress = 0.1 + value * 0.55
                let done = Int(value * Double(fetched.count))
                self.currentPhase = "Detecting duplicates — \(done)/\(fetched.count)"
            }
        }

        currentPhase = "Checking for blur — 0/\(fetched.count)"
        blurryPhotos = await BlurDetector.scan(items: fetched, threshold: 0.002) { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.scanProgress = 0.65 + value * 0.35
                let done = Int(value * Double(fetched.count))
                self.currentPhase = "Checking for blur — \(done)/\(fetched.count)"
            }
        }
        currentPhase = "Complete"
        scanProgress = 1
    }

    func delete(_ assets: [PHAsset]) async {
        do {
            try await PhotoScanner.delete(assets)
            destructionCount += 1
        } catch {
            // The user cancelled the system confirmation — no error to surface.
        }
    }
}

struct PhotosCleanerView: View {
    @State private var model = PhotosViewModel()
    @State private var permissions = PermissionManager.shared
    @State private var presentedCategory: Category?

    enum Category: String, Identifiable, CaseIterable {
        case duplicates, screenshots, screenRecordings, blur, large
        var id: String { rawValue }

        var title: String {
            switch self {
            case .duplicates: "Duplicates"
            case .screenshots: "Screenshots"
            case .screenRecordings: "Screen Recordings"
            case .blur: "Blurry Photos"
            case .large: "Large Media"
            }
        }

        var systemImage: String {
            switch self {
            case .duplicates: "square.on.square"
            case .screenshots: "camera.viewfinder"
            case .screenRecordings: "record.circle"
            case .blur: "wand.and.stars.inverse"
            case .large: "film.stack"
            }
        }
    }

    var body: some View {
        NavigationStack {
            PermissionGate(
                title: "Photos Access",
                systemImage: "photo.on.rectangle.angled",
                message: "Meister scans your library on-device to find duplicates, screenshots, and blurry photos. Nothing is uploaded.",
                isGranted: permissions.isPhotosAuthorized,
                request: { await permissions.requestPhotosAccess() }
            ) {
                content
                    .task(id: permissions.photosStatus) {
                        if permissions.isPhotosAuthorized && model.library.isEmpty && !model.isScanning {
                            await model.scan()
                        }
                    }
            }
            .navigationTitle("Photos")
            .refreshable { await model.scan() }
            .task { permissions.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if model.isScanning {
                Section("Scanning") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.currentPhase).font(.subheadline)
                        ProgressView(value: model.scanProgress)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(model.currentPhase), \(Int(model.scanProgress * 100)) percent complete")
                }
            } else if model.library.isEmpty {
                Section {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label("Start Scan", systemImage: "magnifyingglass")
                            .fontWeight(.semibold)
                    }
                    .accessibilityHint("Examines your photo library for cleanup opportunities.")
                }
            }

            if !model.library.isEmpty {
                Section("Reclaim") {
                    summaryRow(
                        .duplicates,
                        itemCount: model.duplicateGroups.reduce(0) { $0 + $1.items.count - 1 },
                        reclaimable: model.duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
                    )
                    summaryRow(.screenshots, itemCount: model.screenshots.count,
                               reclaimable: totalBytes(model.screenshots))
                    summaryRow(.screenRecordings, itemCount: model.screenRecordings.count,
                               reclaimable: totalBytes(model.screenRecordings))
                    summaryRow(.blur, itemCount: model.blurryPhotos.count,
                               reclaimable: totalBytes(model.blurryPhotos.map(\.0)))
                    summaryRow(.large, itemCount: model.largeMedia.count,
                               reclaimable: totalBytes(model.largeMedia))
                }

                Section {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(item: $presentedCategory) { category in
            detail(for: category)
        }
        .haptic(.destruction, trigger: model.destructionCount)
    }

    private func summaryRow(_ category: Category, itemCount: Int, reclaimable: Int64) -> some View {
        Button {
            presentedCategory = category
        } label: {
            HStack {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                    Text("\(itemCount) items · \(ByteSize.formatted(reclaimable)) reclaimable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.title), \(itemCount) items, \(ByteSize.formatted(reclaimable)) reclaimable")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detail(for category: Category) -> some View {
        switch category {
        case .duplicates:
            DuplicateGroupsView(groups: model.duplicateGroups) { assets in
                Task { await model.delete(assets) }
            }
        case .screenshots:
            AssetSelectionView(title: "Screenshots", items: model.screenshots) { assets in
                Task { await model.delete(assets) }
            }
        case .screenRecordings:
            AssetSelectionView(title: "Screen Recordings", items: model.screenRecordings) { assets in
                Task { await model.delete(assets) }
            }
        case .blur:
            AssetSelectionView(title: "Blurry Photos", items: model.blurryPhotos.map(\.0)) { assets in
                Task { await model.delete(assets) }
            }
        case .large:
            AssetSelectionView(title: "Large Media", items: model.largeMedia) { assets in
                Task { await model.delete(assets) }
            }
        }
    }

    private func totalBytes(_ items: [PhotoItem]) -> Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// A sheet that shows duplicate groups and lets the user delete all but the
/// largest copy. Uses a confirmation dialog for the destructive action.
struct DuplicateGroupsView: View {
    let groups: [DuplicateDetector.Group]
    let onDelete: ([PHAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: [PHAsset]?

    var body: some View {
        NavigationStack {
            List(groups) { group in
                Section {
                    ForEach(group.items, id: \.id) { item in
                        AssetThumbnailRow(item: item)
                    }
                    Button(role: .destructive) {
                        let keeper = group.items.max { $0.sizeBytes < $1.sizeBytes }?.id
                        pendingDeletion = group.items
                            .filter { $0.id != keeper }
                            .map(\.asset)
                    } label: {
                        Label("Delete Copies", systemImage: "trash")
                    }
                } header: {
                    Text("^[\(group.items.count) copies](inflect: true) · Save \(ByteSize.formatted(group.reclaimableBytes))")
                }
            }
            .navigationTitle("Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete copies?",
                isPresented: .constant(pendingDeletion != nil),
                presenting: pendingDeletion
            ) { assets in
                Button("Delete \(assets.count) Items", role: .destructive) {
                    onDelete(assets)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("The largest copy is kept. Deleted items move to the Recently Deleted album for 30 days.")
            }
        }
    }
}

/// A generic selection sheet used by Screenshots / Blur / Large Media, etc.
struct AssetSelectionView: View {
    let title: String
    let items: [PhotoItem]
    let onDelete: ([PHAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing Here",
                        systemImage: "checkmark.circle",
                        description: Text("This category is clean.")
                    )
                } else {
                    List(items, id: \.id, selection: $selection) { item in
                        AssetThumbnailRow(item: item)
                            .tag(item.id)
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { selection = Set(items.map(\.id)) } label: {
                        Label("Select All", systemImage: "checklist")
                    }
                    .disabled(items.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label(selection.isEmpty ? "Delete" : "Delete \(selection.count)",
                              systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete \(selection.count) items?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let assets = items.filter { selection.contains($0.id) }.map(\.asset)
                    onDelete(assets)
                    selection.removeAll()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleted items move to the Recently Deleted album.")
            }
        }
    }
}

/// A single row with a thumbnail + metadata, loaded lazily via PhotoKit.
struct AssetThumbnailRow: View {
    let item: PhotoItem
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemFill)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                Text("\(item.pixelWidth) × \(item.pixelHeight) · \(ByteSize.formatted(item.sizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            thumbnail = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: 104, height: 104)
            )
        }
        .accessibilityElement(children: .combine)
    }
}
