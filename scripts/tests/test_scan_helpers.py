"""Run scanner regressions without launching the app or accessing user data."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "macOS Foundation/CryptoKit required")
class ScanHelpersTests(unittest.TestCase):
    def test_duplicate_scan_and_age_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            main = path / "checks.swift"
            main.write_text(r"""
import Foundation

@main struct Checks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        let alias = root.appendingPathComponent("alias.bin")
        let payload = Data(repeating: 17, count: DuplicateFinder.hashChunk + 19)
        try payload.write(to: a)
        try payload.write(to: b)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        try Data(repeating: 18, count: payload.count).write(to: root.appendingPathComponent("different.bin"))
        try Data([1]).write(to: root.appendingPathComponent("small.bin"))
        let finder = DuplicateFinder()
        let groups = await finder.find(in: [root, root, a, alias], minSize: 2)
        precondition(groups.count == 1)
        precondition(Set(groups[0].files.map { $0.resolvingSymlinksInPath() }) == Set([a, b].map { $0.resolvingSymlinksInPath() }))
        precondition(groups[0].wastedBytes == Int64(payload.count))
        let explicitAlias = await finder.find(in: [a, alias], minSize: 2)
        precondition(explicitAlias.isEmpty)
        precondition(DuplicateFinder.sha256(of: root.appendingPathComponent("missing")) == nil)
        let hello = root.appendingPathComponent("hello")
        try Data("hello".utf8).write(to: hello)
        precondition(DuplicateFinder.sha256(of: hello) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await finder.find(in: [root], minSize: 1)
        }
        let cancelledGroups = await cancelled.value
        precondition(cancelledGroups.isEmpty)

        let predicate = LargeFilesScanner().makePredicate(minBytes: 100, olderThanDays: 30)
        let old = Date(timeIntervalSinceNow: -60 * 86_400)
        let recent = Date()
        func matches(_ used: Date?, _ modified: Date?) -> Bool {
            var item: [String: Any] = [NSMetadataItemFSSizeKey: 200, NSMetadataItemContentTypeKey: "public.data"]
            item[NSMetadataItemLastUsedDateKey] = used
            item[NSMetadataItemFSContentChangeDateKey] = modified
            return predicate.evaluate(with: item)
        }
        precondition(matches(old, old))
        precondition(matches(old, nil))
        precondition(matches(nil, old))
        precondition(!matches(old, recent))
        precondition(!matches(recent, old))
        precondition(!matches(nil, recent))
        precondition(!matches(recent, nil))
        precondition(!matches(nil, nil))
    }
}
""")
            binary = path / "checks"
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(ROOT / "MeisterMacOS/Duplicates/DuplicateFinder.swift"),
                    str(ROOT / "MeisterMacOS/LargeFiles/LargeFilesScanner.swift"),
                    str(main),
                    "-o",
                    str(binary),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=90,
            )
            result = subprocess.run(
                [str(binary)], capture_output=True, text=True, timeout=30
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
