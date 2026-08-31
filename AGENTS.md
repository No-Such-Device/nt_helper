# nt_helper - Disting NT MIDI Helper

Flutter app for Disting NT Eurorack module: preset management, algorithm loading, parameter control via MIDI SysEx.

**Platforms:** Linux, macOS, iOS, Android, Windows
**Modes:** Demo (no hardware), Offline (cached), Connected (live MIDI)

## Architecture

- **State:** Cubit pattern with delegate decomposition (`lib/cubit/disting_cubit.dart`)
- **MIDI:** Interface-based with mock/offline/live implementations (`lib/domain/i_disting_midi_manager.dart`)
- **Database:** Drift ORM (`lib/db/database.dart`)
- **MCP:** Model Context Protocol server (`lib/services/mcp_server_service.dart`)

### DistingCubit Delegates

The main cubit is decomposed into delegates and mixins for maintainability.

**Rule of thumb**: keep `lib/cubit/disting_cubit.dart` as an orchestration/facade layer. Add new non-trivial behavior in a delegate or an existing ops mixin.

| File | Type | Purpose |
|------|------|---------|
| `*_connection_delegate.dart` | Delegate | MIDI device connection |
| `*_parameter_fetch_delegate.dart` | Delegate | Parameter loading with retry |
| `*_parameter_refresh_delegate.dart` | Delegate | Live parameter polling |
| `*_parameter_value_delegate.dart` | Delegate | Parameter value writes + verification |
| `*_parameter_string_delegate.dart` | Delegate | Parameter value-string reads/writes |
| `*_mapping_delegate.dart` | Delegate | CV/MIDI/i2c/performance mappings |
| `*_slot_state_delegate.dart` | Delegate | Slot state updates + routing refresh |
| `*_slot_maintenance_delegate.dart` | Delegate | Slot repair/refresh/reset helpers |
| `*_state_refresh_delegate.dart` | Delegate | Refresh state from MIDI manager |
| `*_state_helpers_delegate.dart` | Delegate | Routing + offline metadata helpers |
| `*_algorithm_library_delegate.dart` | Delegate | Algorithm library refresh/rescan |
| `*_plugin_delegate.dart` | Delegate | Plugin installation |
| `*_sd_card_delegate.dart` | Delegate | SD card preset listing/scanning |
| `*_lua_reload_delegate.dart` | Delegate | Lua reload with state preservation |
| `*_offline_demo_delegate.dart` | Delegate | Demo/offline mode |
| `*_hardware_commands_delegate.dart` | Delegate | Screenshot/display/reboot/remount |
| `*_monitoring_delegate.dart` | Delegate | CPU monitoring + USB video |
| `*_refresh_delegate.dart` | Delegate | Refresh/cancelSync orchestration |
| `*_algorithm_ops.dart` | Mixin | Algorithm operations |
| `*_preset_ops.dart` | Mixin | Preset operations |
| `*_slot_ops.dart` | Mixin | Slot operations |

All use `part of 'disting_cubit.dart'` for private access. See `docs/architecture/coding-standards.md` for pattern details and guardrails.

## Routing System

OO framework in `lib/core/routing/` for data-driven routing visualization.

- `AlgorithmRouting.fromSlot()` creates routing from live Slot data
- `ConnectionDiscoveryService` discovers connections via bus assignments (1-12 inputs, 13-20 outputs)
- `RoutingEditorCubit` orchestrates state; `RoutingEditorWidget` displays only
- ES-5 algorithms (clck, eucp, clkm, clkd, pycv) support direct output routing via `Es5DirectOutputAlgorithmRouting`

## Key Files

| Area | Path |
|------|------|
| State | `lib/cubit/disting_cubit.dart` (+ delegates/mixins) |
| Routing | `lib/core/routing/algorithm_routing.dart` |
| Main UI | `lib/ui/synchronized_screen.dart` |
| Routing UI | `lib/ui/widgets/routing/routing_editor_widget.dart` |
| Metadata | `lib/services/algorithm_metadata_service.dart` |

