"""Offline ASC regressions: no credentials, API requests, uploads, or invitations."""

import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

SOURCE = Path(__file__).resolve().parents[1] / "asc_client.py"


class ASCClientTests(unittest.TestCase):
    def http_error(self, status):
        error = HTTPError("https://example.invalid", status, "failed", {}, io.BytesIO())
        self.addCleanup(error.close)
        return error

    def setUp(self):
        spec = importlib.util.spec_from_file_location("asc_client_checks", SOURCE)
        self.client = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"jwt": types.ModuleType("jwt")}):
            spec.loader.exec_module(self.client)

    def test_network_requests_have_a_timeout(self):
        response = Mock()
        response.read.return_value = b'{"data": []}'
        opened = Mock()
        opened.__enter__ = Mock(return_value=response)
        opened.__exit__ = Mock(return_value=False)
        with patch.object(self.client, "token", return_value="fixture"), \
             patch.object(self.client.urllib.request, "urlopen", return_value=opened) as urlopen:
            self.assertEqual(self.client.request("GET", "/apps"), {"data": []})
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 30)

    def test_preflight_is_local_only(self):
        with patch.object(self.client, "token", return_value="fixture") as token, \
             patch.object(self.client, "find_app") as find_app, \
             patch.object(sys, "argv", ["asc_client.py", "preflight"]), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.client.main(), 0)
        token.assert_called_once()
        find_app.assert_not_called()

    def test_activation_does_not_hide_assignment_failures(self):
        for status in (401, 403, 409, 429, 500):
            with self.subTest(status=status), \
                 patch.object(self.client, "find_app", return_value={"id": "app"}), \
                 patch.object(self.client, "wait_until_processed", return_value={"id": "build", "attributes": {"version": "2"}}), \
                 patch.object(self.client, "set_export_compliance"), \
                 patch.object(self.client, "ensure_internal_group", return_value={"id": "group", "attributes": {"name": "Internal"}}), \
                 patch.object(self.client, "attach_build_to_group", side_effect=self.http_error(status)), \
                 patch.object(sys, "argv", ["asc_client.py", "activate", "--version", "2"]), \
                 contextlib.redirect_stdout(io.StringIO()) as output:
                with self.assertRaises(HTTPError):
                    self.client.main()
                self.assertNotIn("active in", output.getvalue())

    def test_tester_group_assignment_does_not_hide_permission_errors(self):
        with patch.object(self.client, "request", side_effect=[
            {"data": [{"id": "tester"}]}, self.http_error(403)
        ]):
            with self.assertRaises(HTTPError):
                self.client.invite_tester("app", "fixture@example.test", group_id="group")

    def test_missing_dependencies_explain_the_remediation(self):
        with patch.dict(sys.modules, {"jwt": None}):
            with self.assertRaisesRegex(RuntimeError, "Install release dependencies"):
                self.client.token()

    def test_missing_key_explains_the_configuration(self):
        with patch.dict(sys.modules, {"jwt": types.ModuleType("jwt")}), \
             patch.object(self.client, "KEY_PATH") as key_path:
            key_path.is_file.return_value = False
            with self.assertRaisesRegex(RuntimeError, "ASC_KEY_ID or ASC_KEY_PATH"):
                self.client.token()
            key_path.read_text.assert_not_called()

    def test_latest_build_number_is_numeric_across_pages(self):
        def build(number):
            return {"attributes": {"version": number}}
        with patch.object(self.client, "request", side_effect=[
            {"data": [build("9"), build("10")], "links": {"next": self.client.BASE + "/builds?cursor=two"}},
            {"data": [build("101"), build("99")], "links": {"next": None}},
        ]) as request:
            self.assertEqual(self.client.latest_build_number("app"), 101)
        self.assertEqual(request.call_count, 2)

    def test_invalid_build_numbers_do_not_reset_to_zero(self):
        for data in ([{"attributes": {"version": "bad"}}], [{"attributes": {}}]):
            with self.subTest(data=data), patch.object(self.client, "request", return_value={"data": data}):
                with self.assertRaises((ValueError, RuntimeError)):
                    self.client.latest_build_number("app")

    def test_empty_build_list_starts_at_zero(self):
        with patch.object(self.client, "request", return_value={"data": []}):
            self.assertEqual(self.client.latest_build_number("app"), 0)

    def test_polling_finds_an_explicit_build_outside_latest_five(self):
        target = {"id": "target", "attributes": {"version": "100", "processingState": "VALID"}}
        recent = [{"id": str(i), "attributes": {"version": str(i), "processingState": "VALID"}}
                  for i in range(95, 100)]

        def response(method, path, params):
            return {"data": [target] if params.get("filter[version]") == "100" else recent}

        with patch.object(self.client, "request", side_effect=response) as request, \
             patch.object(self.client.time, "sleep", side_effect=AssertionError("Available target must not poll again")), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.client.wait_until_processed("app", "100"), target)
        self.assertEqual(request.call_args.kwargs["params"]["filter[version]"], "100")

    def test_pagination_cannot_redirect_credentials_or_loop(self):
        for next_url in ("https://example.test/v1/builds", self.client.BASE + "/builds"):
            with self.subTest(next_url=next_url), patch.object(self.client, "request", return_value={
                "data": [{"attributes": {"version": "1"}}], "links": {"next": next_url}
            }):
                with self.assertRaises(ValueError):
                    self.client.latest_build_number("app")


if __name__ == "__main__":
    unittest.main()
