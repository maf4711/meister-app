import Foundation
import UIKit

struct HardwareInfo {
    let deviceName: String
    let systemName: String
    let systemVersion: String
    let model: String
    let identifier: String
    let thermalState: ProcessInfo.ThermalState
    let lowPowerMode: Bool
    let batteryLevel: Float
    let batteryState: UIDevice.BatteryState

    static func read() -> HardwareInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        var systemInfo = utsname()
        uname(&systemInfo)
        let ident = Mirror(reflecting: systemInfo.machine).children.reduce("") { acc, el in
            guard let v = el.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
        return HardwareInfo(
            deviceName: device.name,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            model: device.model,
            identifier: ident,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: device.batteryLevel,
            batteryState: device.batteryState
        )
    }
}
