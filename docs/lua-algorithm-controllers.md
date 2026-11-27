# Lua Algorithm Controllers

Lua algorithm controllers are optional, algorithm-specific property editors.
They run inside nt_helper, not on the disting NT. The standard parameter editor
remains the default and fallback.

The app currently bundles controllers for Euclidean Patterns (`eucp`), Clock
(`clck`), Clock Divider (`clkd`), Attenuverter (`attn`), Crossfader (`xfad`),
DJ Filter (`djfi`), LFO (`lfo `), Envelope (DAHDSR) (`envq`), Envelope
(AR/AD) (`env2`), EQ Parametric (`eqpa`), Mixer Mono (`mix1`), Mixer Stereo
(`mix2`), Dream Machine (`drea`), Macro Oscillator 2 (`mac2`), Poly Macro
Oscillator 2 (`pym2`), Filter Bank (`fbnk`), Chaos (`xaoc`), Quantizer
(`quan`), Envelope Sequencer (`ensq`), Quadraphonic Mixer (`quad`), Seaside
Jawari (`ssjw`), and Stopwatch (`stpw`). Installation and Gallery distribution
are intentionally not enabled yet.

## Lifecycle

A controller is a pure function of the latest immutable `Slot` from
`DistingCubit`:

1. nt_helper converts the current slot into the global `algorithm` table.
2. The Lua file runs and returns a versioned UI document.
3. Flutter validates and renders that document using native Material widgets.
4. Bound controls write through `DistingCubit.updateParameterValue`.
5. A new slot snapshot causes Lua to run again and replace the UI document.

Lua never sends MIDI or SysEx and never retains a mutable copy of slot state.
The selected Standard, Spreadsheet, or Controller mode is owned by the
parameter-editor state above `SlotDetailView`, so rebuilding the parameter
workspace or toggling Routing does not reset the selection.

Bypass is also owned by the host. Every slot editor keeps a pinned Bypass
affordance above its scrollable content and displays the current strings
reported by the NT. Controller scripts receive Bypass in the immutable snapshot
for compatibility, but bundled scripts do not render a duplicate control.

## Document interface

Every script returns one table:

```lua
return {
  version = 1,
  title = "My controller",
  root = ui.column {
    children = {
      ui.text { text = algorithm.name },
      ui.slider { label = "Level", parameter = 3 }
    }
  }
}
```

Unknown versions, nodes, actions, and malformed fields are rejected. A failure
returns the user to the standard editor.

## Algorithm snapshot

The global `algorithm` table contains:

- `slot_index`, `guid`, `name`, and numeric `specifications`
- `parameters`, in device order
- `pages`, with their parameter-number lists
- raw `routing` values

Each parameter contains:

- `number`, `name`, `minimum`, `maximum`, and `default`
- `value`, `disabled`, `display_value`, and `enum_values`
- `unit`, `unit_index`, and `power_of_ten`
- `io_flags`, `is_input`, and `is_output`

Helpers are available for common lookups:

```lua
local cutoff = nt.parameter("Cutoff")
local parameter = nt.parameter_by_number(42)
local mask_page = nt.page("Mask")
local steps = nt.channel_parameter(1, "Steps")
local channel_numbers = nt.channels()
```

`nt.parameter` accepts an optional occurrence number for duplicate names.
`nt.page` likewise accepts an optional occurrence number. Snapshot lookup
results are immutable for the lifetime of one evaluation.

## Authoring rules

Lua controllers edit algorithm behavior, never I/O routing. Do not bind any
slider, choice, toggle, button action, XY-pad axis, or note-mask entry to a
parameter with non-zero `ioFlags` (input, output, audio, or output-mode), or to
an unflagged endpoint selector such as a bus, ES-5 expander/output, MIDI or i2c
channel, breakout, Select Bus, USB, or internal destination. Leave those
parameters to the standard parameter and Routing editors.

