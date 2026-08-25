# MCP API Guide for Disting NT

## Overview

The Disting NT MCP (Model Context Protocol) API provides individual, well-named tools for interacting with your hardware. Each tool does one thing with a flat parameter structure, making it easy for any LLM to use correctly.

### Design Philosophy

- **Individual tools**: Each tool has a single purpose with simple parameters
- **No multiplexing**: No `target` parameters to route behavior — tool name says what it does
- **Flat schemas**: Parameters are top-level, not nested inside `data` objects
- **Mapping support**: Full CV/MIDI/i2c/performance page mapping for parameter control
- **Snake_case JSON**: All response fields use snake_case for LLM compatibility

### Important: Field Naming Convention

**All JSON fields use snake_case, not camelCase.**

- Correct: `midi_channel`, `is_midi_enabled`, `cv_input`
- Incorrect: `midiChannel`, `isMidiEnabled`, `cvInput`

## Tool Reference

### Reference Tools

Any tool can return a `tool_reference` instead of a large payload. Use these tools to read or search the referenced result.

#### read_reference

Read a page from a large tool result reference.

**Parameters**:
- `reference_id` (required, string): Reference ID returned by a previous tool result.
- `offset` (optional, integer): Character offset to start reading from. Default: 0.
- `limit` (optional, integer): Maximum characters to return. Default: 8000, max: 16000.

```json
{"tool": "read_reference", "arguments": {"reference_id": "ref_123", "offset": 0, "limit": 8000}}
```

#### search_reference

Search inside a large tool result reference and return matching snippets with offsets.

**Parameters**:
- `reference_id` (required, string): Reference ID returned by a previous tool result.
- `query` (required, string): Case-insensitive text to search for.
- `start_offset` (optional, integer): Character offset to begin searching from. Default: 0.
- `limit` (optional, integer): Maximum matches to return. Default: 20, max: 50.
- `context_chars` (optional, integer): Context characters around each match. Default: 120, max: 500.

```json
{"tool": "search_reference", "arguments": {"reference_id": "ref_123", "query": "cutoff"}}
```

---

### Template Tools

#### apply_template_to_preset

Apply selected slots from a saved template to the connected device or to a saved local preset.

**Parameters**:
- `template_id` (optional, integer): Template preset id.
- `template_name` (optional, string): Alternative to `template_id`; resolved by exact match, then case-insensitive exact match.
- `slot_indices` (optional, array of integers): Template slot positions to apply. Omit to apply all slots. Duplicates are allowed.
- `target` (optional, string): `device` or `preset`. Default: `device`.
- `target_preset_id` (optional, integer): Required when `target` is `preset` unless `target_preset_name` is supplied.
- `target_preset_name` (optional, string): Alternative to `target_preset_id`.
- `insertion_offset` (optional, integer): Target slot index. Defaults to append for device mode and `0` for preset mode.
- `overwrite` (optional, boolean): Replace target slots starting at `insertion_offset` instead of inserting. Default: `false`.

```json
{
  "tool": "apply_template_to_preset",
  "arguments": {
    "template_name": "Space Kit",
    "target": "preset",
    "target_preset_name": "Live Set",
    "slot_indices": [0, 2],
    "insertion_offset": 4
  }
}
```

**Success response**:
```json
{
  "success": true,
  "target": "preset",
  "target_preset_id": 42,
  "applied_slot_count": 2,
  "inserted_slot_indices": [4, 5],
  "skipped_template_slot_indices": [],
  "warning": null
}
```

If the target would exceed the 40-slot device limit, the tool returns a structured error:

```json
{"success": false, "error": "space", "current": 39, "applied": 2, "limit": 40}
```

Device mode requires a connected Disting NT. If a device apply fails mid-operation, inspect the current device state with `show_preset`; hardware writes are not transactional.

---

### Search Tools

#### search_algorithms

Search for algorithms by name, category, description, use cases, parameter names, or port descriptions. Supports fuzzy name matching, BM25 text search across all fields, and synonym expansion for common Eurorack terminology.

**Parameters**:
- `query` (required, string): Algorithm name, partial name, category, or descriptive terms (e.g., "reverb", "pitch shifting", "clock divider", "resonance")

**Returns**: Top 10 matches sorted by relevance with GUID, name, category, and description.

