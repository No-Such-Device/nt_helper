# Patch Helper native UI evidence

Captured from the actual Flutter editor with its shipped Lua companion and
illustrative records served by the test device. These are widget renders, not
physical-device or full-application acceptance evidence.

- `editor-desktop.png`: 1280 × 820, E2 Out 8 selected by an NT property change through Lua.
- `editor-compact.png`: 707 × 853, expanded minimap, 48 × 48 socket targets.
- `editor-name-conflict.png`: historical evidence of the superseded manual Apply
  interaction; it does not describe the current editor.

Reproduce from the repository root:

```sh
CAPTURE_PATCH_EDITOR=1 flutter test --no-pub test/ui/patch_map/patch_map_editor_test.dart
```

The test also checks minimap navigation in a short 1280 × 420 editor and Tag
validation (13 rejected, 7 accepted, blank cleared). Capture fonts use SFNS and
Material Icons when available on the development Mac; assertions do not depend
on their availability. Embedded PNG provenance records the capture origin.

The current interaction test also checks automatic loading and synchronization,
colour-only socket dots, stable layout during edits and validation, app
pause/resume, merging local field changes with NT updates, and stopped polling
after editor disposal.
