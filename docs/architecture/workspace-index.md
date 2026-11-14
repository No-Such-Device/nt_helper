# Workspace architecture index

Source-inspected orientation for `nt_helper` at commit `6302310d` (branch `main`).
This is a retrieval map, not an API specification or a claim of runtime acceptance.
Recheck the owning source before changes. No app behavior is changed by this index.
The compact [architecture guide](../architecture.md) remains the boundary guide;
[AGENTS.md](../../AGENTS.md) remains the instruction authority.

## Contents

- [Bootstrap summary](#bootstrap-summary)
- [Roots and entry points](#roots-and-entry-points)
- [State and device data flow](#state-and-device-data-flow)
- [Screens and feature map](#screens-and-feature-map)
- [Subsystem boundaries](#subsystem-boundaries)
- [Persistence and startup safety](#persistence-and-startup-safety)
- [Network, authentication and trust](#network-authentication-and-trust)
- [Native platform boundaries](#native-platform-boundaries)
- [Build and verification](#build-and-verification)
- [Documentation shelf](#documentation-shelf)
- [Retrieval and refresh](#retrieval-and-refresh)
- [Coverage and open gaps](#coverage-and-open-gaps)

## Bootstrap summary

- One Flutter/Dart application package at repository root, for desktop (macOS,
  Windows, Linux), iOS and Android; no separate backend or web app root found.
- Purpose: edit Expert Sleepers Disting NT presets, algorithms, parameters,
  routing and CV/MIDI/i2c/performance mappings. Live, cached offline and demo
  modes share a manager interface. NTX-8CV has its own protocol and cubits.
- `lib/main.dart` admits storage through a recovery shell, initializes metadata
  and routing dependencies, then `DistingApp` creates the root `DistingCubit`.
- Device operations: widgets/tools → cubit facade → private delegates/ops →
  `IDistingMidiManager` → sequential MIDI scheduler → typed SysEx packets.
- State is principally Bloc/Cubit + Freezed immutable unions; Provider supplies
  database/logging, GetIt is scoped to routing, and preferences use notifiers.
- Drift/SQLite stores algorithm metadata, presets/templates and plugin tracking;
  preferences, chat checkpoint files, chat memory and gallery cache are separate.
- Routing models/discovery belong in `lib/core/routing/`, not rendering widgets.
  In-app chat and MCP share `ToolRegistry`; Genkit owns the chat agent loop.
- Read `AGENTS.md`, this index and the relevant tests before editing. Generated
  outputs must be built in new worktrees. Do not restart a running app merely to
  inspect it, or mutate connected hardware for architecture exploration.

## Roots and entry points

| Path / symbol | Responsibility |
| --- | --- |
| `pubspec.yaml`, `pubspec.lock` | Package/dependencies, SDK constraint, assets and locked resolution; use these rather than copied version lists |
| `lib/main.dart`: `main`, `_bootstrapApp` | Early logging/global error handlers, window restoration, settings, storage recovery/admission, dependency activation and shutdown |
| `lib/services/startup_controller.dart`, `startup_storage_opener.dart` | Admission/retry/close orchestration and real SQLite open; normal routes wait for admission |
| `lib/ui/startup_recovery_app.dart` | Recovery shell rather than silently substituting an empty library |
| `lib/disting_app.dart`: `DistingApp.buildRoutes`, `DistingPage` | Material theme/scale/shortcuts, root cubit, connection screen/state switch and MCP settings activation |
| `lib/driver_main.dart` | Alternate Flutter Driver entry; `routing_dump` diagnostic handler; calls normal app entry |
| `lib/ui/video_popup_app.dart`, `services/video_popup_window_service.dart` | Secondary desktop video-window app/IPC; main branches early for popup arguments |
| `lib/debug_poly_sample_upload_command.dart` | Explicit command-line debug upload branch before normal UI startup; not a safe read-only inspection command |
| `lib/scripts/extract_algorithm_metadata.dart` | Metadata extraction utility; inspect prerequisites before invocation |
| `android/`, `ios/`, `macos/`, `windows/`, `linux/` | Platform runners, native channels, entitlements and packaging |
| `assets/` | Bundled metadata, Lua controllers, icons, Linux integration and certificates |
| `test/`, `integration_test/`, `hardware_test/` | Ordinary contracts, device integration entry and opt-in live tests respectively |
| `tool/`, `tools/`, `scripts/`, `installers/` | Test/diagnostic utilities, capture tools, release automation, Windows installer |
| `specs/` | Temporary execution programs, not a second maintained architecture authority |

This checkout also had untracked `.durable-chat/` and `.scratch/`; they were not
used as application architecture authorities or modified. Build outputs and local
agent configuration are not additional application roots.

## State and device data flow

`DistingState` (`lib/cubit/disting_state.dart`, a part of the cubit library) has
`initial`, `selectDevice`, `connected` and `synchronized` variants. Connected
state can be syncing; synchronized state carries firmware, device I/O profile,
preset name, algorithm catalogue, slots, units, offline/demo flags, dirty state,
performance items, screenshot/video and update availability. Do not treat a
connected manager as proof that synchronized slot state is ready.

`Slot` groups algorithm identity/specification values, routing, parameter pages,
metadata, values, enums, mappings, value strings and output-mode usage. Explicit
hydration flags distinguish device responses from fallback data during strict
respecification. Parameter numbers are identifiers, not necessarily list indices:
start at `domain/parameter_number_lookup.dart` for lookup changes.

The facade `lib/cubit/disting_cubit.dart` composes `part` delegates with private
library access, not independently injectable public modules. Existing work owners:

- Connection/offline: `disting_cubit_connection_delegate.dart`,
  `disting_cubit_offline_demo_delegate.dart`, `disting_cubit_refresh_delegate.dart`.
- Parameter reads/polling/writes/strings: `*_parameter_fetch_delegate.dart`,
  `*_parameter_refresh_delegate.dart`, `*_parameter_value_delegate.dart`,
  `*_parameter_string_delegate.dart`; mappings and CC notification have their
  own delegates. `ParameterUpdateQueue` coalesces latest values; also inspect
  `util/parameter_write_debouncer.dart` for UI write timing.
- Structural operations: `*_algorithm_ops.dart`, `*_preset_ops.dart`,
  `*_slot_ops.dart`; slot maintenance/state, state refresh/helpers and algorithm
  library operations have dedicated delegates.
- Plugins: install, verified install and smoke-test delegates are distinct.
  Verified workflows must preserve confirmation/rescan/cleanup contracts.
- Hardware, monitoring, memory, remote sessions, performance-page items,
  SD-card operations, checkpoints and Lua reload each have named delegates.

`IDistingMidiManager` (`lib/domain/i_disting_midi_manager.dart`) has live
`DistingMidiManager`, `OfflineDistingMidiManager` and `MockDistingMidiManager`
implementations. Offline resolution is not a network backend: it uses local
metadata/presets and specification-aware shapes.

`DistingMessageScheduler` serializes requests (idle → sending → waiting), filters
device/SysEx ID, attributes responses, handles retries/timeouts/cancellation and
stream recovery. Request identity/controls live in `request_key.dart` and
`disting_request_control.dart`. `domain/sysex/requests/`, `responses/`,
`sysex_parser.dart` and `response_factory.dart` own wire encoding/decoding.
`domain/disting_nt_sysex.dart` supplies shared device types.

**Hardware safety:** root instructions cap SysEx at 1024 bytes and upload file
data chunks at 512 bytes; downloads are whole-file only. Do not invent offset /
count download requests, or verify large WAV uploads by whole-file download.

## Screens and feature map

Navigation uses Flutter `Navigator` / `MaterialPageRoute`, dialogs and sheets,
not a discovered go_router route graph. Named routes in `DistingApp` are `/`
and `/template-manager`; most features are pushed from the synchronized shell.
Feature availability depends on platform, firmware, build flags and live/offline
state; a file's existence does not imply all platforms expose it.

| User surface | Primary paths / state owners |
| --- | --- |
| Device selection, demo, offline entry and synchronization | `disting_app.dart`: `DistingPage`; connection/offline delegates |
| Main editing shell, slot tabs, responsive split editing/routing, toolbar, dirty state, settings/status | `ui/synchronized_screen.dart`: `SynchronizedScreen`; `utils/responsive.dart` |
| Slot editing (standard, spreadsheet, controller) | `ui/widgets/slot_detail_view.dart`, `slot_editor_mode.dart`, `parameter_list_view.dart`, `section_parameter_list_view.dart`, `parameter_spreadsheet_view.dart` |
| Specialized parameter editors (BPM/files/strings/numeric) | `ui/parameter_editor_registry.dart`, `ui/bpm_editor_widget.dart`, `ui/widgets/file_parameter_editor.dart`, `parameter_numeric_editing.dart` |
| Add/search/document algorithms and specifications | `ui/add_algorithm_screen.dart`, `algorithm_documentation_screen.dart`, `widgets/algorithm_specification_dialog.dart`; metadata search service |
| Custom algorithm views | `AlgorithmViewRegistry` in `ui/algorithm_registry.dart`: Patch Map (`ThPh`), Notes (`note`), Step Sequencer (`spsq`); `ui/patch_map/`, `notes_algorithm_view.dart`, `step_sequencer_view.dart` |
| CV/MIDI/i2c mapping and MIDI Learn | `widgets/mapping_editor_bottom_sheet.dart`, `packed_mapping_data_editor.dart`, `mapping_edit_button.dart`; `ui/midi_listener/midi_listener_cubit.dart`, pure `midi_detection_engine.dart` |
| Routing canvas/list/bus lanes | `cubit/routing_editor_cubit.dart`, `routing_editor_state.dart`, `ui/widgets/routing/` |
| Performance controls | `ui/performance_screen.dart`, `widgets/performance/`; mapping and performance-page delegates |
| Preset browsing/save/load/packages, drag/drop | `widgets/preset_browser_dialog.dart`, `preset_package_dialog.dart`, `package_install_dialog.dart`; `cubit/preset_browser_cubit.dart` |
| Templates (local presets plus metadata/import/export/apply) | `ui/template_manager/`, `services/template_share_service.dart`, `models/template_metadata.dart`, presets DAO |
| Plugin gallery/download/install/update | `ui/plugin_gallery_screen.dart`, `ui/gallery/`; gallery/plugin services and cubit delegates |
| Poly multisample builder, loose WAV / DecentSampler import, preview, upload/apply | `ui/poly_multisample/`, `lib/poly_multisample/`; individual import/builder cubits and hardware/upload services |
| In-app assistant, settings, history picker, attachments | `chat/ui/`, `chat/cubit/`, `chat/services/`; embedded panel in synchronized shell |
| Metadata synchronization/rescan/export | `ui/metadata_sync/`, `services/metadata_sync_service.dart`, metadata delegates and debug export dialog |
| CPU, memory, screenshots, USB video and remote physical controls | `ui/cpu_monitor_widget.dart`, `widgets/memory_detail.dart`, floating overlays, `remote_control_cluster.dart`, video popup app; monitoring/memory/remote delegates |
| Firmware update and initial-SDP experiment | `ui/firmware/`, `cubit/firmware_update_cubit.dart`, `initial_sdp_experiment_cubit.dart`; availability gates in app/synchronized shell |
| NTX-8CV settings | `ui/ntx_8cv/`, `cubit/ntx_8cv_connection_cubit.dart`, `ntx_8cv_settings_cubit.dart`, `domain/ntx_8cv/` |
| Diagnostics/logging/recovery | `ui/debug_diagnostics_screen.dart`, `ui/common/log_display_page.dart`, `services/startup_log_service.dart`, `debug_service.dart`, `sysex_diagnostics_service.dart`, `util/in_app_logger.dart` |

## Subsystem boundaries

### Routing

`AlgorithmRouting.fromSlot` and `RoutingFactory` choose data-driven and special
algorithm routing classes. `ConnectionDiscoveryService` derives signal paths;
`bus_flow_solver.dart`, `bus_session_resolver.dart`, `aux_bus_consolidation.dart`,
`port_compatibility_validator.dart` and `slot_reorder_planner.dart` support flow,
validation and editing. Models also live in `core/routing/models/` and
`lib/models/`. `RoutingEditorCubit` owns orchestration/layout, widgets render.
`RoutingServiceLocator.setup/reset` registers routing factory, validator and
haptic service with GetIt.

Use `models/device_io_profile.dart` / `DeviceIoProfile.resolve` rather than
hard-coding bus counts: firmware/device responses determine input/output/AUX
ranges; contextual ES-5 buses are special. `node_positions_persistence_service`
handles saved positions. Older `util/routing_analyzer.dart` and
`routing_info_builder.dart` coexist: inspect callers before adding new logic.

### Metadata and algorithm shape

`AlgorithmMetadataService.initialize` imports bundled
`assets/metadata/full_metadata.json` if needed, upgrades I/O flags, loads
`docs/features/` and `docs/algorithms/`, merges synchronized DB metadata, and
builds `AlgorithmTextSearchIndex`. `MetadataSyncService` reads hardware metadata;
`AlgorithmRepeatInferenceService`, `AlgorithmRepeatGrammar`,
`AlgorithmShapeSnapshot` and `OfflineAlgorithmShapeResolver` support compact,
specification-aware offline shapes. Treat repeat inference and active shape
hydration as separate from static algorithm documentation.

### Lua and Patch Helper

`algorithm_controller/algorithm_controller.dart` defines validated controller
documents; `LuaAlgorithmControllerEngine` evaluates immutable slot snapshots as
pure data, removing unsafe globals. UI rendering/actions live under
`ui/widgets/algorithm_controller/`; bundled sources are in
`assets/algorithm_controllers/`. Actions must pass through application controls,
not obtain raw runtime filesystem/network/MIDI access.

`SdCardCompanion` loads GUID-scoped `/programs/helper/<guid>.lua` with a bounded
source budget, bounded isolate evaluation and optional endpoint-scoped scratch
cache. `companion_table.dart`, `domain/patch_map/`, `ui/patch_map/` and
[Patch Helper integration](../patch-helper-integration.md) describe richer
companion/property/table flows. Do not conflate these with firmware Lua reload.

### Packages and plugins

`interfaces/preset_file_system.dart` abstracts preset/device file access, with
`interfaces/impl/preset_file_system_impl.dart` implementation. `PresetAnalyzer`,
`PresetPackageAnalyzer`, `PackageCreator`, `PackageEstimator`, `FileCollector`
and `FileConflictDetector` split dependency collection, analysis and packaging.

`GalleryService`, `PluginUpdateChecker`, `PluginMetadataExtractor` and
`ElfGuidExtractor` handle catalogue/artifact identity. GUID extraction follows
`pluginEntry` relocations and factory struct shape; compiler factory symbol names
are fallback only. Gallery feed GUIDs and multi-file archive collection status
are distinct. `test/fixtures/plugins/` and extractor tests protect real toolchain
layouts; add a provenance/licensed fixture for misdetections, not naming hacks.

## Persistence and startup safety

- `AppDatabase` in `db/database.dart` owns the actual Drift migration strategy;
  `db/tables.dart` defines relational tables, and `db/daos/` separates metadata,
  presets/templates and plugin installations. Do not assume the standalone
  `db/migrations.dart` is the active migration authority; inspect callers.
- `StartupStorageOpener` opens and queries the real library before admission.
  On macOS, application support `nt_helper/library.sqlite` uses `LibraryStorage`
  for one-time legacy import: lock, SQLite backup, migrate a temporary DB, then
  atomic rename. It is not a second database authority layer.
- Other platforms use `nt_helper_db.sqlite` in the app directory resolved by
  `utils/app_directory.dart`; Windows can persistently fall back from unavailable
  Documents to application support. Legacy and macOS paths differ: do not infer
  an installed path from this repository's checkout.
- `GalleryCacheStorage` transfers `gallery_cache.json` independently of DB
  startup. Cache failures should not make library admission fail.
- `SettingsService` uses SharedPreferences (connection choices, UI settings,
  gallery/MCP/chat configuration, allowed file roots); UI theme/scale expose
  notifiers. `NodePositionsPersistenceService` is a separate layout concern.
- `FileConversationStore` writes serialized atomic JSON checkpoints and small
  picker sidecars in application support `chat_conversations/`. Checkpoints are
  passive: loading a conversation never resumes hardware actions by itself.
- `MemoryService` uses application support `chat_memory/`: `memory.md` (line
  capped), append-only daily logs and session snapshots. This is distinct from
  device RAM/memory usage and from chat transcript checkpoints.
- Poly sample preferences, WAV/listing caches, companion scratch files, temporary
  package files and startup/flash logs have separate owners. Inspect
  `poly_sample_preferences_service.dart`, `wave_cache_maintenance_service.dart`,
  `sample_directory_listing_cache.dart` and `utils/temp_directory_utils.dart`.

## Network, authentication and trust

No central app login/account backend was found in inspected entry paths.
Network operations are feature-specific Dart HTTP clients and local/native I/O:

- Gallery feed is configurable in `SettingsService`; `GalleryService` fetches
  feed/artifacts and GitHub release data. App updates query GitHub releases;
  `FirmwareVersionService` parses Expert Sleepers firmware listings;
  `FlashToolManager` obtains `nt-flash`. TLS support/diagnostics live in
  `github_tls_support.dart`, `tls_certificate_diagnostics.dart` and bundled
  certificate assets. Do not weaken TLS to solve connectivity.
- `McpServerService` is Streamable HTTP on `/mcp`, default port 3847; supports
  POST/GET/DELETE, sessions and event replay. Disabled by default in settings;
  desktop normally binds loopback, with explicit remote binding option.
  iPad support is foreground/settings/network gated and validates local-network
  peers/hosts. Android is not admitted by the inspected service platform gate.
  No application bearer-token enforcement was found in its inspected request
  dispatch; an Authorization CORS header alone is not authentication. Do not
  expose remote MCP as if it were an authenticated public service.
- `mcp/tool_registry.dart` is the shared execution/schema boundary. Tool classes
  in `mcp/tools/` adapt via `DistingController` / `DistingControllerImpl` or cubit
  operations. `ToolReferenceStore` supports bounded/progressive reference data.
  Do not implement an independent chat-only device command API.
- `ChatCubit` owns conversations, cancellation/generation isolation, compaction
  and checkpoints; `ChatService` delegates ordered model/tool rounds to Dart
  Genkit. `ToolBridgeService` adapts registry calls/results; provider transports
  retain wire/auth behavior. No Node sidecar, remote agent backend or MCP client
  is enabled by that inspected loop.
- `createChatProvider` selects Anthropic API/subscription, OpenAI API,
  OpenAI Subscription (Codex), Gemini, OpenRouter or local/OpenAI-compatible
  transports. Model catalog/endpoint normalization/history codecs are separate
  services. Gemini/OpenRouter/local reuse the compatible transport, not new loops.
- Codex subscription uses existing local desktop sign-in; refresh requires
  remembered user consent after unauthorized response and may rotate credentials.
  See [ADR 0001](../adr/0001-use-codex-local-auth-for-openai-subscription-chat.md).
  Credentials are preferences/local auth state, not an encrypted vault introduced
  by this app; never copy credentials, transcripts, local auth files or env values
  into architecture docs or diagnostics.
- Chat memory and bounded local-file tools are registered as chat-only tools;
  allowed roots/actor permissions constrain reads/search/writes. Inspect
  `chat/models/allowed_file_root.dart`, `chat/services/local_file_tools.dart` and
  registry filtering before changing exposure. Presence in a shared registry
  does not imply unrestricted filesystem access over external MCP.

## Native platform boundaries

USB video spans `domain/video/usb_video_manager.dart`, `VideoFrameCubit`,
`services/platform_channels/` and per-platform native capture implementations.
The manager includes reconnect/backoff/watchdog and screenshot fallback paths.
Desktop popup control is IPC, including a Windows native popup backend; inspect
`video_popup_remote_contract.dart` and `video_popup_window_service.dart` together.

- Android: `android/app/src/main/kotlin/com/example/nt_helper/MainActivity.kt`,
  `UsbVideoCapturePlugin.kt`; USB permissions/manifest and UVC dependency matter.
- iOS: `ios/Runner/AppDelegate.swift`, `UsbVideoCapturePlugin.swift`,
  `IosFileAccessPlugin.swift`, `InitialSdpPlugin.swift`, `FirmwareSessionPlugin.swift`
  and `FirmwareSessionState.swift`; entitlements and local network permissions
  constrain experimental firmware/MCP features.
- macOS: `macos/Runner/AppDelegate.swift`, `MainFlutterWindow.swift`,
  `UsbVideoCapturePlugin.swift`; sandbox, storage-access and popup/window channels.
- Windows: `windows/runner/main.cpp`, `flutter_window.cpp`,
  `usb_video_capture_plugin.cpp`, `windows_video_popup_manager.*`,
  `windows_video_popup_remote.h`; early native logging can precede Dart startup.
- Linux: `linux/main.cc`, `my_application.cc`, `usb_video_capture_plugin.cc`.

Desktop firmware uses `FlashToolBridge` to spawn `nt-flash` with machine-readable
progress (Linux via `pkexec`); sandboxed builds need special executable/temp-path
handling. iPad firmware-session and initial-SDP transports use MethodChannel /
EventChannel instead; the experiment is not proof of general mobile flashing.
`utils/build_config.dart` and app route gates distinguish store capabilities.

## Build and verification

Stack owners: `pubspec.yaml` / lockfile (Flutter/Dart, MIDI, Bloc/Freezed, Drift,
HTTP, Genkit, Lua, native video), `analysis_options.yaml` (Flutter lints), and
`.github/workflows/ci.yml` (actual CI SDK pin). The declared Dart floor is not
sufficient to infer the usable toolchain: the manifest notes a higher Genkit
requirement. Read current workflow/dependency constraints before SDK changes.

```sh
# Fresh checkout/worktree setup; generated source is not hand-maintained.
flutter pub get
dart run build_runner build --delete-conflicting-outputs
# For Dart changes, choose affected files and then neighboring tests.
dart format --output=none --set-exit-if-changed <changed-dart-files>
flutter analyze --no-pub
flutter test --no-pub test/path/to/affected_test.dart
# Current CI selection (different from full release-local suite):
flutter test --no-pub --tags regression
# Release-local full suite, required by root instructions:
flutter test --no-pub
# Scripts have separate Python tests:
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

**Documentation drift observed:** `AGENTS.md`, `test/AGENTS.md` and parts of
`developer-feedback.md` describe full/default ordinary CI tests; the inspected
`ci.yml` actually uses `--tags regression`, as does
[testing-regression-classification.md](../testing-regression-classification.md).
Use workflow source for what CI executes; do not silently weaken release checks.

Tests mirror `domain`, `cubit`, `services`, `core/routing`, `ui`, `mcp`, `chat`,
`algorithm_controller`, `poly_multisample`, `db`, `models`, `util` and `utils`.
`test/test_helpers/`, `test/support/` and `test/fixtures/` hold wire/device/native
harnesses and real artifacts. `test/native/` has Swift/C++ popup contracts;
`tool/run_video_popup_backend_tests.sh` drives native checks.
`integration_test/memory_flow_test.dart` and `hardware_test/` are separate from
ordinary unit/widget runs; read [hardware prerequisites](../../hardware_test/README.md)
and `tool/run_hardware_tests.sh` before any device-mutating test.

`tag-build.yml` owns platform distribution; `production-release.yml` handles
store promotion, and retention/notes/version scripts have Python tests. The
`version` script is release tooling, not a harmless inspection command. Follow
root release instructions/skill rather than rebuilding a release process here.

Cross-cutting requirements: immutable state, cancellation/disposal of subscriptions,
bounded deterministic async tests, fixed loading/error geometry, screen-reader
semantics/live announcements, keyboard/focus traversal and no unsolicited debug
logging. The MIDI Learn detection engine and local mapping-editor open state
must remain distinct ([ADR 0002](../adr/0002-preserve-midi-learn-and-mapping-editor-boundaries.md)).

## Documentation shelf

- Instructions/boundaries: [AGENTS](../../AGENTS.md), [architecture guide](../architecture.md),
  [coding standards](coding-standards.md), [CONTEXT terminology](../../CONTEXT.md),
  [test guidance](../../test/AGENTS.md), [developer feedback](../developer-feedback.md).
- Device/protocol: [SysEx](../SYSEX_REFERENCE.md), [menu map](../disting-nt-menu-map.md),
  [NTX-8CV protocol](../ntx_8cv_protocol.md) and [acceptance](../ntx_8cv_hardware_validation.md).
- Tool API: [MCP API](../mcp-api-guide.md), [mappings](../mcp-mapping-guide.md),
  [remote tutorial](../mcp-remote-control-tutorial.md),
  [connected memory evidence](../mcp-memory-connected-validation.md).
- Metadata/controllers: [collection process](../metadata-collection-process.md),
  [Lua controllers](../lua-algorithm-controllers.md),
  [Patch Helper](../patch-helper-integration.md), `docs/schema/`, `docs/algorithms/`,
  `docs/features/`, `docs/plugin_gallery_schema.json`.
- Chat: [providers](../chat-providers.md), [Genkit migration assessment](../genkit-chat-migration.md),
  [runtime alternatives](../chat-agent-runtime-options.md),
  [conversation picker review](../chat-conversation-picker-review.md), [ADRs](../adr/).
  Assessments contain historical proposals; current source decides implementation.
- UX: [accessibility summary](../a11y/00-summary.md),
  [blind coverage checklist](../a11y/blind-coverage-checklist.md),
  [keyboard scheme](../a11y/keyboard-navigation-scheme.md).
- Platform acceptance/operations: [iPad SDP experiment](../ipad-initial-sdp-development.md),
  [Windows storage verification](../windows-startup-storage-verification.md),
  [macOS TestFlight setup](../macos-testflight-setup.md),
  [Windows runner access](../dev-windows-runner-access.md). Keep operational
  credentials and machine state out of this index.
- `docs/investigations/` and `docs/reports/` are historical evidence, not proof of
  current hardware behavior; `specs/README.md` explains active program lifecycle.
- README links external user documentation. External website content, gallery
  server code and `nt-flash` source are not part of this inspected checkout.

## Retrieval and refresh

Start a future session with root instructions → bootstrap summary → relevant
section → owning source → nearest tests. Use repository-relative commands:

```sh
git status --short; git rev-parse --short HEAD
git ls-files 'lib/**' 'docs/**' 'test/**' 'hardware_test/**'
# Source only (exclude generated output when discovering behavior):
rg -n 'class |sealed class |abstract interface class |part ' lib \
  -g '*.dart' -g '!*.g.dart' -g '!*.freezed.dart' -g '!*.mocks.dart'
rg -n 'Navigator\.|MaterialPageRoute|buildRoutes|showDialog|showModalBottomSheet' lib
rg -n 'updateParameterValue|respecifyAlgorithm|saveMapping' lib test
rg -n 'ToolRegistryEntry\(|name:|registerWithServer|chatOnly' lib/mcp
rg -n 'MethodChannel|EventChannel|Process\.start|HttpServer|http\.' lib
rg -n '^#{1,3} ' docs -g '*.md'
# Find contracts by symbol as well as by feature filename:
rg -l 'DistingMessageScheduler|OfflineAlgorithmShapeResolver' test hardware_test
```

For semantic relationship work, root guidance requests the `graphify` skill and
Substrate-registered Graphify tools only: find the skill/service first, then use
small graph queries and relevant communities, corroborating with source. Never
rebuild/connect directly to a standalone graph just because the integration is
unavailable. In this scouting session `search_skill(query: "graphify")` returned
no registered skill; this index therefore rests on direct source inspection,
not a graph freshness/completeness claim.

Refresh this document after boundary/navigation/storage/runtime changes:

1. Record new commit/branch; inspect `git diff 6302310d..HEAD -- lib docs test
   pubspec.yaml .github/workflows` (replace baseline after refresh).
2. Re-read main/bootstrap, app routes, state unions, changed delegate parts,
   registry, storage opener/migrations and actual workflow commands.
3. Trace callers and tests for changed features; update owners and links, not
   copied method/dependency/version inventories. Explicitly retain unresolved
   contradictions and untested platform/hardware claims.
4. Run `git diff --check` and relative Markdown link checks for changed docs.
   Docs-only changes need no unrelated Flutter run; Dart changes use root/test
   guidance. Never regenerate metadata or mutate a device merely to refresh prose.
5. Update the inspected baseline and coverage notes. Keep secrets, user memory,
   local auth state and incidental scratch files out of the result.

## Coverage and open gaps

Verified by reading actual checkout files and targeted symbol/caller searches:
entry/bootstrap paths, state/delegate structure, navigation call sites, core
protocol/scheduler, routing/profile owners, persistence/open/import paths, shared
MCP/chat registry and provider creation, controller runtime boundaries, workflow
source and existing documentation headings. Major subsystems are indexed; not
every source file, API method, test assertion or historical document was read.

Not performed: launching/restarting the app, Flutter analyze/tests/builds, native
compilation, real MIDI/USB/firmware operations, paid provider requests, credential
inspection, release/remote branch checks or external website validation. Hardware
and provider compatibility, installed permissions/storage paths, graph currency,
complete security audit and end-to-end platform availability remain unverified.
The CI prose/command discrepancy above is recorded, not changed by this docs task.