**Search capabilities**:
- **Exact/fuzzy name match**: "Clock", "Oscilator" (typo-tolerant)
- **Category match**: "Filter", "Audio-IO"
- **Description keywords**: "tempo synchronization", "voltage controlled"
- **Parameter names**: "resonance", "cutoff", "feedback"
- **Synonym expansion**: "echo" finds delay algorithms, "wobble" finds modulation/LFO

```json
{"tool": "search_algorithms", "arguments": {"query": "filter"}}
```

```json
{"tool": "search_algorithms", "arguments": {"query": "echo"}}
```

```json
{"tool": "search_algorithms", "arguments": {"query": "pitch shifting"}}
```

---

#### algorithm_info

Show documentation-style metadata for a specific algorithm. This uses the same metadata source as the app's algorithm Help screen.

**Parameters**:
- `guid` (optional, string): Algorithm GUID, for example `"clck"`.
- `name` (optional, string): Algorithm name. Used if `guid` is omitted.
- `expand_features` (optional, boolean): If true, expands feature-provided parameters into the parameter list. Default: false.

Provide either `guid` or `name`.

**Returns**: Description, categories, ports, specifications, parameters, and features.

```json
{"tool": "algorithm_info", "arguments": {"guid": "clck"}}
```

```json
{"tool": "algorithm_info", "arguments": {"name": "Clock", "expand_features": true}}
```

---

#### search_parameters

Search for parameters by name within the current preset or a specific slot.
Prefer this over browsing `show_slot` pages when you already know all or part
of the parameter name.

**Parameters**:
- `query` (required, string): Parameter name (case-insensitive)
- `scope` (optional, string): "preset" (all slots) or "slot" (specific slot)
- `slot_index` (optional, integer): Slot index (0-39), required when scope is "slot"
- `partial_match` (optional, boolean): If true, find parameters containing the query. Default: false

```json
{"tool": "search_parameters", "arguments": {"query": "Cutoff", "scope": "preset"}}
```

```json
{"tool": "search_parameters", "arguments": {"query": "freq", "scope": "slot", "slot_index": 0, "partial_match": true}}
```

---

### Show Tools

#### show_preset

Show a compact preset overview: preset name and slot list with algorithm names and parameter counts. Does NOT include parameter values or mappings.

**Parameters**: None

**Returns**: Preset name and array of slot summaries.

```json
{"tool": "show_preset", "arguments": {}}
```

**Example response**:
```json
{
  "name": "My Synth",
  "slots": [
    {"slot_index": 0, "algorithm": {"guid": "vcod", "name": "Dual VCO"}, "parameter_count": 18},
    {"slot_index": 1, "algorithm": {"guid": "flt4", "name": "4-Pole Filter"}, "parameter_count": 8}
  ]
}
```

---

#### get_preset

Read the complete current preset without changing it, one bounded page at a
time. This is the safe choice for backup/export or whenever a task needs exact
current state rather than the compact overview from `show_preset`.

**Parameters**:
- `slot_offset` (optional, integer): Zero-based offset into populated slots.
  Default: 0.
- `parameter_offset` (optional, integer): Zero-based parameter offset within
  the current slot. Default: 0.
- `parameter_limit` (optional, integer): Parameters in this page. Default: 4;
  minimum: 1; maximum: 16.

**Returns**: Preset name plus compact `edit_slot_arguments` for one populated
slot and a bounded slice of its parameter values. The arguments include the
custom slot name, readable parameter names, exact current values, and enabled
CV/MIDI/i2c/performance mappings. They also include algorithm identity and its
construction specifications when those values are known.

`restore_ready` states whether the page can recreate its slot. When a preset
was loaded from the device and the firmware did not report the current values
for a required-spec algorithm, `restore_ready` is false. In that case the safe
`edit_slot_arguments` deliberately omit `algorithm`, so they can patch an
existing matching slot without triggering replacement validation. The
response also returns `algorithm_identity` and a `restore_limitation`; do not
claim that such a page is a standalone complete backup. Static ranges,
defaults, type flags, and full enum lists remain omitted; use `show_parameter`
when those inspection details are needed.

The `paging.next` object contains the exact next `get_preset` call. Follow it
until `has_more` is false; the first page is not the complete preset. Do not
modify the source preset while paging through an export, because each page
reads the current live state.

```json
{"tool": "get_preset", "arguments": {}}
```

**Example paging response**:

