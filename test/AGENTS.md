# Test feedback loop

After dependency or worktree setup, generate ignored mocks before running tests:
`dart run build_runner build --delete-conflicting-outputs`.

Select tests by changed behavior (inspect imports and callers as well as names):

```bash
# One service / regression
flutter test --no-pub test/services/startup_controller_test.dart
# One failing example; use its exact test description
flutter test --no-pub test/services/startup_controller_test.dart --plain-name 'description'
# Shared routing changes
flutter test --no-pub test/core/routing/
# Multiple affected files
flutter test --no-pub test/services/startup_controller_test.dart test/core/routing/device_io_profile_routing_test.dart
```

Start narrow, then expand to neighboring callers when interfaces or shared
fixtures change. Keep new regressions, assertions, and asynchronous geometry /
semantics checks. Fix flaky behavior rather than deleting tests or adding skips.
Hardware/live-service tests retain their existing explicit opt-ins; ordinary CI
runs the complete default suite without file, name, or tag exclusions.

## Timing audit and local categories

Run `python3 scripts/audit_test_timing.py --timeout 5` to audit each file in
isolation. Results, raw Flutter JSON logs, and the slow-file fix queue go to
`.dart_tool/test-timing/`. The deadline includes startup and compilation; a
file timeout alone does not identify a slow individual test or justify deletion.
Use `--resume` only on the same commit/deadline, or pass exact test paths for a
focused audit. Run saved local categories with `--run fast`, `--run slow`, or
`--run all`; new unaudited files remain in the fast selection. Slow files run
only when explicitly selected by this local runner. Required CI/release commands
still run the full suite. Delete a slow non-regression test only after confirming
it adds no distinct behavior coverage; preserve and repair bug regressions.

Record the actual selection and result in the PR; a focused pass is not evidence
that the full suite passed. CI owns the full suite for ordinary changes.
