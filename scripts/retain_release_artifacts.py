#!/usr/bin/env python3
"""Keep the five newest published nt_helper releases and their Actions artifacts.

Delete older published releases/assets, never Git tags. Preserve unpublished work.

Dry-run is the default. Requires gh authentication; --apply opts into deletion.
Unknown artifacts are preserved. Any API/provenance/race error aborts cleanup.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime

REPO = "No-Such-Device/nt_helper"
REPO_ID = 909516521
WORKFLOW_ID = 139037423
WORKFLOW_PATH = ".github/workflows/tag-build.yml"
CLEANUP_PATH = ".github/workflows/retain-release-artifacts.yml"
VERSION = r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def api(path, method="GET", missing_ok=False):
    require(path == f"repos/{REPO}" or path.startswith(f"repos/{REPO}/"),
            "Repository scope violation")
    require(method == "GET" or (method == "DELETE" and re.fullmatch(
        rf"repos/{re.escape(REPO)}/(?:actions/artifacts|releases)/[1-9][0-9]*", path)),
        "Mutation endpoint not authorized")
    proc = subprocess.run(
        ["gh", "api", "--hostname", "github.com", "--include", "--method", method, path],
        capture_output=True, text=True, check=False,
    )
    # gh --include writes HTTP headers then JSON, including for 204/404.
    header, separator, body = proc.stdout.partition("\n\n")
    require(separator and header.startswith("HTTP/"), "Missing HTTP response")
    status = int(header.splitlines()[0].split()[1])
    if missing_ok and status == 404:
        return None
    require(proc.returncode == 0 and status in (200, 204),
            f"GitHub API failed: {method} {path} (HTTP {status})")
    if method == "DELETE":
        require(status == 204, "Deletion did not return HTTP 204")
        return {"status": status}
    return json.loads(body)


def pages(path, key=None, fetch=api):
    """Validate every page, totals and uniqueness; never use partial results."""
    result, expected = [], None
    for page in range(1, 1001):
        data = fetch(f"{path}{'&' if '?' in path else '?'}per_page=100&page={page}")
        if key:
            require(isinstance(data, dict) and type(data.get("total_count")) is int,
                    "Missing pagination total")
            if expected is None:
                expected = data["total_count"]
            require(data["total_count"] == expected, "Inventory changed during pagination")
            rows = data.get(key)
        else:
            rows = data
        require(isinstance(rows, list) and len(rows) <= 100, "Malformed API page")
        result.extend(rows)
        if len(rows) < 100:
            require(expected is None or len(result) == expected, "Incomplete pagination")
            ids = [x.get("id", x.get("name", x.get("ref"))) for x in result]
            require(None not in ids and len(ids) == len(set(ids)), "Duplicate/missing identity")
            return result
    raise RuntimeError("Pagination limit exceeded")


def timestamp(value):
    require(isinstance(value, str) and value.endswith("Z"), "Missing chronology")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def trusted(run):
    return (run["repository"]["id"] == REPO_ID
            and run["repository"]["full_name"] == REPO
            and run["head_repository"]["id"] == REPO_ID
            and run["workflow_id"] == WORKFLOW_ID
            and run["path"] == WORKFLOW_PATH and run["event"] == "push"
            and re.fullmatch("v" + VERSION, run["head_branch"]) is not None)


def assert_idle(runs, own_id):
    for run in runs:
        if run["status"] == "completed":
            continue
        require(str(run["id"]) == own_id
                and run["path"] == CLEANUP_PATH
                and run["event"] in ("schedule", "workflow_run")
                and run["head_branch"] == "main"
                and run["repository"]["id"] == REPO_ID
                and run["head_repository"]["id"] == REPO_ID,
                f"Active producer/consumer: {run['id']}; defer cleanup")


def plan(artifacts, runs, releases, tags, historical_sources=None):
    require(isinstance(artifacts, list) and runs and tags,
            "Empty inventory/provenance; refusing cleanup")
    by_run = {r["id"]: r for r in runs}
    by_tag = {t["name"]: t["commit"]["sha"] for t in tags}
    selected, obsolete = select_releases(releases)
    published = {r["tag_name"]: timestamp(r["published_at"]) for r in selected + obsolete}
    groups, unknown = {}, []
    for artifact in artifacts:
        require(type(artifact["id"]) is int and type(artifact["size_in_bytes"]) is int
                and artifact["size_in_bytes"] > 0 and artifact["expired"] is False,
                "Malformed/expired artifact inventory")
        match = re.fullmatch(r"nt_helper-(" + VERSION + r")\.aab", artifact["name"])
        if not match:
            unknown.append(artifact["id"])
            continue
        run = by_run[artifact["workflow_run"]["id"]]
        if not trusted(run):
            unknown.append(artifact["id"])
            continue
        tag = "v" + match[1]
        historical = (historical_sources or {}).get(run["head_sha"], "")
        # Deleted historical tags: only accept the immutable, known tag-only
        # producer header plus its push-run metadata, never infer from a name.
        historical_tag_push = historical.startswith(
            'name: Multi-Platform Build\n\non:\n  push:\n    tags:\n'
            '      - "v*" # e.g., v1.0, v1.2.3, etc.\n  workflow_dispatch:')
        tag_verified = (by_tag.get(tag) == run["head_sha"] if tag in by_tag
                        else historical_tag_push and run["conclusion"] in ("failure", "cancelled")
                        and tag not in published)
        require(tag == run["head_branch"] and tag_verified
                and artifact["workflow_run"]["head_sha"] == run["head_sha"]
                and artifact["workflow_run"]["repository_id"] == REPO_ID
                and artifact["workflow_run"]["head_repository_id"] == REPO_ID,
                "Artifact/tag/run provenance mismatch")
        require(run["status"] == "completed" and run["conclusion"] in
                ("success", "failure", "cancelled", "timed_out", "startup_failure", "action_required", "stale", "neutral", "skipped"),
                "Nonterminal or unknown release attempt")
        groups.setdefault(tag, []).append(artifact)
    keep = [r["tag_name"] for r in selected]
    # Only artifacts belonging to explicitly obsolete published releases may go.
    # Draft/unpublished attempts never consume slots and are never deleted.
    old_tags = {r["tag_name"] for r in obsolete}
    protected = {r["tag_name"] for r in releases if r["draft"] or r["published_at"] is None}
    return {
        "keep": keep,
        "keep_release_ids": [r["id"] for r in selected],
        "delete_releases": obsolete,
        "reason": "Published_at descending, then release ID descending; includes prereleases",
        "unknown_preserved": unknown,
        "delete": sorted([a for t, rows in groups.items() if t in old_tags - protected
                          for a in rows], key=lambda a: a["id"]),
    }


def select_releases(releases):
    require(isinstance(releases, list), "Malformed releases")
    ids, tags, published = set(), set(), []
    for release in releases:
        require(type(release["id"]) is int and release["id"] > 0
                and release["id"] not in ids and type(release["draft"]) is bool
                and type(release["prerelease"]) is bool
                and isinstance(release["tag_name"], str) and release["tag_name"]
                and isinstance(release["assets"], list), "Malformed release identity")
        ids.add(release["id"])
        if release["draft"] or release["published_at"] is None:
            continue
        timestamp(release["published_at"])
        require(release["tag_name"] not in tags, "Duplicate published release tag")
        tags.add(release["tag_name"])
        published.append(release)
    require(len(published) >= 5, "Fewer than five published releases; refusing cleanup")
    published.sort(key=lambda r: (timestamp(r["published_at"]), r["id"]), reverse=True)
    return published[:5], published[5:]


def normalize_release(release):
    for asset in release["assets"]:
        asset.pop("download_count", None)
    return release


def release_assets(release):
    assets = pages(f"repos/{REPO}/releases/{release['id']}/assets")
    for asset in assets:
        asset.pop("download_count", None)
    require(assets == release["assets"], "Incomplete/changed release asset listing")
    return assets


def tag_refs():
    # GitHub matching-refs is NOT paginated (it ignores page/per_page).
    refs = api(f"repos/{REPO}/git/matching-refs/tags/")
    require(isinstance(refs, list) and refs, "Missing tag refs")
    names = []
    for ref in refs:
        require(ref["ref"].startswith("refs/tags/")
                and re.fullmatch(r"[0-9a-f]{40}", ref["object"]["sha"]),
                "Malformed tag ref")
        names.append(ref["ref"])
    require(len(names) == len(set(names)), "Duplicate tag refs")
    return refs


def release_guard():
    # Re-list complete release and ref inventories before EVERY release deletion.
    runs = pages(f"repos/{REPO}/actions/runs", "workflow_runs")
    assert_idle(runs, os.environ.get("GITHUB_RUN_ID", ""))
    releases = [normalize_release(r) for r in pages(f"repos/{REPO}/releases")]
    return releases, tag_refs()


def snapshot():
    repo = api(f"repos/{REPO}")
    require(repo["id"] == REPO_ID and repo["full_name"] == REPO
            and repo["default_branch"] == "main", "Unexpected repository")
    workflow = api(f"repos/{REPO}/actions/workflows/{WORKFLOW_ID}")
    require(workflow["path"] == WORKFLOW_PATH and workflow["state"] == "active",
            "Unexpected release workflow")
    artifacts = pages(f"repos/{REPO}/actions/artifacts", "artifacts")
    runs = pages(f"repos/{REPO}/actions/runs", "workflow_runs")
    assert_idle(runs, os.environ.get("GITHUB_RUN_ID", ""))
    runs = [r for r in runs if str(r["id"]) != os.environ.get("GITHUB_RUN_ID", "")]
    # Historical artifact runs may have aged out of the run listing.
    known = {r["id"] for r in runs}
    for artifact in artifacts:
        run_id = artifact["workflow_run"]["id"]
        if run_id not in known:
            runs.append(api(f"repos/{REPO}/actions/runs/{run_id}"))
            known.add(run_id)
    releases = pages(f"repos/{REPO}/releases")
    # Download counters are unrelated to retention and may change during cleanup.
    releases = [normalize_release(r) for r in releases]
    tags = pages(f"repos/{REPO}/tags")
    names = {t["name"] for t in tags}
    historical_sources = {}
    artifact_runs = {a["workflow_run"]["id"] for a in artifacts}
    for run in runs:
        if run["id"] in artifact_runs and trusted(run) and run["head_branch"] not in names:
            sha = run["head_sha"]
            require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid historical SHA")
            source = api(f"repos/{REPO}/contents/{WORKFLOW_PATH}?ref={sha}")
            require(source["path"] == WORKFLOW_PATH and source["encoding"] == "base64",
                    "Missing immutable historical workflow")
            historical_sources[sha] = base64.b64decode(source["content"]).decode("utf-8")
    return {"artifacts": artifacts, "runs": runs, "releases": releases, "tags": tags,
            "historical_sources": historical_sources}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def apply_artifacts(manifest, before, directory):
    # Replan a complete fresh inventory before mutation, including release/tag
    # chronology. Abort on concurrent upload or changes to any keep/delete input.
    fresh = snapshot()
    require(fresh == before, "Snapshot changed; rerun dry-run")
    require(plan(**fresh) == manifest, "Plan changed")
    receipts = []
    for artifact in manifest["delete"]:
        current = snapshot()
        removed = {r["id"] for r in receipts}
        remaining = [a for a in before["artifacts"] if a["id"] not in removed]
        expected = {**before, "artifacts": remaining}
        if "historical_sources" in before:
            shas = {a["workflow_run"]["head_sha"] for a in remaining}
            expected["historical_sources"] = {sha: source for sha, source in
                                               before["historical_sources"].items() if sha in shas}
        require(current == expected, "Concurrent inventory/provenance change; defer")
        artifact_path = f"repos/{REPO}/actions/artifacts/{artifact['id']}"
        require(api(artifact_path) == artifact, "Artifact identity changed")
        run_id = artifact["workflow_run"]["id"]
        original_run = next(r for r in before["runs"] if r["id"] == run_id)
        require(api(f"repos/{REPO}/actions/runs/{run_id}") == original_run,
                "Producer rerun/identity changed")
        receipt = {"id": artifact["id"], **api(artifact_path, "DELETE")}
        require(api(artifact_path, missing_ok=True) is None, "Deleted artifact still exists")
        receipt["verified_absent"] = True
        receipts.append(receipt)
        write_json(directory / "receipts.json", receipts)
    after = snapshot()
    write_json(directory / "after.json", after)
    deleted = {a["id"] for a in manifest["delete"]}
    require(sorted(after["artifacts"], key=lambda a: a["id"]) ==
            sorted([a for a in before["artifacts"] if a["id"] not in deleted],
                   key=lambda a: a["id"]), "Unexpected final artifact inventory")
    require(after["releases"] == before["releases"] and after["tags"] == before["tags"],
            "Release/tag/assets snapshot changed")
    return receipts


def apply(manifest, before, directory):
    # Artifact deletion runs first while all published provenance still exists.
    artifact_receipts = apply_artifacts(manifest, before, directory)
    expected = before["releases"]
    refs = tag_refs()
    require(refs == json.loads((directory / "tag-refs-preflight.json").read_text()),
            "Tag refs changed since preflight")
    write_json(directory / "tag-refs-before.json", refs)
    receipts = []
    for release in manifest["delete_releases"]:
        current, current_refs = release_guard()
        require(current == expected and current_refs == refs,
                "Concurrent release/ref change; defer")
        kept, obsolete = select_releases(current)
        require([r["id"] for r in kept] == manifest["keep_release_ids"]
                and release in obsolete, "Release keep set changed")
        path = f"repos/{REPO}/releases/{release['id']}"
        require(normalize_release(api(path)) == release, "Release identity changed")
        release_assets(release)
        receipt = {"id": release["id"], "tag": release["tag_name"],
                   **api(path, "DELETE")}
        # Persist the HTTP receipt even if subsequent absence verification fails.
        receipts.append(receipt)
        write_json(directory / "release-receipts.json", receipts)
        require(api(path, missing_ok=True) is None, "Deleted release still exists")
        receipt["verified_absent"] = True
        write_json(directory / "release-receipts.json", receipts)
        expected = [r for r in expected if r["id"] != release["id"]]
    current, current_refs = release_guard()
    require(current == expected and current_refs == refs, "Final release/ref mismatch")
    for release in current:
        release_assets(release)
    after = snapshot()
    require(after["releases"] == expected and after["tags"] == before["tags"],
            "Final release/tag mismatch")
    removed_artifacts = {a["id"] for a in manifest["delete"]}
    require(after["artifacts"] == [a for a in before["artifacts"]
                                   if a["id"] not in removed_artifacts],
            "Final artifact inventory changed during release cleanup")
    write_json(directory / "after.json", after)
    write_json(directory / "tag-refs-after.json", current_refs)
    return artifact_receipts + receipts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--evidence-dir", type=Path, required=True)
    args = parser.parse_args()
    require(os.environ.get("GITHUB_REPOSITORY", REPO) == REPO, "Wrong repository environment")
    args.evidence_dir.mkdir(parents=True, exist_ok=False)
    before = snapshot()
    write_json(args.evidence_dir / "before.json", before)
    manifest = plan(**before)
    # Paginate ALL assets, including drafts and every retained release, before mutation.
    assets = {str(r["id"]): release_assets(r) for r in before["releases"]}
    write_json(args.evidence_dir / "release-assets-before.json", assets)
    refs = tag_refs()
    require({r["ref"][10:] for r in refs} == {t["name"] for t in before["tags"]},
            "Incomplete refs/tags inventory")
    write_json(args.evidence_dir / "tag-refs-preflight.json", refs)
    write_json(args.evidence_dir / "manifest.json", manifest)
    digest = hashlib.sha256((args.evidence_dir / "manifest.json").read_bytes()).hexdigest()
    (args.evidence_dir / "manifest.sha256").write_text(digest + "\n")
    print(json.dumps({"keep": manifest["keep"], "delete_count": len(manifest["delete"]),
                      "delete_bytes": sum(a["size_in_bytes"] for a in manifest["delete"]),
                      "delete_release_count": len(manifest["delete_releases"]),
                      "delete_release_asset_bytes": sum(a["size"] for r in
                          manifest["delete_releases"] for a in r["assets"]),
                      "manifest_sha256": digest, "apply": args.apply}))
    if args.apply:
        apply(manifest, before, args.evidence_dir)


if __name__ == "__main__":
    main()