```json
{
  "success": true,
  "preset_name": "My Synth",
  "populated_slot_count": 3,
  "edit_slot_arguments": {
    "slot_index": 0,
    "data": {
      "name": "Lead Voice",
      "algorithm": {"guid": "vcod", "name": "Dual VCO"},
      "parameters": [
        {"parameter_number": 0, "name": "Pitch", "value": 60}
      ]
    }
  },
  "restore_ready": true,
  "slot_parameter_count": 18,
  "paging": {
    "slot_offset": 0,
    "parameter_offset": 0,
    "parameter_limit": 1,
    "count": 1,
    "total": 18,
    "has_more": true,
    "next": {
      "tool": "get_preset",
      "arguments": {
        "slot_offset": 0,
        "parameter_offset": 1,
        "parameter_limit": 1
      }
    }
  }
}
```

---

#### show_slot

Show a slot with compact, paged parameter summaries. Each parameter shows its
name and current value. Ranges, enum value lists, and full mapping details are
reserved for `show_parameter`. The `is_enum`, `is_disabled`, and `has_mapping`
flags are included only when true.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)
- `parameter_offset` (optional, integer): Zero-based parameter offset. Default: 0.
- `parameter_limit` (optional, integer): Parameters in this response. Default: 8;
  minimum: 1; maximum page size: 16. This does not limit the slot total.

```json
{"tool": "show_slot", "arguments": {"slot_index": 0, "parameter_limit": 2}}
```

**Example response**:
```json
{
  "slot_index": 0,
  "algorithm": {"guid": "vcod", "name": "Dual VCO"},
  "parameter_count": 18,
  "offset": 0,
  "limit": 2,
  "count": 2,
  "has_more": true,
  "parameters": [
    {"parameter_number": 0, "parameter_name": "Pitch", "value": 60},
    {"parameter_number": 1, "parameter_name": "Waveform", "is_enum": true, "value": "Sawtooth", "has_mapping": true, "performance_page": 1}
  ],
  "next": {
    "tool": "show_slot",
    "arguments": {"slot_index": 0, "parameter_offset": 2, "parameter_limit": 2}
  }
}
```

---

#### refresh_slot

Force one slot to be re-read from the connected NT, update nt_helper's slot
state, and return a compact refreshed slot view. Use this synchronization step
before comparing a numeric parameter with `show_screen` or an SD catalogue
reconstructed through `list_sd_directory`.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39).

```json
{"tool": "refresh_slot", "arguments": {"slot_index": 1}}
```

---

#### show_slot_metadata

Show the complete raw metadata shape currently reported by the physical device
for one slot. This read-only tool includes specification values, parameter
definitions and enum strings, pages and page memberships, and output-mode usage.
It exists for deterministic hardware validation; large responses are returned
as a `tool_reference`.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)

```json
{"tool": "show_slot_metadata", "arguments": {"slot_index": 2}}
```

---

#### show_parameter

Show a single parameter with its current and default values, range, unit,
complete enum vocabulary, disabled state, and enabled mappings. This is the
detailed inspection tool to use before an enum or mapping-sensitive edit.
Focused edit validation errors also report allowed enum labels or numeric
ranges; when that information is already present, use it directly rather than
making a redundant inspection call.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)
- `parameter` (required, integer): Parameter number (0-based index)

```json
{"tool": "show_parameter", "arguments": {"slot_index": 0, "parameter": 5}}
```

---

#### show_screen

Capture and return the current device screen as a base64 JPEG image.

**Parameters**:
- `display_mode` (optional, string): Display mode to switch to before capturing. Options: "parameter", "algorithm", "overview", "vu_meters"

```json
{"tool": "show_screen", "arguments": {}}
```

```json
{"tool": "show_screen", "arguments": {"display_mode": "overview"}}
```

---

#### list_sd_directory

Read one directory directly from the connected NT SD card. Entries retain the
exact order returned by the device; the tool does not apply the File Browser's
alphabetical or date sorting. Use `ordinal` when comparing directory traversal
against a numeric folder parameter, and recurse by calling the tool again for
entries where `is_directory` is true.

**Parameters**:
- `path` (required, string): Absolute NT SD card directory path.
- `offset` (optional, integer): Zero-based entry offset. Default: 0.
- `limit` (optional, integer): Entries to return (1-512). Default: 128.

```json
{"tool": "list_sd_directory", "arguments": {"path": "/samples/Multisamples"}}
```