Channel sections are appropriate only for DSP, performance, or sequencing
controls. Omit them when their parameters are routing-only. A controller may
read routing parameters to explain an honest preview, but must not expose them
as editable controls.

Drawings must describe configuration available in the current immutable
snapshot. Do not present a configured gate as a live envelope, invent audio
telemetry, or imply a summed frequency response when the host has only
per-filter settings. State limitations in visible copy and accessibility
semantics when a diagram could otherwise be mistaken for measured or live
data.

## UI primitives

Layout and content:

- `ui.column { children, gap, padding }`
- `ui.row { children, gap }` — a wrapping horizontal flow
- `ui.section { title, subtitle, children }` — individually collapsible
- `ui.text { text, style, align }`
- `ui.divider {}`
- `ui.spacer { size }`

The slot editor's collapse-all control collapses or unfurls every `ui.section`
while preserving the same action bar and overflow menu used by the standard
parameter editor. Number keys use the standard parameter-editor behavior:
`1` selects the first section through `9` for the ninth and `0` for the tenth,
expanding that section while collapsing its peers. Individual and global
section state survives immutable `Slot` updates and Parameters/Routing layout
changes.

Controls:

- `ui.slider { label, parameter, minimum, maximum, enabled }`
- `ui.choice { label, parameter, enabled }`
- `ui.toggle { label, parameter, on_value, off_value, enabled }`
- `ui.button { label, style, enabled, action }`
- `ui.xy_pad { label, x_parameter, y_parameter, x_label, y_label,
  aspect_ratio, invert_y, enabled }`
- `ui.note_mask { label, layout, notes, enabled }`

Buttons currently support these declarative actions:

```lua
action = { type = "set_parameter", parameter = 4, value = 0 }
action = { type = "adjust_parameter", parameter = 4, delta = 1 }
action = {
  type = "pulse_parameter",
  parameter = 4,
  on_value = 1,
  off_value = 0,
  duration_ms = 100
}
```

`pulse_parameter` sends the high write, waits, and then clears the parameter.
Its `on_value`, `off_value`, and `duration_ms` default to `1`, `0`, and `100`;
the host bounds the delay to one second. Use it for repeatable edge-triggered
algorithm commands.

The host intersects controller slider ranges with the live parameter range and
clamps every control result before writing. Sliders prefer the current
device-formatted value, then the matching enum string, then the standard
parameter-editor formatting for the raw value, including `powerOfTen` scaling
and units. Double-clicking a slider resets it to the parameter's live default
value. Choices require a complete enum range and otherwise fall back to a
slider. Flutter owns input semantics, keyboard behavior, disabled state, and
the actual parameter write.

An XY pad binds both axes directly to live parameters. Its range, value,
disabled state, formatted text, and reset values come from the latest slot
snapshot. Tap or drag to position the point, use the arrow keys for fine
movement, and double-click to reset both axes. `invert_y` defaults to `true`, so
larger Y values appear higher on the pad; set it to `false` when the algorithm's
coordinate system increases downward. The host exposes each axis and reset as
screen-reader actions.

A note mask renders text-free, 48-pixel circular targets while retaining note
names and inclusion state for screen readers. Use `layout = "piano"` for one
octave of 12-tone pitch classes and provide a unique `pitch_class` from 0
through 11 for every bound note:

```lua
ui.note_mask {
  label = "Allowed notes",
  layout = "piano",
  notes = {
    { label = "C", parameter = 22, pitch_class = 0 },
    { label = "F sharp", parameter = 25, pitch_class = 6 }
  }
}
```

Naturals form the lower row and accidentals the raised row; pitch classes
without a corresponding live parameter remain visible but inert. For Scala,
MTS, or another tuning whose degrees cannot be represented truthfully as 12
pitch classes, use `layout = "degrees"` and omit `pitch_class`. Each entry must
bind its exact live parameter number. The host reads inclusion from every new
`Slot` snapshot and writes `0` or `1` without keeping separate selection state.

