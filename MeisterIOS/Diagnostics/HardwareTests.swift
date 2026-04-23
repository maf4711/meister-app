import AVFoundation
import CoreMotion
import Foundation
import UIKit

/// A suite of quick self-tests the user can run: microphone, speaker, vibration,
/// motion sensors. Each test returns a simple pass/fail + detail string.
enum HardwareTest: String, CaseIterable, Identifiable {
    case microphone, speaker, vibration, accelerometer, gyroscope, touch, battery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .speaker: "Speaker"
        case .vibration: "Vibration"
        case .accelerometer: "Accelerometer"
        case .gyroscope: "Gyroscope"
        case .touch: "Touch Response"
        case .battery: "Battery"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic"
        case .speaker: "speaker.wave.2"
        case .vibration: "waveform"
        case .accelerometer: "gyroscope"
        case .gyroscope: "gauge"
        case .touch: "hand.tap"
        case .battery: "battery.100"
        }
    }
}

struct HardwareResult {
    let test: HardwareTest
    let passed: Bool
    let detail: String
}

enum HardwareTestRunner {
    static func run(_ test: HardwareTest) async -> HardwareResult {
        switch test {
        case .microphone: await testMicrophone()
        case .speaker: testSpeaker()
        case .vibration: testVibration()
        case .accelerometer: await testAccelerometer()
        case .gyroscope: await testGyroscope()
        case .touch: HardwareResult(test: .touch, passed: true, detail: "Requires manual confirmation in UI")
        case .battery: testBattery()
        }
    }

    private static func testMicrophone() async -> HardwareResult {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            return HardwareResult(
                test: .microphone,
                passed: granted,
                detail: granted ? "Permission granted" : "Permission denied"
            )
        } catch {
            return HardwareResult(test: .microphone, passed: false, detail: error.localizedDescription)
        }
    }

    private static func testSpeaker() -> HardwareResult {
        AudioServicesPlaySystemSound(1104) // tick
        return HardwareResult(test: .speaker, passed: true, detail: "Played test tick")
    }

    private static func testVibration() -> HardwareResult {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        return HardwareResult(test: .vibration, passed: true, detail: "Played success haptic")
    }

    private static func testAccelerometer() async -> HardwareResult {
        let manager = CMMotionManager()
        guard manager.isAccelerometerAvailable else {
            return HardwareResult(test: .accelerometer, passed: false, detail: "Not available")
        }
        manager.accelerometerUpdateInterval = 0.1
        manager.startAccelerometerUpdates()
        try? await Task.sleep(nanoseconds: 400_000_000)
        defer { manager.stopAccelerometerUpdates() }
        if let data = manager.accelerometerData {
            let magnitude = sqrt(data.acceleration.x * data.acceleration.x
                + data.acceleration.y * data.acceleration.y
                + data.acceleration.z * data.acceleration.z)
            return HardwareResult(test: .accelerometer, passed: magnitude > 0.1,
                                  detail: String(format: "Magnitude: %.2f g", magnitude))
        }
        return HardwareResult(test: .accelerometer, passed: false, detail: "No data")
    }

    private static func testGyroscope() async -> HardwareResult {
        let manager = CMMotionManager()
        guard manager.isGyroAvailable else {
            return HardwareResult(test: .gyroscope, passed: false, detail: "Not available")
        }
        manager.gyroUpdateInterval = 0.1
        manager.startGyroUpdates()
        try? await Task.sleep(nanoseconds: 400_000_000)
        defer { manager.stopGyroUpdates() }
        return HardwareResult(test: .gyroscope, passed: manager.gyroData != nil, detail: "Receiving updates")
    }

    private static func testBattery() -> HardwareResult {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return HardwareResult(
            test: .battery,
            passed: level >= 0,
            detail: level >= 0 ? String(format: "%.0f%% charged", level * 100) : "Unavailable"
        )
    }
}
