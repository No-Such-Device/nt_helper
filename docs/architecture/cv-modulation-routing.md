# CV modulation in routing views

`core/routing/cv_modulation.dart` projects cached `Slot.mappings` into
`CvModulation` records. These are deliberately separate from ordinary
`Port`/`Connection` objects: inspecting or selecting a modulation must not
clear a parameter, toggle Add/Replace, assign a bus, or reorder slots.

## Meaning

- `cvInput == 0`: no configured CV relation, even if another mapping is enabled.
- Source `0`: the destination algorithm's input bus snapshot.
- Source `1`: original module physical inputs.
- Source `2 + slotIndex`: that real preset slot's output bus snapshot.
- Versions 1–3 imply source `0`.
- Bus numbers and labels come from `DeviceIoProfile`. For the extended standard
  profile, Aux 12/13 are buses 32/33.

The projection resolves preceding Add/Replace contributors at that snapshot,
including hardware input seeds. It does not assume the selected algorithm is
the only writer. Multiple Add writers in one slot are order-independent; a later
single Replace starts a new known session even after an ambiguous older one.
Mixed or multiple-Replace same-slot write ordering, later/missing selected slots,
invalid buses and contradictory mapping identities retain an inspectable
bus/snapshot relation without inventing an algorithm cable. Contributor
attribution is labelled inferred, not measured. The shared records include each
resolved producer's real slot, algorithm and port name for inspection,
accessibility and the cached API. Disabled parameters and zero
mapping depth remain configured topology, not evidence of effective modulation.

Mapping storage is positional. Parameter numbers, page-qualified names and
fallback names are kept separately from ordinary routing-port identity.
GUID-occurrence render IDs are rebuilt from the unfiltered real slot roster;
they are not persisted device-instance identity across duplicate reorders.

## Presentation and refresh

`RoutingAlgorithm.cvModulations` supplies the canvas, Bus Lanes, signal-flow
matrix and accessible list. Cached MCP `show_routing` uses the same projection,
returning per-slot `cv_modulation` records and mapping-coverage diagnostics.
No new MIDI reads, polling, database or fetch service is involved.

The canvas uses existing cards/curves, green lines, diamond endpoints and a
`CV → parameter` label. Multiple targets remain separate records; the compact
label's count opens an inspect-only list of every target. Bus Lanes uses green
CV markers at the bus/algorithm boundary; the matrix uses CV markers/counts.
The accessible list exposes the same full target/bus/snapshot descriptions.
Green is theme-managed and contrast-adjusted, with text/shape/semantics so color
is not the only distinction.

All slot presentation positions exist before late mapping responses arrive.
Mapping updates do not add per-parameter node rows or rerun layout. Newly seen
Bus Lanes buses append while that roster is displayed, keeping existing lane
coordinates fixed. Inspector content follows the current immutable state;
removed targets become unavailable without resizing the dialog. Inspection
clears any previous ordinary cable/bead selection before keyboard Delete.

## Mutation safety and limits

Known mapped buses (including zero-depth/disabled/invalid-source mappings)
are reserved during free-bus allocation and excluded from both sides of AUX
consolidation/moves. Incomplete mapping coverage cannot authorize these
optimizations. Known `unit == -1` nonmappable parameters need no mapping reply;
unknown metadata and missing/failed mappable replies remain incomplete.
Consolidation revalidates a queued plan and current mappings before writes.
Automatic connection creation refuses actual mapped-bus writer changes, but
allows reader-only fanout from unchanged Replace or mode-less writers without
sending redundant mode writes.

Shared slot-move entry points permit complete, validated Module-input-only
mappings on physical input buses: their original-input snapshot has no algorithm
source identity to retarget. Other configured CV snapshots, invalid source/bus
pairs and incomplete coverage remain conservatively blocked. Raw user-directed
moves without any known CV mappings retain their existing workflow; automatic
routing optimizations always require complete mapping evidence. MCP composite
insert/reorder/notes operations preflight before their first mutation; ordinary
parameter-only preset edits remain available. UI rejection uses error feedback,
not a partial optimistic reorder. This feature does not migrate mappings during
user-directed preset changes, and does not promise isolation from simultaneous
external device edits.

The user's actual preset and hardware have not been inspected or modified.
Tests cover synthetic Aux 12/13 mappings, source variants, real-slot gaps,
fanout/multiwriters, cached API/view parity, mutation guards, and stable geometry.

## Design provenance

The pstack ground research informed this implementation. The arenas did not
produce a terminal verified design report; the second run stopped on quota.
The owner subsequently authorized this minimal incumbent-style extension.
No arena approval or live-voltage validation is claimed.
