import Observation
import Photos
import SwiftUI

/// State and logic for the Photos cleaner tab.
@Observable
@MainActor
final class PhotosViewModel {
    var library: [PhotoItem] = []
    var duplicateGroups: [SimilarityClustering.Cluster] = []
    /// Photos whose fingerprint couldn't be computed (e.g. iCloud-only) — surfaced
    /// so the user knows they were skipped, not silently treated as unique.
    var unanalyzedCount = 0
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

        let detector = SimilarityClustering(distanceThreshold: 0.5)
        let dupResult = await detector.cluster(fetched) { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.scanProgress = 0.1 + value * 0.55
                let done = Int(value * Double(fetched.count))
                self.currentPhase = "Detecting duplicates — \(done)/\(fetched.count)"
            }
        }
        duplicateGroups = dupResult.clusters
        unanalyzedCount = dupResult.failedIDs.count

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
            // Remove the just-deleted assets from in-memory lists so the UI
            // updates immediately — without waiting for the user to re-scan.
            let deletedIDs = Set(assets.map(\.localIdentifier))
            library.removeAll { deletedIDs.contains($0.asset.localIdentifier) }
            screenshots.removeAll { deletedIDs.contains($0.asset.localIdentifier) }
            screenRecordings.removeAll { deletedIDs.contains($0.asset.localIdentifier) }
            blurryPhotos.removeAll { deletedIDs.contains($0.0.asset.localIdentifier) }
            largeMedia.removeAll { deletedIDs.contains($0.asset.localIdentifier) }
            duplicateGroups = duplicateGroups
                .map { group in
                    let survivors = group.items.filter { !deletedIDs.contains($0.asset.localIdentifier) }
                    // Preserve the chosen best-shot keeper if it survived; only let
                    // the Cluster re-derive one when the keeper itself was deleted.
                    let keeperID = SimilarityClustering.preservedKeeperID(
                        current: group.keeperID,
                        survivingIDs: Set(survivors.map(\.id))
                    )
                    return SimilarityClustering.Cluster(items: survivors, keeperID: keeperID)
                }
                .filter { $0.items.count > 1 }   // drop groups that no longer have duplicates
        } catch {
            // The user cancelled the system confirmation — no error to surface.
        }
    }
}

struct PhotosCleanerView: View {
    @State private var model = PhotosViewModel()
    @State private var permissions = PermissionManager.shared
    @State private var presentedCategory: Category?
    @State private var showAutoDeleteConfirm = false

    /// Every reclaimable asset across all categories — duplicates (copies only),
    /// screenshots, screen recordings, blurry photos. Excludes Large Media —
    /// large files often aren't junk, opt-in only.
    private var allReclaimableAssets: [PHAsset] {
        var ids = Set<String>()
        var out: [PHAsset] = []
        let add: (PHAsset) -> Void = { a in
            if ids.insert(a.localIdentifier).inserted { out.append(a) }
        }
        for group in model.duplicateGroups {
            // Keep the best shot; the rest are deletion candidates.
            for copy in group.deletable { add(copy.asset) }
        }
        model.screenshots.forEach { add($0.asset) }
        model.screenRecordings.forEach { add($0.asset) }
        model.blurryPhotos.forEach { add($0.0.asset) }
        return out
    }

    private var allReclaimableBytes: Int64 {
        allReclaimableAssets.reduce(0) { acc, asset in
            // Best-effort size lookup via PhotoItem mapping
            let id = asset.localIdentifier
            for item in model.library where item.asset.localIdentifier == id {
                return acc + item.sizeBytes
            }
            return acc
        }
    }

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
                state: permissions.photosGateState,
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
                        itemCount: model.duplicateGroups.reduce(0) { $0 + $1.deletable.count },
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
                    if model.unanalyzedCount > 0 {
                        Text("^[\(model.unanalyzedCount) photo](inflect: true) couldn't be analyzed (still in iCloud). Re-run with Wi-Fi to include them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showAutoDeleteConfirm = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Delete All").fontWeight(.semibold)
                                Text("\(allReclaimableAssets.count) Items · \(ByteSize.formatted(allReclaimableBytes))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trash.fill")
                        }
                    }
                    .disabled(allReclaimableAssets.isEmpty)

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
        .confirmationDialog("Alle Vorschläge in den Papierkorb?",
                            isPresented: $showAutoDeleteConfirm,
                            titleVisibility: .visible) {
            Button("\(allReclaimableAssets.count) löschen · \(ByteSize.formatted(allReclaimableBytes))",
                   role: .destructive) {
                Task { await model.delete(allReclaimableAssets) }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Duplicates (Copies), Screenshots, Screen Recordings und Blurry Photos. Large Media bleibt aus — ist meistens kein Junk. Items landen in 'Recently Deleted' und sind 30 Tage rückholbar.")
        }
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
/// best shot. Uses a confirmation dialog for the destructive action.
struct DuplicateGroupsView: View {
    let groups: [SimilarityClustering.Cluster]
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
                        pendingDeletion = group.deletable.map(\.asset)
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
                Text("The best shot is kept. Deleted items move to the Recently Deleted album for 30 days.")
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
/// Tapping the thumbnail shows a full-screen preview (Tom's "Vorschau ist
/// ja winzig" request — bigger thumbnail + pinch-zoom in fullscreen).
struct AssetThumbnailRow: View {
    let item: PhotoItem
    @State private var thumbnail: UIImage?
    @State private var showFullscreen = false

    /// Bumped from 52→88 so the in-list preview is actually usable.
    private let thumbSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail itself does NOT capture taps anymore — when this row
            // sits inside an .editMode(.active) List (Screenshots, Blurry,
            // Large Media), the selection mechanism intercepts row taps and
            // a per-thumbnail .onTapGesture never fires. Tom: "Bau mal die
            // Foto Preview rein, damit man sehen kann was genau auf dem
            // Foto drauf ist" — he was tapping the thumbnail and nothing
            // happened. Solution: dedicated magnifying-glass button to the
            // right that opens fullscreen explicitly.
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemFill)
                }
            }
            .frame(width: thumbSize, height: thumbSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                Text("\(item.pixelWidth) × \(item.pixelHeight) · \(ByteSize.formatted(item.sizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Explicit preview button — works in both editMode lists and
            // plain lists. .buttonStyle(.borderless) keeps it from claiming
            // the whole row.
            Button {
                showFullscreen = true
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Vorschau in voller Größe")
        }
        .task {
            thumbnail = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: thumbSize * 2, height: thumbSize * 2)
            )
        }
        .accessibilityElement(children: .combine)
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenPhotoView(item: item)
        }
    }
}

/// Full-screen photo viewer shown when tapping a thumbnail.
/// Pinch-to-zoom + drag-to-pan + double-tap-to-toggle-zoom + tap-to-dismiss
/// (only when not zoomed). Loads at full asset resolution, falling back to
/// a 1600px preview while the original streams.
private struct FullscreenPhotoView: View {
    let item: PhotoItem
    @State private var fullImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = fullImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .ignoresSafeArea()
                    .gesture(magnification)
                    .simultaneousGesture(drag)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture { if scale <= minScale + 0.01 { dismiss() } }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            fullImage = await PhotoThumbnailLoader.thumbnail(
                for: item.asset,
                size: CGSize(width: 1600, height: 1600)
            )
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(item.pixelWidth) × \(item.pixelHeight) · \(ByteSize.formatted(item.sizeBytes))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(20)
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(maxScale, max(minScale, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if scale > minScale {
                scale = minScale
                lastScale = minScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }
}
