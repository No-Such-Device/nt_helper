# Patch Helper integration foundation

The companion C++ project is `thorinside/patch_helper` (private). Its source
spec is Substrate `d4abe223-d4c5-4784-811b-417aa43586ee`, still a discovery draft.

The first slice added preset-data APIs. Revision 2 adds a live USB transport
and a typed client; the visible editor remains the next step. `PatchMap` validates an immutable native-socket map;
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
string parameters therefore do not establish plug-in editing support. The revision-2 bridge uses a separate experimental SysEx namespace, checked
protocol version, slot address, client lease, request ID, and map revision.
Writes replace one connection or title atomically, and are never replayed
automatically. A conflict, preset change, malformed reply, or uncertain write
invalidates the client until a complete reload. Live managers implement the
optional `PatchMapTransport` capability, using the existing MIDI queue and
selected-device filtering; demo/offline managers do not claim support.

Frames are at most 122 bytes, below the existing 1024-byte ceiling. USB is the
only reply destination. Use a direct connection to one NT; the public plug-in
API does not expose device SysEx ID or the incoming port. Hardware callback
dispatch, preset-save behavior, and dirty marking still need owner verification.
The bridge changes the live map; the normal Save preset action persists it.

`PatchMapClient.load()` obtains the title and all 20 records at one revision.
`setConnection()` and `setTitle()` return a new snapshot only on acknowledgement.
Do not offer another write after an exception until `load()` succeeds. The
matching wire fixture is `test/fixtures/patch_map/midi-session.json`; its bytes
must match the C++ repository fixture. Both implementations test the exact same
open/read/write exchange. Scheduler tests cover fragmented replies, endpoint
filtering, queue ordering, and interrupted writes without replay.

Lua controllers should receive immutable state and emit declarative actions
executed by the host. They must not send MIDI directly or own a competing map.
SD-card companion loading additionally needs compatibility metadata, trust and
execution isolation, and a standard-editor fallback. Expander support and
end-of-chain preset lifecycle remain separate discovery work.

Run `flutter test test/domain/patch_map/patch_map_test.dart` for the shared
format, validation, immutability, and slot preservation checks.
