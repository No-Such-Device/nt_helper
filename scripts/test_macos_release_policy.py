"""Protect existing-review release policy changes from submission side effects."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tool"))
from macos_release_policy import AppleAPI, release_policy
from resolve_store_baselines import apple_token


class MacOSReleasePolicyTests(unittest.TestCase):
    def setUp(self):
        self.release_type = "MANUAL"
        self.state = "WAITING_FOR_REVIEW"
        self.build = "354"
        self.writes = []
        self.api = Mock(request=self.request)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def request(self, path, payload=None):
        if payload is not None:
            self.writes.append((path, payload))
            self.release_type = payload["data"]["attributes"]["releaseType"]
        if path.startswith("/apps?"):
            self.assertIn("dev.nosuch.macos.ntHelper", path)
            return {"data": [{"id": "mac-app"}]}
        data = {"id": "pending", "attributes": {
            "versionString": "2.63.3", "platform": "MAC_OS",
            "releaseType": self.release_type, "appStoreState": self.state,
        }}
        if path.startswith("/apps/mac-app/appStoreVersions?"):
            self.assertIn("MAC_OS", path)
            return {"data": [data]}
        if path == "/appStoreVersions/pending/build":
            return {"data": {"attributes": {"version": self.build}}}
        self.assertEqual(path, "/appStoreVersions/pending")
        return {"data": data}

    def test_inspection_never_changes_existing_review(self):
        result = release_policy(self.api, "2.63.3", "354")
        self.assertEqual(result["after"]["releaseType"], "MANUAL")
        self.assertFalse(result["changed"])
        self.assertEqual(self.writes, [])

    def test_pending_review_patch_only_changes_release_type_and_verifies_readback(self):
        result = release_policy(self.api, "2.63.3", "354", apply=True)
        self.assertEqual(self.writes, [("/appStoreVersions/pending", {"data": {
            "type": "appStoreVersions", "id": "pending",
            "attributes": {"releaseType": "AFTER_APPROVAL"},
        }})])
        self.assertTrue(result["changed"])
        self.assertEqual(result["after"]["releaseType"], "AFTER_APPROVAL")
        self.assertEqual(result["after"]["state"], "WAITING_FOR_REVIEW")

    def test_already_automatic_version_is_left_unchanged(self):
        self.release_type = "AFTER_APPROVAL"
        result = release_policy(self.api, "2.63.3", "354", apply=True)
        self.assertFalse(result["changed"])
        self.assertEqual(self.writes, [])

    def test_wrong_candidate_build_or_nonpending_version_fails_without_patch(self):
        for attribute, value in (("build", "353"), ("state", "READY_FOR_SALE")):
            with self.subTest(attribute=attribute):
                previous = getattr(self, attribute)
                setattr(self, attribute, value)
                with self.assertRaises(RuntimeError):
                    release_policy(self.api, "2.63.3", "354", apply=True)
                self.assertEqual(self.writes, [])
                setattr(self, attribute, previous)

    def test_apple_policy_lock_is_reported_without_withdrawing_review(self):
        from urllib.error import HTTPError
        error = HTTPError("https://api.appstoreconnect.apple.com/v1/appStoreVersions/pending",
                          409, "Conflict", {}, io.BytesIO(json.dumps({"errors": [{
                              "code": "STATE_ERROR", "detail": "Version is not editable"}]}).encode()))
        self.addCleanup(error.close)
        with patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, "409.*STATE_ERROR.*Version is not editable"):
                AppleAPI("secret-token").request("/appStoreVersions/pending", {"data": {}})

    def test_api_token_accepts_same_indented_escaped_pem_as_submission_flow(self):
        fake_jwt = Mock()
        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory) / "key.json"
            key_path.write_text(json.dumps({"key_id": "TEST", "issuer_id": "TEST",
                                            "key": "  BEGIN\\n  BODY\\n  END"}))
            with patch.dict(sys.modules, jwt=fake_jwt):
                apple_token(key_path)
            self.assertEqual(fake_jwt.encode.call_args.args[1], "BEGIN\nBODY\nEND\n")


if __name__ == "__main__":
    unittest.main()
