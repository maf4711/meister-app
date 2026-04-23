import AppIntents
import Photos

/// A Siri/Shortcuts entry point that summarizes Meister's photo scan results.
///
/// Opens the app so the full UI is available once the summary is spoken.
struct CleanPhotosIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Photo Library"
    static var description = IntentDescription(
        "Finds duplicates, screenshots, and blurry photos. Reports reclaimable space."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return .result(dialog: "Open Meister once to grant Photos access.")
        }
        let library = PhotoScanner.fetchAll()
        let screenshots = ScreenshotDetector.screenshots(in: library)
        let large = LargeMediaFinder.largerThan(100 * 1024 * 1024, in: library)
        let screenshotBytes = screenshots.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let largeBytes = large.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let reclaimable = ByteSize.formatted(screenshotBytes + largeBytes)
        return .result(dialog: "Found \(library.count) items. Potential savings: \(reclaimable).")
    }
}

/// Exposes the intent as a suggested Shortcut so it appears in the Shortcuts app
/// and can be triggered with a voice phrase.
struct MeisterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanPhotosIntent(),
            phrases: [
                "Scan photos in \(.applicationName)",
                "Clean photos with \(.applicationName)"
            ],
            shortTitle: "Scan Photos",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
