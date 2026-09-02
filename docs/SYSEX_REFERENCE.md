# Disting NT SysEx Protocol - Tools Reference

Developer documentation for all SysEx messages used by the official Disting NT tools.
Derived from the source code in `distingNT/tools/`.

## Message Format

All messages share a common header:

```
F0 00 21 27 6D <sysExId> <command> [data...] F7
```

| Byte(s) | Value | Description |
|---------|-------|-------------|
| `F0` | — | SysEx start |
| `00 21 27` | — | Expert Sleepers manufacturer ID |
| `6D` | — | Disting NT device ID |
| `sysExId` | 0–126 | Configurable per-device ID (distinguishes multiple units on same MIDI bus) |
| `command` | — | Command byte (see tables below) |
| `F7` | — | SysEx end |

## Data Encoding Conventions

### 21-bit short values

Many parameters and indices are encoded as 21-bit signed values across 3 bytes:

```
byte0 = (value >> 14) & 0x03
byte1 = (value >>  7) & 0x7F
byte2 = (value >>  0) & 0x7F
```

To decode (with sign extension):

```javascript
v = (byte0 << 14) | (byte1 << 7) | byte2;
v = (v << 16) >> 16;  // sign extend
```

### 64-bit file positions/sizes

File operations encode 64-bit values as 10 bytes. In practice only the lower 32 bits are used:

```
bytes[0..4] = 0  (upper bits, unused)
bytes[5]    = (value >> 28) & 0x0F
bytes[6]    = (value >> 21) & 0x7F
bytes[7]    = (value >> 14) & 0x7F
bytes[8]    = (value >>  7) & 0x7F
bytes[9]    = (value >>  0) & 0x7F
```

### Hex nibble encoding (file data)

Raw binary data in file operations is encoded as two nibbles per byte:

```
nibble_high = (byte >> 4) & 0x0F
nibble_low  = (byte     ) & 0x0F
```

### Checksum

File operation messages (command `0x7A`) require a checksum before the `F7` terminator:

```
sum = 0
for each byte from index 7 to end of data:
    sum += byte
checksum = (-sum) & 0x7F
```

The checksum is appended after all data bytes, immediately before `F7`.

---

## System Commands

### `0x01` — Request Screenshot

**Direction:** Host → Device
**Used by:** `dnt_screenshot_tool.html`

```
F0 00 21 27 6D <id> 01 F7
```

Requests the current display contents. Device responds with command `0x33`.

---

### `0x04` — Set RTC (Real-Time Clock)

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`, `dnt_screenshot_tool.html`, `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 04 <d4> <d3> <d2> <d1> <d0> F7
```

Sets the device real-time clock. The timestamp is a Unix epoch (seconds), adjusted for the local timezone:

```
d = Math.floor(Date.now() / 1000) - timezoneOffset * 60

d4 = (d >> 28) & 0x0F
d3 = (d >> 21) & 0x7F
d2 = (d >> 14) & 0x7F
d1 = (d >>  7) & 0x7F
d0 = (d >>  0) & 0x7F
```

No response.

---

### `0x07` — Wake

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 07 F7
```

Wakes the device from sleep/standby. No response.

---

### `0x7F` — Reboot

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 7F F7
```

Reboots the device. No response (device restarts).

---

## Lua Console Commands

### `0x08` — Send Console Line

**Direction:** Host → Device
**Used by:** `dnt_lua_console.html`

```
F0 00 21 27 6D <id> 08 <ascii chars...> F7
```

Sends a line of text to the Lua console for execution. Characters are raw ASCII bytes.

---

### `0x09` — Console Output / Install Program

**Direction (receive):** Device → Host
**Direction (send):** Host → Device
**Used by:** `dnt_lua_console.html`

**Receiving console output:**
```
F0 00 21 27 6D <id> 09 <ascii chars...> F7
```

The device sends console output text back via this command.

**Installing a Lua program:**
```
F0 00 21 27 6D <id> 09 <slot> <program bytes...> F7
```

| Field | Description |
|-------|-------------|
| `slot` | Target algorithm slot (currently hardcoded to `0x00` = first Lua algorithm) |
| `program bytes` | Lua source code, each character masked to 7 bits (`char & 0x7F`) |

---

## Scala Tuning Commands

### `0x11` — Send SCL File

**Direction:** Host → Device
**Used by:** `dnt_scala_tool.html`

```
F0 00 21 27 6D <id> 11 <which> <scl text...> F7
```

| Field | Description |
|-------|-------------|
| `which` | Target slot (currently hardcoded to `0`) |
| `scl text` | Raw ASCII contents of a Scala .scl tuning file |

---

### `0x12` — Send KBM File

**Direction:** Host → Device
**Used by:** `dnt_scala_tool.html`

```
F0 00 21 27 6D <id> 12 <which> <kbm text...> F7
```

| Field | Description |
|-------|-------------|
| `which` | Target slot (currently hardcoded to `0`) |
| `kbm text` | Raw ASCII contents of a Scala .kbm keyboard mapping file |

---

## Display Control

### `0x20` — Set Display Mode

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 20 <mode> F7
```

