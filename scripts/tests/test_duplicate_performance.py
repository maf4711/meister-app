"""Check scanner results and actual bytes read using temporary synthetic files.

Use --benchmark for optimized, uninstrumented baseline/candidate timings.
"""

from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
INPUTS = [
    ROOT / "MeisterMacOS/Duplicates/DuplicateFinder.swift",
    ROOT / "scripts/tests/fixtures/duplicate_finder_reference.swift",
    ROOT / "scripts/tests/fixtures/duplicate_performance_checks.swift",
]


def source_hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in INPUTS}


def compile_checks(directory, instrument=True):
    sources = []
    for index, path in enumerate(INPUTS[:2]):
        source = path.read_text()
        if instrument:
            marker = "            if read < 0 { return nil }"
            if source.count(marker) != 1:
                raise AssertionError("Update the read probe for the current hash implementation")
            source = source.replace(marker, f"            ReadProbe.record(read, baseline: {str(index == 1).lower()})\n" + marker)
        target = Path(directory) / path.name
        target.write_text(source)
        sources.append(str(target))
    binary = Path(directory) / "duplicate-checks"
    result = subprocess.run(
        ["swiftc", "-swift-version", "5", "-O", "-parse-as-library", *sources,
         str(INPUTS[2]), "-o", str(binary)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return binary


@unittest.skipUnless(sys.platform == "darwin", "macOS Foundation/CryptoKit required")
class DuplicatePerformanceTests(unittest.TestCase):
    def test_prefix_filter_keeps_full_hash_safety_and_reduces_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([str(compile_checks(directory))], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Duplicate scanner checks passed", result.stdout)


if __name__ == "__main__":
    if sys.argv[1:] == ["--benchmark"]:
        before = source_hashes()
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([str(compile_checks(directory, instrument=False)), "--benchmark"], check=True, timeout=240)
        if before != source_hashes():
            raise RuntimeError("Sources changed during benchmarking; rerun against a stable snapshot")
        print(json.dumps({"source_sha256": before}, sort_keys=True))
    else:
        unittest.main()