## Drawing primitives

`ui.canvas` is a responsive, normalized drawing surface. Coordinates and sizes
are expressed relative to the canvas instead of in Flutter pixels. The host
caps canvases at 720 logical pixels wide and lets them shrink in narrower
editors, so drawings stay legible without growing indefinitely on wide screens.

```lua
ui.canvas {
  semantics_label = "Four pulses across sixteen steps",
  aspect_ratio = 5,
  shapes = {
    ui.rect {
      x = 0, y = 0.1, width = 1, height = 0.8,
      radius = 0.1, fill = "surface_container_highest"
    },
    ui.circle {
      x = 0.25, y = 0.5, radius = 0.06,
      fill = "primary", stroke = "outline"
    },
    ui.line {
      x1 = 0.25, y1 = 0.5, x2 = 0.75, y2 = 0.5,
      stroke = "secondary", stroke_width = 2
    }
  }
}
```

Theme tokens include `primary`, `on_primary`, `secondary`, `tertiary`,
`surface`, `surface_container`, `surface_container_highest`, `on_surface`,
`on_surface_variant`, `outline`, `error`, and `transparent`. Hex colors are
accepted, but theme tokens should be preferred. Every canvas requires a useful
`semantics_label`; paint-only canvases omit `targets` and keep shapes
non-focusable with normal parent scrolling.

### Opt-in canvas input targets

A `ui.canvas` can opt in to typed host pointer, focus, and wheel input by
supplying a `targets` array (up to 256 targets per document). When `targets` is
omitted or empty, the canvas remains paint-only.

Optional canvas-level fields:

- `drag_threshold` — finite non-negative movement distance in logical pixels
  before a drag begins (defaults to `4`)
- `cycle_overlapping_selection` — when `true`, repeated clicks on overlapping
  selectable targets cycle selection and focus in deterministic order without
  writing parameters (defaults to `false`)

Each entry in `targets` binds directly to live parameters (never I/O
parameters) and uses normalized canvas coordinates (`0..1`):

```lua
ui.canvas {
  semantics_label = "Interactive two-axis control surface",
  aspect_ratio = 4,
  drag_threshold = 4,
  cycle_overlapping_selection = true,
  shapes = { ... },
  targets = {
    {
      id = "point-1",
      label = "Point 1",
      shape = "circle", -- or "rect" with x, y, width, height
      x = 0.5,
      y = 0.5,
      radius = 0.06,
      selectable = true,
      order = 1,
      enabled = true,
      x_axis = {
        parameter = 2,
        from = 0.04,
        to = 0.96,
        step = 1,
        invert = false,
        enabled = true
      },
      y_axis = {
        parameter = 3,
        from = 0.08,
        to = 0.92,
        step = 1,
        invert = true,
        enabled = true
      },
      wheel = {
        parameter = 4,
        step = 1,
        invert = false,
        enabled = true
      }
    }
  }
}
```

The host routes hits against the actual rendered canvas bounds, separates
selection-only click/focus from thresholded single-pointer drag capture, writes
through `DistingCubit.updateParameterValue` with clamping and quantization,
clears active capture immediately on release, cancel, Escape, disposal,
slot/binding replacement, or reconnect (without fabricating undo writes), and
consumes mouse wheel only over a single unambiguous, enabled, writable target.

## Runtime restrictions

Controllers receive data and return data. The host exposes no Dart callbacks,
widgets, MIDI manager, filesystem, network, process, package-loading, or OS
library. Documents are limited to 512 UI nodes, 2,048 shapes, and 32 levels of
nesting.

Those restrictions are not yet a sufficient sandbox for untrusted Gallery
downloads. Before third-party installation is enabled, controller execution
also needs an isolate with a hard time budget, package manifests and capability
declarations, durable install/remove management, and clear trust information in
the Gallery UI.