## Graphify Codebase Graph

`nt_helper` is indexed in Substrate's registered `graphify-mcp` graph. Invoke
the `graphify` skill for graph search, architecture discovery, relationship
tracing, ownership/adjacency checks, or PR impact work. The skill is the source
of truth for live service discovery and tool routing.

Route every Graphify service lookup and tool call through `mcp__substrate`.
Use the `graphify-mcp__*` tools mapped by Substrate, or
`mcp__substrate.invoke_tool` when the compatibility wrapper is required. Never
connect to or invoke a standalone Graphify MCP server directly.

Use Graphify to find existing behavior before introducing a new helper,
delegate, service, or parallel implementation.

1. Start with the smallest useful query: `query_graph` for orientation,
   `get_node`/`get_neighbors` for a specific symbol, and `shortest_path` for a
   relationship between concepts.
2. For architecture or impact work, inspect the relevant communities rather
   than stopping at Community 0, which is only the largest cluster.
3. Treat Graphify as a map, not source truth. Confirm important findings with
   `rg` and the actual files in this checkout before editing.

Follow the skill's Substrate-registered service workflow rather than using
generic knowledge search, an external Graphify install, or a local graph
rebuild. Prefer plain `rg` for a simple exact text/file lookup. Use PR-impact
tools only for PR/merge work, and corroborate current GitHub status separately.

## Commands

```
flutter analyze          # Must pass with zero warnings
flutter test             # Run before commits
flutter run -d macos --print-dtd   # Run with DTD URL for MCP connection
```

## Updating Flutter (fvm)

```
fvm releases                     # List versions; find latest stable at the bottom
fvm install <VERSION>            # e.g. fvm install 3.41.6
fvm global <VERSION>             # Set as global default
```

## Worktrees

Generated files (mocks, freezed, drift) are gitignored. After `git worktree add`, run:

```
dart run build_runner build --delete-conflicting-outputs
```

before `flutter analyze` or `flutter test`.

## Release

Use the `nt-helper-release` skill and the existing
`.github/workflows/tag-build.yml` workflow. A tag or release page is not the
finish line: every required distribution job and public asset must be verified.

Before creating a tag:

1. Confirm `main` is clean and synchronized with `origin/main`.
2. Run `flutter analyze` and the full `flutter test` suite on the exact commit
   being released.
3. Start and verify the self-hosted Windows runner as described below. Do not
   push the tag while that runner is offline.
4. Choose `patch` for fixes/maintenance, `minor` for any user-visible feature,
   and `major` only for an intentional breaking release.
5. Run `./version <patch|minor|major>`, inspect the generated version commit and
   exact `vX.Y.Z` tag, then push `main` followed by that exact tag. Do not use a
   broad `git push --tags`.

Monitor the tag-triggered release with:

```bash
bash /Users/nealsanche/.codex/skills/nt-helper-release/scripts/wait-for-release.sh \
  vX.Y.Z
```

A release is complete only when these seven jobs succeed: Android APK, Android
AAB/Play upload, Windows, Linux, macOS, macOS/TestFlight, and iOS. The public,
non-draft GitHub release must contain five non-empty assets: APK, Linux ZIP,
macOS ZIP, Windows ZIP, and Windows installer. Download and inspect any affected
package when the release changes packaging, signing, native libraries, or the
installer. Finish with a clean worktree whose `HEAD` matches `origin/main`.

### Windows self-hosted release runner

The Windows job targets `[self-hosted, Windows, ARM64]`. It runs in the UTM VM
named `Windows 11 Flutter Runner` on this Mac, registered with GitHub as
`MacBookPro-Windows`. The VM is intentionally off between releases and does not
start automatically at Mac login.

Start it hidden before tagging:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl start --hide \
  47DEC67B-0AD4-424C-A7F7-AA538D93B970
```

Wait for GitHub to report the runner online and idle:

```bash
gh api orgs/No-Such-Device/actions/runners \
  --jq '.runners[] | select(.name=="MacBookPro-Windows") | {name,status,busy}'
