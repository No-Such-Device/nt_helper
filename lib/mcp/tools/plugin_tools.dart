import 'dart:convert';

import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/services/local_file_tools.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/models/plugin_install_report.dart';
import 'package:nt_helper/models/plugin_smoke_test_report.dart';
import 'package:path/path.dart' as path;

/// Registers `install_plugin` and `smoke_test_plugin` for [actor]. Local
/// reads are limited to the allowed roots that grant [actor] read
/// permission, exactly as `read_file`.
void registerPluginTools(
  List<ToolRegistryEntry> entries,
  DistingCubit cubit, {
  required FileRootActor actor,
}) {
  final tools = PluginTools(cubit, actor: actor);
  entries.add(
    ToolRegistryEntry(
      name: 'install_plugin',
      description:
          'Install a C++ plug-in (.o) or Lua script (.lua) from this computer '
          'onto the connected Disting NT SD card, then verify it. .o files go '
          'to /programs/plug-ins/ and trigger a plug-in rescan; the result lists '
          'the algorithms the device reports for the file (matched by the GUIDs '
          'inside it) and whether every expected GUID appeared. .lua files go to '
          '/programs/lua/ and are verified by SD listing only. Requires a live, '
          'synchronized device; refused in offline and demo mode. Before any '
          'upload, a .o must be a 32-bit little-endian ARM relocatable ELF '
          'that defines pluginEntry and at least one factory GUID, and none of '
          'its GUIDs may belong to a built-in algorithm or to a plug-in from a '
          'different file (reinstalling the same file is allowed). If the '
          'algorithm list is still loading in the background, the .o check '
          'waits up to 10 s for it, then refuses with '
          'algorithm_library_loading. A .lua must '
          'be UTF-8 text without NUL bytes. The file must '
          'be inside an allowed root with MCP read permission (see '
          'list_allowed_roots) and at most 2 MiB. Upload runs at roughly '
          '5-10 KB/s. If the .o is in use by the current preset, the preset is '
          'cleared for the upload and reloaded from its last saved copy, so call '
          'save first to keep unsaved edits. An existing file with the same '
          'name is overwritten.',
      inputSchema: {
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute local path of the file to install, ending in .o or '
                '.lua, for example /Users/me/plugins/build/myfilter.o. The file '
                'name is kept on the SD card.',
          },
          'load': {
            'type': 'boolean',
            'default': false,
            'description':
                'For .o files only: after the rescan, load every algorithm '
                'found for the file so it is ready to add without a delay. '
                'Default: false. Rejected for .lua files.',
          },
        },
        'required': ['path'],
        'additionalProperties': false,
      },
      handler: tools.installPlugin,
      timeout: const Duration(minutes: 10),
    ),
  );
  entries.add(
    ToolRegistryEntry(
      name: 'smoke_test_plugin',
      description:
          'Smoke-test an installed plug-in on the connected Disting NT. '
          'Loads it if needed, appends it as a new slot at the end of the '
          'current preset, waits settle_ms, then checks that the slot answers '
          'with the plug-in GUID and at least one parameter (or the exact '
          'expected_parameter_count and expected_parameter_names), and samples '
          'CPU cpu_samples times. Fails if the slot\'s peak CPU exceeds '
          'cpu_budget_percent (the per-slot percentage show_cpu reports) or, '
          'when set, if either core exceeds max_core_percent. Afterwards the '
          'slot is removed and the device is asked to confirm the original '
          'slot lineup, unless every check passed and keep is true. The '
          'preset is never saved. If the removal cannot be confirmed, the '
          'last saved preset is reloaded from the SD card, automatically only '
          'when the preset had no pre-existing or observed intervening edits, '
          'or with reload_saved_on_failure. Stale baselines are refused; '
          'structural/connection conflicts or a different cleanup-slot GUID '
          'stop deletion and reload. Concurrent smoke tests are refused. '
          'The result reports each check, the CPU '
          'samples, and rollback (kept, not_needed, removed_slot, '
          'reloaded_saved_preset or failed). Requires a live, synchronized '
          'device; refused in offline and demo mode and when all slots are '
          'in use, and with algorithm_library_loading if the algorithm list '
          'is still loading after 10 s. Typical use: install_plugin with load: true, then this.',
      inputSchema: {
        'properties': {
          'guid': {
            'type': 'string',
            'description':
                'GUID of the installed plug-in algorithm to test, for example '
                'MyFl. install_plugin reports it in algorithms[].guid.',
          },
          'cpu_budget_percent': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description':
                'Highest CPU percentage the test slot may reach in any '
                'sample, in the per-slot units show_cpu reports as '
                'usage_percent.',
          },
          'max_core_percent': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'description':
                'Optional ceiling for either core\'s total CPU percentage '
                '(cpu1_percent and cpu2_percent in show_cpu) during sampling. '
                'Exceeding it fails with core_cpu_over_budget.',
          },
          'specifications': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description':
                'Specification values for the test slot, as in add. Count and '
                'ranges must match the loaded plug-in\'s definitions. Default: '
                'each specification\'s default value.',
          },
          'expected_parameter_count': {
            'type': 'integer',
            'minimum': 1,
            'description':
                'Exact number of parameters the slot must report. Default: '
                'at least one.',
          },
          'expected_parameter_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Names the first parameters must have, in order. Leading and '
                'trailing spaces are ignored. Default: names are not checked.',
          },
          'settle_ms': {
            'type': 'integer',
            'minimum': 0,
            'maximum': PluginTools.maxSettleMs,
            'default': 1000,
            'description':
                'Wait after the slot is confirmed and before the checks, in '
                'milliseconds. Default: 1000.',
          },
          'cpu_samples': {
            'type': 'integer',
            'minimum': 1,
            'maximum': PluginTools.maxCpuSamples,
            'default': 3,
            'description':
                'CPU samples to take, 250 ms apart. The peak is judged. '
                'Default: 3.',
          },
          'keep': {
            'type': 'boolean',
            'default': false,
            'description':
                'Keep the test slot when every check passes. It stays at the '
                'end of the preset and the preset is not saved. Default: '
                'false. Failed tests attempt cleanup only when the target can '
                'be identified safely.',
          },
          'reload_saved_on_failure': {
            'type': 'boolean',
            'default': false,
            'description':
                'If removing the test slot cannot be confirmed and the preset '
                'has unsaved edits, reload the last saved preset anyway. '
                'Parameter values from before the test are written back when '
                'the slot lineup matches; later parameter edits and other '
                'unsaved edits are lost. Structural/connection conflicts '
                'detected during the test block reload even with opt-in. '
                'Default: false, which leaves the slot and reports '
                'rollback: failed.',
          },
        },
        'required': ['guid', 'cpu_budget_percent'],
        'additionalProperties': false,
      },
      handler: tools.smokeTestPlugin,
      timeout: const Duration(minutes: 2),
    ),
  );
}

