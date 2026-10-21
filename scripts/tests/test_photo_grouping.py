"""Run the actual pure photo-grouping method without PhotoKit access or a simulator.

Use --benchmark for optimized baseline/candidate timings on synthetic distances.
"""

from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MeisterIOS/Photos/SimilarityClustering.swift"
FIXTURES = ROOT / "scripts/tests/fixtures"
INPUTS = [SOURCE, FIXTURES / "photo_grouping_reference.swift", FIXTURES / "photo_grouping_checks.swift"]


def source_hashes():
    return {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest() for source in INPUTS}


def compile_checks(directory):
    source = SOURCE.read_text()
    start = source.index("    static func groupIndices(")
    end = source.index("    /// Fallback keeper", start)
    protocol_start = source.index("protocol CaptureTimed {")
    protocol_end = source.index("extension PhotoItem: CaptureTimed", protocol_start)
    split_start = source.index("    static func splitByCaptureWindow")
    split_end = source.index("    /// Whether a photo", split_start)
    window = next(line for line in source.splitlines() if "static let captureWindow:" in line)
    extracted = Path(directory) / "PhotoGrouping.swift"
    extracted.write_text("import Foundation\n" + source[protocol_start:protocol_end] +
                         "enum SimilarityClustering {\n" + window + "\n" +
                         source[start:end] + source[split_start:split_end] + "}\n")
    binary = Path(directory) / "photo-checks"
    result = subprocess.run(
        ["swiftc", "-swift-version", "5", "-O", "-parse-as-library", str(extracted),
         str(INPUTS[1]), str(INPUTS[2]), "-o", str(binary)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return binary


@unittest.skipUnless(sys.platform == "darwin", "macOS Swift required")
class PhotoGroupingTests(unittest.TestCase):
    def test_grouping_equivalence_and_invalid_distances(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([str(compile_checks(directory))], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Photo grouping checks passed", result.stdout)


if __name__ == "__main__":
    if sys.argv[1:] == ["--benchmark"]:
        before = source_hashes()
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([str(compile_checks(directory)), "--benchmark"], check=True, timeout=240)
        if before != source_hashes():
            raise RuntimeError("Sources changed during benchmarking; rerun against a stable snapshot")
        print(json.dumps({"source_sha256": before}, sort_keys=True))
    else:
        unittest.main()
