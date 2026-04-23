#!/usr/bin/env python3
"""App Store Connect API client for Meister.

Generates JWT from a .p8 key and exposes helpers for:
  - listing apps / builds
  - polling processing state
  - setting export compliance
  - setting TestFlight release notes
  - inviting internal + external testers
  - submitting builds for Beta App Review (external distribution)

Environment variables (override the defaults below):
  ASC_KEY_ID        App Store Connect API Key ID
  ASC_ISSUER_ID     Team-wide Issuer ID
  ASC_KEY_PATH      Path to the .p8 file
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

KEY_ID = os.environ.get("ASC_KEY_ID", "AA42M2D5C8")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "18daeaec-9343-4c57-9b01-481a7da981c6")
KEY_PATH = Path(os.environ.get(
    "ASC_KEY_PATH",
    str(Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"),
))

BASE = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    private_key = KEY_PATH.read_text()
    now = dt.datetime.now(dt.timezone.utc)
    payload = {
        "iss": ISSUER_ID,
        "iat": int(now.timestamp()),
        "exp": int((now + dt.timedelta(minutes=15)).timestamp()),
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def request(method: str, path: str, body: dict | None = None, params: dict | None = None) -> dict:
    url = f"{BASE}{path}"
    if params:
        qs = urllib.parse.urlencode(params)
        url = f"{url}?{qs}"
    payload = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, method=method, data=payload, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        print(f"HTTP {e.code}: {body_text}", file=sys.stderr)
        raise


def find_app(bundle_id: str) -> dict:
    data = request("GET", "/apps", params={"filter[bundleId]": bundle_id, "limit": 1})
    items = data.get("data", [])
    if not items:
        raise RuntimeError(f"app {bundle_id} not found in App Store Connect")
    return items[0]


def list_builds(app_id: str, limit: int = 5) -> list[dict]:
    data = request("GET", "/builds", params={
        "filter[app]": app_id,
        "sort": "-version",
        "limit": limit,
        "include": "buildBetaDetail",
    })
    return data.get("data", [])


def latest_build_number(app_id: str) -> int:
    builds = list_builds(app_id, limit=1)
    if not builds:
        return 0
    try:
        return int(builds[0]["attributes"]["version"])
    except (ValueError, KeyError):
        return 0


def build_beta_detail(build_id: str) -> dict:
    data = request("GET", f"/builds/{build_id}/buildBetaDetail")
    return data.get("data", {})


def wait_until_processed(app_id: str, target_version: str | None = None, timeout: int = 1800) -> dict:
    start = time.time()
    while time.time() - start < timeout:
        builds = list_builds(app_id, limit=5)
        if not builds:
            print("… no builds yet, waiting", flush=True)
            time.sleep(15)
            continue
        if target_version is None:
            build = builds[0]
        else:
            build = next(
                (b for b in builds if b["attributes"]["version"] == target_version),
                None,
            )
            if build is None:
                elapsed = int(time.time() - start)
                print(f"[{elapsed:4d}s] build {target_version} not yet ingested by Apple, waiting", flush=True)
                time.sleep(20)
                continue
        state = build["attributes"].get("processingState", "UNKNOWN")
        elapsed = int(time.time() - start)
        print(f"[{elapsed:4d}s] build {build['attributes']['version']} — {state}", flush=True)
        if state == "VALID":
            return build
        if state in {"FAILED", "INVALID"}:
            raise RuntimeError(f"build processing failed: {build}")
        time.sleep(20)
    raise TimeoutError("build did not finish processing in time")


def set_export_compliance(build_id: str, uses_crypto: bool = False) -> None:
    request("PATCH", f"/builds/{build_id}", body={
        "data": {
            "type": "builds",
            "id": build_id,
            "attributes": {"usesNonExemptEncryption": uses_crypto},
        }
    })


def set_release_notes(build_id: str, notes: str, locale: str = "en-US") -> None:
    """Write TestFlight "What to Test" text via BuildBetaLocalizations."""
    existing = request("GET", f"/builds/{build_id}/betaBuildLocalizations").get("data", [])
    match = next((x for x in existing if x["attributes"].get("locale") == locale), None)
    if match:
        request("PATCH", f"/betaBuildLocalizations/{match['id']}", body={
            "data": {
                "type": "betaBuildLocalizations",
                "id": match["id"],
                "attributes": {"whatsNew": notes},
            }
        })
    else:
        request("POST", "/betaBuildLocalizations", body={
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"whatsNew": notes, "locale": locale},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        })


def ensure_internal_group(app_id: str, name: str = "Internal") -> dict:
    groups = request("GET", "/betaGroups", params={
        "filter[app]": app_id,
        "filter[name]": name,
        "limit": 1,
    }).get("data", [])
    if groups:
        return groups[0]
    created = request("POST", "/betaGroups", body={
        "data": {
            "type": "betaGroups",
            "attributes": {"name": name, "isInternalGroup": True, "publicLinkEnabled": False},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    return created["data"]


def ensure_external_group(app_id: str, name: str = "External Beta") -> dict:
    groups = request("GET", "/betaGroups", params={
        "filter[app]": app_id,
        "filter[name]": name,
        "limit": 1,
    }).get("data", [])
    if groups:
        return groups[0]
    created = request("POST", "/betaGroups", body={
        "data": {
            "type": "betaGroups",
            "attributes": {
                "name": name,
                "publicLinkEnabled": True,
                "publicLinkLimitEnabled": False,
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    return created["data"]


def attach_build_to_group(build_id: str, group_id: str) -> None:
    request("POST", f"/betaGroups/{group_id}/relationships/builds", body={
        "data": [{"type": "builds", "id": build_id}],
    })


def invite_tester(app_id: str, email: str, first: str = "", last: str = "", group_id: str | None = None) -> dict:
    """Invite a tester by email. If the email belongs to a team member (admin/developer),
    App Store Connect returns 409 — those accounts are testers implicitly via team membership."""
    existing = request("GET", "/betaTesters", params={
        "filter[email]": email,
        "limit": 1,
    }).get("data", [])
    if existing:
        tester = existing[0]
    else:
        rel: dict = {"apps": {"data": [{"type": "apps", "id": app_id}]}}
        if group_id:
            rel["betaGroups"] = {"data": [{"type": "betaGroups", "id": group_id}]}
        try:
            created = request("POST", "/betaTesters", body={
                "data": {
                    "type": "betaTesters",
                    "attributes": {"email": email, "firstName": first, "lastName": last},
                    "relationships": rel,
                }
            })
            tester = created["data"]
        except urllib.error.HTTPError as e:
            if e.code == 409:
                # Already registered on this or another app — look up the existing record.
                again = request("GET", "/betaTesters", params={"filter[email]": email, "limit": 1})
                hits = again.get("data", [])
                if not hits:
                    raise
                tester = hits[0]
            else:
                raise
    if group_id:
        try:
            request("POST", f"/betaGroups/{group_id}/relationships/betaTesters", body={
                "data": [{"type": "betaTesters", "id": tester["id"]}],
            })
        except urllib.error.HTTPError:
            pass  # Already in group — ignore.
    return tester


def submit_for_beta_review(build_id: str) -> dict:
    return request("POST", "/betaAppReviewSubmissions", body={
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    })


def set_review_contact(
    app_id: str,
    first: str,
    last: str,
    email: str,
    phone: str = "",
    demo_account_required: bool = False,
    notes: str = "",
) -> None:
    """Fill in the Beta App Review contact details required before submitting for external review."""
    request("PATCH", f"/betaAppReviewDetails/{app_id}", body={
        "data": {
            "type": "betaAppReviewDetails",
            "id": app_id,
            "attributes": {
                "contactFirstName": first,
                "contactLastName": last,
                "contactEmail": email,
                "contactPhone": phone,
                "demoAccountRequired": demo_account_required,
                "notes": notes,
            },
        }
    })


def set_beta_app_info(
    app_id: str,
    description: str,
    feedback_email: str,
    locale: str = "en-US",
    marketing_url: str = "",
    privacy_url: str = "",
    tos_url: str = "",
) -> None:
    """Fill in the required beta localisation so the build can be submitted for external review."""
    existing = request("GET", f"/apps/{app_id}/betaAppLocalizations").get("data", [])
    match = next((x for x in existing if x["attributes"].get("locale") == locale), None)
    attrs = {
        "description": description,
        "feedbackEmail": feedback_email,
    }
    if marketing_url:
        attrs["marketingUrl"] = marketing_url
    if privacy_url:
        attrs["privacyPolicyUrl"] = privacy_url
    if tos_url:
        attrs["tosUrl"] = tos_url
    if match:
        request("PATCH", f"/betaAppLocalizations/{match['id']}", body={
            "data": {
                "type": "betaAppLocalizations",
                "id": match["id"],
                "attributes": attrs,
            }
        })
    else:
        attrs["locale"] = locale
        request("POST", "/betaAppLocalizations", body={
            "data": {
                "type": "betaAppLocalizations",
                "attributes": attrs,
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })


def main() -> int:
    parser = argparse.ArgumentParser(description="Meister ASC client")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="List recent builds")
    sub.add_parser("next-build-number", help="Print the next build number (latest+1)")

    p_wait = sub.add_parser("wait", help="Poll until build is processed")
    p_wait.add_argument("--version", help="Target version (default: latest)")

    p_compliance = sub.add_parser("compliance", help="Set export compliance")
    p_compliance.add_argument("--version", help="Target version (default: latest)")
    p_compliance.add_argument("--uses-crypto", action="store_true")

    p_notes = sub.add_parser("notes", help="Set TestFlight 'What to Test' text")
    p_notes.add_argument("text", nargs="?", help="Text; if omitted, read from stdin")
    p_notes.add_argument("--version", help="Target version (default: latest)")

    p_invite = sub.add_parser("invite", help="Invite a tester by email")
    p_invite.add_argument("email")
    p_invite.add_argument("--first", default="")
    p_invite.add_argument("--last", default="")
    p_invite.add_argument("--group", default="Internal", help="Group name (Internal/External Beta)")

    p_setup = sub.add_parser("setup-beta-info", help="Set Beta App Description + feedback email (required for external review)")
    p_setup.add_argument("--description", required=True)
    p_setup.add_argument("--feedback-email", required=True)
    p_setup.add_argument("--privacy-url", default="")
    p_setup.add_argument("--marketing-url", default="")

    p_external = sub.add_parser("submit-external", help="Submit build for Beta App Review")
    p_external.add_argument("--version")

    p_activate = sub.add_parser("activate", help="Full pipeline: wait → compliance → internal group")
    p_activate.add_argument("--version")
    p_activate.add_argument("--notes", help="What to Test text")

    for p in (parser, *sub.choices.values()):
        p.add_argument("--bundle", default="com.merados.meister.ios")

    args = parser.parse_args()
    app = find_app(args.bundle)
    app_id = app["id"]

    if args.cmd == "status":
        builds = list_builds(app_id, limit=5)
        print(f"App: {app['attributes']['name']} ({app_id})")
        for b in builds:
            a = b["attributes"]
            print(f"  build {a['version']}  state={a['processingState']}  uploaded={a.get('uploadedDate', '')}")
        return 0

    if args.cmd == "next-build-number":
        print(latest_build_number(app_id) + 1)
        return 0

    if args.cmd == "wait":
        build = wait_until_processed(app_id, args.version)
        print(f"processed: {build['id']}")
        return 0

    if args.cmd == "compliance":
        build = wait_until_processed(app_id, args.version)
        set_export_compliance(build["id"], uses_crypto=args.uses_crypto)
        print(f"compliance set: {build['id']}")
        return 0

    if args.cmd == "notes":
        text = args.text if args.text is not None else sys.stdin.read()
        text = text.strip()
        if not text:
            print("error: empty notes", file=sys.stderr)
            return 1
        build = wait_until_processed(app_id, args.version)
        set_release_notes(build["id"], text)
        print(f"notes set on build {build['id']} ({len(text)} chars)")
        return 0

    if args.cmd == "invite":
        group_name = args.group
        if group_name == "Internal":
            group = ensure_internal_group(app_id)
        else:
            group = ensure_external_group(app_id, group_name)
        tester = invite_tester(app_id, args.email, args.first, args.last, group["id"])
        print(f"invited {args.email} → {group_name} ({tester['id']})")
        return 0

    if args.cmd == "setup-beta-info":
        set_beta_app_info(
            app_id,
            description=args.description,
            feedback_email=args.feedback_email,
            privacy_url=args.privacy_url,
            marketing_url=args.marketing_url,
        )
        print(f"beta info saved for {app['attributes']['name']}")
        return 0

    if args.cmd == "submit-external":
        build = wait_until_processed(app_id, args.version)
        sub_data = submit_for_beta_review(build["id"])
        print(f"submitted build {build['id']} for Beta App Review → {sub_data['data']['id']}")
        return 0

    if args.cmd == "activate":
        build = wait_until_processed(app_id, args.version)
        set_export_compliance(build["id"], uses_crypto=False)
        group = ensure_internal_group(app_id)
        try:
            attach_build_to_group(build["id"], group["id"])
        except urllib.error.HTTPError:
            pass  # Already attached.
        if args.notes:
            set_release_notes(build["id"], args.notes)
        print(f"✅ build {build['attributes']['version']} active in '{group['attributes']['name']}'")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