| Mode | Description |
|------|-------------|
| `0` | Parameters |
| `1` | Algorithm UI |
| `2` | Overview |
| `3` | Overview VUs |

No response.

---

## Algorithm Management

### `0x30` — Get Number of Algorithms

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 30 F7
```

**Response:**
```
F0 00 21 27 6D <id> 30 <count as 21-bit short> F7
```

Returns the total number of available algorithms (built-in + plugins).

---

### `0x31` — Get Algorithm Info

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 31 <index as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 31
  <index: 3 bytes>
  <guid: 4 bytes>
  <numSpecs: 1 byte>
  [for each spec: <min: 3> <max: 3> <default: 3> <flags: 1>]
  <algorithm name: null-terminated string>
  [for each spec: <spec name: null-terminated string>]
  <isPlugin: 1 byte>
  <isLoaded: 1 byte>
  <filename: null-terminated string>
F7
```

---

### `0x32` — Add Algorithm

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 32
  <guid[0]> <guid[1]> <guid[2]> <guid[3]>
  <spec0 as 21-bit short>
  <spec1 as 21-bit short>
  <spec2 as 21-bit short>
F7
```

Adds an algorithm to the preset with the given GUID and spec values.

---

### `0x33` — Remove Algorithm

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 33 <slot> F7
```

Removes the algorithm in the specified slot.

---

### `0x34` — Load Preset

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 34 <append> <path bytes...> 00 F7
```

| Field | Description |
|-------|-------------|
| `append` | `0x00` = replace current preset |
| `path bytes` | Null-terminated file path on device (e.g., `/presets/My Preset.json`) |

---

### `0x35` — New Preset

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 35 F7
```

Creates a new blank preset, clearing all slots. No response.

---

### `0x36` — Save Preset

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 36 <option> F7
```

| Option | Description |
|--------|-------------|
| `0` | Save with prompt |
| `1` | Save (safe — won't overwrite) |
| `2` | Save (force overwrite) |

No ACK response. Python tools add a 0.5s delay after this command.

---

### `0x37` — Move Algorithm Slot

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 37 <from_slot & 0x7F> <to_slot & 0x7F> F7
```

Moves an algorithm from one slot position to another (reorders the processing chain).

---

### `0x38` — Load Plugin

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 38 <guid[0]> <guid[1]> <guid[2]> <guid[3]> F7
```

Loads an unloaded plugin into memory by its GUID. Required before adding a plugin algorithm if it's not yet loaded.

---

## Preset/Slot Queries

### `0x40` — Get Algorithm (by Slot)

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 40 <slot> F7
```

**Response:**
```
F0 00 21 27 6D <id> 40 <slot>
  <guid: 4 bytes>
  <custom name: up to 24 bytes, null-terminated when shorter>
  [<style version> <left indent> <right indent>
   <line above> <line below> <bracket>]
F7
```

Firmware 1.18 and newer append the versioned algorithm visual-style block
after the name field. Style version `1` uses these values:

| Field | Values |
|-------|--------|
| `left indent` | 0–15 |
| `right indent` | 0–15 |
| `line above` | 0 = off, 1 = on |
| `line below` | 0 = off, 1 = on |
| `bracket` | 0 = none, 1 = open, 2 = close, 3 = line, 4 = open and close |

---

### `0x41` — Get Preset Name

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 41 F7
```

**Response:**
```
F0 00 21 27 6D <id> 41 <name: up to 21 chars, null-terminated> F7
```

---

### `0x42` — Get Number of Parameters

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 42 <slot> F7
```