/// Handlers behind the plugin MCP tools.
final class PluginTools {
  /// Creates handlers that read local files as [actor] and install them
  /// through [_cubit]. [maxRescanAttempts] and [rescanPollInterval] bound the
  /// wait for a rescanned `.o` to appear; [libraryReadyTimeout] bounds the
  /// wait for a background algorithm-list load before GUIDs are checked.
  PluginTools(
    this._cubit, {
    required this.actor,
    this.maxRescanAttempts = 5,
    this.rescanPollInterval = const Duration(seconds: 1),
    this.libraryReadyTimeout = const Duration(seconds: 10),
  });

  final DistingCubit _cubit;

  /// Caller whose allowed-root read permission governs local file access.
  final FileRootActor actor;

  /// Maximum algorithm-list reads while waiting for a rescan.
  final int maxRescanAttempts;

  /// Delay between algorithm-list reads while waiting for a rescan.
  final Duration rescanPollInterval;

  /// Longest wait for a background algorithm-list load to finish before
  /// `install_plugin` checks collisions or `smoke_test_plugin` looks up the
  /// GUID. Still loading after this, both refuse with
  /// `algorithm_library_loading`.
  final Duration libraryReadyTimeout;

  /// Largest file `install_plugin` accepts, in bytes.
  static const maxFileBytes = 2 * 1024 * 1024;

  /// Lower-case extensions `install_plugin` accepts.
  static const supportedExtensions = {'.o', '.lua'};

  /// Longest `settle_ms` `smoke_test_plugin` accepts.
  static const maxSettleMs = 5000;

  /// Most `cpu_samples` `smoke_test_plugin` accepts.
  static const maxCpuSamples = 10;

  static const _smokeTestArguments = {
    'guid',
    'cpu_budget_percent',
    'max_core_percent',
    'specifications',
    'expected_parameter_count',
    'expected_parameter_names',
    'settle_ms',
    'cpu_samples',
    'keep',
    'reload_saved_on_failure',
  };

