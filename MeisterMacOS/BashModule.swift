import SwiftUI

/// Descriptor for a module that wraps a bash-meister command.
struct BashModule: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let group: Group
    let command: [String]
    let takesHostInput: Bool
    let runsLive: Bool   // true = user explicitly triggers with a button

    enum Group: String, CaseIterable {
        case maintenance = "Maintenance"
        case storage = "Storage & System"
        case network = "Network"
        case hardware = "Hardware"
        case dataTools = "Data & Tools"
    }

    static let all: [BashModule] = [
        // Maintenance
        .init(id: "overview",        title: "Health Overview",   symbol: "heart.text.square",            group: .maintenance, command: ["-H"],            takesHostInput: false, runsLive: false),
        .init(id: "maintain-dry",    title: "Maintenance Preview", symbol: "wrench.adjustable",          group: .maintenance, command: ["-n", "-a"],      takesHostInput: false, runsLive: false),
        .init(id: "heal",            title: "Auto-Healer",       symbol: "bandage",                      group: .maintenance, command: ["heal", "--dry-run"], takesHostInput: false, runsLive: false),

        // Storage & System
        .init(id: "disk",            title: "Disk Analyzer",     symbol: "externaldrive",                group: .storage,     command: ["disk"],          takesHostInput: false, runsLive: false),
        .init(id: "startup",         title: "Startup Items",     symbol: "power",                        group: .storage,     command: ["startup"],       takesHostInput: false, runsLive: false),
        .init(id: "free",            title: "Free RAM",          symbol: "memorychip",                   group: .storage,     command: ["free"],          takesHostInput: false, runsLive: true),

        // Network
        .init(id: "wifi",            title: "Wi-Fi Diagnostics", symbol: "wifi",                         group: .network,     command: ["wifi"],          takesHostInput: false, runsLive: false),
        .init(id: "ports",           title: "Open Ports",        symbol: "lock.open",                    group: .network,     command: ["ports"],         takesHostInput: false, runsLive: false),
        .init(id: "dns",             title: "DNS Leak Test",     symbol: "globe",                        group: .network,     command: ["dns"],           takesHostInput: false, runsLive: false),
        .init(id: "certs",           title: "SSL Certificates",  symbol: "checkmark.seal",               group: .network,     command: ["certs"],         takesHostInput: true,  runsLive: false),
        .init(id: "ntop",            title: "Network Top",       symbol: "chart.line.uptrend.xyaxis",    group: .network,     command: ["ntop", "1"],     takesHostInput: false, runsLive: false),

        // Hardware
        .init(id: "battery",         title: "Battery Health",    symbol: "battery.75",                   group: .hardware,    command: ["battery"],       takesHostInput: false, runsLive: false),
        .init(id: "thermal",         title: "Thermal",           symbol: "thermometer.medium",           group: .hardware,    command: ["thermal", "1"],  takesHostInput: false, runsLive: false),

        // Data & Tools
        .init(id: "addressbook",     title: "AddressBook Cleanup", symbol: "externaldrive.badge.exclamationmark", group: .dataTools, command: [],          takesHostInput: false, runsLive: false), // native Swift
        .init(id: "dotfiles",        title: "Dotfiles Sync",     symbol: "arrow.triangle.2.circlepath",  group: .dataTools,   command: ["push"],          takesHostInput: false, runsLive: true),
        .init(id: "simfix",          title: "Simulator Fix",     symbol: "iphone.gen2",                  group: .dataTools,   command: ["simfix"],        takesHostInput: false, runsLive: true),
    ]

    static func grouped() -> [(Group, [BashModule])] {
        Group.allCases.map { g in
            (g, all.filter { $0.group == g })
        }
    }
}
