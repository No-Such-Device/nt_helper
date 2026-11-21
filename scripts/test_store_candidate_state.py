"""Deterministic store inspection/readback tests; no credentials or store calls."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
import store_candidate_state as store
import resolve_store_baselines as baselines


class FakeApple:
    def pages(self, path):
        if path.startswith("/apps?"):
            return [{"id": "app"}]
        if "/appStoreVersions?" in path:
            return [{"id": "live", "attributes": {"versionString": "2.63.3", "platform": "IOS",
                                                   "appStoreState": "READY_FOR_SALE"}},
                    {"id": "candidate-version", "attributes": {"versionString": "2.64.1", "platform": "IOS",
                        "appStoreState": "WAITING_FOR_REVIEW", "releaseType": "AFTER_APPROVAL"}}]
        if path.startswith("/builds?"):
            return [{"id": "candidate-build", "attributes": {"version": "356", "processingState": "VALID", "expired": False}}]
        if path.endswith("/appStoreVersionLocalizations"):
            return [{"attributes": {"locale": "en-CA", "whatsNew": "Reviewed Apple notes."}}]
        raise AssertionError(path)

    def get(self, path):
        if path.startswith("/apps/app/appStoreVersions?"):
            return {"data": [self.pages(path)[0]], "links": {"next": "older-history"}}
        if path.endswith("/preReleaseVersion"):
            return {"data": {"attributes": {"version": "2.64.1", "platform": "IOS"}}}
        if path.endswith("/build"):
            return {"data": {"id": "candidate-build"}}
        raise AssertionError(path)


class StoreCandidateTests(unittest.TestCase):
    def setUp(self):
        apple = store.apple_state(FakeApple(), "bundle", "IOS", "2.64.1", "356")
        macos = copy.deepcopy(apple)
        macos["platform"] = "MAC_OS"
        macos["store_version"]["notes"] = {"en-US": "Reviewed Apple notes."}
        release = {"status": "completed", "versionCodes": ["356"],
                   "releaseNotes": [{"language": "en-US", "text": "Reviewed Google notes."}]}
        self.state = {"ios": apple, "macos": macos,
                      "google_play": {"internal": {"releases": [release]},
                                      "production": {"releases": [copy.deepcopy(release)]}}}

    def test_exact_accepted_build_policy_and_notes_readback(self):
        store.validate(self.state, "356", True, "Reviewed Google notes.", "Reviewed Apple notes.")
        self.assertEqual(self.state["ios"]["live_version"], "2.63.3")
        self.assertEqual(self.state["ios"]["build_id"], "candidate-build")

    def test_readback_rejects_wrong_build_policy_state_and_notes(self):
        for key, value in (("build_id", "wrong"), ("releaseType", "MANUAL"),
                           ("state", "PREPARE_FOR_SUBMISSION"), ("notes", {"en-US": "Wrong locale"})):
            with self.subTest(key=key):
                state = copy.deepcopy(self.state)
                state["ios"]["store_version"][key] = value
                with self.assertRaises(RuntimeError):
                    store.validate(state, "356", True, "Reviewed Google notes.", "Reviewed Apple notes.")
        with self.assertRaisesRegex(RuntimeError, "en-US notes"):
            store.validate(self.state, "356", True, "Unapproved notes")

    def test_readback_rejects_uncommitted_or_wrong_android_release(self):
        for release in ({"status": "draft", "versionCodes": ["356"]},
                        {"status": "completed", "versionCodes": ["355"]},
                        {"status": "inProgress", "versionCodes": ["356"]}):
            with self.subTest(release=release):
                self.state["google_play"]["production"]["releases"] = [release]
                with self.assertRaisesRegex(RuntimeError, "production lacks completed"):
                    store.validate(self.state, "356", True)

    def test_prepare_refuses_duplicate_submission_and_old_pending_review(self):
        self.state["google_play"]["production"]["releases"] = []
        with self.assertRaisesRegex(RuntimeError, "already submitted"):
            store.validate(self.state, "356", False)
        for platform in ("ios", "macos"):
            self.state[platform]["store_version"] = None
        store.validate(self.state, "356", False)
        self.state["macos"]["other_pending_versions"] = [{"version": "2.63.3", "state": "IN_REVIEW"}]
        with self.assertRaisesRegex(RuntimeError, "older pending submission"):
            store.validate(self.state, "356", False)

    def test_prepare_refuses_duplicate_android_and_unprocessed_apple(self):
        for platform in ("ios", "macos"):
            self.state[platform]["store_version"] = None
        with self.assertRaisesRegex(RuntimeError, "already in production"):
            store.validate(self.state, "356", False)
        self.state["google_play"]["production"]["releases"] = []
        self.state["ios"]["processingState"] = "PROCESSING"
        with self.assertRaisesRegex(RuntimeError, "not a valid"):
            store.validate(self.state, "356", False)
        self.state["ios"]["processingState"] = "VALID"
        self.state["ios"]["expired"] = True
        with self.assertRaisesRegex(RuntimeError, "not a valid"):
            store.validate(self.state, "356", False)

    def test_deselected_platforms_are_not_required(self):
        store.validate({"ios": self.state["ios"]}, "356", True)
        store.validate({"google_play": self.state["google_play"]}, "356", True)

    def test_candidate_must_be_unique_for_exact_marketing_version(self):
        api = FakeApple()
        with patch.object(api, "get", return_value={"data": {"attributes": {"version": "2.64.0", "platform": "IOS"}}}):
            with self.assertRaisesRegex(RuntimeError, "exactly one IOS candidate"):
                store.apple_state(api, "bundle", "IOS", "2.64.1", "356")

    def test_google_inspection_deletes_temporary_edit_even_on_failure(self):
        api = MagicMock()
        edits = api.edits.return_value
        edits.insert.return_value.execute.return_value = {"id": "temporary-edit"}
        modules = {name: MagicMock() for name in ("google", "google.oauth2", "googleapiclient", "googleapiclient.discovery")}
        modules["googleapiclient.discovery"].build.return_value = api
        with patch.dict(sys.modules, modules):
            result = store.google_state(Path("unused.json"), "package")
            self.assertEqual(set(result), {"internal", "production"})
            edits.delete.assert_called_with(packageName="package", editId="temporary-edit")
            edits.commit.assert_not_called()
            edits.tracks.return_value.get.return_value.execute.side_effect = RuntimeError("Read failed")
            with self.assertRaisesRegex(RuntimeError, "Read failed"):
                store.google_state(Path("unused.json"), "package")
            self.assertEqual(edits.delete.call_count, 2)
            edits.commit.assert_not_called()

    def test_live_baseline_uses_store_current_query_not_historical_ready_states(self):
        api = FakeApple()
        pages = api.pages
        def historical(path):
            result = pages(path)
            if "/appStoreVersions?" in path:
                result.append({"id": "old", "attributes": {"versionString": "2.60.0",
                    "platform": "IOS", "appStoreState": "READY_FOR_SALE"}})
            return result
        with patch.object(api, "pages", side_effect=historical):
            state = store.apple_state(api, "bundle", "IOS", "2.64.1", "356")
        self.assertEqual(state["live_version"], "2.63.3")

    def test_ambiguous_baseline_never_guessed(self):
        with self.assertRaisesRegex(RuntimeError, "exactly one git tag"):
            baselines.find_tag({"v1": ("2.63.3", "354"), "v2": ("2.63.3", "355")}, "2.63.3", None)


if __name__ == "__main__":
    unittest.main()