```

Starting the VM is sufficient: Windows starts the
`actions.runner.No-Such-Device.MacBookPro-Windows` service automatically and it
reconnects to GitHub. Do not switch the job back to GitHub-hosted Windows as a
fallback when hosted minutes are unavailable; fix a missing runner prerequisite
instead.

The guest is Windows 11 ARM64, but Flutter has no Windows ARM64 SDK archive, so
the workflow must keep `architecture: x64` and the existing x64 build/output
paths. These guest prerequisites are already provisioned and are part of the
runner contract:

- Visual Studio Build Tools at `C:\BuildTools`, including
  `Microsoft.VisualStudio.Workload.VCTools` and
  `Microsoft.VisualStudio.Component.VC.ATL` (`atlbase.h` is required by the USB
  video plugin).
- Windows Developer Mode enabled machine-wide so Flutter plugins can create
  symlinks.
- Machine-wide PowerShell 7 at
  `C:\Program Files\PowerShell\7\pwsh.exe`.
- Git Bash at `C:\Program Files\Git\bin\bash.exe`.
- `jq.exe` at `C:\ProgramData\nt-helper-runner\bin\jq.exe`.
- Machine-wide Inno Setup 6 at
  `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`.
- Git and GitHub CLI available to the runner service.

The workflow's `Add runner tools to PATH` and `Verify Inno Setup` steps are
intentional portability checks; do not replace them with assumptions inherited
from GitHub-hosted images. If a Windows build fails, inspect the exact failed
step, repair the persistent guest prerequisite, and rerun the failed job. Do not
move/delete the release tag or create another version merely to retry it.

After the full release and assets are verified, confirm the runner is not busy
and no Windows job is queued, then shut down the VM:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl stop \
  47DEC67B-0AD4-424C-A7F7-AA538D93B970
```

## MCP Docs

- [MCP API Guide](./docs/mcp-api-guide.md) — 4-tool API (search, new, edit, show)
- [MCP Mapping Guide](./docs/mcp-mapping-guide.md) — CV, MIDI, i2c mappings

## Flutter Accessibility

- Build Flutter UI so blind users can understand state, navigate controls, and complete workflows with a screen reader.
- Provide semantic labels for icon-only controls, custom widgets, progress indicators, and non-text affordances.
- Mark page, dialog, section, and group titles with `Semantics(header: true)` when they structure navigation.
- Use `Semantics(liveRegion: true)` and `SemanticsService.sendAnnouncement` for meaningful async state changes, validation errors, empty states, selection changes, and completion of non-visual operations.
- Wrap decorative or duplicated visual-only content in `ExcludeSemantics` so screen readers do not announce noise.
- Preserve keyboard and focus traversal for dialogs, lists, toggles, segmented controls, file import/export flows, and drag/drop alternatives.
- Add or update widget semantics tests for new interactive UI, especially icon-only actions, live status text, selected states, and error paths.

## Commits

- Use Conventional Commit-style subjects so changelog and semver tooling can classify changes.
- Prefer types such as `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `build:`, `ci:`, `chore:`, and `revert:`.
- Use an optional scope when it adds clarity, for example `feat(template-manager): add JSON import`.
- Mark breaking changes with `!` in the subject or a `BREAKING CHANGE:` footer.
- Keep the subject imperative and focused on the user-visible or release-relevant change.

## Rules

- Zero tolerance for `flutter analyze` errors
- Never add debug logging unless explicitly asked
- Do not restart the app if already running — disrupts MCP/debugger connections
- SysEx messages must be at most 1024 bytes. SD-card file upload (`7A 04`)
  must use 512-byte file data chunks. SD-card file download (`7A 02`) is
  canonical whole-file only; do not invent offset/count chunked download
  requests. Verify large WAV uploads by directory listing names/sizes or a
  mounted SD-card filesystem, not whole-file SysEx download.
- Prefer snackbars for exceptions, failures, or invalid actions; avoid success snackbars unless explicitly requested.
