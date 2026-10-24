/// Why a plug-in smoke test was refused before the preset was touched.
enum PluginSmokeTestRefusal {
  /// Another smoke test already owns the temporary-slot lifecycle.
  busy('smoke_test_busy'),

  /// The live preset no longer matches the synchronized baseline.
  presetChanged('preset_changed'),

  /// Construction values do not match the plug-in's specification metadata.
  invalidSpecifications('invalid_specifications'),

  /// No synchronized device session exists.
  notConnected('not_connected'),

  /// The app is synchronized from the offline cache, not a live device.
  offline('offline_mode'),

  /// The app is running against demo data, not a live device.
  demo('demo_mode'),

  /// No algorithm with the requested GUID is in the algorithm list.
  unknownGuid('unknown_guid'),

  /// The GUID belongs to a built-in algorithm, not a plug-in.
  notAPlugin('not_a_plugin'),

  /// Every preset slot is already in use, so no test slot can be appended.
  presetFull('preset_full'),

  /// The plug-in was not loaded and loading it did not succeed.
  loadFailed('load_failed'),

  /// The algorithm list was still loading in the background when the wait
  /// for it ran out, so the GUID could not be looked up reliably.
  algorithmLibraryLoading('algorithm_library_loading');

  const PluginSmokeTestRefusal(this.code);

  /// Stable snake_case error code reported to MCP clients.
  final String code;
}

/// Thrown by `DistingCubit.smokeTestPlugin` when the test cannot start.
/// The preset is unchanged.
class PluginSmokeTestRefused implements Exception {
  const PluginSmokeTestRefused(this.reason, this.message, [this.details]);

  /// Machine-readable reason.
  final PluginSmokeTestRefusal reason;

  /// Human-readable explanation, suitable for showing to a client.
  final String message;

  /// Extra snake_case fields for the client, such as the slot limit for
  /// [PluginSmokeTestRefusal.presetFull].
  final Map<String, Object?>? details;

  @override
  String toString() => message;
}

/// Why a smoke test that started did not pass.
enum PluginSmokeTestFailure {
  /// The device did not confirm the appended test slot.
  addFailed('add_failed'),

  /// The test slot did not answer the parameter-count or GUID reads.
  parametersUnavailable('parameters_unavailable'),

  /// The test slot answered, but its algorithm or parameters were not the
  /// expected ones.
  parameterMismatch('parameter_mismatch'),

  /// The test slot's peak CPU sample exceeded `cpu_budget_percent`.
  cpuOverBudget('cpu_over_budget'),

  /// A core's peak CPU sample exceeded `max_core_percent`.
  coreCpuOverBudget('core_cpu_over_budget'),

  /// A CPU sample was missing or did not cover the test slot.
  cpuUnavailable('cpu_unavailable'),

  /// The device stopped answering during the test.
  deviceUnresponsive('device_unresponsive'),

  /// Every check passed, but removing the test slot was not confirmed.
  rollbackFailed('rollback_failed'),

  /// An unexpected error interrupted the test.
  internalError('internal_error');

  const PluginSmokeTestFailure(this.code);

  /// Stable snake_case error code reported to MCP clients.
  final String code;
}

/// What happened to the test slot at the end of a smoke test.
enum PluginSmokeTestRollback {
  /// The test passed and `keep` was set, so the slot stays in the preset.
  kept('kept'),

  /// The slot never appeared, and the device confirmed the original lineup.
  notNeeded('not_needed'),

  /// The device confirmed the slot's removal and the original lineup.
  removedSlot('removed_slot'),

  /// Removal was not confirmed, so the preset was reloaded from its last
  /// saved copy on the SD card.
  reloadedSavedPreset('reloaded_saved_preset'),

  /// The preset could not be confirmed back to its original lineup.
  failed('failed');

  const PluginSmokeTestRollback(this.code);

  /// Stable snake_case value reported to MCP clients.
  final String code;

  /// Whether the preset is back to the lineup it had before the test.
  bool get restoredLineup =>
      this == notNeeded || this == removedSlot || this == reloadedSavedPreset;
}

/// Inputs to a smoke test. Durations default to values suited to hardware;
/// tests shorten them.
class PluginSmokeTestOptions {
  const PluginSmokeTestOptions({
    required this.cpuBudgetPercent,
    this.specifications,
    this.maxCorePercent,
    this.expectedParameterCount,
    this.expectedParameterNames,
    this.settle = const Duration(seconds: 1),
    this.cpuSamples = 3,
    this.keep = false,
    this.reloadSavedOnFailure = false,
    this.cpuSampleInterval = const Duration(milliseconds: 250),
    this.requestTimeout = const Duration(seconds: 2),
    this.removePollInterval = const Duration(milliseconds: 500),
    this.removePollAttempts = 10,
    this.reloadTimeout = const Duration(seconds: 20),
    this.libraryReadyTimeout = const Duration(seconds: 10),
  });

