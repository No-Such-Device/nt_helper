# Patch Helper native UI evidence

Captured from the actual Flutter editor with its shipped Lua companion and
illustrative records served by the test device. These are widget renders, not
physical-device or full-application acceptance evidence.

- `editor-desktop.png`: 1280 × 820, selected E2 Out 8.
- `editor-compact.png`: 707 × 853, expanded minimap, 48 × 48 socket targets.

Reproduce from the repository root:

```sh
CAPTURE_PATCH_EDITOR=1 flutter test --no-pub test/ui/patch_map/patch_map_editor_test.dart
```

The test also checks minimap navigation in a short 1280 × 420 editor and Tag
validation (13 rejected, 7 accepted, blank cleared). Capture fonts use SFNS and
Material Icons when available on the development Mac; assertions do not depend
on their availability. Embedded PNG provenance records the capture origin.
