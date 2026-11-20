#!/usr/bin/env python3
"""Read exact candidate processing, submission, and production store state."""
from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path

from resolve_store_baselines import apple_token


API = "https://api.appstoreconnect.apple.com/v1"
ACCEPTED = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_APPLE_RELEASE",
            "PROCESSING_FOR_APP_STORE", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE"}


class AppleAPI:
    def __init__(self, token: str):
        self.token = token

    def get(self, path: str) -> dict:
        request = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {self.token}"})
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)

    def pages(self, path: str) -> list[dict]:
        result = []
        while path:
            page = self.get(path)
            result.extend(page["data"])
            next_url = page.get("links", {}).get("next")
            if next_url and not next_url.startswith(API + "/"):
                raise RuntimeError("Unexpected Apple pagination URL")
            path = next_url[len(API):] if next_url else None
        return result


def apple_state(api: AppleAPI, bundle: str, platform: str, version: str, build: str) -> dict:
    apps = api.pages("/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle, "limit": 2}))
    if len(apps) != 1:
        raise RuntimeError(f"Expected exactly one app for {bundle}")
    app_id = apps[0]["id"]
    versions = api.pages(f"/apps/{app_id}/appStoreVersions?" + urllib.parse.urlencode(
        {"filter[platform]": platform, "limit": 200}))
    versions = [v for v in versions if v["attributes"]["platform"] == platform]
    live = [v for v in versions if v["attributes"]["appStoreState"] == "READY_FOR_SALE"]
    if len(live) != 1:
        raise RuntimeError(f"Expected exactly one live {platform} version")
    builds = api.pages("/builds?" + urllib.parse.urlencode(
        {"filter[app]": app_id, "filter[version]": build, "limit": 200}))
    matching = []
    for candidate in builds:
        prerelease = api.get(f"/builds/{candidate['id']}/preReleaseVersion")["data"]["attributes"]
        if prerelease["version"] == version and prerelease["platform"] == platform:
            matching.append(candidate)
    if len(matching) != 1:
        raise RuntimeError(f"Expected exactly one {platform} candidate {version} ({build})")
    candidate = matching[0]
    selected = [v for v in versions if v["attributes"]["versionString"] == version]
    if len(selected) > 1:
        raise RuntimeError(f"Ambiguous {platform} store version {version}")
    store_version = None
    if selected:
        data = selected[0]
        selected_build = api.get(f"/appStoreVersions/{data['id']}/build")["data"]
        store_version = {"id": data["id"], "state": data["attributes"]["appStoreState"],
                         "releaseType": data["attributes"]["releaseType"],
                         "build_id": selected_build["id"] if selected_build else None,
                         "notes": {loc["attributes"]["locale"]: loc["attributes"].get("whatsNew")
                                   for loc in api.pages(f"/appStoreVersions/{data['id']}/appStoreVersionLocalizations")}}
    return {"app_id": app_id, "platform": platform,
            "live_version": live[0]["attributes"]["versionString"],
            "candidate_version": version, "candidate_build": build, "build_id": candidate["id"],
            "processingState": candidate["attributes"]["processingState"],
            "expired": candidate["attributes"]["expired"], "store_version": store_version,
            "other_pending_versions": [
                {"version": v["attributes"]["versionString"], "state": v["attributes"]["appStoreState"]}
                for v in versions if v["attributes"]["versionString"] != version
                and v["attributes"]["appStoreState"] in ACCEPTED - {"READY_FOR_SALE"}]}


def google_state(key_file: Path, package: str) -> dict:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    credentials = service_account.Credentials.from_service_account_file(
        key_file, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    api = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False)
    edits = api.edits()
    edit_id = edits.insert(packageName=package, body={}).execute()["id"]
    try:
        return {track: edits.tracks().get(packageName=package, editId=edit_id, track=track).execute()
                for track in ("internal", "production")}
    finally:
        edits.delete(packageName=package, editId=edit_id).execute()


def has_release(track: dict, build: str, completed: bool = False) -> bool:
    return any(build in list(map(str, r.get("versionCodes", [])))
               and (not completed or r.get("status") == "completed")
               for r in track.get("releases", []))


def validate(state: dict, build: str, verify: bool, google_notes: str | None = None,
             apple_notes: str | None = None) -> None:
    google = state.get("google_play")
    if google and not has_release(google["production" if verify else "internal"], build, completed=True):
        raise RuntimeError(f"Google Play {'production' if verify else 'internal'} lacks completed code {build}")
    if verify and google and google_notes is not None:
        releases = [r for r in google["production"].get("releases", [])
                    if build in list(map(str, r.get("versionCodes", [])))]
        if not any(any(n.get("language") == "en-US" and n.get("text") == google_notes
                       for n in r.get("releaseNotes", [])) for r in releases):
            raise RuntimeError("Google Play en-US notes readback did not match reviewed notes")
    for platform in ("ios", "macos"):
        if platform not in state:
            continue
        apple = state[platform]
        if apple["processingState"] != "VALID" or apple["expired"]:
            raise RuntimeError(f"{platform} candidate is not a valid, unexpired processed build")
        selected = apple["store_version"]
        if verify:
            if (not selected or selected["build_id"] != apple["build_id"]
                    or selected["state"] not in ACCEPTED
                    or selected["releaseType"] != "AFTER_APPROVAL"):
                raise RuntimeError(f"{platform} exact candidate submission/automatic-release readback failed")
            locale = "en-CA" if platform == "ios" else "en-US"
            if apple_notes is not None and selected["notes"].get(locale) != apple_notes:
                raise RuntimeError(f"{platform} {locale} notes readback did not match reviewed notes")
        elif apple["other_pending_versions"]:
            raise RuntimeError(f"{platform} has an older pending submission; do not withdraw it automatically")
        elif selected and selected["state"] in ACCEPTED:
            raise RuntimeError(f"{platform} candidate already submitted; do not submit twice")
    if not verify and google and has_release(google["production"], build):
        raise RuntimeError("Android candidate already in production; do not promote twice")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--google-json", type=Path, required=True)
    parser.add_argument("--apple-json", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--google-notes", type=Path)
    parser.add_argument("--apple-notes", type=Path)
    parser.add_argument("--android", choices=("true", "false"), default="true")
    parser.add_argument("--ios", choices=("true", "false"), default="true")
    parser.add_argument("--macos", choices=("true", "false"), default="true")
    args = parser.parse_args()
    state = {}
    if args.android == "true":
        state["google_play"] = google_state(args.google_json, "dev.nosuch.nt_helper")
    if args.ios == "true" or args.macos == "true":
        api = AppleAPI(apple_token(args.apple_json))
        for name, bundle, platform in (("ios", "dev.nosuch.ntHelper", "IOS"),
                                       ("macos", "dev.nosuch.macos.ntHelper", "MAC_OS")):
            if getattr(args, name) == "true":
                state[name] = apple_state(api, bundle, platform, args.version, args.build)
    args.output.write_text(json.dumps(state, indent=2) + "\n")
    print(json.dumps(state, indent=2), flush=True)
    validate(state, args.build, args.verify,
             args.google_notes.read_text() if args.google_notes else None,
             args.apple_notes.read_text() if args.apple_notes else None)


if __name__ == "__main__":
    main()