The response echoes `path`, reports `order: "device_response"`, and includes an
exact `next` call when more entries remain. This is a diagnostic view of the
device response, not the folder numbering algorithm itself.

The NT sample-folder catalogue is reconstructed separately: traverse folders
depth-first, sort sibling folder names case-insensitively at each level, and
assign values only to folders that directly contain `.wav`, `.aif`, or `.aiff`
files. Once a playable folder is assigned a value, do not descend into its
subfolders. Otherwise traverse its subfolders without consuming a value;
non-sample files such as PDFs do not affect the catalogue.

---

#### show_routing

Show the current signal routing state with input/output bus assignments for all slots.

**Parameters**: None

```json
{"tool": "show_routing", "arguments": {}}
```

---

#### show_cpu

Show CPU usage for the device and per-slot usage breakdown.

**Parameters**: None

```json
{"tool": "show_cpu", "arguments": {}}
```

---

### Edit Tools

#### rename_preset

Rename and save the current preset without changing any slot, algorithm,
parameter, specification, slot name, or mapping.

**Parameters**:
- `name` (required, string): New preset name. Leading/trailing whitespace is
  removed; the resulting name must contain 1-31 characters.

```json
{"tool": "rename_preset", "arguments": {"name": "Live Set"}}
```

This operation saves automatically. Use it for a name-only change; do not
reconstruct the preset with `edit_preset` merely to rename it.

---

#### edit_preset

Replace the entire preset state including name and all slots. This is a
destructive full replacement, not a partial update.

**Parameters**:
- `data` (required, object): Full preset data with `name` and `slots` array

**Use when**: Restructuring preset, reordering algorithms, or making deliberate
bulk changes. For a name-only change, use `rename_preset`.

```json
{
  "tool": "edit_preset",
  "arguments": {
    "data": {
      "name": "Updated Preset",
      "slots": [
        {
          "algorithm": {"name": "Oscillator"},
          "parameters": [{"parameter_number": 0, "value": 1.5}]
        },
        {
          "algorithm": {"name": "Filter"},
          "parameters": [{"parameter_number": 2, "value": 0.8}]
        }
      ]
    }
  }
}
```

---

#### edit_slot

Edit and save a specific slot: change algorithm, set parameters, or rename.
Repeating the GUID already instantiated in the slot is a patch and does not
require its construction specifications. A successful response reports
`persisted: true`.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)
- `data` (required, object): Slot data with optional `algorithm`, `parameters`, and `name`

**Use when**: Changing algorithm in single slot, updating all parameters for one algorithm.

```json
{
  "tool": "edit_slot",
  "arguments": {
    "slot_index": 0,
    "data": {
      "algorithm": {"name": "Wavetable Oscillator"},
      "parameters": [
        {
          "parameter_number": 0,
          "value": 1.0,
          "mapping": {
            "midi": {
              "is_midi_enabled": true,
              "midi_channel": 0,
              "midi_type": "cc",
              "midi_cc": 74
            }
          }
        }
      ]
    }
  }
}
```

---

#### edit_parameter

Edit and save a single parameter value and/or mapping. A successful response
reports `persisted: true`.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)
- `parameter` (required, string or integer): Parameter name or number (0-based)
- `value` (optional, number): Parameter value (omit to update only mapping)
- `mapping` (optional, object): CV/MIDI/i2c/performance page mapping

**Use when**: Quick tweaks, mapping updates, individual value changes.

```json
{
  "tool": "edit_parameter",
  "arguments": {
    "slot_index": 0,
    "parameter": "Cutoff Frequency",
    "value": 0.65,
    "mapping": {
      "cv": {
        "source": 1,
        "cv_input": 3,
        "is_unipolar": false,
        "is_gate": false,
        "volts": 100,
        "delta": 50
      }
    }
  }
}
```

---

### Preset Management Tools

#### new

Create a new blank preset or preset with initial algorithms. WARNING: Clears current preset.

**Parameters**:
- `name` (required, string): Name for the new preset
- `algorithms` (optional, array): Array of `{name: string}` or `{guid: string}` to add

```json
{"tool": "new", "arguments": {"name": "My Preset"}}
```

```json
{
  "tool": "new",
  "arguments": {
    "name": "Audio Chain",
    "algorithms": [
      {"name": "Low-Pass Filter"},
      {"name": "Delay"},
      {"name": "Reverb"}
    ]
  }
}
```

