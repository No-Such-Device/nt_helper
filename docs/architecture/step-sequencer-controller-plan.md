# Step Sequencer shared Controller toggle

## Scope and baseline

Plan recorded before implementation on `be2ab3b2`, following investigation
artifact `fef0dea0-7c0e-4413-80ed-3f4c5277e31a`. This change moves only the
native `spsq` editor behind the existing Controller button. It does not rewrite
the editor in Lua, introduce a firmware threshold, or change Notes (`note`),
Patch Map (`ThPh`), bundled Lua controllers, or the demo-only `seq ` identity.

## Dispatch contract

- Standard: ordinary parameter pages for `spsq`.
- Controller: existing native `StepSequencerView` for exact GUID `spsq`.
- Spreadsheet: unchanged generic numeric editor.
- Availability, selector name, effective mode and selection guard share the
  same native descriptor lookup; Lua definitions remain real Lua definitions.
- The workspace's global, in-memory requested mode remains authoritative.
  Unsupported slots locally fall back without clearing that requested mode.
- Lua section navigation/collapse remains Lua-only. Native Parameter Pages,
  Randomize, randomize settings, quantization and playback controls remain.

## State and lifetime decision

Use lazy same-mounted-slot native subtree retention rather than lifting every
sequencer field into a new persistence/controller framework. Once opened, its
body remains mounted during Standard/Spreadsheet selection. Hidden native
content has no focus, pointer, semantics or ticker activity. Only the active
surface owns a header and its Bypass focus node; headers are not retained in
hidden editor bodies.

Lane, snap/scale/root, quantize undo and grid scroll survive those mode toggles.
Accepted grid/playback edits are debounced while editing, then explicitly
flushed by the mode-selection event before exposing the other editor. Thus an
older native debounce cannot overwrite a newer Standard/Spreadsheet edit.
Disposal only cancels work; it never flushes MIDI writes.

Pending writes are anchored to the displayed sequence, not a newer snapshot
that happened to arrive before repaint. Each short-lived edit scope observes
state departures and latches cancellation, so sequence 1 → 2 → 1, a disconnect
or a reorder cannot revive old work. Completion, replacement and disposal
release its subscription. Ordinary value readback is not treated as user input.

Editor/write identity includes manager, real slot index, a local algorithm
instance token and the parameter/specification schema. `Algorithm.copyWith`
retains that token for rename/style changes; fresh Algorithm construction gets
another token, including same-GUID replacement or full rehydration. Schema
changes invalidate work even when the token is retained.
No polling is introduced for hidden editors. Latest immutable slot data still
updates the retained body. Retention is not disk persistence and does not
promise preservation across parent layout reparenting, preset reloads or
reconnects. Existing index/GUID keys cannot distinguish every same-GUID
instance replacement; this feature does not invent that guarantee.

Sequence changes invalidate sequence-specific undo and pending step edits;
accepted old-sequence edits must not run against the new sequence. Randomise
pulse cleanup is algorithm/session-bound instead: after an accepted high edge,
its low edge still runs across a sequence change, but never on a replacement
algorithm or after reconnect. The native
Sequence selection uses the parameter's actual min/max, including 1..32 and
legacy 0..31, rather than an assumed 0..31 range.

## Implementation seams

1. Small native alternate descriptor in `AlgorithmViewRegistry`; remove `spsq`
   from Standard replacements, keep `note` and `ThPh` untouched.
2. `SlotDetailView`: honest shared availability, lazy retained native body,
   active-only header, focus continuity and existing Lua dispatch/fallback.
3. Neutral alternate-editor selector hint; preserve keys, icons and selected
   semantics used by existing Lua editors.
4. Narrow lifecycle guards in native sequencer/grid/playback async writes.
   Reuse the current cubit write/debounce path; no transport changes.
5. Metadata-based Sequence bounds fix with regression, adjacent to integration.
6. Expanded playback dropdowns, wrapping quantize/header actions, and reserved
   sequence-progress space avoid overflows/shifts exposed by the third mode.
   Unrelated Start/End snapshots no longer overwrite a text draft or its caret.

## Acceptance and checks

- Exact GUID lookup; all Lua registrations and native Standard neighbors stay
  unchanged; no aliases for `seq `, `spsh` or `ensq`.
- Standard/Controller/Spreadsheet switching; disabled selection; no writes
  caused merely by selecting a mode.
- Same-slot lane/quantize/undo retained; hidden fields absent from traversal and
  semantics; one visible Bypass/header; selector focus retained.
- Pending grid/playback input settles before a mode toggle exposes another
  editor. Newer intent wins in both directions, with hidden keyboard activity
  excluded. Disconnect, replacement, removal and sequence departure cancel
  stale work permanently. Randomise cleanup still follows its original instance.
- Fresh parameter values and Sequence 32 render after hidden updates; legacy
  zero-based Sequence remains valid.
- Standard contains full parameter pages; retained native complementary
  Parameter Pages and other native controls remain in the native editor.
- Offline/demo synchronized snapshots use the same dispatcher; unavailable
  offline algorithms retain their existing fallback.
- Global requested Controller selection survives unsupported-slot fallback;
  native slots do not consume Lua section shortcuts.
- Header and sequence-control geometry remains stable across modes/loading at
  320/600/1200 logical pixels, including 200% text at 600px.
- Run code generation, changed-file format/analyze, new integration tests,
  native component tests, Lua/spreadsheet/header/neighbor regressions, full
  default suite and separate-output macOS Debug build.

## Review and delivery boundary

The independent review identified four lifecycle/order defects; their seven
characterization probes are now permanent positive regressions. Additional
scope and debouncer tests cover stable presentation copies, same-GUID
replacement, schema/specification changes, reorder/disconnect round trips,
readback-versus-intent, cancellation resources and explicit flush ordering.
The reviewed implementation passed the full default suite: 4,849 tests with
one existing hardware opt-in skip, clean analysis/formatting/diff checks and an
unsigned macOS Debug build. These automated checks do not claim physical NT,
VoiceOver or launched-app acceptance. Full rehydration/reconnect may reset editor-local state; the local
instance token is intentionally not persisted or sent over MIDI.

Commit implementation and verification evidence on this worktree branch.
Independent review is complete; publish the PR after fixing and validating its
findings. No merge, release, app reload/restart or hardware operations
are part of this implementation job. The active demo is left untouched.
