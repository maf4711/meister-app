import Foundation

/// Lightweight E.164-ish phone number normalizer. Not a full libphonenumber replacement —
/// opinionated toward DE/AT/CH defaults, extensible by passing a country code.
enum PhoneNormalizer {
    /// Default country if number has no prefix and no leading zero treatment fits.
    static var defaultCountryCode: String = "49" // Germany

    /// Normalize to +E164 form. Returns nil when input is clearly not a phone number (<6 digits).
    static func normalize(_ raw: String, defaultCC: String? = nil) -> String? {
        let cc = defaultCC ?? defaultCountryCode
        let digits = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) || $0 == "+" }.map(String.init).joined()
        guard digits.count >= 6 else { return nil }
        if digits.hasPrefix("+") { return "+\(digits.dropFirst().filter { $0.isNumber })" }
        if digits.hasPrefix("00") { return "+\(digits.dropFirst(2))" }
        if digits.hasPrefix("0") { return "+\(cc)\(digits.dropFirst())" }
        return "+\(digits)"
    }
}
