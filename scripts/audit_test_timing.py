#!/usr/bin/env python3
"""Audit isolated Flutter test files; keep slow files out of the local fast loop.

CI continues to run `flutter test --no-pub` (all categories). A file timeout is
triage evidence, not evidence that its tests are redundant or safe to remove.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / ".dart_tool" / "test-timing"


def test_timings(output):
    starts = {}
    durations = []
    for line in output.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "testStart":
            test = event["test"]
            starts[test["id"]] = (test["name"], event["time"])
        elif event.get("type") == "testDone" and event["testID"] in starts:
            name, start = starts[event["testID"]]
            durations.append({"name": name, "seconds": (event["time"] - start) / 1000,
                              "result": event.get("result"), "skipped": event.get("skipped", False)})
    return sorted(durations, key=lambda test: test["seconds"], reverse=True)


def run_file(path, timeout, log_dir, flutter="flutter"):
    command = [flutter, "test", "--no-pub", "--concurrency=1", "--reporter=json", path]
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, start_new_session=True)
    status = None
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        status = "timeout"
        # Kill the process group, not just the flutter wrapper: compiler and
        # flutter_tester children must not accumulate between files.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=0.5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
    seconds = time.monotonic() - started
    status = status or ("passed" if process.returncode == 0 else "failed")
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / (path.replace("/", "__") + ".log")
    log.write_text(output)
    return {"file": path, "status": status, "seconds": round(seconds, 3),
            "exit_code": process.returncode, "tests": test_timings(output), "log": str(log)}


def categories(results):
    return {"fast": [r["file"] for r in results if r["status"] != "timeout"],
            "slow": [r["file"] for r in results if r["status"] == "timeout"]}


def markdown(report):
    results = report["results"]
    counts = {status: sum(r["status"] == status for r in results)
              for status in ("passed", "failed", "timeout")}
    lines = ["# Isolated Flutter test timing audit", "",
             f"Commit: `{report['commit']}`. Per-file limit: {report['timeout_seconds']:g} seconds.",
             f"Files: {len(results)}; passed: {counts['passed']}; failed: {counts['failed']}; timed out: {counts['timeout']}.", "",
             "The limit includes Flutter startup, compilation, setup, tests, and teardown. Files run serially to avoid Flutter startup-lock contention.",
             "A timeout is a **fix/review queue**, not a deletion recommendation. Later tests in a timed-out file may never have run.",
             "Individual completed-test timings come from Flutter JSON events and exclude wrapper startup.", "",
             "## Slow category (explicit local run only)", "", "| File | Elapsed | Longest completed test |", "|---|---:|---|"]
    for result in results:
        if result["status"] != "timeout":
            continue
        tests = [t for t in result["tests"] if not t["skipped"] and "loading " not in t["name"]]
        longest = tests[0] if tests else None
        description = (f"{longest['seconds']:.3f}s: {longest['name']}" if longest else "No test completed before deadline")
        lines.append(f"| `{result['file']}` | {result['seconds']:.2f}s | {description.replace('|', '/')} |")
    lines += ["", "## Failures (not hidden in the slow category)", ""]
    lines += [f"- `{r['file']}`: exit {r['exit_code']} (see audit log)" for r in results if r["status"] == "failed"] or ["None."]
    lines += ["", "## Running categories", "", "```bash",
              "python3 scripts/audit_test_timing.py --run fast",
              "python3 scripts/audit_test_timing.py --run slow",
              "flutter test --no-pub  # full required CI/release coverage", "```", "",
              "Categories apply only to the explicit local runner. No source tests are tagged/skipped and CI still runs every regression.",
              "Review timeout logs before deleting a test: retain bug regressions, geometry/semantics checks, and distinct protocol/error cases.", ""]
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", help="Optional exact test paths; otherwise discover test/**/*_test.dart")
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--resume", action="store_true", help="Reuse results for the same commit and deadline")
    parser.add_argument("--run", choices=["fast", "slow", "all"], help="Run a saved category without the audit deadline")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "report.json"
    if args.run:
        report = json.loads(manifest.read_text())
        paths = ([r["file"] for r in report["results"]] if args.run == "all"
                 else report["categories"][args.run])
        current = {p.relative_to(ROOT).as_posix() for p in (ROOT / "test").rglob("*_test.dart")}
        if args.run == "fast":
            # Newly added, unaudited files must run, not disappear silently.
            paths = sorted(current - set(report["categories"]["slow"]))
        elif not set(paths) <= current:
            parser.error("Saved category contains missing/invalid test paths; rerun the audit")
        if not paths:
            print("Category is empty; nothing to run.")
            return 0
        return subprocess.call([args.flutter, "test", "--no-pub", *paths], cwd=ROOT)
    paths = args.files or sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "test").rglob("*_test.dart"))
    for path in paths:
        resolved = (ROOT / path).resolve()
        if not resolved.is_relative_to(ROOT / "test") or not resolved.is_file() or not path.endswith("_test.dart"):
            parser.error(f"Not a test file inside test/: {path}")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    results = []
    if args.resume and manifest.exists():
        previous = json.loads(manifest.read_text())
        if previous["commit"] != commit or previous["timeout_seconds"] != args.timeout:
            parser.error("Resume requires the same commit and deadline")
        results = [r for r in previous["results"] if r["file"] in paths]
    completed = {r["file"] for r in results}
    for path in paths:
        if path in completed:
            continue
        result = run_file(path, args.timeout, output / "logs", args.flutter)
        results.append(result)
        report = {"commit": commit, "timeout_seconds": args.timeout,
                  "results": results, "categories": categories(results)}
        manifest.write_text(json.dumps(report, indent=2) + "\n")
        (output / "report.md").write_text(markdown(report))
        print(f"{len(results)}/{len(paths)} {result['status']:7} {result['seconds']:6.2f}s {path}", flush=True)
    print(f"Report: {output / 'report.md'}")
    # Timeouts are expected audit findings; genuine failures remain failures.
    return int(any(r["status"] == "failed" for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
