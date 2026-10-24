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

### Remote Controls

For operating the hardware through screen-feedback navigation, held gestures,
and context-sensitive controls, see the [agent remote-control tutorial](mcp-remote-control-tutorial.md).

External MCP and built-in chat share these tools and the UI's remote-control
transport. They require a synchronized live connection with recognized firmware
1.19 or newer and a transport supporting remote input. Offline and demo modes
cannot send remote commands.

`remote_state` takes no arguments. It reports availability, control mappings, and
local commanded pot/hold state. This is not hardware readback or confirmation of
the hardware's current screen, parameter values, or audio.

`remote_control` takes an ordered `actions` array. Pot indices are 0–2 (left,
center, right), with values 0–4095. Encoder indices are 0–1 (left, right), with
signed `delta` values. Push/release indices are 0–3 for Buttons 1–4, 4–6 for the
three pots, and 7–8 for the two encoders.

Set the left pot:

```json
{"tool":"remote_control","arguments":{"actions":[{"type":"pot_turn","index":0,"value":1024}]}}
```

Turn the left encoder while holding it:

```json
{"tool":"remote_control","arguments":{"actions":[{"type":"push","index":7},{"type":"encoder_turn","index":0,"delta":2},{"type":"release","index":7}]}}
```

Put a complete held combination in one call. Outstanding presses are released
at the end, on cancellation, or after an error while the original transport is
available; holds do not persist across calls. A disconnected device cannot
acknowledge release, so an unknown release outcome must not be described as a
confirmed hardware state. `actions_completed` counts processed actions, including
waits and no-ops, rather than hardware packets. Remote gestures do not save the
preset automatically; use `save` when persistence is intended. Observe navigation
with `show_screen({})`, which accepts no arguments and never switches display
mode. Use `remote_control` for menu navigation.
Gesture size, encoder movement, and waits are bounded,
and the complete sequence is validated before any command is sent. An active UI
remote session must finish before a tool can acquire the controls.

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
flags are included only when true. The response also includes the complete
`visual_style`, so a caller can restore the overview display style after
temporary render comparisons.

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
  "visual_style": {
    "left_indent": 0,
    "right_indent": 0,
    "line_above": false,
    "line_below": false,
    "bracket": "none"
  },
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

Wake the display and capture its current screen as a base64 PNG image.
Takes no arguments; it preserves display mode and menu position. For menu
navigation, send button/encoder gestures with `remote_control`, then capture.

```json
{"tool": "show_screen", "arguments": {}}
```

#### set_display_mode

Explicitly switch to a hardware display view. This can dismiss menus, so use it
only when the user requests a view change, not as a navigation or screenshot tool.

**Parameters**:
- `mode` (required): "parameter", "algorithm", "overview", or "vu_meters".

```json
{"tool": "set_display_mode", "arguments": {"mode": "overview"}}
```

Success means transport send only, not acknowledged hardware execution. Capture
separately with `show_screen({})` to inspect the result.

**Compatibility:** `show_screen(display_mode: ...)` is no longer accepted. Its
observation and mutation behaviors were separated to prevent screenshot requests
from repeatedly resetting menu navigation.

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

#### set_algorithm_visual_style

Set the complete overview display style for one populated algorithm slot. On a
connected NT this requires firmware 1.18 or newer. The edit is applied
immediately and marks the preset as modified, but does not save it.

**Parameters**:
- `slot_index` (required, integer): Slot index (0-39)
- `left_indent` (required, integer): Left indent (0-15)
- `right_indent` (required, integer): Right indent (0-15)
- `line_above` (required, boolean): Draw the upper connecting line
- `line_below` (required, boolean): Draw the lower connecting line
- `bracket` (required, string): `none`, `open`, `close`, `line`, or
  `open_and_close`

Send the complete style on every call. Read the current value with `show_slot`
before a temporary comparison so it can be restored afterward.

