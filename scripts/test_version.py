"""Exercise release preparation in a temporary repository, without Dart or GitHub."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleasePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ)
        self.env.update(GIT_AUTHOR_NAME="Test", GIT_COMMITTER_NAME="Test",
                        GIT_AUTHOR_EMAIL="test@example.com", GIT_COMMITTER_EMAIL="test@example.com")
        self.git("init", "-b", "main")
        shutil.copy(ROOT / "version", self.root / "version")
        (self.root / "pubspec.yaml").write_text("version: 2.63.0+351\n")
        generated = self.root / "lib/chat/services/codex_client_version.g.dart"
        generated.parent.mkdir(parents=True)
        generated.write_text("// fixture\n")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        dart = bin_dir / "dart"
        dart.write_text("#!/bin/sh\nexit 0\n")
        dart.chmod(0o755)
        self.env["PATH"] = f"{bin_dir}:{self.env['PATH']}"
        # Keep the stub out of the worktree status the real script checks.
        (self.root / ".git/info/exclude").write_text("/bin/\n")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root,
                                       env=self.env, text=True, stderr=subprocess.STDOUT).strip()

    def prepare(self):
        return subprocess.run(["bash", "version", "patch"], cwd=self.root,
                              env=self.env, capture_output=True, text=True, timeout=30)

    def test_version_preparation_commits_on_release_branch_without_tagging(self):
        self.git("switch", "-c", "chore/release")
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "pubspec.yaml").read_text(), "version: 2.63.1+352\n")
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        self.assertEqual(self.git("tag", "--list"), "")
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_version_preparation_refuses_main_before_modifying_files(self):
        before = self.git("rev-parse", "HEAD")
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("release branch", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), before)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_version_preparation_preserves_uncommitted_work(self):
        self.git("switch", "-c", "chore/release")
        pubspec = self.root / "pubspec.yaml"
        pubspec.write_text("version: 2.63.0+351\n# user edit\n")
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Commit or stash", result.stderr)
        self.assertEqual(pubspec.read_text(), "version: 2.63.0+351\n# user edit\n")
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "1")
        self.assertEqual(self.git("tag", "--list"), "")


if __name__ == "__main__":
    unittest.main()
