import Foundation

/// A piece of leftover data associated with an installed app — the things
/// dragging an app to Trash leaves behind.
struct LeftoverItem: Identifiable, Hashable {
    enum Source: String, CaseIterable {
        case applicationSupport = "Application Support"
        case caches             = "Caches"
        case preferences        = "Preferences"
        case containers         = "Containers"
        case groupContainers    = "Group Containers"
        case savedState         = "Saved Application State"
        case launchAgents       = "Launch Agents"
        case launchDaemons      = "Launch Daemons"
        case logs               = "Logs"
        case cookies            = "Cookies"
        case webKit             = "WebKit"
        case httpStorages       = "HTTP Storages"
        case appScripts         = "Application Scripts"
    }

    let url: URL
    let source: Source
    let bytes: Int64
    var id: String { url.path }
}

/// Scans for leftover files associated with a given InstalledApp.
/// Uses both the bundle ID and the app's display name as search tokens —
/// many apps store data under their human name, not their reverse-DNS ID.
struct UninstallerScanner {
    let home: URL
    let fileManager: FileManager

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    func leftovers(for app: InstalledApp) -> [LeftoverItem] {
        let library = home.appendingPathComponent("Library")
        var items: [LeftoverItem] = []

        // Source → root directory + match-mode
        let plan: [(LeftoverItem.Source, URL, MatchMode)] = [
            (.applicationSupport, library.appendingPathComponent("Application Support"),       .directChild),
            (.caches,             library.appendingPathComponent("Caches"),                    .prefixedChild),
            (.preferences,        library.appendingPathComponent("Preferences"),               .prefixedFile(suffix: ".plist")),
            (.containers,         library.appendingPathComponent("Containers"),                .directChild),
            (.groupContainers,    library.appendingPathComponent("Group Containers"),          .containsChild),
            (.savedState,         library.appendingPathComponent("Saved Application State"),   .prefixedChild),
            (.launchAgents,       library.appendingPathComponent("LaunchAgents"),              .prefixedFile(suffix: ".plist")),
            (.logs,               library.appendingPathComponent("Logs"),                      .directChild),
            (.cookies,            library.appendingPathComponent("Cookies"),                   .prefixedFile(suffix: ".binarycookies")),
            (.webKit,             library.appendingPathComponent("WebKit"),                    .directChild),
            (.httpStorages,       library.appendingPathComponent("HTTPStorages"),              .prefixedChild),
            (.appScripts,         library.appendingPathComponent("Application Scripts"),       .directChild),
        ]

        for (source, root, mode) in plan {
            items.append(contentsOf: matches(in: root, tokens: app.searchTokens, source: source, mode: mode))
        }

        // System-level launch daemons — read-only listing, deletion needs admin.
        let systemDaemons = URL(fileURLWithPath: "/Library/LaunchDaemons")
        items.append(contentsOf: matches(in: systemDaemons, tokens: app.searchTokens,
                                         source: .launchDaemons,
                                         mode: .prefixedFile(suffix: ".plist")))
        return items.sorted { $0.bytes > $1.bytes }
    }

    // MARK: matching

    enum MatchMode {
        /// Child name equals one of the tokens exactly.
        case directChild
        /// Child name starts with token (e.g. "com.example.app" matches
        /// "com.example.app.helper").
        case prefixedChild
        /// Child name contains the token anywhere.
        case containsChild
        /// File whose name starts with token AND ends with the given suffix.
        case prefixedFile(suffix: String)
    }

    private func matches(in root: URL,
                         tokens: [String],
                         source: LeftoverItem.Source,
                         mode: MatchMode) -> [LeftoverItem] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        guard let kids = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let lowerTokens = tokens.map { $0.lowercased() }
        var results: [LeftoverItem] = []
        for kid in kids {
            let name = kid.lastPathComponent
            let lower = name.lowercased()
            let matched: Bool = {
                switch mode {
                case .directChild:
                    return lowerTokens.contains(lower)
                case .prefixedChild:
                    return lowerTokens.contains { lower == $0 || lower.hasPrefix($0 + ".") }
                case .containsChild:
                    return lowerTokens.contains { lower.contains($0) }
                case .prefixedFile(let suffix):
                    let suf = suffix.lowercased()
                    guard lower.hasSuffix(suf) else { return false }
                    let stem = String(lower.dropLast(suf.count))
                    return lowerTokens.contains { stem == $0 || stem.hasPrefix($0 + ".") }
                }
            }()
            if matched {
                results.append(LeftoverItem(url: kid, source: source, bytes: sizeOf(kid)))
            }
        }
        return results
    }

    private func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            return Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Int64 = 0
        if let e = fileManager.enumerator(at: url,
                                          includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                          options: [.skipsHiddenFiles]) {
            for case let f as URL in e {
                let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
                total += Int64(s)
            }
        }
        return total
    }
}
