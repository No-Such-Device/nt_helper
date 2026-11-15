# Flutter 3.50 and dependency upgrade review

## Toolchain

Discovered with `fvm releases`: latest stable is **3.50.0** (11 November 2026).
The clean baseline was `443fc45a` on `main`; local global Flutter was 3.47.9
with Dart 3.13.7, while CI/release builds still pinned Flutter 3.44.9.

Using **FVM 4.3.2**, ran `fvm install 3.50.0`, `fvm global 3.50.0`, and
`fvm use 3.50.0 --skip-pub-get`. Global `flutter` and `dart` both resolve through
`$HOME/fvm/default/bin`; that symlink points to `$HOME/fvm/versions/3.50.0`.
Flutter reports framework `ab2912035e`, engine `371f77202a`, and bundled
**Dart 3.14.0**. No independent Dart installation or shell PATH edits were needed.

`.fvmrc`, the pubspec SDK minimums, CI, release workflow and current development
instructions now agree. Historical validation records retain their original
versions. No application restart, firmware operation or release/tag is needed.

## Commands and migration policy

- `dart fix --dry-run` proposes supported source migrations; `dart fix --apply`
  applies them. It is not a dependency updater. Reviewed and applied selected
  `deprecated_member_use`, `extraneous_modifier`, `missing_dependency`,
  `prefer_initializing_formals` and `unused_import` fixes, then inspected the
  dependency additions instead of retaining generated `any` constraints.
- `flutter pub outdated --json` compares locked, upgradable, resolvable and latest
  versions. `flutter pub upgrade` updates the lockfile within constraints;
  `flutter pub upgrade --major-versions --dry-run` previews constraint changes.
  After changelog/native review, used `--major-versions` and deliberately bounded
  the incompatible packages below. The final `flutter pub upgrade --dry-run`
  reports **no dependency changes**.
- Regenerated Freezed, Drift, JSON and Mockito outputs with the bundled Dart.
  `build_runner` now ignores the removed `--delete-conflicting-outputs` option;
  `dart run build_runner build` is sufficient.
- Formatted all changed Dart files with Dart 3.14. Mixed CRLF/LF in the scheduler
  was normalized, and generated trailing whitespace was removed. No new analyzer
  ignores, skips or weakened assertions were added. Flutter's automatic
  platform-directory analyzer exclusions were not retained.

## Dependency changes

Versions below are resolved versions before/after, not merely old caret floors.
Unchanged direct dependencies were reviewed through pub's resolver as well.
The lockfile comparison contains **33 direct version changes + 3 new direct
packages**, **68 transitive version changes + 14 new transitive packages**, and
two removed packages (`flutter_markdown`, `markdown`). This is the measured
before/after count, rather than the earlier approximate transitive count.

| Package | Before | After |
|---|---|---|
| `analyzer` | 10.2.0 | 14.7.0 |
| `archive` | 4.0.9 | 4.7.1 |
| `build_runner` | 2.15.1 | 2.16.2 |
| `camera` | 0.12.0+2 | 0.12.2 |
| `clock` | 1.1.2 | 1.1.3 |
| `cross_file` | 0.3.5+4 | 0.3.5+5 |
| `crypto` | 3.0.7 | 3.0.8 |
| `cupertino_icons` | 1.0.9 | 2.0.0 |
| `desktop_drop` | 0.7.1 | 0.8.4 |
| `desktop_multi_window` | 0.3.0 | 0.3.1 |
| `drift` | 2.34.3 | 2.35.4 |
| `drift_dev` | 2.34.0 | 2.35.3 |
| `file_picker` | 12.0.0-beta.7 | 13.3.3 |
| `file_picker_darwin` | new | 2.5.1 |
| `flutter_midi_command` | 1.0.9 | 1.4.0 |
| `flutter_midi_command_platform_interface` | 1.0.9 | 1.4.0 |
| `flutter_svg` | 2.3.0 | 2.4.0 |
| `freezed` | 3.2.5 | 4.0.3 |
| `genkit` | 1.0.0 | 1.0.2 |
| `get_it` | 9.2.1 | 9.3.0 |
| `gpt_markdown` | new | 1.4.1 |
| `haptic_feedback` | 0.6.5 | 0.8.0 |
| `html` | 0.15.6 | 0.15.7 |
| `image` | 4.8.0 | 4.13.1 |
| `json_serializable` | 6.14.1 | 6.15.2 |
| `lua_dardo_plus` | 0.3.0 | 0.3.1 |
| `material_ui` | new | 1.11.0 |
| `mockito` | 5.6.4 | 5.8.1 |
| `package_info_plus` | 10.2.1 | 10.2.2 |
| `pasteboard` | 0.5.0 | 0.6.0 |
| `pub_semver` | 2.2.0 | 2.2.1 |
| `share_plus` | 13.3.0 | 13.3.1 |
| `shared_preferences` | 2.5.5 | 2.5.6 |
| `sqlite3` | 3.5.1 | 3.9.1 |
| `url_launcher` | 6.3.2 | 6.3.3 |
| `vector_math` | 2.2.0 | 2.4.4 |

