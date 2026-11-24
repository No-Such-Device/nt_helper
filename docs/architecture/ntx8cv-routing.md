# NTX-8CV routing

`core/routing/ntx8cv_routing.dart` derives one eight-jack sink from the connected
NT's observed Module Settings. It does not configure or connect to the NTX.

## Supported scope

This first implementation supports **one NTX on Channel Group 1–8**. The owner
confirmed that configuration. The NT does not report the NTX's independent
Channel Group: this is an explicit supported/default-group convention, not
hardware autodetection. The graph title is `NTX-8CV`; its tooltip, the model
scope label and cached API retain the first-channel-group qualification.

The observed NT 1.20.0beta hierarchy is Menu / Settings / Engine / NTX-8CV.
Groups, setting IDs and the Mode enumeration are matched from the discovered
schema, not numeric setting IDs. Fixture IDs intentionally differ from capture.
Only confirmed/observed values are used; drafts do not alter routing.

- CV (8x8): transmit channels 1–8 map to AUX 1–8. Bits 0–7 enable their fixed
  jack positions. A sparse mask does not pack channels into earlier jacks.
- Audio 32 bit (1x8): all eight transmit channels map to AUX 1–8.
- Audio 16 bit (2x8): the supported first group also receives AUX 1–8. The
  independently selected second audio bank is outside this feature's scope.
- Audio output enables live on the NTX, not in the NT CV mask. Audio ports
  indicate transmitted routes; their local audio enable is not detected.

The standard extended profile maps AUX 1–8 to global buses 21–28. Other bus
profiles and unrecognized metadata/mode schemas fail closed. `DeviceIoProfile`
is unchanged: no new buses or native physical outputs are invented. The eight
stable `ntx8cv_out_N` ports have an explicit read-only expander-sink role.

## Lifecycle and presentation

The existing DistingCubit Module Settings delegate owns connection-local state.
Opening routing requests its existing bounded/coalesced load once per supported
session. A hidden routing view in SynchronizedScreen's IndexedStack does not
initiate discovery. Settings-only emissions invalidate routing even with
identical slots. View changes reuse the cache; there is no polling or new service.
The existing Refresh Routing action refreshes settings after discovery has been
requested. Cached `show_routing` never discovers or refreshes settings.

The Canvas reuses the movable physical-output renderer and existing cable
renderer and ES-5 intrinsic header sizing. Bus Lanes and Signal Flow share one
circle-and-number assignment row immediately below the bottom AUX bus labels,
inside the scrolled content. There are no stems crossing those labels and no
separate footer/legend. Accessible List exposes the same eight-port configuration. Ports
remain in place when disabled or during same-session reads/uncertain writes;
uncertain routes are not presented as active. Supported connections start with
an explicitly unresolved configuration, never an assumed unused first group.
Disconnect, offline/demo, old firmware and new connections cannot retain
authoritative old-device routes. Signal Flow reserves its endpoint area before
discovery, including when content is hidden, so the viewport and headers do not
move on initial completion or failure.

Per-slot cached API records gain `ntx8cv_outputs` for that slot's active output
bus taps. Slot-list shape and the empty-preset `[]` response are unchanged. The
API reports first-group scope and does not claim hardware presence.

## Mutation safety

Tap edges are derived, not independently editable cables. They cannot be
created/deleted by dragging, Delete, or ordinary bus-port actions. Tap cable
labels have no output-mode callback or interactive overlay; the source port's
own ordinary mode editing remains available. Algorithm bus
assignments remain editable through existing controls. No setting/mode/mask
write, flash action, reset, reboot or direct NTX request is triggered by routing.

Configured tap buses join CV-reserved buses for AUX allocation, consolidation,
bus moves and smart deletion. While a supported first-group configuration is
unresolved (including initial discovery, failed reads or reconnect), AUX 1–8
remain conservatively reserved without claiming active routes. Confirmed unused
channels can be reused; old unsupported firmware keeps its legacy allocation.
Automatic assignments validate both endpoint ranges before their first write,
so firmware clamping cannot redirect an allocated bus onto a protected channel.
Reader-only fanout is retained where no writer bus or mode changes.

Move guards compare the actual proposed slot permutation. They reject changed
relative writer order involving Replace or changed writer/reader ordering on
protected buses, not unrelated slot moves. Add-only pairs can commute. Existing
CV snapshot protections remain unchanged. Composite operations without a known
permutation retain conservative checks. Disabled channels are not
reported as active voltages; their actual analog behavior is unspecified.

## Sources and limits

- Official NT 1.19 manual, pp. 52–53: fixed transmit-channel order and mode rules.
- Official NTX-8CV 1.1 manual, pp. 40–41: local mode/enables and channel groups.
- Os' NT preset editor `82c23673b7e63371df60a59951ab13182cf703ca`:
  dynamic settings discovery and little-endian 64-bit mask encoding.
- Os' NTX configurator `6addf424c454aac20b26661d00384e6292401b18`: the existing
  app already implements its latest local-settings protocol; no protocol update
  was needed here. NT product `0x6D` settings are not NTX product `0x6A` settings.
- Sanitized existing-session catalogue captured 2026-11-24: NT Mode enum and
  Channel enables Bits64 metadata; cached CV mode and mask `0xff`.

No hardware queries, edits, application restart or live voltage validation were
performed for implementation. Cached values are last observed, not telemetry or
proof of flash persistence. Wayfinder research informed the feature; the pstack
route failed on quota before classification and is not claimed as successful.
