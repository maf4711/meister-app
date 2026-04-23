import Network
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @State private var networkMonitor = NetworkMonitor()
    @State private var hardware = HardwareInfo.read()
    @State private var isRunningSpeedTest = false

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    LabeledContent("Name", value: hardware.deviceName)
                    LabeledContent("Model", value: hardware.identifier)
                    LabeledContent("System", value: "\(hardware.systemName) \(hardware.systemVersion)")
                    LabeledContent("Thermal State", value: thermalLabel(hardware.thermalState))
                    LabeledContent("Low Power Mode", value: hardware.lowPowerMode ? "On" : "Off")
                }

                Section("Battery") {
                    LabeledContent("Charge", value: "\(Int(hardware.batteryLevel * 100))%")
                    LabeledContent("State", value: batteryLabel(hardware.batteryState))
                }

                Section("Network") {
                    LabeledContent("Status", value: networkMonitor.status == .satisfied ? "Connected" : "Offline")
                    LabeledContent("Interface", value: interfaceLabel(networkMonitor.interface))
                    LabeledContent("Expensive", value: networkMonitor.isExpensive ? "Yes" : "No")
                    LabeledContent("Latency",
                                   value: networkMonitor.pingMs.map { String(format: "%.1f ms", $0) } ?? "—")
                    LabeledContent("Download",
                                   value: networkMonitor.downloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—")

                    Button {
                        Task { await runSpeedTest() }
                    } label: {
                        Label(isRunningSpeedTest ? "Running Speed Test…" : "Run Speed Test",
                              systemImage: "speedometer")
                    }
                    .disabled(isRunningSpeedTest)
                }

                Section("Tools") {
                    NavigationLink { SpeedtestProView() } label: {
                        Label("Speedtest Pro", systemImage: "speedometer")
                    }
                    NavigationLink { DNSBenchmarkView() } label: {
                        Label("DNS Benchmark", systemImage: "network.badge.shield.half.filled")
                    }
                    NavigationLink { PrivacyDashboardView() } label: {
                        Label("Privacy Status", systemImage: "lock.shield.fill")
                    }
                    NavigationLink { HardwareTestsView() } label: {
                        Label("Hardware Tests", systemImage: "checklist")
                    }
                    NavigationLink { PrivacyAuditView() } label: {
                        Label("Privacy Audit", systemImage: "lock.shield")
                    }
                    NavigationLink { ClipboardMonitorView() } label: {
                        Label("Clipboard Monitor", systemImage: "doc.on.clipboard")
                    }
                    NavigationLink { WiFiHistoryView() } label: {
                        Label("Network History", systemImage: "network")
                    }
                }

                Section {
                    Button {
                        hardware = HardwareInfo.read()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                #if DEBUG
                Section {
                    Button {
                        Task {
                            let contactCount = try? await DebugSeed.populateContacts()
                            let eventCount = try? await DebugSeed.populateCalendar()
                            print("Seeded contacts=\(contactCount ?? 0) events=\(eventCount ?? 0)")
                        }
                    } label: {
                        Label("Populate Test Data", systemImage: "testtube.2")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Creates fuzzy-duplicate contacts and old calendar events. Only available in debug builds.")
                }
                #endif
            }
            .navigationTitle("Diagnostics")
            .refreshable { hardware = HardwareInfo.read() }
        }
    }

    private func runSpeedTest() async {
        isRunningSpeedTest = true
        await networkMonitor.measurePing()
        await networkMonitor.measureDownload()
        isRunningSpeedTest = false
    }

    private func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func batteryLabel(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: "Unknown"
        case .unplugged: "On Battery"
        case .charging: "Charging"
        case .full: "Full"
        @unknown default: "—"
        }
    }

    private func interfaceLabel(_ interface: NWInterface.InterfaceType?) -> String {
        switch interface {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wiredEthernet: "Ethernet"
        case .loopback: "Loopback"
        case .other: "Other"
        default: "—"
        }
    }
}