**Response:**
```
F0 00 21 27 6D <id> 42 <slot> <count as 21-bit short> F7
```

---

### `0x43` — Get Parameter Info

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 43 <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 43 <slot>
  <param: 3 bytes>
  <min: 3 bytes>
  <max: 3 bytes>
  <default: 3 bytes>
  <unit: 1 byte>
  <name: null-terminated string>
  <flags: 1 byte>  (scaling in bits 0-1, ioFlags in bits 2-5)
F7
```

**Unit values:**
- `0` = no unit (boolean if min=0, max=1)
- `1` = enum (request enum strings with `0x49`)
- `16`, `17`, `18` = string-valued parameters (request string with `0x50`; unit `18` = editable string)
- Other values index into the unit strings table (retrieved via `0x48`)

**ioFlags (bits 2-5 of flags byte):**
- Bit 0 (value 1): input indicator
- Bit 1 (value 2): output indicator
- Bit 2 (value 4): bold indicator arrows
- Bit 3 (value 8): output mode (triggers `0x55` query)

**Scaling (bits 0-1):** Display value = raw value / 10^scaling

---

### `0x44` — Get All Parameter Values

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 44 <slot> F7
```

**Response:**
```
F0 00 21 27 6D <id> 44 <slot>
  [<value as 21-bit short> for each parameter]
F7
```

Returns all parameter values as a contiguous array of 21-bit shorts.

---

### `0x45` — Get Parameter Value

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 45 <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 45 <slot> <param: 3 bytes> <value: 3 bytes> F7
```

---

### `0x46` — Set Parameter Value

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 46 <slot> <param as 21-bit short> <value as 21-bit short> F7
```

Sets a single parameter to the given value. No response.

---

### `0x47` — Set Preset Name

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 47 <name bytes...> 00 F7
```

Sets the current preset's name. Name is a null-terminated ASCII string.

---

### `0x48` — Get Unit Strings

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 48 F7
```

**Response:**
```
F0 00 21 27 6D <id> 48
  <count: 1 byte>
  [<null-terminated string> for each unit]
F7
```

Returns the lookup table of unit display strings (e.g., "dB", "Hz", "ms"). Used to interpret the `unit` field from parameter info.

---

### `0x49` — Get Enum Strings

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 49 <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 49 <slot>
  <param: 3 bytes>
  <count: 1 byte>
  [<null-terminated string> for each enum value]
F7
```

Returns display strings for an enumerated parameter. If exactly 2 values named "Off"/"On", the UI renders a checkbox instead of a dropdown.

---

### `0x4A` — Set Focus

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 4A <slot> <param as 21-bit short> F7
```

Tells the device to focus its display on this parameter (auto-focus feature). No response.

---

### `0x4B` — Get Mapping Info

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 4B <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 4B <slot>
  <param: 3 bytes>
  <version: 1 byte>
  --- CV mapping ---
  [if version >= 4: <source: 1 byte>]
  <input: 1 byte>
  <flags: 1 byte>       (bit 0 = unipolar, bit 1 = gate)
  <volts: 1 byte>
  <delta: 3 bytes (21-bit short)>
  --- MIDI mapping ---
  <cc: 1 byte>
  <flags: 1 byte>       (bit 0 = enabled, bit 1 = symmetric, bit 2 = legacy aftertouch before mapping v7, bits 3-6 = channel)
  [if version >= 2: <flags2: 1 byte>  (bit 0 = relative, bits 2-6 = type)]
  <min: 3 bytes>
  <max: 3 bytes>
  --- I2C mapping ---
  <cc: 1 byte>
  [if version >= 3: <cc_high: 1 byte>]
  <flags: 1 byte>       (bit 0 = enabled, bit 1 = symmetric)
  <min: 3 bytes>
  <max: 3 bytes>
  --- Performance page ---
  [if version == 5: <perfPage: 1 byte>]
F7
```

**Mapping version** is currently `7`. The version field controls which optional fields are present.
Version 6 removed the perf page byte from mapping data; perf page assignments are managed via separate commands (0x54).
Version 7 adds explicit MIDI mapping types for pitch bend and channel pressure.

---

### `0x4D` — Set CV Mapping

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 4D <slot> <param: 3 bytes> <version>
  [if version >= 4: <source>]
  <input> <flags> <volts> <delta: 3 bytes>
F7
```

