# PR #184 test timing report

## Verified improvements

- Popup wire suite: about **33 seconds → 7 seconds** of Flutter-reported test
  time; all 20 regression cases retained. Thirty 1 ms repaints per gesture
  became three 10 ms repaints, preserving simulated time.
- Applied the same repaint reduction to overlay wire tests, queued memory
  consumers, screenshot fallback, and bootloader handoff. The four affected
  files passed together: **23 tests**, about 7 seconds of reported test time
  (14 seconds including startup/compilation).
- Replaced wall-clock sleeps in chat, debounce, DB timestamp, routing,
  loading-dialog, offline-metadata, preview, and protocol tests with completion
  signals or virtual time. Retained geometry, semantics, and error assertions.
- Added disconnect/dispose regressions for delayed video stall cleanup. Both
  failed before the lifecycle fix; video manager and popup suites passed
  together afterward: 30 tests. The full popup assertions also remain green
  after reducing repaints.

## Partial five-second file audit

Stopped the serial audit at the user's request for a faster turnaround.
**163 of 391 files** were measured: **156 passed, 6 timed out, 1 failed**.
The failed file was `test/domain/video/usb_video_manager_test.dart` while its
new teardown regressions were deliberately red; those regressions are now fixed
and separately verified. This is **not** an exhaustive green-suite report.

The six files exceeding the per-file limit were:

- `test/chat/ui/additional_provider_settings_test.dart`
- `test/cubit/disting_cubit_install_plugin_rescan_test.dart`
- `test/cubit/disting_cubit_install_plugin_root_cleanup_test.dart`
- `test/cubit/disting_cubit_plugin_loading_test.dart`
- `test/cubit/firmware_update_cubit_test.dart`
- `test/cubit/preset_dirty_indicator_test.dart`

The five-second limit includes Flutter startup, compilation, setup, and
teardown. A file timeout does not imply that one test takes five seconds or
that its regressions can safely be deleted. Repeated Flutter startup dominated
the audit cost, so an exhaustive serial rerun was not used as a merge gate.

## Reusable tooling and categories

`python3 scripts/audit_test_timing.py --timeout 5 [exact test paths...]`
records JSON events, logs, and a report under `.dart_tool/test-timing/`.
Use `--run fast` for the local fast category and `--run slow` to explicitly
run timeout-listed files. Failures are not hidden as slow, and new unaudited
files remain in the fast selection. `--run all` includes every current test
file. CI and releases continue to run the complete default suite.

The auditor's process-group timeout and classification/report behavior have
Python regression tests. See `AGENTS.md` for best practices and counterexamples.
