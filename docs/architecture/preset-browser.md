# Preset browser: independent pane stacks

## Ownership and navigation

`lib/cubit/preset_browser_state.dart` defines the only stored browser view state:

- `BrowserFrame(path, selectedName)` is one visited location and its selection.
- `BrowserPane(stack)` owns a non-empty stack of frames. Enter pushes a location;
  Back pops that pane only. Returning to an existing location truncates the stack
  to that frame rather than adding a loop. An absolute jump records the visited
  location, not synthetic visits to every ancestor.
- `BrowserSnapshot` owns three panes, the active pane, shared listings keyed by
  absolute path, sorting, in-flight path status and path-specific errors.
- `PresetBrowserState.loaded(browser: ...)` contains that snapshot. Older-named
  renderer getters (`currentPath`, panel items, drill items, breadcrumbs,
  navigation history) are **derived projections**, not additional stored state.

`PresetBrowserCubit` owns navigation, revalidation and file operations.
`ThreePanelNavigator` renders explicit pane paths from the snapshot. A directory
click/Enter navigates **inside the clicked pane**, rather than rebuilding the
other panes as cascading previews. Each pane has its own path header, Back and
Refresh/Retry controls, including empty folders. Alt-Left pops the focused pane;
Tab can move focus to other panes/controls. Enter no longer advances focus to a
different pane after opening a directory.

Mobile renders the **active pane's same frame/listing/selection**. Changing
viewport size does not copy/rebuild navigation, and a hidden mobile selection
cannot override a desktop selection. Root/breadcrumb navigation affects only
that pane. The global toolbar, Load/Delete target and mobile view follow the
active pane. Context menus and drops use their explicit pane directory, not an
inferred directory from another pane's selected entry.

All three panes initially represent real root directories. Only the previous
active location (`fileBrowserLastPath`, the existing preference) is restored into
the first pane; full per-pane stacks are session state, not a new persistent
history format. Recent preset file history remains a separate bounded preference.

## Automatic freshness without polling

- Startup requests root **once** for all three panes. Listings for the same path
  are shared; concurrent requests for that path share one in-flight future.
- Enter, Back, breadcrumbs, absolute navigation and explicit Refresh revalidate
  the destination. Cached data never suppresses a revisit read.
- Pane pointer/keyboard focus and app resume revalidate only stale visible paths.
  The default five-second freshness window uses an injectable `Clock`; it is a
  throttle, **not a timer**. Repeated focus/clicks on fresh data cause no reads.
  Resume deduplicates paths shared by multiple panes. Returning from a child tool
  that can mutate device files also revalidates visible paths.
- Successful file mutations invalidate their parent listing and the relevant
  old/new subtree when necessary. All panes displaying those paths update from
  the same result. Renamed open stacks and recent paths are rebased; deleted
  folders pop affected stacks to a surviving location. Unrelated fresh panes
  are not reread. A verified rename's parent read-back is reused, not repeated.
- Mutation workflows are serialized through verification, not merely at the MIDI
  packet scheduler. Writes are never blindly replayed after ambiguous replies.
  Upload chunks stay bounded to 512 data bytes and preserve inter-chunk pacing;
  read-only downloads retain bounded retry recovery.
- Path generations invalidate older in-flight replies. A reply can update a
  listing, but never restore an earlier pane stack/active selection. Mutation
  invalidation prevents an older listing from overwriting post-mutation data.

A refreshed directory reconciles selection by filename, not object identity.
A vanished selection is cleared. Loading/error feedback uses reserved header
slots; failed or still-refreshing active listings cannot supply a Load target.
Path-specific refresh errors do not discard other pane stacks. Mobile pull-to-
refresh awaits the actual request and works in an empty directory.

This is event-driven freshness, not an SD-card watcher. Changes made externally
while a pane remains continuously focused are seen on revisit, a later focus /
resume event, or explicit refresh. There is no background polling, full-card
scan, automatic remount, or claim of instant detection of external edits.

## Rename and hardware boundaries

The protections described in
[preset-browser rename consistency](../investigations/preset-browser-rename-consistency.md)
remain: single-dispatch rename, status/error propagation, fresh parent
verification, old/new cache invalidation and remembered-path reconciliation.
An uncertain rename leaves affected paths in retry/error status, with stale
loading disabled, rather than destroying unrelated pane stacks or claiming
success. A later fresh listing can resolve the view, not prove lost device
acknowledgement semantics.

Browser listings are host UI state. The Disting NT firmware implements `#n`
Program Change matching and alphabetical fallback. No host-side PC index or
firmware invalidation command is introduced. The original report's exact
connected-device symptom still requires the manual hardware acceptance checklist
in the investigation; app tests do not emulate or prove firmware PC behavior.

## Retrieval and verification

- Ownership/navigation/freshness: `lib/cubit/preset_browser_cubit.dart` and
  `preset_browser_state.dart` (regenerate `preset_browser_state.freezed.dart`
  using build_runner after model changes).
- Desktop/active context/lifecycle: `lib/ui/widgets/preset_browser_dialog.dart`.
- Mobile rendering/awaited refresh: `lib/ui/widgets/mobile_drill_down_navigator.dart`.
- State/races/traffic boundaries: `test/cubit/preset_browser_cubit_test.dart`.
- Retained rename regressions: `test/cubit/preset_browser_rename_test.dart`.
- Real-cubit widget flows, keyboard, resize, resume and stable feedback geometry:
  `test/ui/widgets/preset_browser_panes_test.dart`.
- Existing rendering, context-menu/drop and wire contracts:
  `test/ui/widgets/preset_browser_dialog_test.dart`,
  `test/domain/disting_midi_manager_sd_operation_test.dart`.

Tests use controlled completers and a fake clock rather than sleeps to establish
freshness/race behavior. Live MIDI/USB throughput, cross-platform native focus
notifications and actual module Program Change selection remain device-validation
work; unit/widget passes do not establish them.
