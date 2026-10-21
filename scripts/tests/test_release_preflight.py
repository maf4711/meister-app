"""Release preflight checks with fake profiles and tools; never build, sign, or upload."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        for name in ("build_ipa.sh", "ship.sh"):
            shutil.copy2(SCRIPTS / name, self.root / "scripts" / name)
        design = self.root / "scripts/ensure-design-system.sh"
        design.write_text("#!/bin/bash\nexit 0\n")
        design.chmod(0o755)
        self.calls = self.root / "calls.jsonl"
        self.project = self.root / "project.yml"
        self.project.write_text('CURRENT_PROJECT_VERSION: "1"\n')
        stub = (
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "name = Path(sys.argv[0]).name\n"
            "with open(os.environ['PREFLIGHT_CALLS'], 'a') as output:\n"
            "    output.write(json.dumps({'name': name, 'args': sys.argv[1:]}) + '\\n')\n"
            "if name == 'python3':\n"
            "    if 'preflight' in sys.argv: sys.exit(int(os.environ.get('PREFLIGHT_ASC_FAIL', '0')))\n"
            "    print('42')\n"
            "if name == 'security' and os.environ.get('PREFLIGHT_IDENTITY_MISSING') != '1':\n"
            "    print('1) ABCDEF Fixture Distribution')\n"
        )
        for name in ("security", "python3", "xcodegen", "xcodebuild"):
            tool = self.root / "bin" / name
            tool.write_text(stub)
            tool.chmod(0o755)
        self.app_profile = self.root / "app.mobileprovision"
        self.widget_profile = self.root / "widget.mobileprovision"
        self.env = {**os.environ, "PATH": f"{self.root / 'bin'}:{os.defpath}",
                    "PREFLIGHT_CALLS": str(self.calls), "MEISTER_DIST_IDENTITY": "Fixture Distribution",
                    "MEISTER_APP_PROFILE": str(self.app_profile), "MEISTER_WIDGET_PROFILE": str(self.widget_profile)}

    def run_script(self, script, *arguments, **env):
        return subprocess.run(["/bin/bash", str(self.root / "scripts" / script), *arguments],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=10)

    def assert_no_build(self):
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        self.assertFalse(any(call["name"] in ("xcodegen", "xcodebuild") for call in calls))
        self.assertFalse((self.root / "build").exists())
        self.assertEqual(self.project.read_text(), 'CURRENT_PROJECT_VERSION: "1"\n')

    def test_missing_app_profile_stops_before_archive_or_build_bump(self):
        result = self.run_script("ship.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MEISTER_APP_PROFILE", result.stderr)
        self.assert_no_build()

    def test_missing_widget_profile_stops_before_staging(self):
        self.app_profile.write_text("fixture")
        result = self.run_script("build_ipa.sh", "--preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MEISTER_WIDGET_PROFILE", result.stderr)
        self.assert_no_build()

    def test_missing_identity_stops_before_staging(self):
        self.app_profile.write_text("fixture")
        self.widget_profile.write_text("fixture")
        result = self.run_script("build_ipa.sh", "--preflight", PREFLIGHT_IDENTITY_MISSING="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MEISTER_DIST_IDENTITY", result.stderr)
        self.assert_no_build()

    def test_valid_preflight_does_not_require_or_create_archive(self):
        self.app_profile.write_text("fixture")
        self.widget_profile.write_text("fixture")
        result = self.run_script("build_ipa.sh", "--preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_build()

    def test_invalid_asc_configuration_stops_before_archive(self):
        result = self.run_script("ship.sh", PREFLIGHT_ASC_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_build()


if __name__ == "__main__":
    unittest.main()
