import XCTest
import SwiftUI
@testable import MeisterIOS

/// Exhaustive tests for `ThemePreference` — grounded entirely in
/// `MeisterIOS/Core/ThemePreference.swift`.
///
/// The enum is `String`-backed, `CaseIterable`, `Identifiable` with exactly
/// three cases (`system`, `light`, `dark`) and four pure, deterministic
/// members: `id`, `title`, `systemImage`, `colorScheme`. Everything here is
/// pure value logic — no system objects, no I/O, no localization — so each
/// assertion uses exact equality.
final class ThemePreferenceTests: XCTestCase {

    // MARK: - allCases (exhaustiveness / ordering)

    func testAllCasesCountIsThree() {
        XCTAssertEqual(ThemePreference.allCases.count, 3)
    }

    func testAllCasesContainsEveryCase() {
        XCTAssertTrue(ThemePreference.allCases.contains(.system))
        XCTAssertTrue(ThemePreference.allCases.contains(.light))
        XCTAssertTrue(ThemePreference.allCases.contains(.dark))
    }

    func testAllCasesOrderIsSourceDeclarationOrder() {
        XCTAssertEqual(ThemePreference.allCases, [.system, .light, .dark])
    }

    func testAllCasesHasNoDuplicates() {
        XCTAssertEqual(Set(ThemePreference.allCases).count, ThemePreference.allCases.count)
    }

    // MARK: - rawValue (per case)

    func testRawValueSystem() {
        XCTAssertEqual(ThemePreference.system.rawValue, "system")
    }

    func testRawValueLight() {
        XCTAssertEqual(ThemePreference.light.rawValue, "light")
    }

    func testRawValueDark() {
        XCTAssertEqual(ThemePreference.dark.rawValue, "dark")
    }

    func testRawValuesAreUniqueAcrossAllCases() {
        let raws = ThemePreference.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
    }

    // MARK: - init(rawValue:) round-trip

    func testInitFromRawValueRoundTripsEveryCase() {
        for choice in ThemePreference.allCases {
            XCTAssertEqual(ThemePreference(rawValue: choice.rawValue), choice)
        }
    }

    func testInitFromKnownRawStrings() {
        XCTAssertEqual(ThemePreference(rawValue: "system"), .system)
        XCTAssertEqual(ThemePreference(rawValue: "light"), .light)
        XCTAssertEqual(ThemePreference(rawValue: "dark"), .dark)
    }

    func testInitFromUnknownRawValueIsNil() {
        XCTAssertNil(ThemePreference(rawValue: "auto"))
    }

    func testInitFromEmptyRawValueIsNil() {
        XCTAssertNil(ThemePreference(rawValue: ""))
    }

    func testInitIsCaseSensitive() {
        // rawValues are lowercase; capitalized input must not match.
        XCTAssertNil(ThemePreference(rawValue: "System"))
        XCTAssertNil(ThemePreference(rawValue: "LIGHT"))
        XCTAssertNil(ThemePreference(rawValue: "Dark"))
    }

    func testInitRejectsWhitespacePaddedRawValue() {
        XCTAssertNil(ThemePreference(rawValue: " light"))
        XCTAssertNil(ThemePreference(rawValue: "light "))
    }

    func testInitRejectsUnicodeNearMiss() {
        // Cyrillic small "а" (U+0430) instead of Latin "a" must not match "dark".
        XCTAssertNil(ThemePreference(rawValue: "d\u{0430}rk"))
    }

    // MARK: - id (Identifiable)

    func testIdEqualsRawValueForEveryCase() {
        for choice in ThemePreference.allCases {
            XCTAssertEqual(choice.id, choice.rawValue)
        }
    }

    func testIdSystem() {
        XCTAssertEqual(ThemePreference.system.id, "system")
    }

    func testIdLight() {
        XCTAssertEqual(ThemePreference.light.id, "light")
    }

    func testIdDark() {
        XCTAssertEqual(ThemePreference.dark.id, "dark")
    }

    func testIdsAreUniqueAcrossAllCases() {
        let ids = ThemePreference.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - title

    func testTitleSystem() {
        XCTAssertEqual(ThemePreference.system.title, "System")
    }

    func testTitleLight() {
        XCTAssertEqual(ThemePreference.light.title, "Light")
    }

    func testTitleDark() {
        XCTAssertEqual(ThemePreference.dark.title, "Dark")
    }

    func testTitleIsNonEmptyForEveryCase() {
        for choice in ThemePreference.allCases {
            XCTAssertFalse(choice.title.isEmpty)
        }
    }

    func testTitlesAreUniqueAcrossAllCases() {
        let titles = ThemePreference.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testTitleIsCapitalizedRawValue() {
        // Each title is the rawValue with a leading capital.
        for choice in ThemePreference.allCases {
            XCTAssertEqual(choice.title, choice.rawValue.capitalized)
        }
    }

    // MARK: - systemImage (SF Symbol names)

    func testSystemImageSystem() {
        XCTAssertEqual(ThemePreference.system.systemImage, "circle.lefthalf.filled")
    }

    func testSystemImageLight() {
        XCTAssertEqual(ThemePreference.light.systemImage, "sun.max")
    }

    func testSystemImageDark() {
        XCTAssertEqual(ThemePreference.dark.systemImage, "moon.fill")
    }

    func testSystemImageIsNonEmptyForEveryCase() {
        for choice in ThemePreference.allCases {
            XCTAssertFalse(choice.systemImage.isEmpty)
        }
    }

    func testSystemImagesAreUniqueAcrossAllCases() {
        let names = ThemePreference.allCases.map(\.systemImage)
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - colorScheme

    func testColorSchemeSystemIsNil() {
        XCTAssertNil(ThemePreference.system.colorScheme)
    }

    func testColorSchemeLightIsLight() {
        XCTAssertEqual(ThemePreference.light.colorScheme, .light)
    }

    func testColorSchemeDarkIsDark() {
        XCTAssertEqual(ThemePreference.dark.colorScheme, .dark)
    }

    func testColorSchemeIsNilOnlyForSystem() {
        for choice in ThemePreference.allCases {
            if choice == .system {
                XCTAssertNil(choice.colorScheme)
            } else {
                XCTAssertNotNil(choice.colorScheme)
            }
        }
    }

    func testLightAndDarkColorSchemesDiffer() {
        XCTAssertNotEqual(ThemePreference.light.colorScheme, ThemePreference.dark.colorScheme)
    }

    // MARK: - Idempotency / purity

    func testPropertiesAreStableAcrossRepeatedReads() {
        for choice in ThemePreference.allCases {
            XCTAssertEqual(choice.title, choice.title)
            XCTAssertEqual(choice.systemImage, choice.systemImage)
            XCTAssertEqual(choice.id, choice.id)
            XCTAssertEqual(choice.colorScheme, choice.colorScheme)
        }
    }

    // MARK: - Equatable / Hashable (synthesized via raw-value enum)

    func testEqualityReflexiveForEveryCase() {
        for choice in ThemePreference.allCases {
            XCTAssertEqual(choice, choice)
        }
    }

    func testDistinctCasesAreNotEqual() {
        XCTAssertNotEqual(ThemePreference.system, .light)
        XCTAssertNotEqual(ThemePreference.light, .dark)
        XCTAssertNotEqual(ThemePreference.system, .dark)
    }
}
