#!/usr/bin/env python3
"""Keep five distinct nt_helper release versions; never modify releases or tags.

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
            ids = [x.get("id", x.get("name")) for x in result]
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
                and run["event"] == "schedule"
                and run["head_branch"] == "main"
                and run["repository"]["id"] == REPO_ID
                and run["head_repository"]["id"] == REPO_ID,
                f"Active producer/consumer: {run['id']}; defer cleanup")


def plan(artifacts, runs, releases, tags, historical_sources=None):
    require(artifacts and runs and tags, "Empty inventory/provenance; refusing cleanup")
    by_run = {r["id"]: r for r in runs}
    by_tag = {t["name"]: t["commit"]["sha"] for t in tags}
    published = {}
    for release in releases:
        if not release["draft"]:
            tag = release["tag_name"]
            require(tag not in published, "Duplicate published release tag")
            published[tag] = timestamp(release["published_at"])
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
    # Use original run creation, never updated_at or artifact upload time (reruns).
    dates, successful = {}, set()
    for tag, artifacts_for_tag in groups.items():
        tag_runs = [r for r in runs if trusted(r) and r["head_branch"] == tag]
        success = any(r["conclusion"] == "success" for r in tag_runs)
        if success:
            successful.add(tag)
        if tag in published:
            dates[tag] = published[tag]
        elif success:
            dates[tag] = min(timestamp(r["created_at"]) for r in tag_runs)
        else:
            # Failed unpublished attempts do not consume a keep slot; an attempt
            # newer than the boundary is preserved below, not treated as old.
            dates[tag] = min(timestamp(by_run[a["workflow_run"]["id"]]["created_at"])
                             for a in artifacts_for_tag)
    eligible = {t for t in groups if t in published or t in successful}
    require(len(eligible) >= 5, "Fewer than five verified release versions; no cleanup")
    newest = sorted(eligible, key=lambda t: (dates[t], t), reverse=True)[:5]
    boundary = dates[newest[-1]]
    # Retain ties and newer unpublished attempts; also retain the five latest
    # successful versions if published failed attempts would displace them.
    keep = {t for t in groups if dates[t] >= boundary}
    keep.update(sorted(successful, key=lambda t: (dates[t], t), reverse=True)[:5])
    return {
        "keep": sorted(keep, key=lambda t: (dates[t], t), reverse=True),
        "reason": "Publication chronology (including prereleases); original successful tag-push chronology fallback; preserve ties/new attempts and latest five successes",
        "unknown_preserved": unknown,
        "delete": sorted([a for t, rows in groups.items() if t not in keep for a in rows],
                         key=lambda a: a["id"]),
    }


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
    for release in releases:
        for asset in release["assets"]:
            asset.pop("download_count", None)
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


def apply(manifest, before, directory):
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
    write_json(args.evidence_dir / "manifest.json", manifest)
    digest = hashlib.sha256((args.evidence_dir / "manifest.json").read_bytes()).hexdigest()
    (args.evidence_dir / "manifest.sha256").write_text(digest + "\n")
    print(json.dumps({"keep": manifest["keep"], "delete_count": len(manifest["delete"]),
                      "delete_bytes": sum(a["size_in_bytes"] for a in manifest["delete"]),
                      "manifest_sha256": digest, "apply": args.apply}))
    if args.apply:
        apply(manifest, before, args.evidence_dir)


if __name__ == "__main__":
    main()
