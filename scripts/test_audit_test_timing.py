import json
from pathlib import Path
import tempfile
import unittest

from audit_test_timing import categories, markdown, run_file, test_timings


class TestTimingAudit(unittest.TestCase):
    def test_reads_completed_test_timings_and_ignores_non_events(self):
        events = [
            {"type": "testStart", "time": 120, "test": {"id": 1, "name": "regression"}},
            {"type": "testDone", "time": 175, "testID": 1, "result": "success", "skipped": False},
        ]
        result = test_timings("compiler output\n[]\n" + "\n".join(map(json.dumps, events)))
        self.assertEqual(result, [{"name": "regression", "seconds": 0.055,
                                   "result": "success", "skipped": False}])

    def test_only_timeouts_enter_slow_category_failures_still_run_fast(self):
        self.assertEqual(categories([
            {"file": "a", "status": "passed"},
            {"file": "b", "status": "timeout"},
            {"file": "c", "status": "failed"},
        ]), {"fast": ["a", "c"], "slow": ["b"]})

    def run_fixture(self, source, timeout=5):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "flutter"
            executable.write_text("#!/usr/bin/env python3\n" + source)
            executable.chmod(0o755)
            result = run_file("test/example_test.dart", timeout,
                              Path(directory) / "logs", str(executable))
            self.assertTrue(Path(result["log"]).is_file())
            return result

    def test_exit_zero_is_pass_and_nonzero_is_failure(self):
        self.assertEqual(self.run_fixture("raise SystemExit(0)\n")["status"], "passed")
        result = self.run_fixture("print('failure evidence', flush=True)\nraise SystemExit(2)\n")
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["exit_code"], 2)

    def test_timeout_terminates_child_process_group_and_keeps_output(self):
        result = self.run_fixture(
            "import subprocess, sys\n"
            "print('before timeout', flush=True)\n"
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
            "child.wait()\n", timeout=0.2,
        )
        self.assertEqual(result["status"], "timeout")
        self.assertLess(result["seconds"], 2)
        self.assertNotEqual(result["exit_code"], 0)

    def test_report_explains_deadline_limits_and_preserves_failure_visibility(self):
        result = self.run_fixture("raise SystemExit(2)\n")
        report = markdown({"commit": "abc", "timeout_seconds": 5, "results": [result]})
        self.assertIn("failed: 1", report)
        self.assertIn("startup, compilation", report)
        self.assertIn("Failures (not hidden", report)
        self.assertIn("CI still runs every regression", report)


if __name__ == "__main__":
    unittest.main()
