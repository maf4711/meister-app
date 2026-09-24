"""Compile and exercise URL/redirect boundaries without Keychain or networking."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "macOS Swift compiler required")
class WebhookHelpersTests(unittest.TestCase):
    def test_validation_and_redirect_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main = root / "main.swift"
            main.write_text(r"""
import Foundation
let valid = ["https://hooks.slack.com/services/T/B/secret", "https://hooks.slack.com/services/T123/B456/aZ09_-token"]
let invalid = [
    "", "http://hooks.slack.com/services/T/B/secret",
    "https://example.com/services/T/B/secret", "https://hooks.slack.com.evil.test/services/T/B/secret",
    "https://user:pass@hooks.slack.com/services/T/B/secret", "https://hooks.slack.com:444/services/T/B/secret",
    "https://hooks.slack.com/services/T/B/secret#fragment", "https://hooks.slack.com/services/T/B/secret?query=x",
    "https://hooks.slack.com/services/x", "https://hooks.slack.com/services/T/B/",
    "https://hooks.slack.com/services/T/B/secret/extra", "https://hooks.slack.com/services/X/B/secret",
    "https://hooks.slack.com/services/T/X/secret", "https://hooks.slack.com/services/T/B/%2Fsecret",
    "https://hooks.slack.com/services/T/B/../secret", "https://hooks.slack.com/services/T/B/secret\n",
    " https://hooks.slack.com/services/T/B/secret", "https://hooks.slack.com/services/T/B/se cret"
]
for value in valid { precondition(WebhookSecretStore.validURL(value) != nil, "Valid URL rejected") }
for value in invalid { precondition(WebhookSecretStore.validURL(value) == nil, "Invalid URL accepted") }
let session = URLSession(configuration: .ephemeral)
defer { session.invalidateAndCancel() }
let original = URL(string: valid[0])!
let task = session.dataTask(with: original) // never resumed
let response = HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: nil)!
for target in [original, URL(string: "https://example.com")!] {
    var completed = false
    WebhookSessionDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) { request in
        precondition(request == nil, "Redirect must be denied")
        completed = true
    }
    precondition(completed)
}
print("Webhook boundary checks passed")
""")
            source = ROOT / "MeisterMacOS/SlackWebhook/WebhookSecretStore.swift"
            build = subprocess.run(
                ["swiftc", str(source), str(main), "-o", str(root / "check")],
                capture_output=True,
                text=True,
                timeout=120,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run(
                [str(root / "check")], capture_output=True, text=True, timeout=10
            )
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == "__main__":
    unittest.main()
