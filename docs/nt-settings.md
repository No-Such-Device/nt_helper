# NT Settings

The cog immediately after Plugin Manager in the bottom action bar opens the
module's global settings. It remains available in Play Store builds, where the
Plugin Manager itself is absent. Existing application Settings/preferences are
unchanged.

NT Settings needs a live connection and recognized firmware 1.20 or later with
settings protocol v1 support. The app discovers support when the screen opens;
a version string alone is not proof. Earlier betas may not respond. Retry is
explicit, and unresolved late replies may require reconnection before another
query can safely be attributed. Offline and Demo modes never send settings MIDI.

The module supplies its own menu hierarchy, labels, ranges, defaults, types,
flags and values. Edit locally, then choose **Apply changes** for that group.
The confirmation explains possible audio restart/MIDI disconnection and that
multiple settings are sent sequentially. Values are queried before and after
each mutation; there is no write acknowledgement. Unconfirmed changes retain
the draft and observed value separately and disable more writes until refresh.
Drafts survive leaving and reopening the screen on the same connection. They
are never replayed onto a replacement device.

**Commit to flash** sends the module's persistence command. The protocol does
not acknowledge durable flash storage, so the app reports only that it sent the
command. **Revert to saved** is separately confirmed and requires Refresh to
read active values afterward. The first implementation does not expose factory
reset, auto-commit, automatic reboot, offline caching, or an MCP settings API.

## UI and accessibility

The interface preserves the app's Material 3 themes and native form controls.
Impeccable's Operate/native adaptation/hardening guidance informed the restrained
hierarchy, width-based layout, labelled 48-pixel cog, standard switches/selectors,
and reserved status/error slots. The user's minimal-copy direction takes precedence:
there is no introductory paragraph, breadcrumb, repeated range/default helper,
or explanatory card. Range/default/type details live in tooltips and accessible
hints; concise warnings appear only in context. No new visual world or web-specific
styling was introduced. The Flutter architecture guidance is applied through lean views,
immutable presentation snapshots, the existing Cubit delegate pattern, and the
optional live transport interface—not a parallel state-management stack.

A coherent schema/value snapshot appears together; discovery does not append
interactive fields one at a time. Toolbar/status positions are stable before
and after discovery. Refresh, pending writes, validation and disconnection keep
existing control geometry. Field feedback uses one reserved, text-scale-aware
line (with a minimum 48-pixel interaction slot). A full-status dialog is offered
only when the visible feedback is truncated, avoiding redundant focus stops. Meaningful status updates use live-region
semantics; there are no affirmative/progress snackbars. Section headings,
read-only values and all 64 bit controls are labelled. Standard focus traversal,
text editing, dropdown and toggle keyboard behavior are retained. Each action has
one home: native Back/title; Refresh and Discard drafts in the app bar; flash
Commit/Revert once in the toolbar; scoped Apply once per editable group (none for
read-only groups). There is no duplicate global Apply, reset, reboot or screen
Close action. The existing System dialog and application preferences remain
unchanged.

Subgroups have visible boundaries and indentation, with heading levels matching
the module hierarchy. Root settings following a subgroup remain outside it;
menu order is never rearranged to achieve grouping. Apply retains its native
button focus semantics and visible accessible name. Numeric edits preserve
spelling and caret position when a draft is echoed back. Action buttons grow
with text scaling rather than clipping labels to a fixed height.

## Evidence boundaries

The protocol reference is Os' preset editor at immutable commit
`82c23673b7e63371df60a59951ab13182cf703ca`; see [SysEx reference](SYSEX_REFERENCE.md).
Test data are synthetic fixtures derived from that code, not recordings of an
actual module catalogue. Automated checks cover exact packets, signed16/bit63,
malformed data, ID attribution, one-attempt discovery, late responses,
non-replayed mutations, connection cancellation, drafts/uncertainty, semantics,
widths 390/600/900/1200, 300% text scaling and asynchronous geometry. Additional
regressions cover nested menu boundaries, heading depth, echoed numeric edits,
Apply keyboard focus, truncated feedback, large-text label bounds and dropdown
discard synchronization. No module
was connected or rebooted to verify persistence or setting-specific effects.
