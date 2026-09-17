# Algorithm section header — actual-app agent verification

> **Evidence status:** agent delivery verification only. This is not owner visual acceptance and does not complete AC-HDR-003.

- Verification date: 2026-09-17
- Delivery ticket: `106d122a-ddb6-4f6d-b304-e899b5e23540`
- Requirements exercised: REQ-HDR-001, REQ-HDR-004
- Acceptance criterion exercised: AC-HDR-001
- Platform: macOS 26.6.2, arm64

## Build identity

The verified app was built from source commit `8baddfee1a207ab21f8cf2bea6d4b275b251f977`. That commit contains the Lua-controller renderer; its direct predecessor `140b8504da3b65ed4f9d53f95918d9c091c65370` contains the standard/performance renderer.

The app was launched once with:

```text
flutter run -d macos --print-dtd
```

No app process existed before this launch, and the process was not restarted during verification. The running process was PID 40536 at `build/macos/Build/Products/Debug/nt_helper.app/Contents/MacOS/nt_helper`. The run log identified `lib/main.dart`, the macOS debug build, and one continuous Dart VM/DTD session.

Built bundle hashes at verification time:

```text
feb1328f6af4c15414453fb1823abcac12a81efcb157be0d9976b7f515aac310  Contents/MacOS/nt_helper
9107e0bb60144a9fe71365856f0a4345d825648b70599546be99894ba565b1a0  flutter_assets/kernel_blob.bin
```

The inspected route was the production `DistingApp` (`ThemeMode.system`) → `DistingPage` → `SynchronizedScreen` → `SlotDetailView` path. Screenshots were taken from the actual running app's root render object through the Flutter inspector, not from a widget-test host or the illustrative mockup. Their retained hashes are in [`SHA256SUMS`](SHA256SUMS).

## Reproduction

1. Start the app from the source commit above and enter Demo Mode from the real device-selection page.
2. Use the real overflow-menu **Switch** action, then enter **Offline** mode.
3. Through the running app's MCP server, create the offline preset `Header verification` with the existing `eucp` (Euclidean Patterns) metadata. This supplies 24 real offline parameters, standard `Globals`, `Channel 1`, and `Routing 1` sections, the existing `Performance Parameters (0)` section, and the bundled Euclidean Lua controller.
4. In standard mode, exercise individual expansion controllers and scroll the parameter list. In controller mode, exercise the `Channel 1` expansion controller and observe the `Enabled` toggle row.
5. Change macOS Appearance to Light and Dark while keeping the same app process running. For this agent run, the system-level SkyLight notifying setter used by system appearance controls was invoked; both `SLSGetAppearanceThemeLegacy` and `defaults read -g AppleInterfaceStyle` confirmed each system state. In-app `MediaQuery.platformBrightnessOf` independently reported the matching brightness.
6. Restore the original Dark system appearance. Final checks reported both the SkyLight state and global preference as Dark.

A normal manual reproduction can perform step 5 from **System Settings → Appearance**.

## Actual-app observations

### Standard and performance renderer

| System appearance | Live `onSurface` | Live header tile color | Expected `onSurface` at 0.10 | Exact match | Rendered header over surface | Header text | Contrast | Parameter-row tile color |
|---|---:|---:|---:|---|---:|---:|---:|---|
| Dark | `#FFD8E5E8` | `#1AD8E5E8` | `#1AD8E5E8` | yes | `#FF1E2A2D` | `#FFD8E5E8` | 11.47:1 | `null` |
| Light | `#FF111D20` | `#1A111D20` | `#1A111D20` | yes | `#FFD8E6E9` | `#FF111D20` | 13.42:1 | `null` |

The live color's floating-point alpha was exactly `0.1`; `0x1A` is its 8-bit ARGB representation. The same exact match was observed for the actual `Performance Parameters (0)` header. The unchanged theme text remained plainly readable. `ListTileTheme.of(parameterRow).tileColor == null` confirmed that the shade did not propagate into parameter rows.

The expanded list was moved to `pixels: 240.0` of `maxScrollExtent: 900.5` in both appearances. Header strips remained distinct during the scroll.

| Dark | Light |
|---|---|
| [Collapsed standard/performance sections](dark-standard-collapsed.png) | [Collapsed standard/performance sections](light-standard-collapsed.png) |
| [Expanded and scrolled standard/performance sections](dark-standard-expanded-scrolled.png) | [Expanded and scrolled standard/performance sections](light-standard-expanded-scrolled.png) |

### Lua-controller renderer

| System appearance | Live `onSurface` | Live header tile color | Expected `onSurface` at 0.10 | Exact match | Rendered header over surface | Header text | Contrast | Controller-toggle-row tile color |
|---|---:|---:|---:|---|---:|---:|---:|---|
| Dark | `#FFD8E5E8` | `#1AD8E5E8` | `#1AD8E5E8` | yes | `#FF1E2A2D` | `#FFD8E5E8` | 11.47:1 | `null` |
| Light | `#FF111D20` | `#1A111D20` | `#1A111D20` | yes | `#FFD8E6E9` | `#FF111D20` | 13.42:1 | `null` |

The actual bundled Euclidean controller showed the background-only strip on the `Channel 1` header in both collapsed and expanded states. The title/subtitle remained readable, and the `Enabled` `SwitchListTile` retained the inherited unshaded body theme (`tileColor == null`).

| Dark | Light |
|---|---|
| [Collapsed Lua-controller section](dark-controller-collapsed.png) | [Collapsed Lua-controller section](light-controller-collapsed.png) |
| [Expanded Lua-controller section](dark-controller-expanded.png) | [Expanded Lua-controller section](light-controller-expanded.png) |

## Automated correlation

The implementation assertions were rerun against both renderer test files:

```text
flutter test test/ui/widgets/section_parameter_list_view_test.dart test/ui/widgets/algorithm_controller/lua_algorithm_controller_view_test.dart
00:02 +35: All tests passed!
```

Those tests assert the same `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10)` value for light and dark themes, header-only paint, unchanged geometry/text styling, row isolation, and expansion behavior. The live app reported no Dart/Flutter runtime errors after the theme, expansion, mode, and scroll exercises.

The acceptance ledger's prior valid blocker evidence remains applicable: the full 3,772-test suite and `flutter analyze` had passed for commits `140b8504` and `8baddfee`.

## Reconciliation

The combined blocker tests and this actual-app observation satisfy the agent-producible portions of AC-HDR-001: both existing renderers use the exact approved theme-foreground 10% background in actual light and dark system appearances, text is readable, and the shade is confined to section headers. REQ-HDR-004 is demonstrated by the same-process actual-app captures above.

Final owner visual acceptance is deliberately not claimed here; AC-HDR-003 remains a separate owner-only obligation.
