# Preset browser rename consistency

## Report and evidence boundary

Report: presets renamed with `#n` in the file browser were not seen under the new
names and Program Change selected the wrong presets. The screenshot alone does
not establish firmware version, final on-card filenames, duplicate numbers,
bank settings, or whether the problem persisted after closing the browser.

The host-side defects below are reproducible in automated tests. They are not
proof of the exact connected-device failure: real Program Change acceptance
remains required.

## Trace and confirmed defects

`PresetBrowserDialog._renameAction` passes the selected panel's full path and
new filename to `PresetBrowserCubit.renameEntry`. This uses the SD-card file
rename operation (`7A 05`), **not** the current-preset name/save operations
(`47`/`36`). It must not load, reconstruct, or save preset contents merely to
rename a file.

Before this fix:

- The parent directory cache alone was evicted. Renamed directory descendants,
  recent preset paths and remembered navigation could retain old paths.
- `_refreshDirectory` updated desktop panels with mutually exclusive branches.
  When the same directory was visible in a center/right panel and mobile drill
  view, only the desktop branch ran. `currentDrillItems` and
  `selectedDrillItem` remained stale; `getSelectedPath` prioritizes that mobile
  selection. Subsequent selections/renames could therefore target old paths.
- The state snapshot used for refresh was captured before network I/O. A delayed
  reply could restore navigation/selection that the user had already changed.
- Rename used a generic retry loop despite being non-idempotent: if a rename
  completed but its reply was lost, retries addressed the missing old filename.
  Listing failures were swallowed, allowing a rename-success announcement with
  an unrefreshed view.
- A returned `SdCardStatus(success: false)` was treated as success. This is an
  interface-level guard defect, not evidence that normal live firmware errors
  were hidden: the real scheduler already converts failed `7A` replies into
  `SdCardOperationException`. The wire regression explicitly checks that path.

## Fix contract

Rename dispatches once, propagates device/transport errors, checks returned
status and reads back the parent directory. Success requires the new entry and
absence of the old entry. Rename does not invent a device PC-cache invalidation
command or rewrite JSON contents.

After verification, exact source paths (and descendants for folders) are
rewritten in recent history, remembered navigation, breadcrumbs and selections.
Old/new subtree caches are evicted. Refresh reconciles selections with fresh
entries, updates every matching desktop/mobile view and publishes the cache
snapshot from the current state, not the pre-I/O snapshot. No fixed 200 ms wait
is used for rename verification. Invalid/control/non-7-bit filename input is
rejected before sending the rename's raw MIDI string bytes.

A missing acknowledgement or unverifiable listing is reported as failure /
uncertainty, not successful completion. The browser enters its retry/error view
instead of leaving Load enabled for a possibly vanished filename. It is possible that the file did change;
refresh the browser before retrying. There is no automatic rollback or replay of
an ambiguous non-idempotent operation.

## Program Change: documented, not emulated

The official [firmware 1.17 manual](https://expert-sleepers.co.uk/downloads/manuals/disting_NT_user_manual_1.17.pdf),
page 52, says a filename containing `#` followed by the program number takes
precedence; otherwise filenames are alphabetically sorted and indexed by the
program number. It refers to **filenames**, not the JSON's stored preset name.
Do not infer ambiguous-number precedence, directory scope, MIDI-controller
one-based display conversion or bank behavior beyond the target manual/settings.

No application-owned Program Change preset resolver/index was found in the
browser/load path. Its cached listings are UI caches, not firmware PC mappings.
The automated multi-preset regression changes `Alpha → Alpha #42 → Alpha #3`
and `Beta → Beta #7 → Beta #42`, proving fresh browser/cache/selection/history
paths, not reproducing the firmware's resolver.

The official [SD-card tool](https://github.com/expertsleepersltd/distingNT/blob/main/tools/dnt_sdcard_tool.html)
requests a directory listing after rename success; remount is a separate user
operation. The inspected manual documents remount as filesystem reinitialization,
not a targeted preset-PC-cache invalidation API. Consequently this patch does
**not** automatically remount the card, reboot, rescan plugins, or assert that
such a workaround is necessary/safe while algorithms use SD resources.

## Verification and connected-device acceptance still needed

Automated regression coverage:

- All three desktop panels, simultaneous mobile/desktop views, selected paths,
  repeated `#n` renumbering, history and cache consistency.
- Folder descendants and prefix-similar siblings; remembered folder paths.
- Delayed read-back with intervening navigation; invalid filenames; rejected,
  unacknowledged and unverifiable renames without blind replay.
- Wire framing preserves `#42` and null-terminated old/new paths, with both
  successful and error replies; UI displays rename failure rather than success.

Before claiming the reported PC symptom resolved on hardware:

1. Back up presets and record module firmware, PC channel/bank settings, browser
   platform, controller's displayed number versus actual transmitted MIDI byte.
2. Use disposable, distinguishable presets with no duplicate `#n` names. Retain
   `.json` extensions. Rename multiple files; verify directory read-back, browser
   selections, recent entries and browser close/reopen results.
3. Send the intended raw PC numbers and verify actual loaded algorithm content,
   not only the displayed preset name. Renumber/reassign a previously used number
   and repeat; separately test the documented alphabetical fallback.
4. If on-card names are correct but PC still selects old content, capture that
   distinction as a firmware-side reproduction. Test a **manual**, explicitly
   approved remount/reboot separately if appropriate; do not silently add it to
   the host rename protocol or declare cache semantics from a mock.

No physical MIDI/USB device, firmware mutation, or live PC selection was used in
this change. External documentation was inspected publicly; no credentials or
user preset contents were collected.
