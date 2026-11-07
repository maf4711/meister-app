"""Offline release authorization regression tests; no real build or messages."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]


class ReleaseGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        for name in ("auto-ship.sh", "notify-tom.sh"):
            shutil.copy2(SCRIPTS / name, self.root / "scripts" / name)
        self.calls = self.root / "calls.jsonl"
        stub = (
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "name = Path(sys.argv[0]).name\n"
            "with open(os.environ['GUARD_CALLS'], 'a') as f:\n"
            "    f.write(json.dumps({'name': name, 'argv': sys.argv[1:], "
            "'stdin': sys.stdin.read() if name == 'osascript' else ''}) + '\\n')\n"
            "if name == 'git': print('fixture')\n"
            "if name == 'ship.sh': print('Build 42 live')\n"
        )
        for path in [self.root / "scripts" / "ship.sh"] + [
            self.root / "bin" / name for name in ("git", "osascript", "security")
        ]:
            path.write_text(stub)
            path.chmod(0o755)
        self.env = os.environ.copy()
        for key in ("MEISTER_TESTFLIGHT_AUTO_SHIP", "MEISTER_NOTIFY_CONTACT"):
            self.env.pop(key, None)
        self.env.update(
            PATH=f"{self.root / 'bin'}:{os.defpath}", GUARD_CALLS=str(self.calls)
        )

    def run_script(self, name, *args, **env):
        result = subprocess.run(
            ["/bin/bash", str(self.root / "scripts" / name), *args],
            env={**self.env, **env},
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return (
            [json.loads(line) for line in self.calls.read_text().splitlines()]
            if self.calls.exists()
            else []
        )

    def test_auto_ship_default_has_no_side_effects(self):
        self.assertEqual(self.run_script("auto-ship.sh"), [])
        self.assertFalse((self.root / "build").exists())
        self.assertFalse((self.root / ".auto-ship.lock").exists())

    def test_non_one_auto_ship_values_do_not_authorize(self):
        for value in ("", "0", "true", "yes"):
            with self.subTest(value=value):
                self.assertEqual(
                    self.run_script("auto-ship.sh", MEISTER_TESTFLIGHT_AUTO_SHIP=value),
                    [],
                )

    def test_notify_default_has_no_side_effects(self):
        self.assertEqual(self.run_script("notify-tom.sh"), [])
        self.assertFalse((self.root / "build").exists())

    def test_non_one_notify_values_do_not_authorize(self):
        (self.root / "build").mkdir()
        for value in ("", "0", "true", "yes"):
            with self.subTest(value=value):
                self.assertEqual(
                    self.run_script("notify-tom.sh", MEISTER_NOTIFY_CONTACT=value), []
                )

    def test_ship_opt_in_does_not_authorize_contact(self):
        calls = self.run_script("auto-ship.sh", MEISTER_TESTFLIGHT_AUTO_SHIP="1")
        self.assertEqual(sum(call["name"] == "ship.sh" for call in calls), 1)
        self.assertFalse(any(call["stdin"] for call in calls))
        self.assertFalse((self.root / ".auto-ship.lock").exists())

    def test_contact_opt_in_does_not_authorize_ship(self):
        self.assertEqual(
            self.run_script("auto-ship.sh", MEISTER_NOTIFY_CONTACT="1"), []
        )

    def test_ship_off_switch_overrides_opt_in_without_artifacts(self):
        (self.root / ".no-auto-ship").touch()
        self.assertEqual(
            self.run_script("auto-ship.sh", MEISTER_TESTFLIGHT_AUTO_SHIP="1"), []
        )
        self.assertFalse((self.root / "build").exists())

    def test_contact_off_switch_overrides_opt_in(self):
        (self.root / ".no-tom-notify").touch()
        self.assertEqual(
            self.run_script("notify-tom.sh", MEISTER_NOTIFY_CONTACT="1"), []
        )
        self.assertFalse((self.root / "build").exists())

    def test_contact_opt_in_passes_untrusted_message_as_argument(self):
        (self.root / "build").mkdir()
        message = 'hello "\nend tell\ndo shell script "unexpected"'
        calls = self.run_script("notify-tom.sh", message, MEISTER_NOTIFY_CONTACT="1")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["name"], "osascript")
        self.assertIn(message, calls[0]["argv"])
        self.assertNotIn(message, calls[0]["stdin"])
        self.assertIn("on run argv", calls[0]["stdin"])

    def test_both_opt_ins_ship_then_contact(self):
        calls = self.run_script(
            "auto-ship.sh", MEISTER_TESTFLIGHT_AUTO_SHIP="1", MEISTER_NOTIFY_CONTACT="1"
        )
        self.assertEqual(sum(call["name"] == "ship.sh" for call in calls), 1)
        messages = [call for call in calls if call["stdin"]]
        self.assertEqual(len(messages), 1)
        self.assertTrue(any("Build 42 live" in arg for arg in messages[0]["argv"]))


if __name__ == "__main__":
    unittest.main()