### Source and native migrations

- Migrated SDK Material imports to the official
  [`material_ui`](https://pub.dev/packages/material_ui) package, including tests.
- Removed six `final` parameter modifiers rejected by Dart 3.14/Freezed 4.
- File Picker 13 returns an empty list on cancellation and a nullable URI after
  saving. Updated callers, removed no-op save filters, supplied appropriate MIME
  types, and preserved Android `content:` destinations without treating them as
  local paths. Attachment size checks handle unknown sizes before reading bytes.
- The discontinued `flutter_markdown` and suggested `flutter_markdown_plus`
  replacement both still use SDK Material classes. Replaced them with
  [`gpt_markdown` 1.4.1](https://pub.dev/packages/gpt_markdown/changelog), whose 1.4
  migration supports `material_ui`, rather than adding deprecated compatibility
  bridges or analyzer suppressions. Kept chat selection, reply announcements,
  scrolling, theme styling and release-note link callbacks. HTML and animation
  are disabled; no new code-copy controls are exposed.
- Merged root-note button semantics so its label/value and expanded/menu action
  remain one accessible control with the new Material implementation. Existing
  geometry/keyboard assertions remain, and new renderer/URI regressions cover
  the migration boundaries.
- Updated tooltip test locators for explicit, semantics-excluded Material
  tooltips; the SDK finder only recognizes those from the old Material library.
  Awaited external font loading with `runAsync` and explicit frame completion.
- Archive 4.7 normalizes backslashes on ZIP encoding. Restored raw unsafe names
  in the existing test fixture bytes so firmware preflight regressions still
  test malformed packages rather than silently accepting a sanitized fixture.
  The first Linux CI run also exposed a timestamp-sensitive immutable-copy
  assertion: a second ZIP encoding could cross a second boundary. Compare the
  snapshot against the actual original ZIP bytes instead, retaining the exact
  byte-equality assertion without delays, skips or weaker coverage.
- `desktop_multi_window` 0.3.1 uses Swift Package Manager. The macOS pod lockfile
  and generated Xcode/plugin registration changes were refreshed by the build.
- CI now runs the full default suite, removing the old regression-tag filter to
  satisfy the repository's required-check contract for this toolchain upgrade.

## Intentionally held versions

All remaining outdated entries were checked against package manifests; no extra
pub overrides were added to force an unsupported combination.

| Packages held | Reason |
|---|---|
| `window_manager` 0.5.2 (latest 0.7.0), `screen_retriever` 0.2.2 (latest 0.4.0) | 0.6+ replaces platform channel/native window code with nativeapi FFI and a new synchronous window API. The app's persisted bounds, startup visibility, custom macOS delegate, popup close veto and channel lifecycle regressions depend on 0.5.x. Its deprecated bridge would not meet zero-issue analysis. Keep the working implementation pending a separately verified native window migration. |
| `cross_file` 0.3.5+5 (latest 0.4.0), `desktop_drop` 0.8.4 (latest 0.9.2) | File Picker 13.3.3, Share Plus 13.3.1 and the pinned UVC fork require cross_file 0.3.x. Desktop Drop 0.9 requires its incompatible 0.4 federated types. |
| `equatable` 2.1.0 (latest 3.0.0) | The pinned UVC fork still requires ^2.0.7. |
| `build_runner` 2.16.2, `build` 4.0.11, `build_config` 1.3.3 | Latest Mockito 5.8.1 requires build <5. Runner 2.17.1 requires build 5; runner 2.16 requires build_config <1.4. |
| `built_collection` 5.1.2 (latest 6.0.0) | built_value 8.13.0 and compatible build_runner require 5.x. |
| `cli_util` 0.4.2 (latest 0.6.0), `coverage` 1.15.1, `vector_graphics_compiler` 1.3.4 | flutter_launcher_icons 0.14.4 requires cli_util ^0.4.1; latest coverage/compiler require ^0.6.0. |
| `xml` 7.0.1 (latest 7.1.0) | The SVG compiler has an audited upper bound <=7.0.1. |
| `dbus` 0.7.15 (latest 0.8.0) | Retained by compatible desktop/platform dependencies. |
| `test` 1.32.0, `test_api` 0.7.14, `test_core` 0.6.20 | Flutter 3.50 pins test_api 0.7.14; latest test/test_core require 0.7.15. |
| `material_color_utilities` 0.13.0 (latest 0.13.1) | Flutter's SDK pin. |

### Git dependencies

- Updated the owned [UVC fork](https://github.com/thorinside/UVCCamera/commit/ca9e82ed151c3175498a4897cc6a05d81cd6246e)
  from frame-streaming commit `31bdb66472a0cde05ee6ab3de426661c96f3bb45` to its
  direct child `ca9e82ed151c3175498a4897cc6a05d81cd6246e` on
  `fix/flutter-agp9-library-config`. The entire external diff removes only the
  obsolete Android library `defaultConfig.targetSdk` line, which AGP 9 removed.
  All custom frame-streaming/native changes remain. No pub cache was patched.
  Both Android release jobs now build the native AAR from that same immutable
  owned-fork commit, instead of a floating branch in a different fork.
- Pinned the existing Linux MIDI override to the currently resolved upstream
  HEAD `67e2c8ce5d25670ff1d16bf97cc2198bad378c1f`, retaining the ALSA shutdown fix
  without allowing future floating git updates. No path dependencies were added.

## Android setup and official guidance

Consulted current official documentation, not just build-error suggestions:

- [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup)
- [Flutter built-in Kotlin migration for apps](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
- [AGP 9.3 compatibility](https://developer.android.com/build/releases/agp-9-3-0-release-notes)
- [Gradle 9.5 compatibility](https://docs.gradle.org/9.5.0/userguide/compatibility.html)
- [Kotlin Gradle plugin compatibility](https://kotlinlang.org/docs/gradle-configure-project.html)

Flutter 3.50's own template constants select **Gradle 9.5.0 / AGP 9.3.1 /
KGP 2.4.20**. AGP 9.3 requires Gradle 9.5, Build Tools 36.0.0 and JDK >=17.
KGP 2.4.20 explicitly supports Gradle through 9.7 and AGP through 9.3.1.
The local Android Studio JBR is **21.0.10**, supported by Gradle 9.5; Java and
Kotlin bytecode targets remain 17. Release CI retains its supported JDK 17.

Existing installed SDK components already satisfy the documented setup: Android
platform **36 revision 2** (compile/target 36), **Build Tools 36.0.0**,
**Command-line Tools 20.0**, **CMake 3.22.1**, and **NDK 28.2.13676358 (r28c)**.
The UVC native library separately uses its existing **AGP 8.9.1 / Gradle 8.13 /
NDK 27.0.12077973** build; both NDKs are explicitly installed by release CI.
No new JDK/SDK/NDK/CMake installation or global Flutter/JDK reconfiguration was
necessary in this continuation. Gradle downloaded the UVC wrapper's 8.13
distribution. Rebuilt and published the owned fork's native AAR to Maven Local,
then rebuilt the Android app against it.

Flutter's official migration guide explicitly documents temporary
`android.builtInKotlin=false` and `android.newDsl=false` compatibility flags.
They remain necessary because docman still applies KGP and audioplayers' JUnit
plugin needs the legacy DSL. Host-managed KGP is shared with Android libraries,
including MIDI/clipboard/haptics, that now expect built-in Kotlin. Compiler
options use Kotlin's current `compilerOptions` API. These are documented
transition settings, not permanent claims of built-in-Kotlin compatibility.
Upstream migration warnings remain visible; no diagnostics are suppressed.

Reviewed licenses using `flutter doctor --android-licenses`. The only unaccepted
license is **microxr-sysimage-license**, for an unrelated preview XR emulator;
it was deliberately not accepted or installed. Required standard Android SDK
licenses are already accepted. Doctor also reports duplicate existing adb
installations; no unrelated PATH or device changes were made.

An initial `--no-pub` release attempt reused the development plugin registrant,
which included integration_test while release Gradle correctly excluded it.
Flutter 3.50 skips platform-tooling regeneration with `--no-pub`; building with
normal pub/tooling regeneration resolved that mismatch without source patches.
Use `flutter build apk --debug` for the validated Android workflow.

## Final verification

- `dart run build_runner build`: passed; regenerated Freezed/Drift/JSON/Mockito.
- `flutter analyze --no-pub`: **zero issues**.
- `flutter test --no-pub --reporter expanded`: **4,576 passed, one existing
  hardware opt-in skipped**, no failures (full default suite).
- `flutter build macos --release --no-pub`: **passed**, 108.7 MB app.
- `flutter build apk --debug`: **passed** against the freshly rebuilt owned UVC
  native library. `apksigner verify` and `zipalign -c -P 16 4` passed. All eight
  packaged UVC shared libraries across arm64-v8a/armeabi-v7a have 16 KB ELF LOAD
  alignment.
- External fork: `./gradlew :lib:assembleRelease
  :lib:publishReleasePublicationToMavenLocal` with Android Studio's JBR: passed.
- `dart format --output=none --set-exit-if-changed <all changed Dart files>`:
  **317 files, zero changes**. Broad source/test churn is primarily the required
  Material import migration and Dart 3.14 formatting, plus regenerated outputs.
  Scheduler CRLF normalization explains its large line count; its substantive
  edits are supported initializing-formal fixes, not scheduling changes.
- `flutter pub upgrade --dry-run`: no dependency changes.
- `python3 -m unittest discover -s scripts -p 'test_*.py' -v`: **44 passed**.
- Changed Markdown relative links resolve. Live main-branch rules require a PR
  and the **CI success** check through `main-pull-requests-only`; no repository
  protection settings were changed.
- `git diff --check` and
  `actionlint .github/workflows/ci.yml .github/workflows/tag-build.yml`: passed.
  Quoted existing shell output/artifact paths in the touched release workflow
  to clear its pre-existing ShellCheck diagnostics; no jobs, signing, store
  uploads, runner routes or packaging were removed.

The requested Android acceptance is a **debug APK**, not production release
signing. Before that clarification, a release-mode APK also compiled/packaged
using the existing standard Android debug keystore through environment variables;
this is **not** a production-signed release validation. The release keystore is
not present, no credentials were sought, and signing configuration is unchanged.
The final debug build used the newly rebuilt native AAR. No APK was installed
or launched, no app was restarted, and no firmware/hardware workflow was run.

Linux, Windows and iOS binaries, Play/TestFlight distribution and production
Android signing were not verified. Native upstream deprecation warnings remain
visible. Substrate/Graphify discovery was retried but the MCP session is expired;
no stale graph result was used. No version bump, release, tag or merge is
requested. Delivery is a validated commit and PR on `chore/flutter-3.50.0`.
