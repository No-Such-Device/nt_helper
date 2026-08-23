# MCP Mapping Guide for Disting NT

This guide explains how to work with parameter mappings in the Disting NT MCP API. Mappings allow you to control algorithm parameters through external control sources: CV inputs, MIDI messages, i2c communication, and performance page organization.

Template application preserves packed mapping bytes verbatim. When using `apply_template_to_preset`, copied slots keep their CV, MIDI, i2c, and performance-page mapping data; the tool does not decode or reinterpret those mappings.

## Table of Contents

1. [CV Mapping](#cv-mapping)
2. [MIDI Mapping](#midi-mapping)
3. [i2c Mapping](#i2c-mapping)
4. [Performance Pages](#performance-pages)
5. [Common Patterns](#common-patterns)
6. [Troubleshooting](#troubleshooting)
7. [Implementation Notes](#implementation-notes)

---

## CV Mapping

CV (Control Voltage) mappings allow hardware control voltage inputs to modulate algorithm parameters. The Disting NT has 12 physical CV inputs plus support for CV modulation from other algorithms in the signal chain.

### CV Fields

#### `source` (integer)
- **Range**: 0 or algorithm output index
- **Purpose**: Observe another algorithm's output as modulation source (advanced usage)
- **Default**: 0 (not used)
- **Explanation**: This is an advanced feature that lets you use the output of one algorithm to modulate a parameter in another algorithm. Set to the algorithm index whose output you want to observe. For example, if you have an LFO in slot 0 and want its output to modulate filter cutoff in slot 1, set `source: 0`.

#### `cv_input` (integer)
- **Range**: 0-12
- **Purpose**: Physical CV input number for hardware control voltage
- **Values**:
  - 0 = disabled (no CV input)
  - 1-12 = physical CV input number
- **Explanation**: Connect your CV source to one of the Disting NT's 12 CV inputs, then specify which input controls this parameter.

#### `is_unipolar` (boolean)
- **Type**: boolean
- **Purpose**: Control voltage range mode
- **Values**:
  - `true`: Unipolar (0V to +10V)
  - `false`: Bipolar (-5V to +5V, default)
- **Explanation**: Unipolar mode interprets voltages as 0-10V, while bipolar mode interprets them as -5V to +5V. Choose based on your control voltage source.

#### `is_gate` (boolean)
- **Type**: boolean
- **Purpose**: Enable gate/trigger mode
- **Default**: false
- **Explanation**: When true, the CV input is treated as a gate or trigger signal rather than continuous modulation. Useful for triggering envelopes or drum sounds.

#### `volts` (float)
- **Range**: 0-127 (internal representation)
- **Purpose**: Voltage scaling factor
- **Explanation**: Adjusts the sensitivity and range of the CV input. Higher values increase the effect of CV modulation on the parameter.

#### `delta` (float)
- **Range**: 0+ (internal representation)
- **Purpose**: Sensitivity/responsiveness
- **Explanation**: Controls how quickly the parameter responds to changes in the CV input. Higher values make the response faster and more sensitive.

### CV Example

```json
{
  "slot_index": 0,
  "parameter": "cutoff",
  "mapping": {
    "cv": {
      "source": 0,
      "cv_input": 1,
      "is_unipolar": false,
      "is_gate": false,
      "volts": 64,
      "delta": 32
    }
  }
}
```

This example maps the `cutoff` parameter of the algorithm in slot 0 to CV input 1, using bipolar voltage range with moderate sensitivity.

---

## MIDI Mapping

MIDI mappings allow MIDI controllers, DAW automation, and other MIDI hardware to control algorithm parameters.

### MIDI Fields

#### `is_midi_enabled` (boolean)
- **Purpose**: Enable/disable MIDI control
- **Default**: false
- **Explanation**: Set to true to activate MIDI control for this parameter.

#### `midi_channel` (integer)
- **Range**: 0-15
- **Purpose**: MIDI channel number
- **Explanation**: MIDI channels are 0-indexed. Value 0 represents MIDI channel 1, value 15 represents MIDI channel 16.

#### `midi_type` (string enum)
- **Values**:
  - `"cc"` - Continuous Control Change (default)
  - `"note_momentary"` - Note on/off (momentary button)
  - `"note_toggle"` - Note on/off (toggle button)
  - `"cc_14bit_low"` - 14-bit CC (low byte, CC 0-31)
  - `"cc_14bit_high"` - 14-bit CC (high byte, CC 32-63)
  - `"pitch_bend"` - MIDI pitch bend (firmware 1.17+)
  - `"channel_pressure"` - MIDI channel pressure (firmware 1.17+)
- **Purpose**: Type of MIDI message
- **Explanation**:
  - CC is the most common for continuous parameters
  - Note types are useful for gate signals and drum triggers
  - 14-bit CC provides higher resolution than standard 7-bit CC
  - Pitch bend and channel pressure require firmware 1.17 or newer

#### `midi_cc` (integer)
- **Range**: 0-127 (legacy mappings may use 128 for aftertouch)
- **Purpose**: MIDI CC number
- **Values**:
  - 0-127 = standard MIDI CC numbers
  - 128 = legacy channel aftertouch for pre-v7 mapping data
- **Explanation**: Specifies which MIDI CC controls this parameter. Ignored for `pitch_bend` and `channel_pressure`.

#### `is_midi_symmetric` (boolean)
- **Purpose**: Symmetric scaling around center value
- **Default**: false
- **Explanation**: When true, the parameter value scales bidirectionally from a center point. Useful for parameters that benefit from center-zero behavior (like pan or depth).

#### `is_midi_relative` (boolean)
- **Purpose**: Relative mode for incremental changes
- **Default**: false
- **Explanation**: When true, MIDI values are interpreted as incremental changes rather than absolute values. Useful for knobs that you want to operate in relative mode.

#### `midi_min` (integer)
- **Range**: Typically 0
- **Purpose**: Minimum value for scaling range
- **Explanation**: Maps to the parameter's minimum value. MIDI 0 = parameter min.

#### `midi_max` (integer)
- **Range**: Typically 127
- **Purpose**: Maximum value for scaling range
- **Explanation**: Maps to the parameter's maximum value. MIDI 127 = parameter max.

### MIDI Example

```json
{
  "slot_index": 0,
  "parameter": "cutoff",
  "mapping": {
    "midi": {
      "is_midi_enabled": true,
      "midi_channel": 0,
      "midi_type": "cc",
      "midi_cc": 74,
      "is_midi_symmetric": false,
      "is_midi_relative": false,
      "midi_min": 0,
      "midi_max": 127
    }
  }
}
```

This example maps the filter cutoff to MIDI CC 74 (filter cutoff on most synths), using the full 0-127 range.

### NRPN Control (Firmware 1.18+)

The disting NT uses NRPN numbers 0-127 as alternate addresses for ordinary CC
mappings. There is no separate preset mapping type. Set `midi_cc` to the same
number as the controller's NRPN, and choose the value resolution with
`midi_type`: use `"cc"` for 7-bit values or `"cc_14bit_low"`/
`"cc_14bit_high"` for 14-bit values.

The mapping's `midi_min` and `midi_max` still define the destination parameter
range. MIDI Learn recognizes the NRPN select and Data Entry sequence, records
the NRPN number and channel, and preserves a selected 14-bit mapping type. If
the mapping is not already set to a 14-bit type, Learn uses `"cc"`.

---

## i2c Mapping

i2c mappings allow control via i2c protocol, commonly used with external modules and expanders.

### i2c Fields

#### `is_i2c_enabled` (boolean)
- **Purpose**: Enable/disable i2c control
- **Default**: false
- **Explanation**: Set to true to activate i2c control for this parameter.

#### `i2c_cc` (integer)
- **Range**: 0-255
- **Purpose**: i2c CC number
- **Explanation**: Similar to MIDI CC but with extended range (0-255 instead of 0-127).

#### `is_i2c_symmetric` (boolean)
- **Purpose**: Symmetric scaling
- **Default**: false
- **Explanation**: When true, parameter scales bidirectionally from a center point.

#### `i2c_min` (integer)
- **Range**: 0+
- **Purpose**: Minimum value for scaling range
- **Explanation**: i2c value 0 maps to parameter minimum.

#### `i2c_max` (integer)
- **Range**: 0+
- **Purpose**: Maximum value for scaling range
- **Explanation**: i2c value at max maps to parameter maximum.

### i2c Example

```json
{
  "slot_index": 1,
  "parameter": "resonance",
  "mapping": {
    "i2c": {
      "is_i2c_enabled": true,
      "i2c_cc": 50,
      "is_i2c_symmetric": false,
      "i2c_min": 0,
      "i2c_max": 255
    }
  }
}
```

This example maps the resonance parameter to i2c CC 50 with full range scaling.

---

## Performance Pages

Performance pages are used to organize related parameters for live performance. You can assign parameters to pages 1-30, with page 0 meaning "not assigned".

### Performance Page Field

#### `performance_page` (integer)
- **Range**: 0-15
- **Values**:
  - 0 = not assigned
  - 1-15 = page number
- **Purpose**: Parameter organization for live performance
- **Explanation**: Group related parameters on the same page for quick access during performance. For example, assign all filter parameters to page 1 and all envelope parameters to page 2.

### Performance Page Example

```json
{
  "slot_index": 0,
  "parameter": "cutoff",
  "mapping": {
    "performance_page": 1
  }
}
```

Multiple parameters can be assigned to the same page:

```json
[
  {
    "slot_index": 0,
    "parameter": "cutoff",
    "mapping": { "performance_page": 1 }
  },
  {
    "slot_index": 0,
    "parameter": "resonance",
    "mapping": { "performance_page": 1 }
  },
  {
    "slot_index": 0,
    "parameter": "attack",
    "mapping": { "performance_page": 2 }
  }
]
```

---

## Common Patterns

### Pattern 1: Filter Control via MIDI CC

Map a filter cutoff frequency to a standard MIDI CC (CC 74):

```json
{
  "slot_index": 0,
  "parameter": "cutoff",
  "mapping": {
    "midi": {
      "is_midi_enabled": true,
      "midi_channel": 0,
      "midi_type": "cc",
      "midi_cc": 74,
      "is_midi_symmetric": false,
      "is_midi_relative": false,
      "midi_min": 0,
      "midi_max": 127
    }
  }
}
```

### Pattern 2: Envelope Parameters via CV Inputs

Map envelope parameters to CV inputs 1-3:

```json
{
  "slot_index": 0,
  "parameter": "attack",
  "mapping": {
    "cv": {
      "cv_input": 1,
      "is_unipolar": true,
      "is_gate": false,
      "volts": 64,
      "delta": 16
    }
  }
}
```

Repeat for decay (CV input 2) and release (CV input 3).

### Pattern 3: Performance Page Organization

Organize algorithm parameters across multiple pages:

```json
{
  "algorithms": [
    {
      "slot_index": 0,
      "parameters": [
        {
          "name": "cutoff",
          "mapping": { "performance_page": 1 }
        },
        {
          "name": "resonance",
          "mapping": { "performance_page": 1 }
        }
      ]
    }
  ]
}
```

Page 1 contains filter parameters, page 2 contains envelope, page 3 contains effects, etc.

### Pattern 4: CV Source for Algorithm Modulation

Use LFO output to modulate another parameter:

```json
{
  "slot_index": 1,
  "parameter": "cutoff",
  "mapping": {
    "cv": {
      "source": 0,
      "is_unipolar": false,
      "is_gate": false,
      "volts": 80,
      "delta": 24
    }
  }
}
```

In this case, the algorithm in slot 0 (LFO) modulates the cutoff parameter of the algorithm in slot 1.

### Pattern 5: Partial Mapping Update

Update only MIDI mapping while preserving CV and i2c:

```json
{
  "slot_index": 0,
  "parameter": "cutoff",
  "mapping": {
    "midi": {
      "is_midi_enabled": true,
      "midi_channel": 0,
      "midi_type": "cc",
      "midi_cc": 74,
      "midi_min": 0,
      "midi_max": 127
    }
  }
}
```

Existing CV and i2c mappings are preserved. Only the specified mapping section is updated.

---

## Troubleshooting

### Common Validation Errors

#### "MIDI channel must be 0-15, got 16"
**Problem**: MIDI channels are 0-indexed.
**Solution**: Use values 0-15, not 1-16. Value 0 = MIDI channel 1, value 15 = MIDI channel 16.

#### "CV input must be 0-12, got 13"
**Problem**: Disting NT has only 12 CV inputs.
**Solution**: Use values 0-12 only. 0 = disabled, 1-12 = physical inputs.

#### "MIDI CC must be 0-128, got 129"
**Problem**: MIDI CC numbers have a limited range.
**Solution**: Use values 0-128 only. Value 128 is for legacy channel aftertouch mappings; on firmware 1.17+ use `midi_type: "channel_pressure"`.

#### "Performance page must be 0-30, got 31"
**Problem**: Only 30 performance pages available (1-30), plus 0 for "not assigned".
**Solution**: Use values 0-30 only.

#### "i2c CC must be 0-255, got 256"
**Problem**: i2c CC range is smaller than expected.
**Solution**: Use values 0-255 only.

### Mapping Conflicts

**Problem**: Multiple parameters assigned to same MIDI CC
```json
{
  "parameter_1": { "midi": { "midi_cc": 74 } },
  "parameter_2": { "midi": { "midi_cc": 74 } }
}
```

**Effect**: MIDI CC 74 messages will control both parameters simultaneously.

**Solution**: Either:
1. Use unique MIDI CCs for each parameter
2. Intentionally link related parameters (e.g., filter cutoff and resonance)

### Performance Page Best Practices

**Best Practice 1: Logical Grouping**
- Page 1: Main synthesis parameters (oscillator, filter, LFO)
- Page 2: Modulation parameters (envelope, modulation depth)
- Page 3: Effects parameters (reverb, delay, distortion)

**Best Practice 2: Limited Parameters per Page**
- Assign 3-7 parameters per page for easy performance access
- Too many parameters per page makes live control difficult

**Best Practice 3: Consistent Organization**
- Use the same page numbering scheme across all slots
- Document your page assignments in preset name or comments

### Disabled Mappings

**Note**: Mappings are considered "disabled" when:
- `is_midi_enabled` is false
- `cv_input` is 0
- `is_i2c_enabled` is false
- `performance_page` is 0

**Important**: Disabled mappings are omitted from `show` tool output to keep responses concise, but the data is preserved internally. When you edit a parameter's mapping, disabled sections can be re-enabled.

---

## Implementation Notes

### Tool Updates and Examples

The following tools support mappings:

- **`edit` tool**: Supports CV, MIDI, i2c, and performance page mappings at preset/slot/parameter levels
- **`show` tool**: Displays only enabled mappings (disabled mappings are omitted)
- **`get_preset` tool**: Shows enabled CV, MIDI, i2c, and performance page mappings

### JSON Schema

All mapping fields use snake_case naming convention:

- `cv_input` (not `cvInput`)
- `is_midi_enabled` (not `isMidiEnabled`)
- `midi_cc` (not `midiCc`)
- `is_i2c_enabled` (not `isI2cEnabled`)
- `performance_page` (not `performancePage`)

### Data Types

- Boolean fields: `true` / `false`
- Integer fields: whole numbers (0, 1, 2, etc.)
- Float fields: decimal numbers (0.5, 1.25, etc.)
- String enum fields: values in quotes ("cc", "note_momentary", etc.)

### Scaling and Ranges

MIDI/i2c min/max values define how the incoming MIDI/i2c range maps to parameter range:

- MIDI/i2c 0 → Parameter at min
- MIDI/i2c max value → Parameter at max
- Intermediate values scale linearly between min and max

---

## Examples by Use Case

### Use Case: Build a Synth Preset with Full MIDI Control

```json
{
  "target": "preset",
  "data": {
    "name": "synth-with-midi-control",
    "slots": [
      {
        "algorithm": { "name": "sine" },
        "parameters": [
          {
            "parameter_number": 0,
            "value": 60,
            "mapping": {
              "midi": {
                "is_midi_enabled": true,
                "midi_channel": 0,
                "midi_type": "cc",
                "midi_cc": 1,
                "midi_min": 0,
                "midi_max": 127
              },
              "performance_page": 1
            }
          },
          {
            "parameter_number": 1,
            "value": 50,
            "mapping": {
              "midi": {
                "is_midi_enabled": true,
                "midi_channel": 0,
                "midi_type": "cc",
                "midi_cc": 2,
                "midi_min": 0,
                "midi_max": 127
              },
              "performance_page": 1
            }
          }
        ]
      }
    ]
  }
}
```

### Use Case: CV Modulation from LFO to Filter

Slot 0: LFO, Slot 1: Filter with parameter modulated by LFO output

```json
{
  "slot_index": 1,
  "parameter": "cutoff",
  "mapping": {
    "cv": {
      "source": 0,
      "is_unipolar": false,
      "is_gate": false,
      "volts": 80,
      "delta": 16
    }
  }
}
```

### Use Case: Mix Control Sources (MIDI + CV + Performance Page)

```json
{
  "slot_index": 0,
  "parameter": "amount",
  "mapping": {
    "midi": {
      "is_midi_enabled": true,
      "midi_channel": 0,
      "midi_type": "cc",
      "midi_cc": 50,
      "midi_min": 0,
      "midi_max": 127
    },
    "cv": {
      "cv_input": 3,
      "is_unipolar": true,
      "is_gate": false,
      "volts": 64,
      "delta": 8
    },
    "performance_page": 1
  }
}
```

This parameter is controlled by:
1. MIDI CC 50 on channel 0
2. CV input 3
3. Assigned to performance page 1 for live access

---

## See Also

- [MCP API Guide](./mcp-api-guide.md) - Overview of all MCP tools
- [Architecture Documentation](./architecture.md) - Technical architecture details
