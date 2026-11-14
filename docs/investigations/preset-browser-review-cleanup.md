# Preset-browser review cleanup

## Review provenance

The complete final review outputs were retrieved read-only from the workspace's
durable conversation store: correctness job **#684**, conversation #685 / entry
#770; architecture job **#701**, conversation #702 / entry #765. The Substrate
gateway was unavailable (expired MCP session). No review findings were inferred
from the truncated coordinator summaries, and no private transcript/auth content
is reproduced here.

Both reviews cover `7fb5f7f6..53e115ad` (including `aa52cb1e`). All eleven listed
findings are addressed below; the rename coordination findings overlap.

| Finding | Change and regression evidence |
| --- | --- |
| #684 P1: late `/A` listing attributed to `/B` | Real manager SD requests use shared strict response debt and fail **before sending** another ambiguous SD command. Since error replies omit even the operation, unresolved SD debt blocks every SD operation, including delete. A fake-MIDI/real-manager test times out `/A`, rejects `/B` and delete, replaces the manager, advances virtual time two minutes, drains `/A`'s late frame, and then verifies `/B`'s actual reply. |
| #684 P1: Load/export during overwrite | A connection-scoped `SdCardFileActivity` lease starts before writes, survives browser closure, and is shared by replacement managers on the same MIDI endpoint. UI targets and export stay disabled; manager load/download preflights prevent queued reads from bypassing a later-acquired lease. Reopened-browser, queued-load, export and held-chunk regressions cover this. |
| #684 P2: receive-error replay of rename/delete | Explicit `RequestReplayPolicy.never` for manager SD requests also disables split-frame recovery replay. Partial reply + receive error tests assert one rename/delete transmission. Eligible low-level read recovery remains tested separately. Send failures conservatively retain response debt because bytes may already have reached the device. |
| #684 P2: failed startup restore resets another pane | Restore/fallback explicitly targets the left pane, without activating it, and is guarded by its navigation version. Tests intervene with newer navigation in the left and right panes. |
| #684 P2: deleted historical frame discards surviving current path | Remove invalid frames rather than truncating all successors. Test `[/, /A/child, /A]` retains `/A` after deleting `/A/child`. |
| #684 P2: preferences precede rename publication | Verified listing, path rebasing and selection reconciliation publish atomically before ancillary preference writes. Preference rejection/exception becomes a separate warning, not a failed device rename. A delayed rejected preference write plus newer refresh cannot roll back current data. |
| #701 P2: rename bypasses freshness/pending UI | Verification uses the normal coalesced, generation-checked read/publish path. Disabled stale content stays visible while verification is pending; the reserved status slot shows progress, not a false Empty view. Held-verification tests check geometry, selection and disabled Load/export. |
| #701 P2: pane headers outside focus scope | Whole-pane focus includes Back/Refresh controls; keyboard header focus updates the active pane and Alt-Left uses that stack. Keyboard-only header traversal preserves neighboring selection. |
| #701 P2: scrolling/cursor disagree with location | A location-keyed scrollable resets new-directory scroll activity and restores per-location offset on Back. Same-path updates preserve the arrow cursor by filename, independently of committed selection. Long-directory descent/back and delayed-refresh cursor tests cover both. |
| #701 P2: mobile refresh includes hidden panes | Layout supplies the visible scope. Narrow resume refreshes only the active pane; desktop refresh prioritizes the active pane and deduplicates paths. Hidden timed-out paths cannot precede the mobile read. |
| #701 P3: startup focus erases saved location | Capture the saved location before exposing interactive root state. A held root listing plus intervening center-pane focus still restores the original saved left location. |

## Protocol boundary: fail closed, not a timing workaround

Successful `7A` replies identify only the operation, not the path or transaction;
errors omit the operation. A host cannot distinguish an arbitrarily late reply
from the next same-operation reply. Cubit path generations cannot repair a
misattributed transport future.

The strict tracker retains unanswered request debt across scheduler/manager
replacement on the same MIDI connection/endpoint. No delay expires this debt.
Until attributable outstanding replies drain, new SD operations fail closed.
An interrupted split response may never finish, so recovery may require an
actual verified device reset followed by a fresh app MIDI session. The tracker
does not infer a reset from unplugging or reconnecting; closing a dialog,
recreating a manager, waiting longer, or restarting the app alone is **not**
claimed to establish a safe device boundary. There is no
automatic remount/reboot or unsafe reset-debt button.

This relies on the documented sequential one-response-per-command protocol and
exclusive ownership of the endpoint. It cannot authenticate unsolicited replies
from another controller or infer file identity across arbitrary external edits.
Rescan now awaits its documented acknowledgement rather than discarding a reply
that could contaminate later SD traffic. Actual firmware acknowledgement behavior
and recovery after disconnect remain hardware acceptance work.

## Ownership and visibility limits

The file lease is held by the operation/connection, not by the browser route.
Closing the browser does not free an in-flight upload or expose partial bytes.
Another browser sharing that connection receives busy state and refreshes its
visible affected directory after release. Native focus events and real USB
throughput still require platform/device testing.

The browser remains event-driven: no full-card scan, freshness polling timer,
or hidden-pane resume requests were added. A mutation's parent may still need
one explicit read-back even if it is not the active pane.

## Verification commands

Use the repository-pinned Flutter 3.44.9 toolchain. New regressions are in:

- `test/domain/sd_card_transport_safety_test.dart` (real scheduler/manager with
  controlled MIDI packets and virtual timeout/recovery time).
- `test/cubit/preset_browser_review_regression_test.dart` (controlled I/O and
  preference completion, restoration races, pruning, operation lease lifetime).
- `test/ui/widgets/preset_browser_panes_test.dart` (headers, scrolling/cursors,
  mobile visibility, pending rename and held overwrite chunk).

The broader selected run is:

```sh
flutter test --no-pub test/domain/ \
  test/cubit/preset_browser_cubit_test.dart \
  test/cubit/preset_browser_rename_test.dart \
  test/cubit/preset_browser_review_regression_test.dart \
  test/ui/widgets/preset_browser_dialog_test.dart \
  test/ui/widgets/preset_browser_panes_test.dart \
  test/ui/synchronized_screen_shortcut_guard_test.dart \
  test/services/preset_file_system_impl_test.dart \
  test/services/preset_export_integration_test.dart \
  test/services/gallery_service_cleanup_outcome_test.dart \
  test/poly_multisample/poly_sample_upload_service_test.dart
flutter analyze --no-pub
```

No physical device, firmware `#n` Program Change selection, app restart or release
was used for these checks. The original report's hardware symptom remains
unverified; see the [connected-device checklist](preset-browser-rename-consistency.md).

## Cleanup verification results

- Focused browser/transport/protocol selection: **153 passed** (the existing
  136-test selection plus the new review unit/wire files and widget regressions).
- Broader command above: **433 passed**, including the entire `test/domain/`
  tree and related export/filesystem/gallery/sample-upload consumers.
- `flutter analyze --no-pub`: **No issues found**.
- Source formatting, relative Markdown links and `git diff --check` passed.
  The scheduler's pre-existing mixed line endings were preserved to avoid
  unrelated churn; its LF-normalized source was checked through `dart format
  --stdin-name lib/domain/disting_message_scheduler.dart --output=none
  --set-exit-if-changed`. Generated model output was regenerated and whitespace
  normalized. No full application suite or native build was claimed.
