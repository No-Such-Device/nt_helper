# Patch Helper integration foundation

The companion C++ project is `thorinside/patch_helper` (private). Its source
spec is Substrate `d4abe223-d4c5-4784-811b-417aa43586ee`, still a discovery draft.

This slice adds **preset-data APIs only**, not a visible editor or live MIDI
transport. `PatchMap` validates an immutable native-socket map;
`PatchMapPresetCodec.readSlot`/`writeSlot` operate on one saved slot with GUID
`ThPh`. Writing replaces only `patch_helper`, retains firmware fields, and
refuses to overwrite unknown or invalid existing map data. It does not load
the preset or mark a connected device dirty.

Direct placement of `patch_helper` in the slot is provisional: verify the
firmware's actual custom-data envelope from a device-exported preset before
integrating this codec into user-facing operations. The shared fixture proves
the callback payload and the proposed slot adapter, not that hardware envelope.

The version 1 preview covers twelve inputs and eight outputs. Connections have
explicit socket IDs (0–19), destination, colour (0–11), optional Tag (0 absent,
1–12 set), and group. Clearing destination retains other metadata. All sockets
must appear exactly once. New maps show all sockets unused. Title/destination
are at most 63 printable ASCII characters; group is at most 31. These are
provisional plugin memory/display choices, not native firmware string limits.
See the shared `test/fixtures/patch_map/native-map.json` fixture; its bytes must
match the C++ repository's `tests/fixtures/native-map.json`.

The pinned official C++ API v13 supplies preset serialization and display-only
parameter strings, but no arbitrary string-write callback. Existing Helper
string parameters therefore do not establish plug-in editing support. Before
adding the UI, implement and verify a slot-addressed state transport with
schema negotiation, stale-edit handling, acknowledgements, preset-switch
protection, and recovery. Respect the existing 1024-byte SysEx ceiling.

Lua controllers should receive immutable state and emit declarative actions
executed by the host. They must not send MIDI directly or own a competing map.
SD-card companion loading additionally needs compatibility metadata, trust and
execution isolation, and a standard-editor fallback. Expander support and
end-of-chain preset lifecycle remain separate discovery work.

Run `flutter test test/domain/patch_map/patch_map_test.dart` for the shared
format, validation, immutability, and slot preservation checks.
