# Preset browser: one hierarchy, three fixed columns

This is the corrected user-approved model. The independent-browser interpretation
introduced in `53e115ad` was rejected during manual testing and is superseded;
transport, rename and upload safety hardening from `66e3f88d` remains in place.

## Canonical state and exact navigation semantics

`lib/cubit/preset_browser_state.dart` stores a single `BrowserSnapshot.stack` of
`BrowserFrame(path, selectedName)` from `/` to the deepest browsed directory.
It is a hierarchy, **not three histories or a chronological visit list**.
`activeDepth` is keyboard/action focus only, not a separate navigation root.
Listings, refreshing/errors and connection-owned busy-file paths are shared by
absolute path. `pendingPath` records an in-flight navigation intent while the
committed hierarchy remains visible; `renamedPaths` carries verified identity
rebases for UI cursors and location state. Mobile and desktop render this same
immutable snapshot.

Desktop always builds exactly three equally sized columns:

| Shared hierarchy | Visible column paths |
| --- | --- |
| `/` | `/`, empty placeholder, empty placeholder |
| `/ → /A` | `/`, `/A`, empty placeholder |
| `/ → /A → /A/child` | `/`, `/A`, `/A/child` |
| `/ → /A → /A/child → /A/child/deep` | `/A`, `/A/child`, `/A/child/deep` |
| One more level | `/A/child`, `/A/child/deep`, its selected child |

The viewport starts at `max(0, stack.length - 3)`. Earlier frames remain in the
canonical hierarchy even when offscreen. No fourth column is ever inserted.

- Selecting a folder in a column highlights it, discards all obsolete descendants
  after that column, and appends the child directory. Its listing fills the next
  column; at the right edge, the same three columns shift one level deeper.
  The wire read starts on the first click. Until the destination is ready the
  previous committed hierarchy remains correctly labelled, with unobtrusive
  progress in the reserved status slot. The new stack and populated listings
  publish coherently; rapid sibling clicks use the latest intent.
- Selecting a sibling replaces the old descendant branch. Selecting a file in
  an ancestor column also discards obsolete descendants; Load/Delete never target
  a hidden selection in the old branch.
- Shared **Back** removes one deepest directory frame, re-exposing its parent and
  retaining the parent's folder highlight. It does not reopen that folder. At
  root Back remains present but disabled.
- Breadcrumbs show the full deepest path, including offscreen ancestors. Choosing
  an ancestor truncates to it; Home truncates to `/`. Absolute/saved-path jumps
  reconstruct **every ancestor**, not just the clicked/remembered destination.
- Keyboard Enter opens the focused folder and moves focus to its child column
  (or stays in the right column after a shift). Alt-Left anywhere in the browser
  column uses the shared Back operation.
- Column focus does not alter the hierarchy or remembered deepest directory.
  Context menus and drops use explicit column paths. Empty placeholders have no
  path, no drop target, no context-menu directory and no network request.

Mobile shows the deepest frame with the same breadcrumbs/Back behavior. Resizing
between layouts does not copy navigation or maintain an independent drill-down
selection. `fileBrowserLastPath` remembers only the deepest directory. Recent
preset file history is a separate bounded preference; neither is a pane history.

## Layout continuity is an acceptance contract

Content may change; action-driven geometry may not. User-driven window resizing
and text-scale changes are separate responsive-layout inputs.

- The dialog's content bounds derive only from available window size. The toolbar,
  breadcrumb region, three column boundaries, status area, upload-progress strip
  and action row reserve space in every state. There is no column header row:
  path ancestry is already visible in the fixed breadcrumb bar.
- Back, folder creation, sort, Export and Load stay in place. Unavailable actions
  are disabled rather than inserted/removed. Placeholder columns keep their full
  geometry and stay blank without misleading paths or controls.
- Loading/error/empty states render inside the same column skeleton. Root errors
  use the reserved status/retry area, not a replacement page that removes columns.
  Refresh lives in each real column's background and item context menu (always
  targeting that column's directory), not in visible column/global icon buttons.
  Errors use reserved status text; refreshing is exposed to assistive technology.
- Refresh and mutation invalidation retain the previous listing at full opacity
  until verified content replaces it atomically. Unused/unconfirmed/confirmed
  empty columns stay blank, avoiding distracting empty-state flashes. Listing
  rows are not faded; Load/export and unsafe context actions are disabled while
  their directory or an ancestor is uncertain. Menu callbacks and delete/rename
  confirmations recheck availability before dispatch. Upload progress uses its
  always-reserved strip. Mobile retains pull-to-refresh without a separate icon.
- Breadcrumbs occupy a fixed-height horizontal scrolling region even at root,
  including on mobile. Long path/filename text is clipped/ellipsized inside its
  allocated region instead of changing row heights.