---

### `0x4E` — Set MIDI Mapping

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 4E <slot> <param: 3 bytes> <version>
  <cc> <flags>
  [if version >= 2: <flags2>]
  <min: 3 bytes> <max: 3 bytes>
F7
```

---

### `0x4F` — Set I2C Mapping

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 4F <slot> <param: 3 bytes> <version>
  <cc & 0x7F>
  [if version >= 3: <(cc >> 7) & 0x7F>]
  <flags> <min: 3 bytes> <max: 3 bytes>
F7
```

---

### `0x50` — Get Parameter Value String

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 50 <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 50 <slot> <param: 3 bytes> <name: null-terminated string> F7
```

Returns the formatted display string for a parameter value. Used for unit types 16/17/18 (string-valued parameters like file paths or names).

---

### `0x51` — Set Slot Name

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 51 <slot> <name bytes...> 00 F7
```

Sets a custom display name for an algorithm slot. Null-terminated ASCII.

---

### `0x52` — Get Algorithm Names / Get Parameter Pages

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

This command has two forms depending on whether a slot argument is present:

**Without slot — Get Algorithm Names:**
```
F0 00 21 27 6D <id> 52 F7
```

Triggers the device to respond with the number of algorithms (command `0x30`), followed by algorithm info responses (command `0x31`) for each.

**With slot — Get Parameter Pages:**
```
F0 00 21 27 6D <id> 52 <slot> F7
```

**Response:**
```
F0 00 21 27 6D <id> 52 <slot>
  <numPages: 1 byte>
  [for each page:
    <page name: null-terminated string>
    <numParams: 1 byte>
    [for each param: <index_hi: 1 byte> <index_lo: 1 byte>]
  ]
F7
```

Returns parameter organization grouped by page. Parameter indices are encoded as `(hi << 7) | lo`.

---

### `0x53` — Set Parameter String Value

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

```
F0 00 21 27 6D <id> 53 <slot> <param as 21-bit short> <string bytes...> 00 F7
```

Sets a string-valued parameter (unit type 18). Null-terminated ASCII.

---

### `0x54` — Set Performance Page Mapping / Algorithm Visual Style

**Direction:** Host → Device
**Used by:** `dnt_preset_editor.html`

The meaning is firmware-version dependent. The legacy pre-1.16 performance
page command is:

```
F0 00 21 27 6D <id> 54 <slot> <param as 21-bit short> <mappingVersion> <index> F7
```

| Field | Description |
|-------|-------------|
| `mappingVersion` | Performance page mapping protocol version (`5`) |
| `index` | Performance page position (0–30) |

Firmware 1.18 and newer use `0x54` for algorithm visual style:

```
F0 00 21 27 6D <id> 54 <slot> 01
  <left indent> <right indent> <line above> <line below> <bracket>
F7
```

The style fields use the same version-1 values documented in the `0x40`
response. Firmware 1.16 and newer manage performance-page items through
`0x57`/`0x58`, so nt_helper must gate style writes to firmware 1.18 or newer.

---

### `0x55` — Get Output Mode Usage

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 55 <slot> <param as 21-bit short> F7
```

**Response:**
```
F0 00 21 27 6D <id> 55 <slot>
  <param: 3 bytes>
  <count: 1 byte>
  [<related param: 3 bytes> for each]
F7
```

Returns parameters that share the same output mode group. Used for visual grouping in the UI (colored backgrounds).

---

### `0x56` — Query Paths

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`, `push_plugin_to_device.py`

**Request:**
```
F0 00 21 27 6D <id> 56 F7
```

**Response:**
```
F0 00 21 27 6D <id> 56 <null-terminated strings...> F7
```

Returns the current preset path and related information as null-terminated strings. The Python tool uses the first string as the current preset file path.

---

## Routing

### `0x60` — Get Slot Count

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 60 F7
```

**Response:**
```
F0 00 21 27 6D <id> 60 <count: 1 byte> F7
```

Returns the number of algorithm slots in the current preset.

---

### `0x61` — Get Routing Info

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 61 <slot> F7
```

**Response:**
```
F0 00 21 27 6D <id> 61
  <slot: 1 byte>
  [6 × 32-bit bitmasks, each encoded as 5 bytes (7 bits each)]
F7
```

