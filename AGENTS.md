# nt_helper - Disting NT MIDI Helper

Flutter app for Disting NT Eurorack module: preset management, algorithm loading, parameter control via MIDI SysEx.

**Platforms:** Linux, macOS, iOS, Android, Windows
**Modes:** Demo (no hardware), Offline (cached), Connected (live MIDI)

## Delivery contract: third-party bug reports

When the user asks to debug or fix a problem reported by someone else (for
example a Discord screenshot, support request, or GitHub issue), **the task
includes shipping a release that person can install**. This is authorization to
commit, push, create and merge a PR after required checks, and publish the fix;
a separate request to commit or release is not required. An explicit instruction
such as “investigate only”, “do not commit”, or “do not release” overrides this
default.

Required delivery sequence: **fix → verify → commit → PR → merge → release →
verify downloadable assets**. Use the `nt-helper-release` skill and the Release
section below. For a focused bug fix, take the hotfix path: a small PR followed
by a patch release, without unrelated cleanup or waiting for a feature release.
Keep required checks and release verification intact.

Completion gate: the final delivery report must include the merged PR URL,
released version, and verified download/release URL. Local changes, a commit,
a PR, or a pushed tag alone are intermediate states, not completion. If delivery
is blocked, identify the exact blocker and remaining steps; never silently
reduce the task to a local-only fix or ask whether to release an already
authorized third-party fix.

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
| `*_plugin_verify_delegate.dart` | Delegate | Live-only plugin install with rescan verification (MCP `install_plugin`) |
| `*_plugin_smoke_test_delegate.dart` | Delegate | Live-only plug-in smoke test with confirmed slot removal and no preset save (MCP `smoke_test_plugin`) |
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

## Plug-in Object Detection

`ElfGuidExtractor` (`lib/services/elf_guid_extractor.dart`) reads the algorithm
GUIDs of a plug-in `.o` for install checks, the gallery and SD-card scans.

- The contract is `pluginEntry`, not symbol names. GUIDs come from the
  `_NT_factory` structs reachable from `pluginEntry` through relocations,
  matched by struct shape: a guid no relocation patches, a relocated `name`,
  and a `construct` relocated to code. The last is what tells a factory from
  an `_NT_parameter` table. Factory symbol names (`factory`, `_ZL7factory`,
  `_ZN…FactoryE`) are only a fallback when nothing is reachable.
- Factory names are not a contract. A Rust build emits its factory as an
  anonymous `.Lanon.*` object, and C++ authors name theirs freely: on
  2026-11-08, 14 of the gallery's 99 compiled plug-ins, 13 of them C++, had no
  factory name the fallback recognises. Do not add detection that depends on
  one compiler's or author's naming.
- `test/fixtures/plugins/` holds one real object per toolchain or layout that
  has broken detection, and
  `test/services/elf_guid_extractor_test.dart` asserts each one's exact GUIDs.
  When a plug-in is misdetected, add its object (with provenance and license)
  and a failing test before changing the extractor.
- The gallery feed's `guid`, `isCollection` and `collectionGuids` come from
  the gallery server, not from this code. There, a collection is any entry
  with more than one GUID, so one `.o` with several factories is one
  (`directionalsequencer`). `isActualCollection` in
  `lib/models/gallery_models.dart` asks something else: whether an archive
  holds more than one installable file. `GalleryService` matches device
  algorithms to entries by those feed GUIDs, so an entry whose GUIDs differ
  from its artifact's goes unrecognised on the device; check the artifact
  with `ElfGuidExtractor` before trusting the feed.

## Key Files

| Area | Path |
|------|------|
| State | `lib/cubit/disting_cubit.dart` (+ delegates/mixins) |
| Routing | `lib/core/routing/algorithm_routing.dart` |
| Main UI | `lib/ui/synchronized_screen.dart` |
| Routing UI | `lib/ui/widgets/routing/routing_editor_widget.dart` |
| Metadata | `lib/services/algorithm_metadata_service.dart` |

## Graphify Codebase Graph

`nt_helper` is indexed in Substrate's registered `graphify-mcp` graph; the
`graphify` skill describes the workflow. Use it to find existing behavior before
adding a new helper, delegate or service, and confirm findings in the checkout.

Route every Graphify call through `mcp__substrate` (`graphify-mcp__*` tools, or
`mcp__substrate.invoke_tool`). Never use a standalone Graphify MCP server, an
external install, or a local graph rebuild. Community 0 is only the largest
cluster; inspect the relevant communities for architecture or impact work.

## Commands

```
flutter analyze          # Must pass with zero warnings
flutter test test/path/to/affected_test.dart --no-pub  # Tight local loop
flutter run -d macos --print-dtd   # Run with DTD URL for MCP connection
```

Locally, run the affected tests plus `dart format` and `flutter analyze --no-pub`
on changed Dart files. The full suite runs in CI on every PR and main push; it is
required locally only on the release commit. Before committing, report the exact
checks run. See `test/AGENTS.md` and `docs/developer-feedback.md` for test
selection and CI routing.