  /// Highest per-slot CPU percentage the test slot may report.
  final int cpuBudgetPercent;

  /// Specification values for the new slot; null uses each
  /// specification's default.
  final List<int>? specifications;

  /// Highest CPU percentage either core may report, or null to skip.
  final int? maxCorePercent;

  /// Exact parameter count the test slot must report, or null to require
  /// only at least one parameter.
  final int? expectedParameterCount;

  /// Names the first parameters must have, in order, or null to skip.
  final List<String>? expectedParameterNames;

  /// Wait after the slot is confirmed and before any check.
  final Duration settle;

  /// Number of CPU samples.
  final int cpuSamples;

  /// Keep the slot when every check passes.
  final bool keep;

  /// Allow reloading the saved preset when removal fails even though the
  /// preset has unsaved edits, which that reload discards.
  final bool reloadSavedOnFailure;

  /// Delay between CPU samples.
  final Duration cpuSampleInterval;

  /// Longest wait for any single device read.
  final Duration requestTimeout;

  /// Delay between slot-count reads while waiting for a removal.
  final Duration removePollInterval;

  /// Slot-count reads before a removal counts as unconfirmed.
  final int removePollAttempts;

  /// Longest wait for the saved preset to reload.
  final Duration reloadTimeout;

  /// Longest wait for a background algorithm-list load to finish before the
  /// GUID is looked up.
  final Duration libraryReadyTimeout;
}

/// One named check and its outcome.
class PluginSmokeCheck {
  const PluginSmokeCheck(this.name, {required this.passed, this.detail});

  /// snake_case check name, such as `parameter_count`.
  final String name;

  /// Whether the check passed.
  final bool passed;

  /// What was measured, for the client.
  final String? detail;
}

/// CPU samples taken from the test slot and both cores.
class PluginSmokeCpuReport {
  const PluginSmokeCpuReport({
    required this.budgetPercent,
    required this.maxCorePercent,
    required this.slotSamples,
    required this.coreSamples,
  });

  /// The per-slot budget the samples were judged against.
  final int budgetPercent;

  /// The per-core ceiling, or null when none was set.
  final int? maxCorePercent;

  /// The test slot's CPU percentage in each sample.
  final List<int> slotSamples;

  /// The higher of the two cores' CPU percentages in each sample.
  final List<int> coreSamples;

  /// Highest test-slot sample, or null when there were no samples.
  int? get slotPeak =>
      slotSamples.isEmpty ? null : slotSamples.reduce((a, b) => a > b ? a : b);

  /// Highest core sample, or null when there were no samples.
  int? get corePeak =>
      coreSamples.isEmpty ? null : coreSamples.reduce((a, b) => a > b ? a : b);
}

/// The outcome of `DistingCubit.smokeTestPlugin`.
class PluginSmokeTestReport {
  const PluginSmokeTestReport({
    required this.guid,
    required this.name,
    required this.slotIndex,
    required this.loadedPlugin,
    required this.checks,
    required this.cpu,
    required this.failure,
    required this.failureDetail,
    required this.rollback,
    required this.rollbackError,
    required this.restoredParameterValues,
  });

  /// GUID of the plug-in under test.
  final String guid;

  /// Algorithm name from the algorithm list.
  final String name;

  /// Slot the test appended, which is always the end of the preset.
  final int slotIndex;

  /// Whether the test had to load the plug-in first.
  final bool loadedPlugin;

  /// Every check that ran, in order.
  final List<PluginSmokeCheck> checks;

  /// CPU samples, or null when the test stopped before sampling.
  final PluginSmokeCpuReport? cpu;

  /// Why the test did not pass, or null when it passed.
  final PluginSmokeTestFailure? failure;

  /// Readable explanation of [failure].
  final String? failureDetail;

  /// What happened to the test slot.
  final PluginSmokeTestRollback rollback;

  /// Why the rollback ended where it did, when it needed a fallback or
  /// failed.
  final String? rollbackError;

  /// Parameter values re-applied from the pre-test snapshot after a saved
  /// preset reload, or null when no reload happened.
  final int? restoredParameterValues;

  /// Whether every check passed and the slot was either kept or confirmed
  /// removed.
  bool get passed => failure == null;
}
