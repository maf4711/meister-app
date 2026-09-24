"""Exercise native helper contracts without starting the app or modifying macOS."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "macOS Foundation/SwiftUI required")
class NativeHelpersTests(unittest.TestCase):
    def test_commands_and_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            main = path / "main.swift"
            main.write_text(r'''
import Foundation
let large = CommandRunner.run("/bin/sh", ["-c", "yes abcdefghijklmnop | head -n 20000"], timeout: 5)
precondition(large.succeeded && large.output.count > 200_000)
precondition(CommandRunner.run("/usr/bin/false", []).status == 1)
precondition(CommandRunner.run("/nonexistent/meister-test", []).failureKind == .missingTool)
let started = Date()
let timeout = CommandRunner.run("/bin/sleep", ["10"], timeout: 0.1)
precondition(!timeout.succeeded && timeout.failureKind == .timedOut)
precondition(Date().timeIntervalSince(started) < 4)
let quoted = "space ' quote \" $HOME $(printf BAD) `printf BAD`\nnewline"
precondition(CommandRunner.run("/bin/sh", ["-c", "printf %s " + CommandRunner.shellQuote(quoted)]).output == quoted)
let issue = DiagnosticIssue(kind: .permissionDenied, source: "fixture")
let report = DiagnosticReport(value: [String](), issues: [issue, issue])
precondition(report.issues.count == 1 && !report.isComplete)
precondition(DiagnosticReport(value: [String]()).isComplete)
precondition(!DiagnosticReport<[String]>(value: nil).isComplete)
precondition(CommandRunner.Result(status: 1, output: "Permission denied").issue(source: "fixture") == issue)
precondition(CommandRunner.Result(status: 0, output: "").issue(source: "fixture") == nil)
''')
            binary = path / "checks"
            subprocess.run(["swiftc", str(ROOT / "MeisterMacOS/Diagnostics/DiagnosticReport.swift"),
                            str(ROOT / "MeisterMacOS/Commands/CommandRunner.swift"), str(main),
                            "-o", str(binary)], check=True, capture_output=True, text=True, timeout=90)
            subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=15)
