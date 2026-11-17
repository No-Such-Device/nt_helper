#!/usr/bin/env python3
"""Inspect or change only the release policy of one existing macOS version."""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from resolve_store_baselines import apple_token


BUNDLE_ID = "dev.nosuch.macos.ntHelper"
API = "https://api.appstoreconnect.apple.com/v1"


class AppleAPI:
    def __init__(self, token: str):
        self.token = token

    def request(self, path: str, payload: dict | None = None) -> dict:
        request = urllib.request.Request(
            API + path,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
            data=None if payload is None else json.dumps(payload).encode(),
            method="GET" if payload is None else "PATCH",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Report Apple's exact policy restriction, never the request/auth headers.
            errors = json.loads(error.read()).get("errors", [])
            details = [{k: e.get(k) for k in ("status", "code", "title", "detail")}
                       for e in errors]
            raise RuntimeError(f"Apple {request.method} {path}: HTTP {error.code}: {json.dumps(details)}") from None


def release_policy(api: AppleAPI, version: str, build: str, apply: bool = False) -> dict:
    apps = api.request("/apps?" + urllib.parse.urlencode(
        {"filter[bundleId]": BUNDLE_ID, "limit": 2}))["data"]
    if len(apps) != 1:
        raise RuntimeError("Expected exactly one matching macOS app")
    path = f"/apps/{apps[0]['id']}/appStoreVersions?" + urllib.parse.urlencode(
        {"filter[platform]": "MAC_OS", "limit": 200})
    versions = []
    while path:
        page = api.request(path)
        versions.extend(v for v in page["data"]
                        if v["attributes"]["versionString"] == version
                        and v["attributes"]["platform"] == "MAC_OS")
        next_url = page.get("links", {}).get("next")
        if next_url and not next_url.startswith(API + "/"):
            raise RuntimeError("Unexpected Apple pagination URL")
        path = next_url[len(API):] if next_url else None
    if len(versions) != 1:
        raise RuntimeError(f"Expected exactly one existing MAC_OS version {version}")
    version_path = f"/appStoreVersions/{versions[0]['id']}"

    def readback() -> dict:
        data = api.request(version_path)["data"]
        attrs = data["attributes"]
        selected = api.request(version_path + "/build")["data"]
        if (attrs["versionString"] != version or attrs["platform"] != "MAC_OS"
                or not selected or selected["attributes"]["version"] != build):
            raise RuntimeError("Existing macOS version/platform/build does not match candidate")
        return {"version_id": data["id"], "version": version, "build": build,
                "platform": attrs["platform"], "state": attrs["appStoreState"],
                "releaseType": attrs["releaseType"]}

    before = readback()
    print(json.dumps({"before": before}), flush=True)
    changed = False
    if apply and before["releaseType"] != "AFTER_APPROVAL":
        if before["state"] not in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
            raise RuntimeError(f"Refusing policy change outside pending review: {before['state']}")
        api.request(version_path, {"data": {
            "type": "appStoreVersions", "id": before["version_id"],
            "attributes": {"releaseType": "AFTER_APPROVAL"},
        }})
        changed = True
    after = readback()
    if apply and after["releaseType"] != "AFTER_APPROVAL":
        raise RuntimeError("Readback did not confirm AFTER_APPROVAL")
    result = {"after": after, "changed": changed, "applied": apply}
    print(json.dumps(result), flush=True)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apple-json", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--apply", action="store_true", help="Set AFTER_APPROVAL; otherwise read only")
    args = parser.parse_args()
    try:
        token = apple_token(args.apple_json)
    except Exception:
        raise SystemExit("Invalid App Store Connect credential; expected a private P-256 key") from None
    try:
        release_policy(AppleAPI(token), args.version, args.build, args.apply)
    except Exception as error:
        print(f"Release policy check failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