---

#### save

Save the current preset to the device.

**Parameters**: None

```json
{"tool": "save", "arguments": {}}
```

---

#### add

Add an algorithm to the preset. Inserts without replacing existing algorithms.

**Parameters**:
- `target` (required): Must be "algorithm"
- `name` (optional, string): Algorithm name (fuzzy matching)
- `guid` (optional, string): Algorithm GUID (exact match)
- `slot_index` (optional, integer): Target slot (0-39). Omit for first empty slot.

```json
{"tool": "add", "arguments": {"target": "algorithm", "name": "Dual VCO"}}
```

```json
{"tool": "add", "arguments": {"target": "algorithm", "slot_index": 3, "guid": "vcod"}}
```

---

#### remove

Remove the algorithm from a slot, leaving it empty.

**Parameters**:
- `target` (required): Must be "slot"
- `slot_index` (required, integer): Slot index to clear (0-39)

```json
{"tool": "remove", "arguments": {"target": "slot", "slot_index": 3}}
```

---

## Workflow Examples

### Workflow 1: Creating a Simple Preset

1. Create preset with algorithms:
```json
{"tool": "new", "arguments": {"name": "Simple Audio Chain", "algorithms": [{"name": "Low-Pass Filter"}, {"name": "Reverb"}]}}
```

2. Verify state:
```json
{"tool": "show_preset", "arguments": {}}
```

---

### Workflow 2: Modifying a Parameter with MIDI Control

1. View current parameter:
```json
{"tool": "show_parameter", "arguments": {"slot_index": 0, "parameter": 2}}
```

2. Update parameter with MIDI mapping:
```json
{
  "tool": "edit_parameter",
  "arguments": {
    "slot_index": 0,
    "parameter": "Cutoff",
    "value": 0.65,
    "mapping": {
      "midi": {
        "is_midi_enabled": true,
        "midi_channel": 0,
        "midi_type": "cc",
        "midi_cc": 74
      }
    }
  }
}
```

3. Verify mapping:
```json
{"tool": "show_parameter", "arguments": {"slot_index": 0, "parameter": 2}}
```

---

### Workflow 3: Exploring Algorithms

1. Search:
```json
{"tool": "search_algorithms", "arguments": {"query": "Delay"}}
```

2. Add to preset:
```json
{"tool": "add", "arguments": {"target": "algorithm", "name": "Ping Pong Delay"}}
```

---

### Workflow 4: Performance Page Organization

1. Assign parameters to performance pages:
```json
{"tool": "edit_parameter", "arguments": {"slot_index": 0, "parameter": "Cutoff Frequency", "mapping": {"performance_page": 1}}}
```

```json
{"tool": "edit_parameter", "arguments": {"slot_index": 0, "parameter": "Resonance", "mapping": {"performance_page": 1}}}
```

```json
{"tool": "edit_parameter", "arguments": {"slot_index": 1, "parameter": "Level", "mapping": {"performance_page": 2}}}
```

2. Verify:
```json
{"tool": "show_preset", "arguments": {}}
```

---

## Mapping Reference

### CV Mapping

For hardware control voltage integration and internal modulation.

Fields:
- `source`: Output index from another algorithm (0=not used)
- `cv_input`: Physical input (0=disabled, 1-12=inputs)
- `is_unipolar`: True for 0-10V, false for +/-5V
- `is_gate`: Gate/trigger mode
- `volts`: Scaling factor (0-127)
- `delta`: Sensitivity/responsiveness

```json
{"mapping": {"cv": {"source": 1, "cv_input": 3, "is_unipolar": false, "is_gate": false, "volts": 100, "delta": 50}}}
```

### MIDI Mapping

For MIDI controller and DAW integration.

Fields:
- `is_midi_enabled`: Boolean (required!)
- `midi_channel`: 0-15 (where 0=MIDI Channel 1, 15=MIDI Channel 16)
- `midi_type`: "cc", "note_momentary", "note_toggle", "cc_14bit_low", "cc_14bit_high", "pitch_bend", "channel_pressure"
- `midi_cc`: CC number (0-127); ignored for pitch bend/channel pressure; legacy mappings may use 128 for aftertouch
- `is_midi_symmetric`: Symmetric scaling around center
- `is_midi_relative`: Incremental changes
- `midi_min`/`midi_max`: Scaling range

