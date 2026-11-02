#!/usr/bin/env python3
"""Resolve live store versions to nt_helper release tags."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path


def tags(repo: Path) -> dict[str, tuple[str, str]]:
    refs = subprocess.check_output(
        ["git", "for-each-ref", "refs/tags/v*", "--format=%(refname:short)"],
        cwd=repo,
        text=True,
    ).splitlines()
    result = {}
    for tag in refs:
        try:
            text = subprocess.check_output(
                ["git", "show", f"{tag}:pubspec.yaml"], cwd=repo, text=True
            )
        except subprocess.CalledProcessError:
            continue
        match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", text, re.MULTILINE)
        if match:
            result[tag] = (match.group(1), match.group(2))
    return result


def google_production_version(service_json: Path, package: str) -> str:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    credentials = service_account.Credentials.from_service_account_file(
        service_json, scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    api = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False)
    edit = api.edits().insert(packageName=package, body={}).execute()
    edit_id = edit["id"]
    try:
        track = api.edits().tracks().get(
            packageName=package, editId=edit_id, track="production"
        ).execute()
        releases = track.get("releases", [])
        codes = [code for release in releases for code in release.get("versionCodes", [])]
        if not codes:
            raise RuntimeError("Google Play production track has no version code")
        return str(max(map(int, codes)))
    finally:
        api.edits().delete(packageName=package, editId=edit_id).execute()


def apple_token(key_json: Path) -> str:
    import time
    import jwt

    data = json.loads(key_json.read_text())
    key = data["key"].replace("\\n", "\n")
    return jwt.encode(
        {"iss": data["issuer_id"], "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": data["key_id"]},
    )


def apple_live_version(key_json: Path, bundle_id: str, platform: str) -> str:
    token = apple_token(key_json)
    headers = {"Authorization": f"Bearer {token}"}

    def get(url: str) -> dict:
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request) as response:
            return json.load(response)

    apps_url = "https://api.appstoreconnect.apple.com/v1/apps?" + urllib.parse.urlencode(
        {"filter[bundleId]": bundle_id, "limit": 1}
    )
    apps = get(apps_url)["data"]
    if not apps:
        raise RuntimeError(f"No App Store Connect app found for {bundle_id}")
    versions_url = "https://api.appstoreconnect.apple.com/v1/apps/{}/appStoreVersions?{}".format(
        apps[0]["id"],
        urllib.parse.urlencode(
            {"filter[platform]": platform, "filter[appStoreState]": "READY_FOR_SALE", "limit": 1}
        ),
    )
    versions = get(versions_url)["data"]
    if not versions:
        raise RuntimeError(f"No READY_FOR_SALE {platform} version found for {bundle_id}")
    return versions[0]["attributes"]["versionString"]


def find_tag(release_tags: dict[str, tuple[str, str]], version: str, build: str | None) -> str:
    matches = [tag for tag, values in release_tags.items() if values[0] == version and (build is None or values[1] == build)]
    if len(matches) != 1:
        detail = f"version {version}" + (f"+{build}" if build else "")
        raise RuntimeError(f"Could not map live store {detail} to exactly one git tag: {matches}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--google-json", type=Path, required=True)
    parser.add_argument("--google-package", default="dev.nosuch.nt_helper")
    parser.add_argument("--apple-json", type=Path, required=True)
    parser.add_argument("--ios-bundle", default="dev.nosuch.ntHelper")
    parser.add_argument("--macos-bundle", default="dev.nosuch.macos.ntHelper")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    release_tags = tags(args.repo)
    google_build = google_production_version(args.google_json, args.google_package)
    ios_version = apple_live_version(args.apple_json, args.ios_bundle, "IOS")
    macos_version = apple_live_version(args.apple_json, args.macos_bundle, "MAC_OS")
    google_tags = [tag for tag, (_, build) in release_tags.items() if build == google_build]
    if len(google_tags) != 1:
        raise RuntimeError(
            f"Could not map Google Play version code {google_build} to exactly one git tag: {google_tags}"
        )
    result = {
        "google_play": {"version_code": google_build, "previous_tag": google_tags[0]},
        "ios": {"version": ios_version, "previous_tag": find_tag(release_tags, ios_version, None)},
        "macos": {"version": macos_version, "previous_tag": find_tag(release_tags, macos_version, None)},
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
