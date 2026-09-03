# Preserve MIDI learn and mapping-editor boundaries

Status: Accepted

## Context

MIDI Learn must classify controller input without requiring the user to choose
a message type first. Mapping rows also need to show which editor is open
without conflating that temporary UI state with persisted mapping state.

## Decision

- `MidiListenerCubit` delegates classification to the pure
  `MidiDetectionEngine`.
- The engine automatically distinguishes ordinary CC, standard paired 14-bit
  CC, notes, pitch bend, channel pressure, and supported NRPN messages.
- Ordinary and paired CC detection uses a ten-event sliding buffer; toggle CC
  values can resolve after four events. Standard 14-bit pairs are CC numbers 32
  apart with the lower member below 32. The first member observed determines
  the `cc14BitLowFirst` or `cc14BitHighFirst` variant.
- Mapping-editor open state stays local to `MappingEditButton`. A tertiary
  border represents the open editor; the mapped background continues to
  represent persisted mapping state.
- The button keeps its fixed geometry while the temporary border changes.

## Consequences

Adding MIDI message types belongs in the detection engine and its focused tests,
not as parallel classification in widgets. Mapping-editor lifecycle or styling
changes must preserve the distinction between open and mapped state.

Current contracts are exercised by
`test/ui/midi_listener/midi_detection_engine_test.dart` and
`test/ui/widgets/mapping_edit_button_highlight_test.dart`.
