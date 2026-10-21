"""Check contact matching without requesting Contacts access or starting a simulator.

Run directly with --benchmark to compare optimized builds against the frozen baseline.
"""

from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "MeisterIOS/Contacts/FuzzyMatcher.swift",
    ROOT / "MeisterIOS/Contacts/ContactDeduplicator.swift",
    ROOT / "MeisterIOS/Contacts/PhoneNormalizer.swift",
    ROOT / "MeisterIOS/Contacts/ContactScanner.swift",
    ROOT / "scripts/tests/fixtures/contact_matching_reference.swift",
    ROOT / "scripts/tests/fixtures/contact_matching_checks.swift",
]


def compile_checks(directory):
    binary = Path(directory) / "contact-checks"
    result = subprocess.run(
        ["swiftc", "-swift-version", "5", "-O", "-parse-as-library", *map(str, SOURCES), "-o", str(binary)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return binary


@unittest.skipUnless(sys.platform == "darwin", "macOS Contacts/Swift required")
class ContactMatchingTests(unittest.TestCase):
    def test_matching_equivalence(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [str(compile_checks(directory))],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Contact matching checks passed", result.stdout)


if __name__ == "__main__":
    if sys.argv[1:] == ["--benchmark"]:
        source_hashes = {
            str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()
            for source in SOURCES
        }
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([str(compile_checks(directory)), "--benchmark"], check=True, timeout=240)
        final_hashes = {
            str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()
            for source in SOURCES
        }
        if source_hashes != final_hashes:
            raise RuntimeError("Sources changed during benchmarking; rerun against a stable snapshot")
        print(json.dumps({"source_sha256": source_hashes}, sort_keys=True))
    else:
        unittest.main()
