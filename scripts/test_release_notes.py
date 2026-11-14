"""Verify reviewed release notes win over obsolete intermediate commit subjects."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'release-notes-for-workflow.sh'


class ReleaseNotesTests(unittest.TestCase):
    def test_reviewed_version_notes_are_published_with_matching_compare_link(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / 'docs/releases/2.63.3.md'
            notes.parent.mkdir(parents=True)
            notes.write_text('## Fixed three-column hierarchy\nReviewed safety details.\n')
            result = subprocess.run(['bash', str(SCRIPT), 'v2.63.3', 'v2.63.2'],
                                    cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = (root / 'release_notes.md').read_text()
            self.assertIn(notes.read_text(), output)
            self.assertIn('compare/v2.63.2...v2.63.3', output)
            self.assertNotIn('independent pane stacks', output)

    def test_versions_without_reviewed_notes_keep_categorized_commit_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def git(*args):
                subprocess.run(['git', *args], cwd=root, check=True,
                               capture_output=True, text=True, timeout=10)
            git('init')
            git('config', 'user.email', 'release-test@example.invalid')
            git('config', 'user.name', 'Release test')
            git('commit', '--allow-empty', '-m', 'initial')
            git('tag', 'v1.0.0')
            git('commit', '--allow-empty', '-m', 'fix: preserve fallback behavior')
            git('tag', 'v1.0.1')
            result = subprocess.run(['bash', str(SCRIPT), 'v1.0.1', 'v1.0.0'],
                                    cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = (root / 'release_notes.md').read_text()
            self.assertIn('fix: preserve fallback behavior', output)
            self.assertIn('compare/v1.0.0...v1.0.1', output)


if __name__ == '__main__':
    unittest.main()
