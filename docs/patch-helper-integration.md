# Patch Helper SD-card companion

The plug-in's GUID is `ThPh`. Its companion lives at `/programs/helper/ThPh.lua` on the
NT's SD card. Helper resolves `/programs/helper/<GUID>.lua` with case preserved; the
script must declare the matching GUID and companion API version. This is host
Lua: Helper downloads the file through the existing whole-file SD operation
and runs it on the computer. Install only scripts from a source you trust.

In File Browser, right-click `programs` and choose **New Folder** to create
`helper` inside it, then upload `ThPh.lua` there. Right-clicking blank space in
a directory panel creates a folder in that directory, including the SD root.
The folder-plus button creates a folder in the current directory (the leftmost
panel on desktop, or the open directory on mobile).

Opening the Patch Helper standard editor automatically loads its companion. The Lua
module's `render(state)` supplies a validated table document: field labels,
ordered sections and socket-grid geometry. `handle(state, event)` supplies a
validated declarative action. The existing Lua evaluator is reused inside a
disposable isolate; Flutter renders the native controls. No bundled editor
substitutes for a missing or failed script. The ordinary parameter/spreadsheet
views remain available. There are no manual load/reload controls or patch-title
field. The sockets panel is labelled **Sockets**, with no instructional copy.
A small yellow status dot means **Up to date**; its tooltip and screen-reader
label distinguish syncing and errors. Status changes use fixed-size slots; errors use tooltips
and overlay messages, so they never shift the table.

Downloaded Lua is stored in Helper's writable scratch directory under
`nt_helper/companions/v1/<endpoint-hash>/<GUID>.lua`. The endpoint includes MIDI
input/output identities and SysEx device ID. The next opening uses the cached
source immediately, then checks the SD source in the background and once per
minute while active. Missing/corrupt scratch files are downloaded again. Scratch
storage failures do not prevent SD loading. Background failures show an error;
recovery retries after five seconds, reconciling desired fields against a fresh
NT snapshot before deciding whether another write is necessary. A
missing SD file reports its expected path. A corrected file is picked up
automatically. Active edits defer companion checks.

The host removes file/process/module/debug APIs and limits evaluations to two
seconds, with 64 KiB source/output budgets. Isolates do not impose a hard memory
quota: this is a trusted-companion preview, not a hostile-code sandbox.

The table orders 12 inputs, 8 outputs and each expander's eight outputs. The
minimap uses 3 rows × 4 columns, 4 × 2, then 8 × 1 per expander, left to right.
Dots show the selected cable colour even before a destination is named;
empty uncoloured sockets are hollow. Clicking a dot
scrolls to and highlights its row. Tag is a plain optional integer (1–12), with
blank meaning none. Valid field edits appear immediately and sync after a short
300 ms typing pause, with no Apply/Discard workflow. Expander names also sync
automatically. Pending fields merge with fresh NT records so unrelated hardware
changes survive. Changes made during an in-flight write remain queued. A lost
acknowledgement triggers a reread; already-applied values are not written twice. Save the preset separately to persist it.

Supported record types are NTX-8CV, ES-5, ESX-8GT and ESX-8CV. Repeated types,
instance names and manual bank ordering are supported. A move carries all eight
records with the instance. This records physical cabling without configuring
hardware or signal routing. New maps allow 12 expander banks so independent native colour/tag controls fit
the connected firmware's measured 240-parameter limit. Older 13-bank maps remain
readable and editable in Helper; the NT provides a compatibility selector page
for their final bank. This is not a hardware topology limit.

Native-only maps remain preset format 1. Format 2 adds `expanders` objects with
`type` and `name`, and exactly 20 + 8×count connection records. The client uses
extended Open payload `02`, reads every bank and socket at one revision, then
publishes an immutable map. Older binaries reject extended Open with a clear
update instruction. The legacy empty Open remains supported by the new plug-in.

Commands 5/6/7/8 add/read/rename/move expanders; command 6 is read-only. Individual writes compare leases and revisions and are never blindly replayed.
After an uncertain result, the editor rereads the map and reconciles queued field
values before sending another write. Frames stay within 122 bytes. Direct USB to one NT
remains the supported development transport.

Cross-repository fixtures: `native-map.json`, `midi-session.json`, and
`expanded-session.json` match `patch_helper/tests/fixtures/`. The Lua test fixture
matches `patch_helper/helper/ThPh.lua`. Tests exercise the actual Lua source,
GUID/path compatibility, broken/infinite scripts, acknowledged writes, exact
C++/Dart wire exchange, expander persistence and a rendered widget interaction.

Source spec: Substrate `d4abe223-d4c5-4784-811b-417aa43586ee`. The approved table
refines the original UI direction. NT-side text editing, gear-oriented sorting,
arbitrary algorithm shared-state adapters, and regular/end-of-chain preset
lifecycle verification remain separate work. The provisional saved-slot codec
is not wired into UI: its firmware envelope still requires device evidence.


## Live property callbacks

The ThPh adapter polls command 9 every second while the editor and app are active.
It observes native First socket, Cable colour and Tag as `state.properties`
keys `first_socket`, `colour`, `tag`. First socket is one-based; other values use
existing palette and tag indexes. The compatibility controls retain plug-in
indices 0, 1 and 2; the per-socket pages use appended colour/tag pairs. Standard
NT common-parameter offsets remain a firmware concern, not Lua IDs. Each snapshot also carries `state.revision`.

An optional `on_change(state, change)` receives `{type="nt_changed",
properties={key={previous,value}}, map_changed=boolean}` and returns a view
only. Missing callbacks fall back to render. Changed keys are coalesced between
polls. A new runtime is used for each evaluation; there are no persistent Lua
listeners. The bundled SD companion requests `focus_socket` on selection changes,
which Flutter scrolls/highlights without moving keyboard focus.

Unchanged revisions cost one read; changed maps are read consistently at that
revision. Notifications never execute write actions. Local desired field values are retained during concurrent NT changes and
transient errors, and retried until acknowledged while the editor remains open.
A preset/lease change opens a fresh session; changing the selected preset or
endpoint creates a separate editor. Structural actions remain acknowledged
operations and are disabled while field edits are syncing. Timer reads and user writes are
serialized; disposal/inactive app or editor stops scheduling reads. An already
in-flight read may complete, but cannot publish to a closed editor.

The callback API can serve other adapters, but this revision implements only
ThPh's property and map adapter. Native NT destination/group text entry and universal adapter discovery remain
pending. Hardware evidence is recorded separately from widget and protocol tests.

## Lua-defined expander dialog

The companion table document accepts an optional `actions` array. Its supported
`add_expander` action declares `label` and a `choice_dialog` with `title`,
`cancel`, and `{label, value}` choices. Values are unique model IDs 0–3. Flutter
renders the action at the top right, with the fixed sync indicator at the top
left. The model dropdown no longer occupies the editor. Cancel, Escape and
barrier dismissal leave the map alone.

Selection rechecks the latest Lua action, editability, pending synchronization,
and bank limit. The returned Lua action cannot change the requested model.
This is an additive API-1 primitive; old scripts without actions remain valid.

V1 is documented in the original Substrate spec
`d4abe223-d4c5-4784-811b-417aa43586ee` and `patch_helper/docs/v1-spec.md`.
Native text-property editing remains required for full device parity; this
host dialog change does not implement it.
