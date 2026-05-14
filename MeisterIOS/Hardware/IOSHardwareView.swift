import SwiftUI
import UIKit
import MeradOSDesign4

/// iOS-side hardware inventory. Limited to what UIDevice + ProcessInfo
/// expose; no system_profiler equivalent on iOS.
struct IOSHardwareView: View {
    @StateObject private var model = IOSDashboardModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hardware Inventory")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MD4.SemColor.textPrimary)
                if let s = model.snapshot {
                    section("Device", icon: s.runtimeKind.icon,
                            rows: [
                                ("Runtime", s.runtimeKind.label),
                                ("Model", s.modelName),
                                ("OS", "\(s.osName) \(s.osVersion)"),
                                ("Hardware ID", hardwareIdentifier()),
                            ])
                    section("Speicher", icon: "internaldrive",
                            rows: [
                                ("Gesamt", s.totalDiskBytes.humanBytes),
                                ("Frei", s.freeDiskBytes.humanBytes),
                                ("Belegt", (s.totalDiskBytes - s.freeDiskBytes).humanBytes),
                                ("Diese App", s.appUsedBytes.humanBytes),
                            ])
                    section("CPU/RAM", icon: "memorychip",
                            rows: [
                                ("CPU Cores", "\(s.processorCount)"),
                                ("RAM", Int64(s.physicalMemoryBytes).humanBytes),
                                ("Architektur", architecture()),
                            ])
                    section("Energie", icon: s.hasBattery ? batteryIcon(s) : "powerplug.fill",
                            rows: s.hasBattery
                                ? [
                                    ("Akku-Stand", s.batteryLevel < 0 ? "—" : "\(Int((s.batteryLevel * 100).rounded()))%"),
                                    ("Status", s.batteryState.label),
                                    ("Low Power Mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "an" : "aus"),
                                    ("Thermal", thermalState()),
                                  ]
                                : [
                                    ("Quelle", "Netzstrom"),
                                    ("Hinweis", "Mac hat keinen Akku — UIDevice-Werte spiegeln keine reale Hardware"),
                                    ("Thermal", thermalState()),
                                  ])
                    section("Bildschirm", icon: "display",
                            rows: screenRows())
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(20)
        }
        .background(MD4.SemColor.background)
        .task { if model.snapshot == nil { await model.reload() } }
        .refreshable { await model.reload() }
    }

    private func section(_ title: String, icon: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(MD4.SemColor.brandPrimary)
                Text(title)
                    .font(MD4.Typo.headline)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Spacer()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.0)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text(pair.1)
                        .font(MD4.Typo.tabular(MD4.Typo.body))
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func hardwareIdentifier() -> String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    private func architecture() -> String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "—"
        }
    }

    private func screenRows() -> [(String, String)] {
        let screen = UIScreen.main
        let pts = screen.bounds.size
        let scale = screen.scale
        let pixelW = Int(pts.width * scale)
        let pixelH = Int(pts.height * scale)
        return [
            ("Auflösung", "\(pixelW) × \(pixelH)"),
            ("Punkte", "\(Int(pts.width)) × \(Int(pts.height))"),
            ("Scale", "\(Int(scale))×"),
        ]
    }

    private func batteryIcon(_ s: IOSDeviceSnapshot) -> String {
        if s.batteryState == .charging { return "battery.100.bolt" }
        if s.batteryLevel < 0 { return "battery.0" }
        let pct = Int((s.batteryLevel * 100).rounded())
        switch pct {
        case 75...:   return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default:      return "battery.0"
        }
    }
}