- Keyboard outlines paint in the foreground without adding padding or altering
  row sizes, only after keyboard input. Mouse presses/hover hide them; restoring
  focus after a dialog does not invent keyboard modality. Selection remains a
  separate state. Row identities survive refresh reordering, so a focus refresh
  between pointer-down and pointer-up cannot retarget a single click. Per-location scroll offsets/cursor names are shared by
  the column renderer, so a location moving between columns retains its UI
  position; a new location starts at the top. Back restores the parent offset.

`test/ui/widgets/preset_browser_panes_test.dart` compares exact rectangles for
dialog, toolbar, breadcrumb/status areas, columns and action controls
across root → child → grandchild → deeper shifts, sibling/file selections,
Back/breadcrumbs, held root/refresh/rename/upload replies, empty/error/retry and
mobile transitions. It also tests row geometry during keyboard focus/refresh.
These protect the requested continuity, not incidental colors or typography.

## Freshness, reconciliation and safety

`PresetBrowserCubit` owns navigation/state and revalidation; widgets own layout,
focus and scroll only. The existing injected `IDistingMidiManager` remains the
wire/data boundary; no second data or navigation controller is introduced.

- Startup reads root once. Navigation/Back/breadcrumbs always revalidate the
  destination; absolute jumps hydrate previously unseen ancestors. Concurrent
  reads of a path coalesce, and generation checks reject superseded publications.
- Focus/resume revalidate stale **visible** paths, with a five-second injectable
  clock throttle, not polling. Desktop prioritizes the deepest path; mobile reads
  only the deepest displayed directory, never hidden columns/offscreen ancestors.
- Refresh reconciles selected entries by name. A vanished selected folder prunes
  its obsolete descendants; a vanished file clears selection. Delayed reads can
  update a cache but cannot restore a superseded branch/navigation snapshot.
- Verified rename atomically rebases the entire ancestry and selected entry with
  the parent read-back, before ancillary preference writes. Old/new subtree
  caches are invalidated; recent/saved paths are rewritten with path boundaries.
  Descendant snapshots are rebased as stale (not cleared) while their new paths
  revalidate. Cursor aliases retain renamed entry identity independently of
  selection. Preference failure reports a warning, not a failed device rename.
- Delete truncates an actually removed subtree to its nearest surviving ancestor;
  there are no unrelated historical frames to accidentally discard. Create,
  upload and deletion refresh affected visible listings without full-card scans.
- Serialized mutation workflows and connection-owned busy-file leases survive
  browser closure/reopening. UI Load/export, file reads and queued manager load/
  download preflights cannot consume a partially overwritten file. Upload chunks
  stay at most 512 file-data bytes with existing pacing.
- Real SD replies lack path/transaction IDs; errors omit even operation identity.
  Strict unresolved-response debt fails closed before another ambiguous SD
  command is sent and survives same-endpoint manager replacement. SD mutations
  are not replayed after interrupted responses. Debt has no arbitrary time expiry;
  verified device reset plus a fresh app MIDI session may be needed for recovery.

No automatic remount, reboot, directory polling or firmware Program Change index
is introduced. UI cache correctness does not prove actual firmware `#n` matching.
See [rename investigation](../investigations/preset-browser-rename-consistency.md)
and the [review cleanup](../investigations/preset-browser-review-cleanup.md) for
transport evidence and the connected-device acceptance checklist.

## Retrieval and refresh

- Models/projections: `lib/cubit/preset_browser_state.dart`; regenerate its
  Freezed output with build_runner after changes.
- Navigation/read/mutation orchestration: `lib/cubit/preset_browser_cubit.dart`.
- Fixed desktop skeleton and UI lifecycle: `lib/ui/widgets/preset_browser_dialog.dart`.
- Fixed mobile breadcrumbs/refresh: `lib/ui/widgets/mobile_drill_down_navigator.dart`.
- Hierarchy, viewport, freshness/races: `test/cubit/preset_browser_cubit_test.dart`.
- Retained rename and upload regressions: `test/cubit/preset_browser_rename_test.dart`,
  `test/cubit/preset_browser_review_regression_test.dart`.
- Fixed-column flows, focus, scroll and layout continuity:
  `test/ui/widgets/preset_browser_panes_test.dart`.
- Context-menu/drop and real wire contracts:
  `test/ui/widgets/preset_browser_dialog_test.dart`,
  `test/domain/sd_card_transport_safety_test.dart`.

Refresh this map when navigation ownership or reserved geometry changes. Preserve
transport safety tests; do not reinstate independent pane histories while fixing
focus or scroll. Native macOS retesting and live device PC selection are separate
from deterministic unit/widget evidence. See the
[focus/frame investigation](../investigations/preset-browser-focus-and-frame-continuity.md)
for the mouse-outline, single-click race and blank-column diagnoses.
