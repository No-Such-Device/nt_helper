# NT Settings

The cog immediately after Plugin Manager opens the module's global settings.
It remains available in Play Store builds. Application Settings/preferences and
the System dialog are unchanged.

NT Settings requires a live connection, recognized firmware 1.20 or later and
settings protocol v1. Discovery happens on opening the screen; a version string
alone does not prove support. Earlier betas may not respond. Offline and Demo
modes never send settings MIDI.

## Editing and recovery

The module supplies the hierarchy, labels, ranges, defaults, types and flags.
The expandable navigation tree selects one group's direct settings. Child groups
appear only in navigation, not as nested forms. Compact windows use a group
picker/drawer; desktop uses a 280-pixel sidebar. Drafts, selection and scroll
positions survive group changes and layout changes on the same connection.
Hidden drafts/errors are indicated in navigation. A replacement connection resets
navigation and never receives old drafts.

Ordinary **Apply changes** immediately applies valid drafts in the selected group.
Only batches marked as restarting audio or requiring reboot, and changes to the
known “SysEx Device ID” connection-address setting, ask for confirmation.
An approval covers the reviewed batch, not subsequent draft changes. No automatic
reboot occurs. Writes are sequential, not atomic, and are not saved to flash.

Settings reads have a bounded timeout of at least one second, preserving a longer
configured timeout. They use one attempt and strict same-ID reply attribution.
The ordinary request timeout (including a configured 50ms timeout) is insufficient
for potentially large replies: 1024 bytes takes about 330ms over DIN MIDI alone.
A pre-write read establishes attribution before mutation. Command `66` has no ACK
and is never replayed; after sending, the app waits the maintained editor's 20ms
settling interval and queries `65` for the observed value. That interval is not a
response deadline or a firmware timing guarantee.

Failed reads retain drafts and observed values, mark the affected field as needing
refresh, and prevent resending it. Other valid fields remain independently
editable/applicable. Refresh can recover values against the existing schema
without discarding drafts. Unresolved late replies can still require another
explicit refresh or reconnection. No timeout is treated as proof of unsupported
firmware, successful mutation, or durable flash storage.

**Commit to flash** and **Revert to saved** occupy one persistent inset bottom
dock, outside the scrolling form. They stay disabled while drafts or uncertainty
remain. Both are explicitly confirmed; the protocol provides no durable-write
acknowledgement. Revert requires Refresh afterward. No factory reset, auto-commit,
automatic reboot, offline settings cache or MCP settings API is exposed.

## Read-only paths

Path values are displayed as selectable text with a read-only tooltip and
accessible hint. Read-only flag 4 is always enforced, independently of type.
Even without flag 4, type 5 Path remains display-only: Os' reference editor renders
it `readonly`, and its write encoder has no Path branch. A NUL-terminated Path
*read* does not establish a supported Path *write*.

Read-only inspection of the running app's cached snapshot on 2026-11-23 found
firmware `v1.20.0beta`, build date `Nov 23 2026 15:10:49`. “Audio recordings folder”
was setting 56, type 5, unit 18, flags 4, maxLength 255, observed `/recordings`.
“Preset save folder” likewise had type 5 and flags 4. These are observations,
not hardcoded IDs or a fresh hardware query. No folder was modified. A folder
picker must wait for a supported wire contract and writable firmware metadata;
a local-computer filesystem picker would not select an NT SD-card directory.
Question for Os: will a later revision expose writable Path metadata and a Path
write encoding, or is a separate directory-selection command required?

## Layout and accessibility

Only navigation is indented. Desktop editor controls begin exactly 24 logical pixels after the separator;
compact content retains its 16-pixel inset. Dirty fields show `was <confirmed
value>` in the reserved feedback slot; successful readback clears it, while
failures retain the confirmed baseline and error. The detail pane has one scoped Apply footer and no
redundant visible heading, breadcrumb, explanatory card or global Apply. Refresh
and Discard drafts remain in the app bar. Status, field feedback, footer and
bottom persistence dock reserve their space through loading, errors and pending
operations. No affirmative/progress snackbars are used.

The tree is one keyboard Tab stop: Up/Down/Home/End select visible rows;
Right expands or moves to the first child; Left collapses or selects the parent
(swapped in RTL). Enter/Space activates. Collapsing an ancestor selects it. Rows
expose selected/expanded state and draft/error status; disclosure buttons are
separately labelled. The compact drawer preserves Back, restores picker focus
on close, and keeps container-only selections open. Forms retain native keyboard
editing, labelled read-only values, all 64 bit labels, and live-region feedback.

## Evidence boundaries

Protocol source: Os' preset editor at immutable commit
`82c23673b7e63371df60a59951ab13182cf703ca`; see [SysEx reference](SYSEX_REFERENCE.md).
Automated wire tests use synthetic fixtures, including delayed 140ms replies
against a 50ms general timeout. These are not measured hardware timings.

The current live app has no NT Settings MCP operations; VM expression evaluation
reports no compilation service. Read-only VM object inspection captured cached
firmware/schema/values only. No hardware write/readback/restore cycle or `65`/`66`
latency measurement was performed for this follow-up, and no app restart was
performed. The user's report that settings work better is positive manual
feedback, not proof of a measured transport budget or flash persistence.
