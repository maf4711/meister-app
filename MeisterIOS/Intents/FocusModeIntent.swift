import AppIntents

/// A Focus Filter users can add in Settings → Focus → Cleaning Focus that
/// toggles a "cleaning mode" inside Meister. When active the app pauses any
/// notifications and hides non-essential UI.
struct CleaningFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Cleaning Focus"
    static var description: LocalizedStringResource = "Pauses Meister notifications while you clean."

    @Parameter(title: "Silence While Cleaning")
    var silenceNotifications: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Silence notifications: \(\.$silenceNotifications)")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Cleaning Focus",
            subtitle: silenceNotifications ? "Silent" : "Audible"
        )
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(silenceNotifications, forKey: "focusSilence")
        return .result()
    }
}
