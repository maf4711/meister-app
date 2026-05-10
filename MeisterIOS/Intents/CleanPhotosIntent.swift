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

/// Single AppShortcutsProvider for the whole iOS target — Apple allows only
/// one conformance per app, so all Siri/Shortcuts entry points live here.
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
        AppShortcut(
            intent: QuickCleanIntent(),
            phrases: [
                "Quick-Clean mit \(.applicationName)",
                "\(.applicationName) Quick-Clean",
                "\(.applicationName) aufräumen",
            ],
            shortTitle: "Quick-Clean",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: ShowHealthScoreIntent(),
            phrases: [
                "\(.applicationName) Health Score",
                "Wie gesund ist mein iPhone laut \(.applicationName)?",
                "\(.applicationName) Status",
            ],
            shortTitle: "Health Score",
            systemImageName: "heart.text.square.fill"
        )
    }
}
