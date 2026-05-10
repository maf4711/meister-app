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
        case privacy = "Privacy & Security"
        case backup = "Backup"
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
        .init(id: "dashboard",       title: "Dashboard",           symbol: "square.grid.2x2.fill",      group: .overview,     command: []), // native Swift, Apple Design 2026
        .init(id: "health-score",    title: "Health Score",        symbol: "heart.text.square.fill",    group: .overview,     command: []), // native Swift
        .init(id: "health",          title: "Health Dashboard",    symbol: "heart.text.square",         group: .overview,     command: ["-H"]),
        .init(id: "menu",            title: "TUI Menu",            symbol: "list.bullet.rectangle",     group: .overview,     command: ["menu"], runsLive: true),

        // Maintenance
        .init(id: "maintain-dry",    title: "Maintenance Preview", symbol: "wrench.adjustable",         group: .maintenance,  command: ["-n", "-a"]),
        .init(id: "maintain-all",    title: "Run All Maintenance", symbol: "wrench.and.screwdriver.fill", group: .maintenance, command: ["-a"],   runsLive: true, destructive: true),
        .init(id: "heal-dry",        title: "Auto-Heal Preview",   symbol: "bandage",                   group: .maintenance,  command: ["heal", "--dry-run"]),
        .init(id: "heal",            title: "Auto-Heal",           symbol: "cross.case.fill",           group: .maintenance,  command: ["heal"], runsLive: true, destructive: true),
        .init(id: "launch-agent",    title: "Install LaunchAgent", symbol: "clock.arrow.circlepath",    group: .maintenance,  command: ["-I"],   runsLive: true, destructive: true),

        // Storage & Cleanup
        .init(id: "auto-clean-all",  title: "Alles erledigen",     symbol: "wand.and.stars.inverse",    group: .storage,      command: []), // native Swift, one-click EVERYTHING
        .init(id: "quick-clean",     title: "Quick Clean",         symbol: "wand.and.stars",            group: .storage,      command: []), // native Swift, system caches only
        .init(id: "autopilot",       title: "Autopilot",           symbol: "clock.arrow.2.circlepath",  group: .storage,      command: []), // native Swift, scheduler
        .init(id: "storage-forecast", title: "Storage Forecast",   symbol: "chart.line.uptrend.xyaxis", group: .storage,      command: []), // native Swift
        .init(id: "extended-attributes", title: "Extended Attrs",  symbol: "doc.badge.gearshape",       group: .storage,      command: []), // native Swift
        .init(id: "symlink-inspector", title: "Symlink Inspector", symbol: "link.badge.exclamationmark", group: .storage,     command: []), // native Swift
        .init(id: "system-cleanup",  title: "System Cleanup",      symbol: "sparkles",                  group: .storage,      command: []), // native Swift
        .init(id: "uninstaller",     title: "Uninstaller",         symbol: "trash.square",              group: .storage,      command: []), // native Swift
        .init(id: "large-old-files", title: "Large & Old Files",   symbol: "doc.zipper",                group: .storage,      command: []), // native Swift
        .init(id: "duplicates",      title: "Duplicate Finder",    symbol: "doc.on.doc",                group: .storage,      command: []), // native Swift
        .init(id: "undo-cleanup",    title: "Undo Last Cleanup",   symbol: "arrow.uturn.backward.circle", group: .storage,    command: []), // native Swift
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

        // Privacy & Security
        .init(id: "security-status", title: "Security Status",     symbol: "checkmark.shield",          group: .privacy,      command: []), // native Swift
        .init(id: "app-permissions", title: "App Permissions (TCC)", symbol: "lock.shield",             group: .privacy,      command: []), // native Swift
        .init(id: "wifi-passwords",  title: "Wi-Fi Networks",      symbol: "wifi",                      group: .privacy,      command: []), // native Swift
        .init(id: "hosts-blocklist", title: "Hosts Blocklist",     symbol: "shield.lefthalf.filled",    group: .privacy,      command: []), // native Swift
        .init(id: "keychain-audit",  title: "Keychain Audit",      symbol: "key.horizontal",            group: .privacy,      command: []), // native Swift
        .init(id: "ssh-keys",        title: "SSH Keys",            symbol: "key",                       group: .privacy,      command: []), // native Swift
        .init(id: "browser-privacy", title: "Browser Privacy",     symbol: "eye.slash",                 group: .privacy,      command: []), // native Swift
        .init(id: "login-items",     title: "Login Items & Agents",symbol: "person.crop.circle.badge.clock", group: .privacy, command: []), // native Swift
        .init(id: "hosts-file",      title: "/etc/hosts",          symbol: "doc.text",                  group: .privacy,      command: []), // native Swift
        .init(id: "notification-perms", title: "Notification Perms", symbol: "bell.badge",              group: .privacy,      command: []), // native Swift
        .init(id: "vpn-status",      title: "VPN Status",          symbol: "lock.shield",               group: .privacy,      command: []), // native Swift

        // Backup
        .init(id: "time-machine",    title: "Time Machine & Snapshots", symbol: "clock.arrow.circlepath", group: .backup,    command: []), // native Swift
        .init(id: "icloud-sync",     title: "iCloud Drive",        symbol: "icloud",                    group: .backup,      command: []), // native Swift

        // Network
        .init(id: "dns-flush",        title: "DNS-Cache löschen",   symbol: "arrow.clockwise.circle.fill", group: .network,   command: []), // native Swift
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
        .init(id: "hardware-inventory", title: "Hardware Inventory", symbol: "gearshape.2",             group: .hardware,     command: []), // native Swift
        .init(id: "ssd-health",      title: "Disk Health (SMART)", symbol: "stethoscope",               group: .hardware,     command: []), // native Swift
        .init(id: "disk-map",        title: "Disk Map",            symbol: "squareshape.split.3x3",     group: .hardware,     command: []), // native Swift
        .init(id: "process-manager", title: "Prozess-Manager",     symbol: "cpu.fill",                  group: .hardware,     command: []), // native Swift
        .init(id: "network-connections", title: "Network Connections", symbol: "arrow.left.arrow.right", group: .network,    command: []), // native Swift
        .init(id: "system-updates",  title: "System Updates",      symbol: "arrow.down.app",            group: .maintenance,  command: []), // native Swift
        .init(id: "spotlight-audit", title: "Spotlight Index Audit", symbol: "magnifyingglass.circle.fill", group: .maintenance, command: []), // native Swift
        .init(id: "crash-reports",   title: "Crash Reports",       symbol: "exclamationmark.octagon",   group: .maintenance,  command: []), // native Swift
        .init(id: "code-signature",  title: "Code Signature",      symbol: "checkmark.seal",            group: .macTools,     command: []), // native Swift
        .init(id: "memory-pressure", title: "Memory Pressure (Live)", symbol: "memorychip.fill",        group: .hardware,     command: []), // native Swift, live
        .init(id: "bluetooth-devices", title: "Bluetooth Devices", symbol: "antenna.radiowaves.left.and.right", group: .hardware, command: []), // native Swift
        .init(id: "energy-impact",   title: "Energy Impact",       symbol: "bolt.heart",                group: .hardware,     command: []), // native Swift
        .init(id: "usb-devices",     title: "USB Devices",         symbol: "cable.connector",           group: .hardware,     command: []), // native Swift
        .init(id: "battery",         title: "Battery Health",      symbol: "battery.75",                group: .hardware,     command: ["battery"]),
        .init(id: "thermal",         title: "Thermal",             symbol: "thermometer.medium",        group: .hardware,     command: ["thermal", "1"]),
        .init(id: "performance",     title: "Performance Check",   symbol: "speedometer",               group: .hardware,     command: ["-P", "-n"]),

        // Mac Tools — native dev-tool integrations
        .init(id: "xcode-switcher",  title: "Xcode Switcher",      symbol: "hammer.fill",               group: .macTools,     command: []), // native Swift
        .init(id: "simulator-manager", title: "Simulator Manager", symbol: "iphone.gen2.circle",        group: .macTools,     command: []), // native Swift
        .init(id: "docker-cleanup",  title: "Docker Cleanup",      symbol: "shippingbox.and.arrow.backward", group: .macTools, command: []), // native Swift
        .init(id: "brew-doctor",     title: "Brew Doctor",         symbol: "stethoscope",               group: .macTools,     command: []), // native Swift
        .init(id: "rosetta-audit",   title: "Rosetta Audit",       symbol: "rectangle.on.rectangle",    group: .macTools,     command: []), // native Swift
        .init(id: "rosetta",         title: "Install Rosetta",     symbol: "apple.terminal",            group: .macTools,     command: ["-rosetta"], runsLive: true, destructive: true),
        .init(id: "simfix",          title: "Simulator Fix",       symbol: "iphone.gen2",               group: .macTools,     command: ["simfix"], runsLive: true, destructive: true),
        .init(id: "reset-safari",    title: "Reset Safari",        symbol: "safari",                    group: .macTools,     command: ["-resetsafari"], runsLive: true, destructive: true),
        .init(id: "spotlight-fix",   title: "Spotlight Repair",    symbol: "magnifyingglass.circle",    group: .macTools,     command: ["-spotOK"], runsLive: true, destructive: true),
        .init(id: "desktop-fix",     title: "Organize Desktop",    symbol: "square.grid.3x3.topleft.filled", group: .macTools, command: ["-organise_desktop_fix"], runsLive: true, destructive: true),
        .init(id: "moncon",          title: "Monitor Controller",  symbol: "display",                   group: .macTools,     command: ["-moncon"]),
        .init(id: "default-apps",    title: "Default Apps",        symbol: "app.badge",                 group: .macTools,     command: []), // native Swift
        .init(id: "slack-webhook",   title: "Slack Webhook",       symbol: "paperplane",                group: .macTools,     command: []), // native Swift

        // Data
        .init(id: "addressbook",     title: "AddressBook Cleanup", symbol: "externaldrive.badge.exclamationmark", group: .dataTools, command: []), // native Swift
        .init(id: "tag-manager",     title: "Tag Manager",         symbol: "tag",                       group: .dataTools,    command: []), // native Swift
        .init(id: "dotfiles-status", title: "Dotfiles Status",     symbol: "doc.on.doc",                group: .dataTools,    command: ["-dotfiles"]),
        .init(id: "dotfiles-push",   title: "Dotfiles Push",       symbol: "arrow.up.doc",              group: .dataTools,    command: ["push"], runsLive: true, destructive: true),
    ]

    static func grouped() -> [(Group, [BashModule])] {
        Group.allCases.map { g in
            (g, all.filter { $0.group == g })
        }
    }
}