```json
{
  "tool": "set_algorithm_visual_style",
  "arguments": {
    "slot_index": 0,
    "left_indent": 2,
    "right_indent": 0,
    "line_above": true,
    "line_below": true,
    "bracket": "open"
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

### Plugin Tools

#### install_plugin

Install a C++ plug-in (`.o`) or Lua script (`.lua`) from the computer running
nt_helper onto the connected Disting NT SD card, then verify what the device
reports. This replaces copying the file by SD card or with `ntpush`.

- `.o` files are written to `/programs/plug-ins/<name>.o`. The NT is told to
  rescan plug-ins, and the algorithm list is re-read (up to 5 times, 1 s apart)
  until every GUID declared in the local `.o` appears.
- `.lua` files are written to `/programs/lua/<name>.lua`. Lua scripts are not
  algorithms, so they are verified by SD directory listing only. Select the
  script with the Program parameter of a Lua Script slot.
- An existing file with the same name is overwritten.
- If the `.o` being replaced is used by the current preset, the preset is
  cleared so the NT releases the file, and reloaded afterwards from its last
  saved copy on the SD card. Call `save` first to keep unsaved edits.

**Pre-upload checks**: these run on the local file and the synchronized
algorithm list before anything is sent to the device.

- A `.o` must be a 32-bit little-endian ARM (`EM_ARM`) relocatable (`ET_REL`)
  ELF object that defines `pluginEntry` (what `NT_DECLARE_PLUGIN` emits) and
  at least one factory GUID nt_helper can read. Factories are recognised by the
  symbol names `factory` (static or not) and `<Class>::Factory`, and their first
  four bytes must be a printable GUID.
- No GUID in the `.o` may already belong to a built-in algorithm, or to a
  plug-in that the device reports from a different file. Reinstalling the same
  file (compared case-insensitively, relative to `/programs/plug-ins/`) is
  allowed. If the device lists the GUID as a plug-in but does not report its
  file, the install goes ahead and the GUID is listed in `unattributed_guids`.
- A `.lua` must be valid UTF-8 and contain no NUL bytes. It is not parsed.

**Requirements**:
- A live, synchronized connection. Offline and demo mode are refused.
- Firmware with SD card support (1.10 or later).
- The file must be inside an allowed root that grants MCP read permission, the
  same roots `list_allowed_roots`, `list_files`, and `read_file` use. Roots are
  configured in nt_helper Settings. Symlinks and `..` cannot leave a root.
- At most 2 MiB (2,097,152 bytes). Uploads use 512-byte SysEx chunks and run at
  roughly 5-10 KB/s, so a 500 KB plug-in takes about a minute. The tool's own
  timeout is 10 minutes; raise your MCP client's tool-call timeout if it is
  shorter.

**Parameters**:
- `path` (required, string): Absolute local path ending in `.o` or `.lua`
  (case-insensitive). The file name is kept on the SD card.
- `load` (optional, boolean): `.o` only. After the rescan, load every algorithm
  found for the file. Default: `false`. Rejected for `.lua`.

```json
{"tool": "install_plugin", "arguments": {"path": "/Users/me/nt-builds/myfilter.o", "load": true}}
```

Result for a verified `.o` install:

```json
{
  "success": true,
  "plugin_type": "cpp",
  "source_path": "/Users/me/nt-builds/myfilter.o",
  "destination_path": "/programs/plug-ins/myfilter.o",
  "bytes_written": 183204,
  "file_present": true,
  "verified": true,
  "preset_reloaded": false,
  "root_duplicate": {"status": "not_applicable"},
  "rescan_attempts": 1,
  "expected_guids": ["MyFl"],
  "missing_guids": [],
  "unattributed_guids": [],
  "algorithms": [
    {"guid": "MyFl", "name": "My Filter", "is_loaded": false}
  ],
  "load_results": [
    {"guid": "MyFl", "loaded": true}
  ],
  "message": "Uploaded 183204 bytes to /programs/plug-ins/myfilter.o. Rescan found: My Filter (MyFl). Loaded 1 algorithm(s)."
}
```

`algorithms[].is_loaded` is the state reported by the rescan, before any load;
`load_results` (present only when `load` was requested) is the outcome of
loading each one.

Result for a `.lua` install:

```json
{
  "success": true,
  "plugin_type": "lua",
  "source_path": "/Users/me/nt-builds/arp.lua",
  "destination_path": "/programs/lua/arp.lua",
  "bytes_written": 2310,
  "file_present": true,
  "verified": true,
  "preset_reloaded": false,
  "root_duplicate": {"status": "not_applicable"},
  "message": "Uploaded 2310 bytes to /programs/lua/arp.lua. The file is listed on the SD card."
}
```

**Result fields**:
- `verified`: `.o` — at least one algorithm was found and no expected GUID is
  missing. `.lua` — the SD listing shows the file with the uploaded size.
  When a rebuild replaces a plug-in with the same GUIDs, `verified` confirms
  the GUIDs are still listed after the rescan; it cannot tell the new build
  from the old one.
- `file_present`: the destination directory lists the file with the uploaded
  size; `null` if the listing could not be read.
- `unattributed_guids`: GUIDs that an installed plug-in already used before
  the upload, where the device did not say which file provides them, so a
  collision could not be ruled out. Usually empty.
- `missing_guids`: GUIDs read from the local file that the device never
  reported. A plug-in that fails to load on the NT (for example an API
  mismatch) shows up here; check the device screen with `show_screen`.
- `root_duplicate.status`: `not_applicable`, `removed`, `deletion_failed`, or
  `kept_unverified` — cleanup of a same-GUID copy in the plug-ins root, which
  only applies to installs into a subfolder.

An upload that completes but cannot be verified still returns
`"success": true` with `"verified": false` and a `message` that says what is
missing:

```json
{
  "success": true,
  "plugin_type": "cpp",
  "verified": false,
  "rescan_attempts": 5,
  "expected_guids": ["MyFl"],
  "missing_guids": ["MyFl"],
  "algorithms": [],
  "message": "Uploaded 183204 bytes to /programs/plug-ins/myfilter.o. No algorithm for this file appeared after 5 rescan check(s). Check the device screen for a load error, or call search_algorithms later."
}
```

**Errors**: `success` is `false`, `error` is a snake_case code, and `message`
explains it. Nothing is sent to the device for any error except
`install_failed`. File checks run first, then the connection checks, then the
GUID collision check. The collision check needs the device's full algorithm
list, so for a `.o` file the tool first waits up to 10 seconds for any
background algorithm-list load to finish; if it is still loading, the tool
refuses with `algorithm_library_loading` without uploading.

| `error` | Cause |
|---|---|
| `missing_path` | `path` absent or blank |
| `invalid_load` | `load` is not a boolean |
| `unknown_argument` | an argument other than `path` or `load` |
| `unsupported_extension` | not `.o` or `.lua` |
| `load_not_supported` | `load: true` with a `.lua` file |
| `absolute_path_required` | `path` is relative |
| `path_outside_allowed_root` | not inside a root with MCP read permission, or escapes one via `..` or a symlink |
| `file_not_found` | inside a root, but no such file |
| `empty_file` | the file has zero bytes |
| `file_too_large` | over 2 MiB; also returns `size` and `max_bytes` |
| `invalid_elf` | a `.o` that is not a readable ELF file |
| `wrong_architecture` | a `.o` that is not 32-bit little-endian `EM_ARM` |
| `not_relocatable` | a linked `.o` (`ET_EXEC`/`ET_DYN`); the NT needs `ET_REL` |
| `missing_plugin_entry` | a `.o` that does not define `pluginEntry` |
| `no_guid` | a `.o` with no factory GUID nt_helper can read |
| `guid_collision` | a GUID already used by a built-in algorithm or by a plug-in from another file; also returns `guid`, `existing_name`, `existing_kind` (`built_in` or `plugin`), and `existing_path` |
| `algorithm_library_loading` | the algorithm list was still loading from the device after 10 seconds, so collisions could not be checked; retry shortly |
| `invalid_lua` | a `.lua` that is not UTF-8 or contains a NUL byte |
| `invalid_file_name` | the name cannot be used on the SD card |
| `not_connected` | no synchronized device |
| `offline_mode` | nt_helper is in offline mode |
| `demo_mode` | nt_helper is in demo mode |
| `sd_card_unsupported` | firmware older than 1.10 |
| `install_failed` | the upload failed partway; `message` has the device error |

```json
{"success": false, "error": "demo_mode", "message": "Demo mode has no device to install to. Connect a Disting NT."}
```

```json
{"success": false, "error": "guid_collision", "message": "GUID MyFl is already used by My Filter from /programs/plug-ins/old/myfilter.o. Give this plug-in a unique GUID, or delete the other file.", "guid": "MyFl", "existing_name": "My Filter", "existing_kind": "plugin", "existing_path": "/programs/plug-ins/old/myfilter.o"}
```

```json
{"success": false, "error": "file_too_large", "message": "/Users/me/big.o is 3145728 bytes; the limit is 2097152 bytes.", "size": 3145728, "max_bytes": 2097152}
```

**Reloading a rebuilt plug-in**: there is no separate `reload_plugin` tool.
Call `save`, then `install_plugin` with the rebuilt file. If the plug-in is in
use, the preset is reloaded from the saved copy, which restores its slots and
parameter values. For a Lua script in use, reinstall it and then select the
script again from the slot's Program parameter.

**Testing after install**: to check that an installed plug-in loads, answers,
and stays within a CPU budget, call [`smoke_test_plugin`](#smoke_test_plugin)
after `install_plugin` with `load: true`.

#### smoke_test_plugin

Smoke-test an installed plug-in on the connected Disting NT, then put the
preset back the way it was.

1. If the plug-in is not loaded, load it. If it does not report loaded, the
   tool stops with `load_failed` and the preset is unchanged.
2. Validate specification counts/ranges and confirm the hardware slot count
   and GUID lineup against the app snapshot. A stale or unconfirmed snapshot
   is refused with `preset_changed`, before adding anything. Append the
   plug-in as a new slot at the **end** of the current preset, and
   wait for the device to confirm that the slot count went up. Slots are only
   ever appended, so the existing slots keep their positions.
3. Wait `settle_ms`.
4. Check that the new slot answers with the plug-in's GUID and reports at
   least one parameter. With `expected_parameter_count` the count must match
   exactly; with `expected_parameter_names` the first parameters must have
   those names, in order.
5. Sample CPU `cpu_samples` times, 250 ms apart. The test slot's highest
   sample must not exceed `cpu_budget_percent`. With `max_core_percent`, the
   higher of the two cores in each sample must not exceed it either.
6. Remove the test slot and confirm the original slot lineup (slot count and
   each slot's GUID) with the device. With `keep: true` and every check
   passed, the slot stays instead. Before removal, verify that the original
   slots and the cleanup target still belong to this test. An unexpected GUID,
   structural edit or connection change stops positional cleanup and reload;
   the result reports `rollback: failed` rather than deleting an unrelated slot.

Only one smoke test may run at a time (`smoke_test_busy`). Avoid editing the
preset during the test. App-side edits and observed hardware parameter changes
are treated as unsaved changes, even when the preset started clean. Successful
cleanup preserves their dirty status; an automatic reload is not allowed to
silently discard them.

**The preset is never saved.** Saving would write the current preset,
including any unsaved edits, over its file on the SD card, so the tool
removes the slot it added instead. When every check passed and `keep` is set,
the slot stays in the running preset only. Call `save` yourself to keep it.

**When the slot cannot be removed** (the device does not confirm the removal
within 5 s, or the lineup does not match afterwards), the tool falls back to
reloading the preset's last saved copy, `/presets/<preset name>.json`:

- With no pre-existing or observed intervening edits, the reload happens
  automatically.
- With unsaved edits, it happens only with `reload_saved_on_failure: true`.
  After the reload, if the slot lineup matches the one before the test, the
  parameter values from before the test are written back
  (`restored_parameter_values`). The snapshot is from before the test: later
  parameter edits and other unsaved edits, such as mappings and renames, are
  lost. A structural/connection conflict detected during the test blocks reload
  even with opt-in; inspect the live preset rather than overwriting it.
- Otherwise the slot stays where it is, `rollback` is `failed`, and
  `rollback_error` says what to do: remove the slot on the device, or allow
  the reload.

If the plug-in crashes the device, nothing can be undone over MIDI. The
result reports `device_unresponsive` and, unless the reload worked,
`rollback: "failed"`. After a power cycle the NT starts with the last saved
preset, so the test slot is gone, and so are any unsaved edits.

**Requirements**:
- A live, synchronized connection. Offline and demo mode are refused.
- A free slot. A preset that already uses all 40 slots is refused with
  `preset_full`.

**Parameters**:

| Name | Type | Default | Meaning |
|---|---|---|---|
| `guid` | string, required | | GUID of the installed plug-in algorithm |
| `cpu_budget_percent` | integer 1-100, required | | highest per-slot CPU percentage the test slot may reach, in the units `show_cpu` reports as a slot's `usage_percent` |
| `max_core_percent` | integer 1-100 | none | highest percentage either core may reach (`cpu1_percent`/`cpu2_percent` in `show_cpu`) |
| `specifications` | integer array | each specification's default | exact number of values required by the loaded plug-in, each within its advertised range |
| `expected_parameter_count` | integer ≥ 1 | at least 1 | exact parameter count |
| `expected_parameter_names` | string array | not checked | names of the first parameters, in order; surrounding spaces are ignored |
| `settle_ms` | integer 0-5000 | 1000 | wait before the checks |
| `cpu_samples` | integer 1-10 | 3 | number of CPU samples |
| `keep` | boolean | false | keep the slot when every check passes |
| `reload_saved_on_failure` | boolean | false | allow the saved-preset reload even with unsaved edits |

**Example**:

```json
{"tool": "smoke_test_plugin", "arguments": {"guid": "MyFl", "cpu_budget_percent": 30, "max_core_percent": 80, "expected_parameter_names": ["Cutoff", "Resonance"]}}
```

**Passing result**:

```json
{
  "success": true,
  "guid": "MyFl",
  "name": "My Filter",
  "slot_index": 2,
  "loaded_plugin": false,
  "checks": [
    {"name": "slot_added", "passed": true, "detail": "Appended as slot 2."},
    {"name": "slot_responds", "passed": true},
    {"name": "algorithm_guid", "passed": true},
    {"name": "parameter_count", "passed": true, "detail": "Reported 2; expected at least 1."},
    {"name": "parameter_names", "passed": true, "detail": "Expected [Cutoff, Resonance], got [Cutoff, Resonance]."},
    {"name": "slot_cpu", "passed": true, "detail": "Peak 12% over 3 sample(s); budget 30%."},
    {"name": "core_cpu", "passed": true, "detail": "Peak core 41%; ceiling 80%."}
  ],
  "cpu": {"budget_percent": 30, "max_core_percent": 80, "slot_samples": [11, 12, 12], "slot_peak": 12, "core_samples": [40, 41, 41], "core_peak": 41},
  "rollback": "removed_slot",
  "rolled_back": true,
  "message": "My Filter (MyFl) passed every check in slot 2. The test slot was removed, and the original slots are confirmed."
}
```

**Failing result**: `success` is `false` and `error` says why the test failed
(see the table below). Cleanup is attempted only when its target can be
identified safely; `rolled_back` says whether the original lineup was confirmed.

```json
{"success": false, "error": "cpu_over_budget", "guid": "MyFl", "name": "My Filter", "slot_index": 2, "loaded_plugin": false, "checks": [{"name": "slot_added", "passed": true, "detail": "Appended as slot 2."}, {"name": "slot_responds", "passed": true}, {"name": "algorithm_guid", "passed": true}, {"name": "parameter_count", "passed": true, "detail": "Reported 2; expected at least 1."}, {"name": "slot_cpu", "passed": false, "detail": "Peak 47% over 3 sample(s); budget 30%."}], "cpu": {"budget_percent": 30, "max_core_percent": null, "slot_samples": [44, 47, 45], "slot_peak": 47, "core_samples": [70, 72, 71], "core_peak": 72}, "rollback": "removed_slot", "rolled_back": true, "message": "My Filter (MyFl) failed: Slot 2 peaked at 47% CPU; the budget is 30%. The test slot was removed, and the original slots are confirmed."}
```

**`rollback` values**:

| `rollback` | `rolled_back` | Meaning |
|---|---|---|
| `kept` | false | every check passed and `keep` was set; the slot stays, unsaved |
| `not_needed` | true | the slot never appeared; the original lineup is confirmed |
| `removed_slot` | true | the slot was removed and the original lineup is confirmed |
| `reloaded_saved_preset` | true | removal failed, so the saved preset was reloaded; see `rollback_error` and `restored_parameter_values` |
| `failed` | false | the original lineup could not be confirmed; `rollback_error` says why and what to do |

**Test failures** (the test ran, then rolled back):

| `error` | Cause |
|---|---|
| `add_failed` | the device did not confirm the new slot within 10 s |
| `parameters_unavailable` | the slot did not answer the GUID, parameter-count or parameter-name reads |
| `parameter_mismatch` | the slot holds another GUID, reports no parameters, or differs from `expected_parameter_count` or `expected_parameter_names` |
| `cpu_over_budget` | the slot's peak sample exceeded `cpu_budget_percent` |
| `core_cpu_over_budget` | a core's peak sample exceeded `max_core_percent` (reported only if the slot was within budget) |
| `cpu_unavailable` | a CPU sample did not arrive or did not include the test slot |
| `device_unresponsive` | after a failure, the device also stopped answering slot-count reads |
| `rollback_failed` | every check passed, but the original lineup could not be confirmed |
| `internal_error` | an unexpected error; the rollback still runs |

**Refusals** (the preset was not touched):

| `error` | Cause |
|---|---|
| `missing_guid` | `guid` absent or blank |
| `missing_cpu_budget` | `cpu_budget_percent` absent |
| `smoke_test_busy` | another smoke test is still running or rolling back |
| `preset_changed` | hardware/app lineup or session could not be confirmed before adding; refresh and retry |
| `invalid_specifications` | wrong number of construction values or a value outside the loaded plug-in's advertised range |
| `invalid_<argument>` | an argument has the wrong type or is out of range, for example `invalid_cpu_budget_percent` |
| `unknown_argument` | an argument the tool does not accept |
| `not_connected` | no synchronized device |
| `offline_mode` | nt_helper is in offline mode |
| `demo_mode` | nt_helper is in demo mode |
| `unknown_guid` | no installed algorithm has this GUID |
| `not_a_plugin` | the GUID belongs to a built-in algorithm |
| `preset_full` | every slot is in use; also returns `max_slots` |
| `load_failed` | the plug-in did not report loaded |
| `algorithm_library_loading` | the algorithm list was still loading from the device after 10 seconds, so the GUID could not be looked up; retry shortly |

Before looking up the GUID, the tool waits up to 10 seconds for any
background algorithm-list load to finish, because a partly loaded list can
report an installed plug-in as `unknown_guid`.

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