Tests must be deterministic: await futures, stream states or completers, and use
`fakeAsync`/`pump` for timers, never real sleeps. Fix a flaky test rather than
skipping it, lengthening timeouts, or weakening a regression assertion.

Generated files (mocks, freezed, drift) are gitignored. In a fresh worktree, run
`dart run build_runner build --delete-conflicting-outputs` before analyze/test.
Flutter is managed with `fvm`.

## Release

Use the `nt-helper-release` skill and the existing
`.github/workflows/tag-build.yml` workflow. A tag or release page is not the
finish line: every required distribution job and public asset must be verified.

Use the `thorinside` GitHub CLI credential for this repository. Before release
checks or GitHub API operations, run `gh auth switch -u thorinside`; do not use
the `nealsanche` credential.

Release through a version-bump PR; `main` requires PRs and passing CI:

1. From clean, synchronized `main`, create a release branch. Choose `patch` for
   fixes/maintenance, `minor` for user-visible features, or `major` for breaking
   changes. Run `./version <patch|minor|major>` to commit the version without a tag.
   Resume an existing version-bump commit instead of bumping twice.
2. Push the branch, open a PR, wait for required CI, and merge it.
3. Update local `main` to `origin/main`. Run `flutter analyze` and the full
   `flutter test` suite on this exact merged release commit.
4. Verify the Windows runner is online and idle as described below.
5. Create `vX.Y.Z` on the verified `main` commit and push only that exact tag.
   Verify its SHA equals `origin/main`; do not push `main` directly or use
   `git push --tags`.

Published remote tags are immutable. With explicit user authorization, correct
an incorrect local tag to the remote SHA, or remove a premature local-only tag
before recreating it on verified merged `main`. First verify the remote state;
never force-push or delete a remote release tag.

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

The Windows job targets `[self-hosted, Windows, X64]`, the runner `dev-Windows`
in the VirtualBox VM `nt-helper-windows-x64` on
`neal@dev.allosaurus-newton.ts.net`. For guest prerequisites, SSH, direct
Windows commands, desktop access and shutdown, see
[dev-Windows runner access](docs/dev-windows-runner-access.md).

Before tagging, check the VM state and start it headlessly when necessary:

```bash
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage showvminfo "nt-helper-windows-x64" --machinereadable | grep "^VMState="'
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage startvm "nt-helper-windows-x64" --type headless'
```

Wait for GitHub to report the runner online and idle:

```bash
gh api orgs/No-Such-Device/actions/runners \
  --jq '.runners[] | select(.name=="dev-Windows") | {name,status,busy}'
```

Starting the VM is sufficient: Windows starts the
`actions.runner.No-Such-Device.dev-Windows` service automatically and it
reconnects to GitHub. Do not switch the job back to GitHub-hosted Windows as a
fallback when hosted minutes are unavailable; fix a missing runner prerequisite
instead.

If a Windows build fails, inspect the exact failed step, repair the persistent
guest prerequisite, and rerun the failed job. Do not move/delete the release tag
or create another version merely to retry it.

## MCP Docs

- [MCP API Guide](./docs/mcp-api-guide.md) — 4-tool API (search, new, edit, show)
- [MCP Mapping Guide](./docs/mcp-mapping-guide.md) — CV, MIDI, i2c mappings

## Layout Stability

Layout stability is mandatory. Loading, sync, validation, error, and pending-edit
states must not push controls or content around. Keep status indicators in fixed
slots; use tooltips or overlays for details. If inline feedback is necessary,
reserve its space in every state. Keep table rows and headers at stable positions
as feedback appears or clears. Test geometry across asynchronous state changes.

## Flutter Accessibility

Every workflow must be fully usable with a screen reader and keyboard. Label
icon-only and custom controls, mark structural titles as headers, announce
meaningful async results (`SemanticsService.sendAnnouncement` / live regions),
exclude decorative content, and add semantics tests for new interactive UI.

## Commits

Use Conventional Commit subjects; changelog and semver tooling depend on them.

## Rules

- Zero tolerance for `flutter analyze` errors
- Never add debug logging unless explicitly asked
- Do not restart the app if already running — disrupts MCP/debugger connections
- SysEx messages must be at most 1024 bytes. SD-card file upload (`7A 04`)
  must use 512-byte file data chunks. SD-card file download (`7A 02`) is
  canonical whole-file only; do not invent offset/count chunked download
  requests. Verify large WAV uploads by directory listing names/sizes or a
  mounted SD-card filesystem, not whole-file SysEx download.
- Snackbars are exclusively for errors, exceptional warnings, or invalid actions. ZERO affirmative/success or routine progress snackbars anywhere in the app (including helpers). Use ordinary inline state and accessibility announcements; do not replace successes with toasts.
- Never replace code with a comment.
- Use only comments that are absolutely required for code understanding, not for tracking what should have been written in the code.
