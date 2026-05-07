import Foundation

struct SSHKey: Identifiable, Hashable {
    let id: String
    let publicPath: URL
    let privatePath: URL?
    let keyType: String          // ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp256, etc.
    let bits: Int?               // bit length, nil if can't determine
    let fingerprint: String?     // SHA256:abc... format
    let comment: String?
    let hasPassphrase: KeyState
    let lastModified: Date?

    enum KeyState: Equatable {
        case `protected`   // private key encrypted with passphrase
        case unprotected   // private key unencrypted on disk
        case noPrivate     // only public key found
        case unknown
    }

    /// Risk level — combines weak-algo detection with passphrase status.
    var risk: Risk {
        if keyType == "ssh-dss" { return .high }
        if keyType.contains("rsa"), let b = bits, b < 2048 { return .high }
        if hasPassphrase == .unprotected { return .medium }
        return .low
    }

    enum Risk: String {
        case low, medium, high
    }
}

actor SSHKeyReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func read() async -> [SSHKey] {
        let dir = home.appendingPathComponent(".ssh")
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let entries = (try? fm.contentsOfDirectory(at: dir,
                                                   includingPropertiesForKeys: [.contentModificationDateKey],
                                                   options: [.skipsHiddenFiles])) ?? []

        // Public keys end in .pub. Private keys are the file without .pub.
        let publics = entries.filter { $0.pathExtension == "pub" }
        return publics.compactMap { pub in
            parseKey(publicURL: pub, sshDir: dir)
        }
    }

    private nonisolated func parseKey(publicURL: URL, sshDir: URL) -> SSHKey? {
        guard let raw = try? String(contentsOf: publicURL, encoding: .utf8) else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let keyType = String(parts[0])
        let comment = parts.count >= 3 ? String(parts[2]) : nil

        // Private key path: drop .pub
        let candidatePriv = publicURL.deletingPathExtension()
        let privExists = FileManager.default.fileExists(atPath: candidatePriv.path)
        let privPath: URL? = privExists ? candidatePriv : nil

        let bits = bitLength(keyType: keyType, publicURL: publicURL)
        let fingerprint = sshFingerprint(at: publicURL)
        let pp: SSHKey.KeyState = {
            guard let p = privPath else { return .noPrivate }
            return privateKeyHasPassphrase(at: p)
        }()

        let modified = (try? publicURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        return SSHKey(
            id: publicURL.path,
            publicPath: publicURL,
            privatePath: privPath,
            keyType: keyType,
            bits: bits,
            fingerprint: fingerprint,
            comment: comment,
            hasPassphrase: pp,
            lastModified: modified
        )
    }

    private nonisolated func bitLength(keyType: String, publicURL: URL) -> Int? {
        // ssh-keygen -lf <pubkey> prints "<bits> <fingerprint> <comment> (<TYPE>)"
        let out = run("/usr/bin/ssh-keygen", ["-l", "-f", publicURL.path])
        let parts = out.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        return Int(first)
    }

    nonisolated func sshFingerprint(at publicURL: URL) -> String? {
        let out = run("/usr/bin/ssh-keygen", ["-l", "-E", "sha256", "-f", publicURL.path])
        // Format: "<bits> SHA256:<hash> <comment> (<TYPE>)"
        let parts = out.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    /// Detect passphrase state by trying empty passphrase. If `ssh-keygen -y -P "" -f <key>`
    /// succeeds, the key is unprotected. If it fails with "wrong passphrase", protected.
    nonisolated func privateKeyHasPassphrase(at privateURL: URL) -> SSHKey.KeyState {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-y", "-P", "", "-f", privateURL.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return .unknown
        }
        if p.terminationStatus == 0 { return .unprotected }
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if err.lowercased().contains("incorrect passphrase") ||
           err.lowercased().contains("bad passphrase") ||
           err.lowercased().contains("requires a passphrase") {
            return .protected
        }
        return .unknown
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
