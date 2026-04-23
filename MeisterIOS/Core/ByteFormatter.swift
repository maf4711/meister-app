import Foundation

/// Human-readable byte formatter aligned with Apple's own conventions —
/// "1.2 MB", "384 KB", "2 GB". Always rounds to the nearest unit.
enum ByteSize {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    static func formatted(_ bytes: Int64) -> String { formatter.string(fromByteCount: bytes) }
    static func formatted(_ bytes: Int) -> String { formatted(Int64(bytes)) }
}
