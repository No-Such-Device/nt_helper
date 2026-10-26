"""Deterministic offline safety tests; no GitHub credentials or mutations."""

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import retain_release_artifacts as policy


def fixture(count=7):
    artifacts, runs, releases, tags = [], [], [], []
    for n in range(1, count + 1):
        tag, sha = f"v1.0.{n}", str(n) * 40
        date = f"2026-01-{n:02d}T00:00:00Z"
        runs.append({"id": n, "repository": {"id": policy.REPO_ID, "full_name": policy.REPO},
                     "head_repository": {"id": policy.REPO_ID},
                     "workflow_id": policy.WORKFLOW_ID, "path": policy.WORKFLOW_PATH,
                     "event": "push", "head_branch": tag, "head_sha": sha,
                     "status": "completed", "conclusion": "success", "created_at": date})
        artifacts.append({"id": n, "name": f"nt_helper-1.0.{n}.aab", "size_in_bytes": 100,
                          "expired": False, "workflow_run": {
                              "id": n, "head_sha": sha, "repository_id": policy.REPO_ID,
                              "head_repository_id": policy.REPO_ID}})
        releases.append({"id": n, "draft": False, "tag_name": tag, "published_at": date,
                         "prerelease": False, "assets": []})
        tags.append({"name": tag, "commit": {"sha": sha}})
    return dict(artifacts=artifacts, runs=runs, releases=releases, tags=tags)


class PlanningTests(unittest.TestCase):
    def test_latest_five_distinct_versions(self):
        result = policy.plan(**fixture())
        self.assertEqual(result["keep"], [f"v1.0.{n}" for n in (7, 6, 5, 4, 3)])
        self.assertEqual([a["id"] for a in result["delete"]], [1, 2])

    def test_duplicate_attempts_do_not_consume_slots_and_all_old_attempts_deleted(self):
        data = fixture()
        for index in (0, 6):
            artifact = copy.deepcopy(data["artifacts"][index])
            artifact["id"] += 100
            data["artifacts"].append(artifact)
        result = policy.plan(**data)
        self.assertEqual([a["id"] for a in result["delete"]], [1, 2, 101])
        self.assertEqual(len(result["keep"]), 5)

    def test_old_rerun_upload_date_and_updated_at_do_not_reorder_release(self):
        data = fixture()
        data["runs"][0]["updated_at"] = "2026-12-31T00:00:00Z"
        data["runs"][0]["run_attempt"] = 8
        data["artifacts"][0]["created_at"] = "2026-12-31T00:00:00Z"
        self.assertEqual([a["id"] for a in policy.plan(**data)["delete"]], [1, 2])

    def test_publication_not_numeric_version_order_and_prerelease_included(self):
        data = fixture()
        data["releases"][0]["published_at"] = "2026-12-01T00:00:00Z"
        data["releases"][0]["prerelease"] = True
        data["runs"][0]["conclusion"] = "failure"
        result = policy.plan(**data)
        self.assertEqual(result["keep"][0], "v1.0.1")
        # Preserve extra latest successful version at an ambiguous boundary.
        self.assertIn("v1.0.3", result["keep"])
        self.assertEqual([a["id"] for a in result["delete"]], [2])

    def test_successful_original_run_fallback_without_release_records(self):
        data = fixture()
        data["releases"] = []
        data["runs"][0]["updated_at"] = "2026-12-31T00:00:00Z"
        self.assertEqual([a["id"] for a in policy.plan(**data)["delete"]], [1, 2])

    def test_old_failed_and_cancelled_attempts_are_deleted(self):
        for conclusion in ("failure", "cancelled"):
            with self.subTest(conclusion=conclusion):
                data = fixture()
                data["runs"][0]["conclusion"] = conclusion
                data["releases"] = data["releases"][1:]
                self.assertEqual([a["id"] for a in policy.plan(**data)["delete"]], [1, 2])

    def test_new_failed_unpublished_attempt_preserved(self):
        data = fixture(8)
        data["runs"][-1]["conclusion"] = "failure"
        data["releases"].pop()
        self.assertIn("v1.0.8", policy.plan(**data)["keep"])

    def test_equal_boundary_preserves_extra(self):
        data = fixture()
        data["releases"][1]["published_at"] = data["releases"][2]["published_at"]
        self.assertIn("v1.0.2", policy.plan(**data)["keep"])

    def test_unknown_nonrelease_and_dispatch_preserved(self):
        data = fixture()
        data["artifacts"][0]["name"] = "routine-artifact"
        data["runs"][1]["event"] = "workflow_dispatch"
        self.assertEqual(policy.plan(**data)["unknown_preserved"], [1, 2])
        self.assertEqual(policy.plan(**data)["delete"], [])

    def test_fork_untrusted_workflow_preserved(self):
        for field, value in (("workflow_id", 99), ("head_repository", {"id": 99})):
            data = fixture()
            data["runs"][0][field] = value
            self.assertIn(1, policy.plan(**data)["unknown_preserved"])

    def test_missing_mismatched_provenance_and_empty_inventory_fail_closed(self):
        for mutate in (
            lambda d: d["tags"].pop(0),
            lambda d: d["runs"][0].update(head_sha="changed"),
            lambda d: d["runs"][0].pop("repository"),
            lambda d: d["artifacts"].clear(),
            lambda d: d["artifacts"][0].update(expired=True),
            lambda d: d["releases"][0].update(published_at=None),
        ):
            data = fixture()
            mutate(data)
            with self.assertRaises((RuntimeError, KeyError)):
                policy.plan(**data)

    def test_deleted_failed_tag_requires_immutable_tag_only_producer(self):
        data = fixture()
        sha = data["tags"].pop(0)["commit"]["sha"]
        data["runs"][0]["conclusion"] = "failure"
        data["releases"].pop(0)
        source = ('name: Multi-Platform Build\n\non:\n  push:\n    tags:\n'
                  '      - "v*" # e.g., v1.0, v1.2.3, etc.\n  workflow_dispatch:')
        data["historical_sources"] = {sha: source}
        self.assertIn(1, [a["id"] for a in policy.plan(**data)["delete"]])
        data["historical_sources"][sha] = source.replace('tags:', 'branches:')
        with self.assertRaises(RuntimeError):
            policy.plan(**data)

    def test_fewer_than_five_fails_closed(self):
        with self.assertRaises(RuntimeError):
            policy.plan(**fixture(4))

    def test_all_active_states_block_and_only_own_trusted_schedule_exempt(self):
        for status in ("queued", "in_progress", "waiting", "requested", "pending"):
            run = fixture()["runs"][0]
            run["status"] = status
            with self.assertRaises(RuntimeError):
                policy.assert_idle([run], "")
            run.update(path=policy.CLEANUP_PATH, event="schedule", head_branch="main")
            policy.assert_idle([run], "1")
            with self.assertRaises(RuntimeError):
                policy.assert_idle([run], "2")


