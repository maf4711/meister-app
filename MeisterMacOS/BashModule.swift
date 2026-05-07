import SwiftUI

/// Descriptor for a module that wraps a bash-meister command.
/// The bash CLI (`maf4711/homebrew-meister`) is the master source of truth —
/// every entry here is a thin shell-out. To add a module: implement in bash first,
/// then append to `all` below. No Swift code required.
struct BashModule: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let group: Group
    let command: [String]
    let takesHostInput: Bool
    let runsLive: Bool   // true = user explicitly triggers with a button
    let destructive: Bool  // true = needs confirmation

    enum Group: String, CaseIterable {
        case overview = "Overview"
        case maintenance = "Maintenance"
        case storage = "Storage & Cleanup"
        case network = "Network"
        case hardware = "Hardware"
        case macTools = "Mac Tools"
        case dataTools = "Data"
    }

    init(id: String, title: String, symbol: String, group: Group,
         command: [String], takesHostInput: Bool = false,
         runsLive: Bool = false, destructive: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.group = group
        self.command = command
        self.takesHostInput = takesHostInput
        self.runsLive = runsLive
        self.destructive = destructive
    }

    static let all: [BashModule] = [
        // Overview
        .init(id: "health",          title: "Health Dashboard",    symbol: "heart.text.square",         group: .overview,     command: ["-H"]),
        .init(id: "menu",            title: "TUI Menu",            symbol: "list.bullet.rectangle",     group: .overview,     command: ["menu"], runsLive: true),

        // Maintenance
        .init(id: "maintain-dry",    title: "Maintenance Preview", symbol: "wrench.adjustable",         group: .maintenance,  command: ["-n", "-a"]),
        .init(id: "maintain-all",    title: "Run All Maintenance", symbol: "wrench.and.screwdriver.fill", group: .maintenance, command: ["-a"],   runsLive: true, destructive: true),
        .init(id: "heal-dry",        title: "Auto-Heal Preview",   symbol: "bandage",                   group: .maintenance,  command: ["heal", "--dry-run"]),
        .init(id: "heal",            title: "Auto-Heal",           symbol: "cross.case.fill",           group: .maintenance,  command: ["heal"], runsLive: true, destructive: true),
        .init(id: "launch-agent",    title: "Install LaunchAgent", symbol: "clock.arrow.circlepath",    group: .maintenance,  command: ["-I"],   runsLive: true, destructive: true),

        // Storage & Cleanup
        .init(id: "system-cleanup",  title: "System Cleanup",      symbol: "sparkles",                  group: .storage,      command: []), // native Swift
        .init(id: "disk",            title: "Disk Analyzer",       symbol: "externaldrive",             group: .storage,      command: ["disk"]),
        .init(id: "large-files",     title: "Large Files",         symbol: "doc.badge.gearshape",       group: .storage,      command: ["-L", "-n"]),
        .init(id: "caches",          title: "Clean Caches",        symbol: "archivebox",                group: .storage,      command: ["-C", "-n"]),
        .init(id: "trash",           title: "Empty Trash",         symbol: "trash",                     group: .storage,      command: ["-T", "-n"]),
        .init(id: "hardtrash",       title: "Hard Trash Tool",     symbol: "trash.slash",               group: .storage,      command: ["-~:hardtrash"], runsLive: true, destructive: true),
        .init(id: "git-clean",       title: "Git Cleanup",         symbol: "arrow.triangle.branch",     group: .storage,      command: ["-G", "-n"]),
        .init(id: "xcode-clean",     title: "Xcode Cleanup",       symbol: "hammer",                    group: .storage,      command: ["-X", "-n"]),
        .init(id: "free",            title: "Free RAM",            symbol: "memorychip",                group: .storage,      command: ["free"], runsLive: true, destructive: true),
        .init(id: "startup",         title: "Startup Items",       symbol: "power",                     group: .storage,      command: ["startup"]),
        .init(id: "clear-recent",    title: "Clear Recent Items",  symbol: "clock.arrow.2.circlepath",  group: .storage,      command: ["-clearrecent"], runsLive: true, destructive: true),

        // Network
        .init(id: "wifi",            title: "Wi-Fi Diagnostics",   symbol: "wifi",                      group: .network,      command: ["wifi"]),
        .init(id: "ports",           title: "Open Ports",          symbol: "lock.open",                 group: .network,      command: ["ports"]),
        .init(id: "dns",             title: "DNS Leak Test",       symbol: "globe",                     group: .network,      command: ["dns"]),
        .init(id: "dns-debug",       title: "DNS Debug",           symbol: "network.badge.shield.half.filled", group: .network, command: ["-dns-debug"]),
        .init(id: "certs",           title: "SSL Certificates",    symbol: "checkmark.seal",            group: .network,      command: ["certs"], takesHostInput: true),
        .init(id: "ntop",            title: "Network Top",         symbol: "chart.line.uptrend.xyaxis", group: .network,      command: ["ntop", "1"]),
        .init(id: "top",             title: "Process Top",         symbol: "cpu",                       group: .network,      command: ["top", "1"]),
        .init(id: "sniff",           title: "Network Sniffer",     symbol: "dot.radiowaves.left.and.right", group: .network,  command: ["sniff", "1"]),
        .init(id: "sniffnet",        title: "Sniffnet Monitor",    symbol: "waveform.path.ecg",         group: .network,      command: ["-N"], runsLive: true),

        // Hardware
        .init(id: "battery",         title: "Battery Health",      symbol: "battery.75",                group: .hardware,     command: ["battery"]),
        .init(id: "thermal",         title: "Thermal",             symbol: "thermometer.medium",        group: .hardware,     command: ["thermal", "1"]),
        .init(id: "performance",     title: "Performance Check",   symbol: "speedometer",               group: .hardware,     command: ["-P", "-n"]),

        // Mac Tools
        .init(id: "rosetta",         title: "Install Rosetta",     symbol: "apple.terminal",            group: .macTools,     command: ["-rosetta"], runsLive: true, destructive: true),
        .init(id: "simfix",          title: "Simulator Fix",       symbol: "iphone.gen2",               group: .macTools,     command: ["simfix"], runsLive: true, destructive: true),
        .init(id: "reset-safari",    title: "Reset Safari",        symbol: "safari",                    group: .macTools,     command: ["-resetsafari"], runsLive: true, destructive: true),
        .init(id: "spotlight-fix",   title: "Spotlight Repair",    symbol: "magnifyingglass.circle",    group: .macTools,     command: ["-spotOK"], runsLive: true, destructive: true),
        .init(id: "desktop-fix",     title: "Organize Desktop",    symbol: "square.grid.3x3.topleft.filled", group: .macTools, command: ["-organise_desktop_fix"], runsLive: true, destructive: true),
        .init(id: "moncon",          title: "Monitor Controller",  symbol: "display",                   group: .macTools,     command: ["-moncon"]),

        // Data
        .init(id: "addressbook",     title: "AddressBook Cleanup", symbol: "externaldrive.badge.exclamationmark", group: .dataTools, command: []), // native Swift
        .init(id: "dotfiles-status", title: "Dotfiles Status",     symbol: "doc.on.doc",                group: .dataTools,    command: ["-dotfiles"]),
        .init(id: "dotfiles-push",   title: "Dotfiles Push",       symbol: "arrow.up.doc",              group: .dataTools,    command: ["push"], runsLive: true, destructive: true),
    ]

    static func grouped() -> [(Group, [BashModule])] {
        Group.allCases.map { g in
            (g, all.filter { $0.group == g })
        }
    }
}