  /// Handles `install_plugin`. Always returns a JSON object with `success`;
  /// failures carry a snake_case `error` code and a readable `message`.
  Future<String> installPlugin(Map<String, dynamic> args) async {
    final unknown = args.keys.where((k) => k != 'path' && k != 'load');
    if (unknown.isNotEmpty) {
      return _failure(
        'unknown_argument',
        'Unknown argument(s): ${unknown.join(', ')}. Accepted: path, load.',
      );
    }
    final rawPath = args['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return _failure(
        'missing_path',
        'path is required: the absolute local path of a .o or .lua file.',
      );
    }
    final load = args['load'] ?? false;
    if (load is! bool) {
      return _failure('invalid_load', 'load must be true or false.');
    }
    final localPath = rawPath.trim();
    final extension = path.extension(localPath).toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      return _failure(
        'unsupported_extension',
        'Only .o (C++ plug-in) and .lua (Lua script) files can be installed; '
            'got "${extension.isEmpty ? '(none)' : extension}".',
      );
    }
    if (load && extension == '.lua') {
      return _failure(
        'load_not_supported',
        'load applies only to .o plug-ins. Lua scripts are chosen with the '
            'Program parameter of a Lua Script slot.',
      );
    }

    final resolved = await resolveAllowedLocalFile(localPath, actor: actor);
    final file = resolved.file;
    if (file == null) {
      return _failure(resolved.error!, switch (resolved.error) {
        'absolute_path_required' => 'path must be an absolute path.',
        'file_not_found' => 'No file exists at $localPath.',
        _ =>
          '$localPath is not inside an allowed root with ${actor.storageKey} '
              'read permission. Call list_allowed_roots to see readable roots; '
              'roots are configured in nt_helper Settings.',
      });
    }

    final size = await file.length();
    if (size == 0) {
      return _failure('empty_file', '$localPath is empty.');
    }
    if (size > maxFileBytes) {
      return _failure(
        'file_too_large',
        '$localPath is $size bytes; the limit is $maxFileBytes bytes.',
        {'size': size, 'max_bytes': maxFileBytes},
      );
    }

    final PluginInstallReport report;
    try {
      report = await _cubit.installPluginAndVerify(
        path.basename(file.path),
        await file.readAsBytes(),
        load: load,
        maxRescanAttempts: maxRescanAttempts,
        rescanPollInterval: rescanPollInterval,
        libraryReadyTimeout: libraryReadyTimeout,
      );
    } on PluginInstallRefused catch (e) {
      return _failure(e.reason.code, e.message, e.details ?? const {});
    } on FormatException catch (e) {
      return _failure('invalid_file_name', e.message);
    } catch (e) {
      return _failure('install_failed', 'Upload did not complete: $e');
    }
    return jsonEncode(_reportJson(file.path, extension, report, load));
  }

  /// Handles `smoke_test_plugin`. Always returns a JSON object with
  /// `success`; argument errors and refusals carry an `error` code and
  /// change nothing, and test failures also report `rollback`.
  Future<String> smokeTestPlugin(Map<String, dynamic> args) async {
    final unknown = args.keys.where((k) => !_smokeTestArguments.contains(k));
    if (unknown.isNotEmpty) {
      return _failure(
        'unknown_argument',
        'Unknown argument(s): ${unknown.join(', ')}. Accepted: '
            '${_smokeTestArguments.join(', ')}.',
      );
    }
    final guid = args['guid'];
    if (guid is! String || guid.trim().isEmpty) {
      return _failure(
        'missing_guid',
        'guid is required: the GUID of an installed plug-in algorithm.',
      );
    }
    if (!args.containsKey('cpu_budget_percent')) {
      return _failure(
        'missing_cpu_budget',
        'cpu_budget_percent is required: the highest per-slot CPU '
            'percentage (1-100) the test slot may reach.',
      );
    }

    final int budget;
    final int? maxCore;
    final List<int>? specifications;
    final int? expectedCount;
    final List<String>? expectedNames;
    final int settleMs;
    final int samples;
    final bool keep;
    final bool reloadSaved;
    try {
      final requestedBudget = _intArg(
        args,
        'cpu_budget_percent',
        min: 1,
        max: 100,
      );
      if (requestedBudget == null) {
        throw const _ArgumentProblem(
          'cpu_budget_percent',
          'cpu_budget_percent must be an integer from 1 to 100.',
        );
      }
      budget = requestedBudget;
      maxCore = _intArg(args, 'max_core_percent', min: 1, max: 100);
      specifications = _listArg<int>(args, 'specifications', 'integers');
      expectedCount = _intArg(args, 'expected_parameter_count', min: 1);
      expectedNames = _listArg<String>(
        args,
        'expected_parameter_names',
        'strings',
      );
      settleMs = _intArg(args, 'settle_ms', min: 0, max: maxSettleMs) ?? 1000;
      samples = _intArg(args, 'cpu_samples', min: 1, max: maxCpuSamples) ?? 3;
      keep = _boolArg(args, 'keep');
      reloadSaved = _boolArg(args, 'reload_saved_on_failure');
    } on _ArgumentProblem catch (e) {
      return _failure('invalid_${e.name}', e.message);
    }

    final PluginSmokeTestReport report;
    try {
      report = await _cubit.smokeTestPlugin(
        guid.trim(),
        PluginSmokeTestOptions(
          cpuBudgetPercent: budget,
          maxCorePercent: maxCore,
          specifications: specifications,
          expectedParameterCount: expectedCount,
          expectedParameterNames: expectedNames,
          settle: Duration(milliseconds: settleMs),
          cpuSamples: samples,
          keep: keep,
          reloadSavedOnFailure: reloadSaved,
          libraryReadyTimeout: libraryReadyTimeout,
        ),
      );
    } on PluginSmokeTestRefused catch (e) {
      return _failure(e.reason.code, e.message, e.details ?? const {});
    }
    return jsonEncode(_smokeReportJson(report));
  }

  Map<String, dynamic> _smokeReportJson(PluginSmokeTestReport report) {
    final cpu = report.cpu;
    return {
      'success': report.passed,
      if (!report.passed) 'error': report.failure!.code,
      'guid': report.guid,
      'name': report.name,
      'slot_index': report.slotIndex,
      'loaded_plugin': report.loadedPlugin,
      'checks': [
        for (final c in report.checks)
          {'name': c.name, 'passed': c.passed, 'detail': ?c.detail},
      ],
      'cpu': cpu == null
          ? null
          : {
              'budget_percent': cpu.budgetPercent,
              'max_core_percent': cpu.maxCorePercent,
              'slot_samples': cpu.slotSamples,
              'slot_peak': cpu.slotPeak,
              'core_samples': cpu.coreSamples,
              'core_peak': cpu.corePeak,
            },
      'rollback': report.rollback.code,
      'rolled_back': report.rollback.restoredLineup,
      'rollback_error': ?report.rollbackError,
      'restored_parameter_values': ?report.restoredParameterValues,
      'message': _smokeSummary(report),
    };
  }

  String _smokeSummary(PluginSmokeTestReport report) {
    final buffer = StringBuffer(
      report.passed
          ? '${report.name} (${report.guid}) passed every check in slot '
                '${report.slotIndex}.'
          : '${report.name} (${report.guid}) failed: ${report.failureDetail}',
    );
    buffer.write(switch (report.rollback) {
      PluginSmokeTestRollback.kept =>
        ' The slot was kept; the preset was not saved.',
      PluginSmokeTestRollback.notNeeded =>
        ' The slot never appeared, and the original slots are confirmed.',
      PluginSmokeTestRollback.removedSlot =>
        ' The test slot was removed, and the original slots are confirmed.',
      PluginSmokeTestRollback.reloadedSavedPreset =>
        ' The test slot could not be removed, so the saved preset was '
            'reloaded.',
      PluginSmokeTestRollback.failed =>
        ' Rollback failed: ${report.rollbackError}',
    });
    return buffer.toString();
  }

  int? _intArg(
    Map<String, dynamic> args,
    String name, {
    required int min,
    int? max,
  }) {
    final value = args[name];
    if (value == null) return null;
    final range = max == null ? 'at least $min' : 'from $min to $max';
    if (value is! num || value != value.roundToDouble()) {
      throw _ArgumentProblem(name, '$name must be an integer $range.');
    }
    final integer = value.toInt();
    if (integer < min || (max != null && integer > max)) {
      throw _ArgumentProblem(name, '$name must be $range; got $integer.');
    }
    return integer;
  }

  List<T>? _listArg<T>(Map<String, dynamic> args, String name, String kind) {
    final value = args[name];
    if (value == null) return null;
    if (value is! List || value.any((e) => e is! T)) {
      throw _ArgumentProblem(name, '$name must be a list of $kind.');
    }
    return value.cast<T>();
  }

  bool _boolArg(Map<String, dynamic> args, String name) {
    final value = args[name] ?? false;
    if (value is! bool) {
      throw _ArgumentProblem(name, '$name must be true or false.');
    }
    return value;
  }

  Map<String, dynamic> _reportJson(
    String sourcePath,
    String extension,
    PluginInstallReport report,
    bool load,
  ) {
    final isObject = extension == '.o';
    final missing = report.missingGuids;
    final verified = isObject
        ? report.algorithms.isNotEmpty && missing.isEmpty
        : report.filePresent == true;
    final loadFailures = report.loadResults.where((r) => !r.loaded).length;
    return {
      'success': true,
      'plugin_type': isObject ? 'cpp' : 'lua',
      'source_path': sourcePath,
      'destination_path': report.destinationPath,
      'bytes_written': report.bytesWritten,
      'file_present': report.filePresent,
      'verified': verified,
      'preset_reloaded': report.presetReloaded,
      'root_duplicate': _cleanupJson(report.cleanup),
      if (isObject) ...{
        'rescan_attempts': report.rescanAttempts,
        'expected_guids': report.expectedGuids,
        'missing_guids': missing,
        'unattributed_guids': report.unattributedGuids,
        'algorithms': [
          for (final a in report.algorithms)
            {'guid': a.guid, 'name': a.name, 'is_loaded': a.isLoaded},
        ],
      },
      if (load)
        'load_results': [
          for (final r in report.loadResults)
            {'guid': r.guid, 'loaded': r.loaded},
        ],
      'message': _summary(report, isObject, verified, load, loadFailures),
    };
  }

  String _summary(
    PluginInstallReport report,
    bool isObject,
    bool verified,
    bool load,
    int loadFailures,
  ) {
    final buffer = StringBuffer(
      'Uploaded ${report.bytesWritten} bytes to ${report.destinationPath}.',
    );
    if (!isObject) {
      buffer.write(
        verified
            ? ' The file is listed on the SD card.'
            : ' The SD listing did not confirm the file.',
      );
    } else if (verified) {
      final names = report.algorithms.map((a) => '${a.name} (${a.guid})');
      buffer.write(' Rescan found: ${names.join(', ')}.');
    } else if (report.algorithms.isEmpty) {
      buffer.write(
        ' No algorithm for this file appeared after '
        '${report.rescanAttempts} rescan check(s). Check the device screen '
        'for a load error, or call search_algorithms later.',
      );
    } else {
      buffer.write(
        ' Rescan is missing GUID(s): ${report.missingGuids.join(', ')}.',
      );
    }
    if (load) {
      buffer.write(
        report.loadResults.isEmpty
            ? ' Nothing was loaded because no algorithm was found.'
            : loadFailures == 0
            ? ' Loaded ${report.loadResults.length} algorithm(s).'
            : ' $loadFailures of ${report.loadResults.length} algorithm(s) '
                  'did not report loaded.',
      );
    }
    if (report.unattributedGuids.isNotEmpty) {
      buffer.write(
        ' Could not rule out a GUID collision for '
        '${report.unattributedGuids.join(', ')}: the device did not report '
        'which file already provides it.',
      );
    }
    if (report.presetReloaded) {
      buffer.write(' The preset was reloaded from its saved copy.');
    }
    return buffer.toString();
  }

  Map<String, dynamic> _cleanupJson(PluginCleanupOutcome outcome) =>
      switch (outcome) {
        PluginCleanupSkipped() => {'status': 'not_applicable'},
        PluginCleanupRemoved(:final path) => {
          'status': 'removed',
          'path': path,
        },
        PluginCleanupDeletionFailed(:final path) => {
          'status': 'deletion_failed',
          'path': path,
        },
        PluginCleanupCouldNotBeVerified(:final path) => {
          'status': 'kept_unverified',
          'path': path,
        },
      };

  String _failure(
    String code,
    String message, [
    Map<String, Object?> extra = const {},
  ]) => jsonEncode({
    'success': false,
    'error': code,
    'message': message,
    ...extra,
  });
}

/// A `smoke_test_plugin` argument with the wrong type or range.
class _ArgumentProblem implements Exception {
  const _ArgumentProblem(this.name, this.message);

  final String name;
  final String message;
}
