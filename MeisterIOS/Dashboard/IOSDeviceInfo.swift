import Foundation
import UIKit

struct IOSDeviceSnapshot: Equatable {
    let modelName: String
    let osName: String
    let osVersion: String
    let totalDiskBytes: Int64
    let freeDiskBytes: Int64
    let appUsedBytes: Int64
    let physicalMemoryBytes: UInt64
    let processorCount: Int
    let uptimeSeconds: Int64
    let batteryLevel: Float          // 0...1, -1 if unknown
    let batteryState: UIDevice.BatteryState
    let hasBattery: Bool             // false on Mac runtimes — battery readings are fake there
    let runtimeKind: RuntimeKind

    enum RuntimeKind: String, Equatable {
        case iPhone, iPad
        case macCatalyst              // Mac Catalyst-built variant
        case iOSAppOnMac              // "Designed for iPad" running on Apple Silicon Mac

        var label: String {
            switch self {
            case .iPhone:        return "iPhone"
            case .iPad:          return "iPad"
            case .macCatalyst:   return "Mac (Catalyst)"
            case .iOSAppOnMac:   return "Mac (iPad-App)"
            }
        }

        var icon: String {
            switch self {
            case .iPhone:                return "iphone"
            case .iPad:                  return "ipad"
            case .macCatalyst, .iOSAppOnMac: return "macbook"
            }
        }
    }

    var diskUsagePct: Double {
        guard totalDiskBytes > 0 else { return 0 }
        return 1.0 - Double(freeDiskBytes) / Double(totalDiskBytes)
    }
}

actor IOSDeviceReader {
    func read() async -> IOSDeviceSnapshot {
        let device = await MainActor.run { UIDevice.current }
        let runtime = detectRuntimeKind()
        let modelName: String
        let osName: String
        let osVersion: String
        switch runtime {
        case .iOSAppOnMac, .macCatalyst:
            // The host Mac. UIDevice would lie ("iPad"); use sysctl for real info
            // and host operating-system version for the macOS version, since
            // ProcessInfo's version-string still reports the iOS-equivalent.
            modelName = macModelName() ?? "Mac"
            osName = "macOS"
            let v = ProcessInfo.processInfo.operatingSystemVersion
            osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        case .iPhone, .iPad:
            modelName = await MainActor.run { device.model }
            osName = await MainActor.run { device.systemName }
            osVersion = await MainActor.run { device.systemVersion }
        }
        let os = (osName, osVersion)

        let (total, free) = volumeStats()
        let appUsed = appBundleAndContainerSize()
        let mem = ProcessInfo.processInfo.physicalMemory
        let cpu = ProcessInfo.processInfo.processorCount
        let uptime = Int64(ProcessInfo.processInfo.systemUptime)

        // On Mac runtimes (iOS-app-on-Mac and Catalyst) UIDevice's battery
        // properties return spurious values — Justin reported "1% / Voll"
        // because the Mac mini has no battery and the iOS shim invents data.
        // Skip battery monitoring entirely on Mac runtimes.
        let hasBattery = (runtime == .iPhone || runtime == .iPad)
        let level: Float
        let state: UIDevice.BatteryState
        if hasBattery {
            await MainActor.run { device.isBatteryMonitoringEnabled = true }
            // First read after enabling monitoring is sometimes -1; brief wait
            // gives the system a chance to sample.
            try? await Task.sleep(for: .milliseconds(100))
            level = await MainActor.run { device.batteryLevel }
            state = await MainActor.run { device.batteryState }
        } else {
            level = -1
            state = .unknown
        }

        return IOSDeviceSnapshot(
            modelName: modelName,
            osName: os.0,
            osVersion: os.1,
            totalDiskBytes: total,
            freeDiskBytes: free,
            appUsedBytes: appUsed,
            physicalMemoryBytes: mem,
            processorCount: cpu,
            uptimeSeconds: uptime,
            batteryLevel: level,
            batteryState: state,
            hasBattery: hasBattery,
            runtimeKind: runtime
        )
    }

    private nonisolated func detectRuntimeKind() -> IOSDeviceSnapshot.RuntimeKind {
        // ProcessInfo flags are the source of truth on iOS 14+ / macOS 11+.
        if ProcessInfo.processInfo.isiOSAppOnMac { return .iOSAppOnMac }
        if ProcessInfo.processInfo.isMacCatalystApp { return .macCatalyst }
        // Fall back to UIDevice's idiom for native iOS.
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .pad ? .iPad : .iPhone
    }

    /// Best-effort Mac model lookup via sysctl.
    /// `hw.model` returns e.g. "Macmini9,1" or "MacBookPro18,2".
    private nonisolated func macModelName() -> String? {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let raw = String(cString: bytes)
        return raw.isEmpty ? nil : raw
    }

    private nonisolated func volumeStats() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (total, Int64(free))
    }

    /// Sum of the app's container directories — Documents, Library, tmp.
    private nonisolated func appBundleAndContainerSize() -> Int64 {
        let fm = FileManager.default
        let dirs: [URL] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory()),
        ].compactMap { $0 }

        var total: Int64 = 0
        for dir in dirs {
            guard let it = fm.enumerator(at: dir,
                                          includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                          options: [.skipsHiddenFiles]) else { continue }
            for case let f as URL in it {
                let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
                total += Int64(s)
            }
        }
        return total
    }
}

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension UIDevice.BatteryState {
    var label: String {
        switch self {
        case .charging: return "Lädt"
        case .full:     return "Voll"
        case .unplugged: return "Akku"
        case .unknown: return "—"
        @unknown default: return "—"
        }
    }
}