class PaginationTests(unittest.TestCase):
    def test_paginates_all_pages_including_exact_hundred_boundary(self):
        calls = []
        def fetch(path):
            calls.append(path)
            page = int(path.split("page=")[-1])
            return {"total_count": 200, "artifacts": [{"id": n} for n in
                    range((page - 1) * 100, min(page * 100, 200))]}
        self.assertEqual(len(policy.pages("example", "artifacts", fetch)), 200)
        self.assertEqual(len(calls), 3)

    def test_list_pagination(self):
        self.assertEqual(policy.pages("example", fetch=lambda _: [{"name": "tag"}]),
                         [{"name": "tag"}])

    def test_malformed_incomplete_duplicate_and_transient_fail_closed(self):
        for response in ({}, {"total_count": 2, "artifacts": [{"id": 1}]},
                         {"total_count": 0, "artifacts": None},
                         {"total_count": 2, "artifacts": [{"id": 1}, {"id": 1}]}):
            with self.subTest(response=response), self.assertRaises(RuntimeError):
                policy.pages("example", "artifacts", lambda _: response)
        with self.assertRaises(OSError):
            policy.pages("example", fetch=lambda _: (_ for _ in ()).throw(OSError("network")))

    def test_changing_total_fails_closed(self):
        responses = iter([{"total_count": 101, "artifacts": [{"id": n} for n in range(100)]},
                          {"total_count": 102, "artifacts": [{"id": 100}]}])
        with self.assertRaises(RuntimeError):
            policy.pages("example", "artifacts", lambda _: next(responses))


class ApplyTests(unittest.TestCase):
    def test_concurrent_upload_or_active_run_snapshot_aborts_before_delete(self):
        before = fixture()
        manifest = policy.plan(**before)
        changed = copy.deepcopy(before)
        changed["artifacts"][0]["size_in_bytes"] += 1
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(policy, "snapshot", return_value=changed), \
                patch.object(policy, "api") as api:
            with self.assertRaises(RuntimeError):
                policy.apply(manifest, before, Path(directory))
            api.assert_not_called()

    def test_fresh_identity_delete_204_and_absence_receipts(self):
        before = fixture(6)
        manifest = policy.plan(**before)
        after = copy.deepcopy(before)
        after["artifacts"] = after["artifacts"][1:]
        responses = [before["artifacts"][0], before["runs"][0], {"status": 204}, None]
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(policy, "snapshot", side_effect=[before, before, after]), \
                patch.object(policy, "api", side_effect=responses) as api:
            receipts = policy.apply(manifest, before, Path(directory))
            self.assertEqual(receipts, [{"id": 1, "status": 204, "verified_absent": True}])
            self.assertEqual(api.call_args_list[2].args,
                             (f"repos/{policy.REPO}/actions/artifacts/1", "DELETE"))
            self.assertEqual(json.loads((Path(directory) / "receipts.json").read_text()), receipts)

    def test_historical_source_disappears_after_its_last_artifact_deleted(self):
        before = fixture()
        sha = before["artifacts"][0]["workflow_run"]["head_sha"]
        before["historical_sources"] = {sha: "immutable workflow"}
        manifest = policy.plan(**before)
        middle = copy.deepcopy(before)
        middle["artifacts"].pop(0)
        middle["historical_sources"] = {}
        after = copy.deepcopy(middle)
        after["artifacts"].pop(0)
        responses = []
        for n in (0, 1):
            responses.extend([before["artifacts"][n], before["runs"][n], {"status": 204}, None])
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(policy, "snapshot", side_effect=[before, before, middle, after]), \
                patch.object(policy, "api", side_effect=responses):
            self.assertEqual(len(policy.apply(manifest, before, Path(directory))), 2)

    def test_api_scope_and_http_errors(self):
        with self.assertRaises(RuntimeError):
            policy.api("repos/another/repo/actions/artifacts/1", "DELETE")
        for status, code in ((500, 1), (403, 1), (200, 0)):
            result = type("Result", (), {"stdout": f"HTTP/2.0 {status} STATUS\n\n{{}}",
                                         "returncode": code})()
            with patch.object(policy.subprocess, "run", return_value=result), \
                    self.assertRaises(RuntimeError):
                policy.api(f"repos/{policy.REPO}/actions/artifacts/1", "DELETE")


if __name__ == "__main__":
    unittest.main()
