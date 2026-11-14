# Browser input and frame continuity: manual feedback follow-up

Baseline: `18af8c3e`, isolated browser worktree; no main integration.

## Reproduced causes, not a blanket repaint workaround

1. **Extra outlined first row after rename/mouse focus.** `DirectoryPanel` set
   `_showKeyboardFocus = true` for *any* focus acquisition. A context menu or
   rename dialog restoring focus therefore looked like keyboard navigation.
   Its cursor name still referred to the old filename; reconciliation defaulted
   to index zero even though a different file remained selected. Row InkWells
   could also acquire their own focus independently of the column cursor.
   Flutter's desktop `FocusHighlightMode.traditional` alone is insufficient:
   mouse events do not switch it off. The fix observes pointer vs keyboard
   modality explicitly, without consuming events or changing app-wide focus
   policy, and excludes row-internal focus while retaining column keyboard and
   semantic actions. Verified rename aliases preserve cursor identity separately
   from selection, including an unselected right-click target.

2. **Single click lost/retargeted during focus refresh.** Rows were unkeyed and
   reused by index. A refresh that inserted a row between pointer-down and
   pointer-up replaced the pressed row's callback with the new index's item.
   The deterministic regression with identity keys temporarily removed requests
   `/A/aaa` instead of the clicked `/A/child` (`/tmp/nt-blink-unkeyed-baseline.log`).
   Stable path keys plus `findChildIndexCallback` preserve the recognizer and
   target across reordering. The fixed test checks request initiation in the
   first pump after pointer-up, without a second click or double-tap timeout.
   The browser has no `onDoubleTap` recognizer. Focus freshness still runs;
   directory clicks are not silently discarded just because it runs.

3. **Real blank intermediate snapshots.** Verified folder rename rebased stack
   paths but deleted all descendant caches before sequential verification reads.
   Normal navigation similarly published a new path before its first listing.
   These were observable empty column frames, not merely rebuild counts. Rename
   now rebases retained descendant listings as stale. Navigation starts reading
   immediately but commits the destination hierarchy only when coherent contents
   are ready; the previous hierarchy is never mislabeled as the destination.
   Pending navigation disables unsafe actions, uses the reserved status slot,
   and honors latest intent. Refresh reconciliation cannot cancel an unrelated
   newer sibling intent. Fresh parent entries supply actual names, not guessed
   trailing-slash spellings.

4. **Viewport recreation/late scroll correction.** Separate empty/nonempty trees
   replaced the list subtree. Path rekeying recreated scrollables even for the
   same renamed location, and a post-frame jump restored offsets only after an
   initial layout. A uniform list/material tree now renders blank placeholders
   and real contents. Rename identities retain scrollable state; actual location
   changes use a controller with the correct initial offset in their first
   layout. Existing scroll, Back, keyboard and layout regressions remain.

No opacity animation, delay, polling, screenshot mask or speculative GPU workaround
was introduced. Flutter normally publishes a coherent scene, so the above state
and viewport causes do **not** prove an independent macOS compositor defect.
Initial uncached root loading and genuinely empty/unassigned columns may be blank.
Native inspection is non-destructive; physical-display/per-frame GPU behavior
remains a manual acceptance limit if blinking persists after these fixes.

## Deterministic checks

`test/ui/widgets/preset_browser_panes_test.dart` covers mouse/keyboard modality,
rename dialog return, independent renamed cursor, held focus refresh/reorder
across a click, rapid siblings, coherent cascading publication and retained
folder-rename descendant frames/list state. Existing geometry, breadcrumb,
context Refresh, upload lease and stale-action tests remain.
