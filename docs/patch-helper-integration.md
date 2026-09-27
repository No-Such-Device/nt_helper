# Patch Helper SD-card companion

The plug-in's GUID is `ThPh`. Its companion lives at `/helper/ThPh.lua` on the
NT's SD card. Helper resolves `/helper/<GUID>.lua` with case preserved; the
script must declare the matching GUID and companion API version. This is host
Lua: Helper downloads the file through the existing whole-file SD operation
and runs it on the computer. Install only scripts from a source you trust.

Open the Patch Helper standard editor and choose **Load SD companion**. The Lua
module's `render(state)` supplies a validated table document: field labels,
ordered sections and socket-grid geometry. `handle(state, event)` supplies a
validated declarative action. The existing Lua evaluator is reused inside a
disposable isolate; Flutter renders the native controls. No bundled editor
substitutes for a missing or failed script. The ordinary parameter/spreadsheet
views remain available. Reload re-downloads the source and reads a fresh map.

The host removes file/process/module/debug APIs and limits evaluations to two
seconds, with 64 KiB source/output budgets. Isolates do not impose a hard memory
quota: this is a trusted-companion preview, not a hostile-code sandbox.

The table orders 12 inputs, 8 outputs and each expander's eight outputs. The
minimap uses 3 rows × 4 columns, 4 × 2, then 8 × 1 per expander, left to right.
Recorded dots use cable colour; unused sockets are hollow. Clicking a dot
scrolls to and highlights its row. Tag is a plain optional integer (1–12), with
blank meaning none. Edits require Enter or Apply row, and acknowledgement from
the NT before the snapshot changes. Save the preset separately to persist it.

Supported record types are NTX-8CV, ES-5, ESX-8GT and ESX-8CV. Repeated types,
instance names and manual bank ordering are supported. A move carries all eight
records with the instance. This records physical cabling without configuring
hardware or signal routing. The 7-bit socket address bounds this development
format to 13 expander banks; it is not a hardware topology limit.

Native-only maps remain preset format 1. Format 2 adds `expanders` objects with
`type` and `name`, and exactly 20 + 8×count connection records. The client uses
extended Open payload `02`, reads every bank and socket at one revision, then
publishes an immutable map. Older binaries reject extended Open with a clear
update instruction. The legacy empty Open remains supported by the new plug-in.

Commands 5/6/7/8 add/read/rename/move expanders; command 6 is read-only. Writes
compare leases and revisions, never retry automatically, and invalidate edits
after an uncertain result. Frames stay within 122 bytes. Direct USB to one NT
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