```json
{"mapping": {"midi": {"is_midi_enabled": true, "midi_channel": 0, "midi_type": "cc", "midi_cc": 74, "midi_min": 0, "midi_max": 127}}}
```

### i2c Mapping

For external i2c control modules.

Fields:
- `is_i2c_enabled`: Boolean
- `i2c_cc`: CC number (0-255)
- `is_i2c_symmetric`: Symmetric scaling
- `i2c_min`/`i2c_max`: Scaling range

```json
{"mapping": {"i2c": {"is_i2c_enabled": true, "i2c_cc": 50, "i2c_min": 0, "i2c_max": 127}}}
```

### Performance Page

Assign parameters to hardware performance pages (1-30, 0=not assigned).

```json
{"mapping": {"performance_page": 1}}
```

---

## Troubleshooting

### Common Mistakes

1. **Using camelCase instead of snake_case**
   - Wrong: `{"midiChannel": 0}`
   - Right: `{"midi_channel": 0}`

2. **Missing is_midi_enabled flag**
   - Wrong: `{"mapping": {"midi": {"midi_cc": 74}}}`
   - Right: `{"mapping": {"midi": {"is_midi_enabled": true, "midi_cc": 74}}}`

3. **Wrong MIDI channel numbering** (0-indexed)
   - MIDI Channel 1 = `"midi_channel": 0`
   - MIDI Channel 16 = `"midi_channel": 15`

4. **Confusing cv_input with source**
   - `source`: Output index from another algorithm
   - `cv_input`: Physical hardware input (1-12)

5. **Forgetting nested structure for mappings**
   - Wrong: `{"mapping": {"is_midi_enabled": true}}`
   - Right: `{"mapping": {"midi": {"is_midi_enabled": true}}}`

### Ambiguous Parameter Names

Multi-channel algorithms may have duplicate parameter names. Use parameter number instead of name:

```json
{"tool": "edit_parameter", "arguments": {"slot_index": 0, "parameter": 4, "value": 3}}
```

The `show_slot` and `show_parameter` tools always return both `parameter_name` and `parameter_number`.

---

## Specifications and Multi-Channel Algorithms

Some algorithms support **specifications** that modify their behavior (e.g., channel count). When creating with `new` or `edit_slot`, include specifications in the algorithm object:

```json
{"algorithm": {"name": "Clock Divider", "specifications": [2]}}
```

The `show_slot` response includes specifications in the algorithm data so you can see how an algorithm was instantiated.

---

## Progressive Disclosure Workflow

The show tools are designed for progressive disclosure — start broad, drill down only where needed.

### Step 1: Get the overview
```json
{"tool": "show_preset", "arguments": {}}
```
Returns algorithm names and parameter counts per slot. No parameters fetched.

### Step 2: Drill into a slot
```json
{"tool": "show_slot", "arguments": {"slot_index": 0}}
```
Returns parameter summaries (name, current value, range). If the result is large, it returns a `tool_reference`; use `read_reference` or `search_reference` to inspect it.

### Step 3: Inspect a specific parameter before editing
```json
{"tool": "show_parameter", "arguments": {"slot_index": 0, "parameter_number": 1}}
```
Returns full detail: `valid_enum_values` for enums, complete mapping configuration.

---

## Related Documentation

- **[MCP Mapping Guide](./mcp-mapping-guide.md)**: Complete mapping field documentation
- **[Architecture Document](./architecture.md)**: MCP server implementation details

---

## Migration from Previous API

| Previous Tool | New Tool |
|--------------|----------|
| `search` target="algorithm" | `search_algorithms` |
| `search` target="parameter" | `search_parameters` |
| `show` target="preset" | `show_preset` |
| `get_current_preset` | `get_preset` |
| `show` target="slot" | `show_slot` |
| `show` target="parameter" | `show_parameter` |
| `show` target="screen" | `show_screen` |
| `show` target="routing" | `show_routing` |
| `show` target="cpu" | `show_cpu` |
| `edit` target="preset" | `edit_preset` |
| `set_preset_name` | `rename_preset` |
| `edit` target="slot" | `edit_slot` |
| `edit` target="parameter" | `edit_parameter` |
| `new` | `new` (unchanged) |
| `save` | `save` (unchanged) |
| `add` | `add` (unchanged) |
| `remove` | `remove` (unchanged) |

---

**Last Updated**: 2026-08-23
**MCP Library**: mcp_dart 1.2.2