Each bitmask is decoded as:
```
value = byte[0] | (byte[1] << 7) | (byte[2] << 14) | (byte[3] << 21) | (byte[4] << 28)
```

The 6 bitmasks represent (bit positions 1–28 map to channels: inputs 1–12, outputs 1–8, aux 1–8):

| Index | Description |
|-------|-------------|
| 0 | Input mask — which channels this slot reads from |
| 1 | Output mask — which channels this slot writes to |
| 2 | Replace mask — which output channels replace (vs. mix into) existing signal |
| 3–4 | (Additional routing data) |
| 5 | Mapping mask — channels used by CV/MIDI mappings |

---

## CPU Monitoring

### `0x62` — Get CPU Usage

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_preset_editor.html`

**Request:**
```
F0 00 21 27 6D <id> 62 F7
```

**Response:**
```
F0 00 21 27 6D <id> 62 <cpu1> <cpu2> [<per-slot usage>...] F7
```

| Field | Description |
|-------|-------------|
| `cpu1` | CPU core 1 usage percentage |
| `cpu2` | CPU core 2 usage percentage |
| Remaining bytes | Per-slot CPU usage (one byte per active slot) |

The preset editor polls this every 1000ms when "Show CPU" is enabled.

---

## Screenshot Data

### `0x33` — Screenshot Response

**Direction:** Device → Host
**Used by:** `dnt_screenshot_tool.html`

```
F0 00 21 27 6D <id> 33 <unknown byte> <pixel data...> F7
```

Returns a 256×64 pixel grayscale image. Pixel data starts at byte index 8 (after the header + 1 byte). Each pixel is a 4-bit value (0–15). Pixel order is row-major, top-to-bottom.

The screenshot tool optionally applies gamma correction:
```
normalized = pixel / 15.0
corrected  = pow(normalized, 0.45) * 255
```

---

## File Operations (command `0x7A`)

All file operations use command byte `0x7A` with a sub-operation byte. These messages require a checksum (see Checksum section above).

### Response Format

**Success:**
```
F0 00 21 27 6D <id> 7A 00 <operation> F7
```

**Error:**
```
F0 00 21 27 6D <id> 7A 01 <error message: null-terminated string> F7
```

---

### Operation `0x01` — Directory Listing

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_sdcard_tool.html`

**Request:**
```
F0 00 21 27 6D <id> 7A 01 <path chars...> <checksum> F7
```

**Response (success):**
```
F0 00 21 27 6D <id> 7A 00 01
  [for each entry:
    <attrib: 1 byte>
    <date: 3 bytes (21-bit FAT date)>
    <time: 3 bytes (21-bit FAT time)>
    <size: 10 bytes (64-bit)>
    <filename: null-terminated string>
  ]
F7
```

**Attribute flags:** bit 4 (`0x10`) = directory

**FAT date/time decoding:**
```
year   = 1980 + (date >> 9)
month  = ((date >> 5) & 0xF) - 1
day    = date & 0x1F
hour   = time >> 11
minute = (time >> 5) & 0x3F
second = 2 * (time & 0x1F)
```

---

### Operation `0x02` — File Download

**Direction:** Host → Device (request), Device → Host (response)
**Used by:** `dnt_sdcard_tool.html`, `file_receive.py`

**Request:**
```
F0 00 21 27 6D <id> 7A 02 <path chars...> <checksum> F7
```

**Response (success):**
```
F0 00 21 27 6D <id> 7A 00 02 <data as hex nibbles...> F7
```

The file data is encoded as hex nibble pairs. Decode:
```python
for i in range(0, len(data), 2):
    byte = (data[i] << 4) | data[i+1]
```

The Disting NT protocol does not define offset/count fields for operation
`0x02`. Do not send chunked download requests; the canonical tools and manual
define this operation as a whole-file download.

---

### Operation `0x03` — File Delete

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 7A 03 <path chars...> <checksum> F7
```

Deletes a file or empty directory. Response is success/error.

---

### Operation `0x04` — File Upload

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`, `file_send.py`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 7A 04
  <path chars...> 00
  <createAlways: 1 byte>
  <position: 10 bytes>
  <count: 10 bytes>
  <data as hex nibbles...>
  <checksum>
