"""Exercise the actual promotion shell steps without making store requests."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class StorePromotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ruby is already required by Fastlane; use its YAML parser, not a new dependency.
        cls.workflow = json.loads(subprocess.check_output([
            "ruby", "-ryaml", "-rjson", "-e",
            "puts JSON.generate(YAML.load_file(ARGV[0]))",
            str(ROOT / ".github/workflows/production-release.yml"),
        ], text=True))
        cls.key = subprocess.check_output([
            "ruby", "-ropenssl", "-e",
            "print OpenSSL::PKey::EC.generate('prime256v1').private_to_pem",
        ], text=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        # Fastlane and gem are stubs; the workflow's metadata/key preparation is real.
        for name, content in {
            "gem": "#!/bin/sh\nexit 0\n",
            "fastlane": '#!/bin/sh\nprintf "%s\\n" "$@" > "$RUNNER_TEMP/arguments"\n',
        }.items():
            path = bin_dir / name
            path.write_text(content)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        RUNNER_TEMP=str(self.root), ANDROID_PACKAGE="dev.nosuch.nt_helper",
                        VERSION_CODE="348", GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="{}",
                        GOOGLE_PLAY_NOTES="Improved preset editing.", APP_STORE_NOTES="iPad improvements.",
                        APP_VERSION="2.60.4", BUILD_NUMBER="348", APP_PLATFORM="ios", APP_LOCALE="en-CA",
                        BUNDLE_ID="dev.nosuch.ntHelper", AUTOMATIC_RELEASE="true")

    def run_step(self, job, name):
        steps = self.workflow["jobs"][job]["steps"]
        script = next(step["run"] for step in steps if step.get("name") == name)
        return subprocess.run(["bash", "-c", script], cwd=self.root, env=self.env,
                              capture_output=True, text=True, timeout=30)

    def test_android_uses_locale_root_and_only_requested_version(self):
        result = self.run_step("android-production", "Promote internal release")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "arguments").read_text().splitlines()
        self.assertEqual(args[args.index("--version_code") + 1], "348")
        metadata = self.root / args[args.index("--metadata_path") + 1]
        self.assertEqual([p.name for p in metadata.iterdir()], ["en-US"])
        self.assertEqual((metadata / "en-US/changelogs/348.txt").read_text(),
                         self.env["GOOGLE_PLAY_NOTES"])
        self.assertEqual(args[args.index("--skip_upload_metadata") + 1], "true")

    def test_apple_normalizes_indented_or_escaped_pem_before_selecting_exact_build(self):
        for key in (self.key, "\n".join("  " + s for s in self.key.splitlines()),
                    self.key.replace("\n", "\\n")):
            with self.subTest(indented=key.startswith(" "), escaped="\\n" in key):
                self.env["APP_STORE_CONNECT_API_KEY_JSON"] = json.dumps(
                    dict(key_id="TEST", issuer_id="TEST", key=key))
                result = self.run_step("apple-production", "Submit existing build for review")
                self.assertEqual(result.returncode, 0, result.stderr)
                saved = self.root / "app-store-connect-api-key.json"
                check = subprocess.run([
                    "ruby", "-rjson", "-ropenssl", "-e",
                    "k=OpenSSL::PKey::EC.new(JSON.parse(File.read(ARGV[0]))['key']); "
                    "abort unless k.private? && k.group.curve_name == 'prime256v1'", str(saved),
                ], capture_output=True, text=True, timeout=30)
                self.assertEqual(check.returncode, 0, check.stderr)
                self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
                args = (self.root / "arguments").read_text().splitlines()
                self.assertEqual(args[args.index("--build_number") + 1], "348")
                self.assertEqual(args[args.index("--platform") + 1], "ios")
                self.assertEqual((self.root / "fastlane/metadata/en-CA/release_notes.txt").read_text(),
                                 self.env["APP_STORE_NOTES"])
                self.assertFalse((self.root / "fastlane/metadata/en-US").exists())
                self.assertEqual(args[args.index("--precheck_include_in_app_purchases") + 1], "false")

    def test_ios_releases_after_approval_while_macos_remains_manual(self):
        # Credential tests exercise iOS only and do not protect platform release policy.
        self.env["APP_STORE_CONNECT_API_KEY_JSON"] = json.dumps(
            dict(key_id="TEST", issuer_id="TEST", key=self.key))
        job = self.workflow["jobs"]["apple-production"]
        submission = next(step for step in job["steps"]
                          if step.get("name") == "Submit existing build for review")
        self.assertEqual(submission["env"]["AUTOMATIC_RELEASE"], "${{ matrix.automatic_release }}")
        for platform in job["strategy"]["matrix"]["include"]:
            with self.subTest(platform=platform["platform"]):
                self.env.update(APP_PLATFORM=platform["platform"], APP_LOCALE=platform["locale"],
                                BUNDLE_ID=platform["bundle_id"],
                                AUTOMATIC_RELEASE=str(platform["automatic_release"]).lower())
                result = self.run_step("apple-production", "Submit existing build for review")
                self.assertEqual(result.returncode, 0, result.stderr)
                args = (self.root / "arguments").read_text().splitlines()
                self.assertEqual(args[args.index("--automatic_release") + 1],
                                 "true" if platform["platform"] == "ios" else "false")
                self.assertEqual(args[args.index("--submit_for_review") + 1], "true")

    def test_invalid_apple_key_fails_before_fastlane_without_disclosing_secret(self):
        for secret in ("secret-invalid-json", json.dumps(dict(
                key_id="TEST", issuer_id="TEST", key="secret-invalid-pem"))):
            with self.subTest():
                self.env["APP_STORE_CONNECT_API_KEY_JSON"] = secret
                result = self.run_step("apple-production", "Submit existing build for review")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("secret-invalid", result.stdout + result.stderr)
                self.assertFalse((self.root / "arguments").exists())


if __name__ == "__main__":
    unittest.main()
