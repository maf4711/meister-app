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

    var diskUsagePct: Double {
        guard totalDiskBytes > 0 else { return 0 }
        return 1.0 - Double(freeDiskBytes) / Double(totalDiskBytes)
    }
}

actor IOSDeviceReader {
    func read() async -> IOSDeviceSnapshot {
        let device = await MainActor.run { UIDevice.current }
        let modelName = await MainActor.run {
            // Returns "iPhone" / "iPad". Hardware identifier (iPhone15,3) needs sysctl.
            return device.model
        }
        let os = await MainActor.run { (device.systemName, device.systemVersion) }

        let (total, free) = volumeStats()
        let appUsed = appBundleAndContainerSize()
        let mem = ProcessInfo.processInfo.physicalMemory
        let cpu = ProcessInfo.processInfo.processorCount
        let uptime = Int64(ProcessInfo.processInfo.systemUptime)

        await MainActor.run { device.isBatteryMonitoringEnabled = true }
        let level = await MainActor.run { device.batteryLevel }
        let state = await MainActor.run { device.batteryState }

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
            batteryState: state
        )
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