F7
```

| Field | Description |
|-------|-------------|
| `path` | Null-terminated destination file path on device |
| `createAlways` | `1` for the first chunk (creates/truncates file), `0` for subsequent chunks (appends) |
| `position` | Byte offset in the file (64-bit encoded) |
| `count` | Number of raw bytes in this chunk (64-bit encoded) |
| `data` | File content encoded as hex nibble pairs (2 nibbles per byte) |

**Chunking:** Files are sent in 512-byte chunks. Each chunk gets an ACK response:
```
F0 00 21 27 6D <id> 7A 00 04 F7
```

Wait for the ACK before sending the next chunk.

---

### Operation `0x05` — Rename

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 7A 05 <old path...> 00 <new path...> 00 <checksum> F7
```

Both paths are null-terminated strings.

---

### Operation `0x06` — Remount SD Card

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 7A 06 <what: 1 byte> <checksum> F7
```

| Field | Description |
|-------|-------------|
| `what` | Currently `0` (reserved for partial rescan) |

---

### Operation `0x07` — New Folder

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`

```
F0 00 21 27 6D <id> 7A 07 <path chars...> <checksum> F7
```

Creates a new directory at the specified path.

---

### Operation `0x08` — Rescan Plugins

**Direction:** Host → Device
**Used by:** `dnt_sdcard_tool.html`, `push_plugin_to_device.py`

```
F0 00 21 27 6D <id> 7A 08 <checksum> F7
```

Triggers a rescan of the `/programs/plug-ins/` directory. Required after uploading a new plugin for it to be recognized. No data payload. Requires firmware v1.13+.

---

## Tool-to-Command Quick Reference

| Command | Hex | Preset Editor | SD Card | Screenshot | Lua Console | Scala | Python Tools |
|---------|-----|:---:|:---:|:---:|:---:|:---:|:---:|
| Screenshot Request | `01` | | | X | | | |
| RTC Update | `04` | X | X | X | | | |
| Wake | `07` | X | | | | | |
| Lua Send Line | `08` | | | | X | | |
| Lua Output / Install | `09` | | | | X | | |
| Send SCL | `11` | | | | | X | |
| Send KBM | `12` | | | | | X | |
| Display Mode | `20` | X | | | | | |
| Get Num Algorithms | `30` | X | | | | | |
| Get Algorithm Info | `31` | X | | | | | |
| Add Algorithm | `32` | X | | | | | |
| Remove Algorithm | `33` | X | | | | | |
| Load Preset | `34` | X | | | | | X |
| New Preset | `35` | X | | | | | X |
| Save Preset | `36` | X | | | | | X |
| Move Slot | `37` | X | | | | | |
| Load Plugin | `38` | X | | | | | |
| Get Algorithm (Slot) | `40` | X | | | | | |
| Get Preset Name | `41` | X | | | | | |
| Get Num Parameters | `42` | X | | | | | |
| Get Parameter Info | `43` | X | | | | | |
| Get All Param Values | `44` | X | | | | | |
| Get Parameter Value | `45` | X | | | | | |
| Set Parameter Value | `46` | X | | | | | |
| Set Preset Name | `47` | X | | | | | X |
| Get Unit Strings | `48` | X | | | | | |
| Get Enum Strings | `49` | X | | | | | |
| Set Focus | `4A` | X | | | | | |
| Get Mapping Info | `4B` | X | | | | | |
| Set CV Mapping | `4D` | X | | | | | |
| Set MIDI Mapping | `4E` | X | | | | | |
| Set I2C Mapping | `4F` | X | | | | | |
| Get Param Value String | `50` | X | | | | | |
| Set Slot Name | `51` | X | | | | | |
| Get Algo Names / Pages | `52` | X | | | | | |
| Set Param String Value | `53` | X | | | | | |
| Set Perf Mapping / Visual Style | `54` | X | | | | | |
| Get Output Mode Usage | `55` | X | | | | | |
| Query Paths | `56` | X | | | | | X |
| Get Slot Count | `60` | X | | | | | |
| Get Routing Info | `61` | X | | | | | |
| Get CPU Usage | `62` | X | | | | | |
| File Operations | `7A` | | X | | | | X |
| Reboot | `7F` | | X | | | | |
| Screenshot Response | `33` | | | X | | | |

**Python tools** = `file_send.py`, `file_receive.py`, `push_plugin_to_device.py`
