part of 'disting_cubit.dart';

/// Smoke-tests a plug-in on live hardware: appends it to the end of the
/// current preset, checks that the slot answers, samples its CPU, and then
/// removes the slot again unless asked to keep it.
///
/// The preset is never saved. Rollback removes only the appended slot and
/// confirms the original slot lineup with the device. Only when that removal
/// cannot be confirmed does it fall back to reloading the last saved preset
/// from the SD card, and only automatically when the preset had no unsaved
/// edits.
class _PluginSmokeTestDelegate {
  _PluginSmokeTestDelegate(this._cubit);

  final DistingCubit _cubit;
  bool _running = false;

  /// Runs the smoke test for the plug-in [guid] with [options].
  ///
  /// Throws [PluginSmokeTestRefused] before touching the preset when there
  /// is no live session, the algorithm list is still loading after
  /// [PluginSmokeTestOptions.libraryReadyTimeout], [guid] is unknown or
  /// built in, every slot is in use, or the plug-in cannot be loaded. Every other outcome, including
  /// device errors, is returned as a [PluginSmokeTestReport].
  Future<PluginSmokeTestReport> smokeTestPlugin(
    String guid,
    PluginSmokeTestOptions options,
  ) async {
    if (_running) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.busy,
        'Another plug-in smoke test is still running or rolling back.',
      );
    }
    _running = true;
    try {
      return await _run(guid, options);
    } finally {
      _running = false;
    }
  }

  Future<PluginSmokeTestReport> _run(
    String guid,
    PluginSmokeTestOptions options,
  ) async {
    _requireLiveSession();
    // A partly loaded list could report an installed plug-in as unknown.
    if (!await _cubit._algorithmLibraryDelegate.waitForBackgroundLoads(
      options.libraryReadyTimeout,
    )) {
      throw PluginSmokeTestRefused(
        PluginSmokeTestRefusal.algorithmLibraryLoading,
        'The algorithm list is still loading from the device after '
        '${options.libraryReadyTimeout.inSeconds} s, so $guid cannot be '
        'looked up yet. The preset was not changed. Retry in a few seconds.',
      );
    }
    final start = _requireLiveSession();
    var algorithm = _findPlugin(start, guid);
    if (start.slots.length >= DistingLimits.maxPresetSlots) {
      throw PluginSmokeTestRefused(
        PluginSmokeTestRefusal.presetFull,
        'All ${DistingLimits.maxPresetSlots} slots are in use, so there is '
        'no free slot to append the test slot to. Remove a slot first.',
        {'max_slots': DistingLimits.maxPresetSlots},
      );
    }

    final loadedPlugin = !algorithm.isLoaded;
    if (loadedPlugin) {
      final loaded = await _cubit._pluginDelegate.loadPlugin(guid);
      if (loaded == null || !loaded.isLoaded) {
        throw PluginSmokeTestRefused(
          PluginSmokeTestRefusal.loadFailed,
          'The plug-in $guid did not report loaded. Check the device screen '
          'for a load error. The preset was not changed.',
        );
      }
      algorithm = loaded;
    }

    _validateSpecifications(algorithm, options.specifications);
    final observed = _requireLiveSession();
    await _verifyBaseline(observed, options);
    final baseline = _requireLiveSession();
    if (baseline.slots.length >= DistingLimits.maxPresetSlots) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.presetFull,
        'The preset filled up while preparing the smoke test.',
      );
    }
    final run = _SmokeRun(
      cubit: _cubit,
      options: options,
      algorithm: algorithm,
      disting: baseline.disting,
      slotIndex: baseline.slots.length,
      baselineSlots: List.unmodifiable(baseline.slots),
      presetName: baseline.presetName,
      wasDirty: baseline.isDirty,
      checkpoint: _cubit._checkpointDelegate.createCheckpoint(
        label: 'smoke_test_plugin $guid',
      ),
      loadedPlugin: loadedPlugin,
    );
    run.watchChanges();
    try {
      return await run.execute();
    } finally {
      await run.stopWatching();
      final checkpoint = run.checkpoint;
      if (checkpoint != null) {
        _cubit._checkpointDelegate.removeCheckpoint(checkpoint);
      }
    }
  }

  void _validateSpecifications(AlgorithmInfo algorithm, List<int>? supplied) {
    if (supplied == null) return;
    final definitions = algorithm.specifications;
    if (supplied.length != definitions.length) {
      throw PluginSmokeTestRefused(
        PluginSmokeTestRefusal.invalidSpecifications,
        '${algorithm.guid} requires ${definitions.length} specification(s); '
        'got ${supplied.length}.',
      );
    }
    for (var i = 0; i < supplied.length; i++) {
      final definition = definitions[i];
      if (supplied[i] < definition.min || supplied[i] > definition.max) {
        throw PluginSmokeTestRefused(
          PluginSmokeTestRefusal.invalidSpecifications,
          'Specification "${definition.name}" must be from '
          '${definition.min} to ${definition.max}; got ${supplied[i]}.',
        );
      }
    }
  }

  /// Read the hardware lineup before appending, not just the cached app state.
  Future<void> _verifyBaseline(
    DistingStateSynchronized baseline,
    PluginSmokeTestOptions options,
  ) async {
    Future<T?> read<T>(Future<T?> Function() request) async {
      try {
        return await request().timeout(options.requestTimeout * 2);
      } catch (_) {
        return null;
      }
    }

    final count = await read(
      () => baseline.disting.requestNumAlgorithmsInPreset(
        timeout: options.requestTimeout,
        maxRetries: 1,
      ),
    );
    var matches = count == baseline.slots.length;
    for (var i = 0; matches && i < baseline.slots.length; i++) {
      final slot = await read(
        () => baseline.disting.requestAlgorithmGuid(
          i,
          timeout: options.requestTimeout,
          maxRetries: 1,
        ),
      );
      matches = slot?.guid == baseline.slots[i].algorithm.guid;
    }
    final current = _requireLiveSession();
    if (!matches ||
        !identical(current.disting, baseline.disting) ||
        current.presetName != baseline.presetName ||
        !const ListEquality<String>().equals(
          [for (final slot in current.slots) slot.algorithm.guid],
          [for (final slot in baseline.slots) slot.algorithm.guid],
        )) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.presetChanged,
        'The live preset could not be confirmed against the app snapshot. '
        'Refresh the preset and retry; no test slot was added.',
      );
    }
  }

  DistingStateSynchronized _requireLiveSession() {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.notConnected,
        'No Disting NT is connected and synchronized.',
      );
    }
    if (state.demo) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.demo,
        'Demo mode has no device to test on. Connect a Disting NT.',
      );
    }
    if (state.offline) {
      throw const PluginSmokeTestRefused(
        PluginSmokeTestRefusal.offline,
        'Offline mode has no device to test on. Connect a Disting NT.',
      );
    }
    return state;
  }

  AlgorithmInfo _findPlugin(DistingStateSynchronized state, String guid) {
    final algorithm = state.algorithms.where((a) => a.guid == guid).firstOrNull;
    if (algorithm == null) {
      throw PluginSmokeTestRefused(
        PluginSmokeTestRefusal.unknownGuid,
        'No algorithm with GUID $guid is installed. Install it with '
        'install_plugin, or check the GUID with search_algorithms.',
      );
    }
    if (!algorithm.isPlugin) {
      throw PluginSmokeTestRefused(
        PluginSmokeTestRefusal.notAPlugin,
        '$guid is the built-in algorithm ${algorithm.name}; '
        'smoke_test_plugin tests plug-ins only.',
      );
    }
    return algorithm;
  }
}

/// State for one smoke test, from the appended slot to the rollback.
class _SmokeRun {
  _SmokeRun({
    required this.cubit,
    required this.options,
    required this.algorithm,
    required this.disting,
    required this.slotIndex,
    required this.baselineSlots,
    required this.presetName,
    required this.wasDirty,
    required this.checkpoint,
    required this.loadedPlugin,
  });

  final DistingCubit cubit;
  final PluginSmokeTestOptions options;
  final AlgorithmInfo algorithm;
  final IDistingMidiManager disting;
  final int slotIndex;
  final List<Slot> baselineSlots;
  List<String> get baselineGuids => [
    for (final s in baselineSlots) s.algorithm.guid,
  ];
  final String presetName;
  final bool wasDirty;
  final PresetCheckpoint? checkpoint;
  final bool loadedPlugin;

  final checks = <PluginSmokeCheck>[];
  PluginSmokeCpuReport? cpu;
  StreamSubscription<DistingState>? _changes;
  bool _userChanges = false;
  bool _structureChanged = false;

  void watchChanges() {
    _changes = cubit.stream.listen(_observeChanges);
  }

  Future<void> stopWatching() async => _changes?.cancel();

  /// Ignore this run's appended slot and dirty flag, but retain evidence of
  /// any change to the original preset, including changes later undone/saved.
  void _observeChanges(DistingState state) {
    if (state is! DistingStateSynchronized ||
        !identical(state.disting, disting) ||
        state.presetName != presetName ||
        state.slots.length < slotIndex ||
        state.slots.length > slotIndex + 1) {
      _userChanges = true;
      _structureChanged = true;
      return;
    }
    for (var i = 0; i < slotIndex; i++) {
      final before = baselineSlots[i];
      final after = state.slots[i];
      if (before != after) _userChanges = true;
      if (before.algorithm.guid != after.algorithm.guid ||
          !const ListEquality<int>().equals(
            before.algorithm.specifications,
            after.algorithm.specifications,
          )) {
        _structureChanged = true;
      }
    }
    if (state.slots.length == slotIndex + 1 &&
        state.slots.last.algorithm.guid != algorithm.guid) {
      _userChanges = true;
      _structureChanged = true;
    }
  }

  Future<PluginSmokeTestReport> execute() async {
    _SmokeFailure? failure;
    var slotAdded = false;
    try {
      slotAdded = await _addSlot();
      if (!slotAdded) {
        failure = const _SmokeFailure(
          PluginSmokeTestFailure.addFailed,
          'The device did not confirm the new slot.',
        );
      } else {
        await Future<void>.delayed(options.settle);
        failure = await _checkParameters() ?? await _checkCpu();
      }
    } catch (e) {
      failure = _SmokeFailure(
        PluginSmokeTestFailure.internalError,
        'The test stopped unexpectedly: $e',
      );
    }

    if (failure != null &&
        failure.code != PluginSmokeTestFailure.deviceUnresponsive &&
        await _readSlotCount() == null) {
      failure = _SmokeFailure(
        PluginSmokeTestFailure.deviceUnresponsive,
        '${failure.detail} The device then stopped answering slot-count '
        'reads.',
      );
    }

    if (failure == null && options.keep) {
      return _report(null, PluginSmokeTestRollback.kept);
    }

    _observeChanges(cubit.state);
    final _SmokeRollback rollback;
    try {
      rollback = await _rollBack(slotAdded: slotAdded);
    } catch (error) {
      failure ??= _SmokeFailure(
        PluginSmokeTestFailure.internalError,
        'Cleanup stopped unexpectedly: $error',
      );
      return _report(
        failure,
        PluginSmokeTestRollback.failed,
        rollbackError:
            'Cleanup could not be confirmed: $error. Refresh and '
            'inspect the preset before removing any slot manually.',
      );
    }
    if (failure == null && !rollback.status.restoredLineup) {
      failure = const _SmokeFailure(
        PluginSmokeTestFailure.rollbackFailed,
        'Every check passed, but removing the test slot was not confirmed.',
      );
    }
    return _report(
      failure,
      rollback.status,
      rollbackError: rollback.error,
      restoredParameterValues: rollback.restoredParameterValues,
    );
  }

  /// Appends the plug-in and waits for the device to confirm it.
  Future<bool> _addSlot() async {
    final specs =
        options.specifications ??
        [for (final s in algorithm.specifications) s.defaultValue];
    try {
      await cubit.onAlgorithmSelected(algorithm, specs);
    } on AlgorithmAddFailedException {
      checks.add(
        const PluginSmokeCheck(
          'slot_added',
          passed: false,
          detail: 'The slot count did not increase.',
        ),
      );
      return false;
    }
    checks.add(
      PluginSmokeCheck(
        'slot_added',
        passed: true,
        detail: 'Appended as slot $slotIndex.',
      ),
    );
    return true;
  }

  /// Checks that the new slot answers with the plug-in's GUID and at least
  /// one parameter, plus the optional stricter count and name checks.
  Future<_SmokeFailure?> _checkParameters() async {
    final reported = await _read(
      () => disting.requestAlgorithmGuid(
        slotIndex,
        timeout: options.requestTimeout,
        maxRetries: 1,
      ),
    );
    final count = await _read(
      () => disting.requestNumberOfParameters(slotIndex),
    );
    if (reported == null ||
        count == null ||
        count.algorithmIndex != slotIndex) {
      checks.add(
        PluginSmokeCheck(
          'slot_responds',
          passed: false,
          detail:
              'Slot $slotIndex did not answer the '
              '${reported == null ? 'GUID' : 'parameter-count'} read.',
        ),
      );
      return _SmokeFailure(
        PluginSmokeTestFailure.parametersUnavailable,
        'Slot $slotIndex did not answer within '
        '${options.requestTimeout.inMilliseconds} ms.',
      );
    }
    checks.add(const PluginSmokeCheck('slot_responds', passed: true));

    if (reported.guid != algorithm.guid) {
      checks.add(
        PluginSmokeCheck(
          'algorithm_guid',
          passed: false,
          detail: 'Expected ${algorithm.guid}, got ${reported.guid}.',
        ),
      );
      return _SmokeFailure(
        PluginSmokeTestFailure.parameterMismatch,
        'Slot $slotIndex holds ${reported.guid}, not ${algorithm.guid}.',
      );
    }
    checks.add(const PluginSmokeCheck('algorithm_guid', passed: true));

    final expectedCount = options.expectedParameterCount;
    final countOk = expectedCount == null
        ? count.numParameters >= 1
        : count.numParameters == expectedCount;
    checks.add(
      PluginSmokeCheck(
        'parameter_count',
        passed: countOk,
        detail:
            'Reported ${count.numParameters}; expected '
            '${expectedCount ?? 'at least 1'}.',
      ),
    );
    if (!countOk) {
      return _SmokeFailure(
        PluginSmokeTestFailure.parameterMismatch,
        'Slot $slotIndex reports ${count.numParameters} parameter(s); '
        'expected ${expectedCount ?? 'at least 1'}.',
      );
    }

    final expectedNames = options.expectedParameterNames;
    if (expectedNames == null || expectedNames.isEmpty) return null;
    final actualNames = <String>[];
    for (var i = 0; i < expectedNames.length; i++) {
      final info = i < count.numParameters
          ? await _read(() => disting.requestParameterInfo(slotIndex, i))
          : null;
      if (info == null && i < count.numParameters) {
        checks.add(
          PluginSmokeCheck(
            'parameter_names',
            passed: false,
            detail: 'Parameter $i did not answer.',
          ),
        );
        return _SmokeFailure(
          PluginSmokeTestFailure.parametersUnavailable,
          'Parameter $i of slot $slotIndex did not answer.',
        );
      }
      actualNames.add(info?.name.trim() ?? '');
    }
    final namesOk = const ListEquality<String>().equals(actualNames, [
      for (final n in expectedNames) n.trim(),
    ]);
    checks.add(
      PluginSmokeCheck(
        'parameter_names',
        passed: namesOk,
        detail: 'Expected $expectedNames, got $actualNames.',
      ),
    );
    return namesOk
        ? null
        : _SmokeFailure(
            PluginSmokeTestFailure.parameterMismatch,
            'Parameter names differ: expected $expectedNames, got '
            '$actualNames.',
          );
  }

  /// Samples CPU [PluginSmokeTestOptions.cpuSamples] times and judges the
  /// test slot's peak, and both cores' peak when a ceiling is set.
  Future<_SmokeFailure?> _checkCpu() async {
    final slotSamples = <int>[];
    final coreSamples = <int>[];
    cpu = PluginSmokeCpuReport(
      budgetPercent: options.cpuBudgetPercent,
      maxCorePercent: options.maxCorePercent,
      slotSamples: slotSamples,
      coreSamples: coreSamples,
    );
    for (var i = 0; i < options.cpuSamples; i++) {
      if (i > 0) await Future<void>.delayed(options.cpuSampleInterval);
      final usage = await _read(cubit.getCpuUsage);
      if (usage == null || usage.slotUsages.length <= slotIndex) {
        final why = usage == null
            ? 'CPU sample ${i + 1} did not arrive.'
            : 'CPU sample ${i + 1} covers ${usage.slotUsages.length} slot(s), '
                  'not slot $slotIndex.';
        checks.add(PluginSmokeCheck('cpu', passed: false, detail: why));
        return _SmokeFailure(PluginSmokeTestFailure.cpuUnavailable, why);
      }
      slotSamples.add(usage.slotUsages[slotIndex]);
      coreSamples.add(usage.cpu1 > usage.cpu2 ? usage.cpu1 : usage.cpu2);
    }

    final slotPeak = cpu!.slotPeak!;
    final slotOk = slotPeak <= options.cpuBudgetPercent;
    checks.add(
      PluginSmokeCheck(
        'slot_cpu',
        passed: slotOk,
        detail:
            'Peak $slotPeak% over ${slotSamples.length} sample(s); budget '
            '${options.cpuBudgetPercent}%.',
      ),
    );

    final maxCore = options.maxCorePercent;
    final corePeak = cpu!.corePeak!;
    final coreOk = maxCore == null || corePeak <= maxCore;
    if (maxCore != null) {
      checks.add(
        PluginSmokeCheck(
          'core_cpu',
          passed: coreOk,
          detail: 'Peak core $corePeak%; ceiling $maxCore%.',
        ),
      );
    }

    if (!slotOk) {
      return _SmokeFailure(
        PluginSmokeTestFailure.cpuOverBudget,
        'Slot $slotIndex peaked at $slotPeak% CPU; the budget is '
        '${options.cpuBudgetPercent}%.',
      );
    }
    if (!coreOk) {
      return _SmokeFailure(
        PluginSmokeTestFailure.coreCpuOverBudget,
        'A core peaked at $corePeak% CPU; the ceiling is $maxCore%.',
      );
    }
    return null;
  }

  /// Puts the preset back to [baselineGuids]: removes the test slot, and
  /// when that cannot be confirmed, reloads the saved preset if allowed.
  Future<_SmokeRollback> _rollBack({required bool slotAdded}) async {
    _observeChanges(cubit.state);
    if (_structureChanged) {
      return const _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            'The preset or connection changed during the test. No positional '
            'removal or saved-preset reload was attempted. Refresh and inspect '
            'the test slot before removing it manually.',
      );
    }
    final count = await _readSlotCount();
    if (count != null && count != slotIndex && count != slotIndex + 1) {
      return const _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            'The hardware slot count changed unexpectedly. No slot was '
            'removed or preset reloaded; refresh and inspect the lineup.',
      );
    }
    // Confirm ownership of the original prefix as well as the appended slot.
    // Panel changes need not have reached the app stream yet.
    for (var i = 0; count != null && i < slotIndex; i++) {
      final original = await _read(
        () => disting.requestAlgorithmGuid(
          i,
          timeout: options.requestTimeout,
          maxRetries: 1,
        ),
      );
      if (original != null &&
          original.guid != baselineSlots[i].algorithm.guid) {
        return const _SmokeRollback(
          PluginSmokeTestRollback.failed,
          error:
              'An original hardware slot changed during the test. No slot '
              'was removed and the saved preset was not reloaded.',
        );
      }
      if (original == null) break; // Do not repeat timed-out prefix reads.
      final values = await _read(() => disting.requestAllParameterValues(i));
      if (values != null) {
        final before = {
          for (final v in baselineSlots[i].values) v.parameterNumber: v.value,
        };
        if (values.values.any(
          (v) =>
              before.containsKey(v.parameterNumber) &&
              before[v.parameterNumber] != v.value,
        )) {
          _userChanges = true;
        }
      }
    }
    if (count == slotIndex + 1) {
      final candidate = await _read(
        () => disting.requestAlgorithmGuid(
          slotIndex,
          timeout: options.requestTimeout,
          maxRetries: 1,
        ),
      );
      if (candidate != null && candidate.guid != algorithm.guid) {
        return _SmokeRollback(
          PluginSmokeTestRollback.failed,
          error:
              'Slot $slotIndex is ${candidate.guid}, not ${algorithm.guid}. '
              'It was not removed and the saved preset was not reloaded.',
        );
      }
    }
    // An add that was not confirmed in time may still land afterwards.
    final slotPresent = slotAdded || (count != null && count == slotIndex + 1);

    String? error;
    _observeChanges(cubit.state);
    if (_structureChanged) {
      return const _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            'The preset or connection changed before cleanup; no removal '
            'or reload was attempted.',
      );
    }
    if (slotPresent) {
      final removed = await cubit.removeAlgorithmConfirmed(
        slotIndex,
        pollInterval: options.removePollInterval,
        pollAttempts: options.removePollAttempts,
        requestTimeout: options.requestTimeout,
      );
      if (!removed) {
        error =
            'Removing slot $slotIndex was not confirmed within '
            '${options.removePollAttempts} slot-count read(s).';
      }
    }
    error ??= await _lineupError();
    if (error == null) {
      _restoreDirtyFlag();
      return _SmokeRollback(
        slotPresent
            ? PluginSmokeTestRollback.removedSlot
            : PluginSmokeTestRollback.notNeeded,
      );
    }

    _observeChanges(cubit.state);
    if (_structureChanged) {
      return _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error: '$error The original preset changed, so it was not reloaded.',
      );
    }
    if ((wasDirty || _userChanges) && !options.reloadSavedOnFailure) {
      return _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            '$error The preset has unsaved edits, so it was not reloaded '
            'from the SD card. Remove slot $slotIndex on the device, or '
            'call smoke_test_plugin with reload_saved_on_failure to allow '
            'the reload. If the device is not answering, power-cycle it; it '
            'starts with the last saved preset.',
      );
    }

    final hadUnsavedChanges = wasDirty || _userChanges;
    await stopWatching();
    _observeChanges(cubit.state);
    if (_structureChanged) {
      return const _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            'The connection or preset changed before reload; reload aborted.',
      );
    }
    try {
      await cubit
          .loadPreset('/presets/$presetName.json', false)
          .timeout(options.reloadTimeout);
    } catch (e) {
      return _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            '$error Reloading /presets/$presetName.json also failed: $e. '
            'Remove slot $slotIndex on the device, or power-cycle it.',
      );
    }
    final reloadError = await _lineupError();
    if (reloadError != null) {
      return _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error: '$error After reloading /presets/$presetName.json: $reloadError',
      );
    }
    final restored = hadUnsavedChanges && checkpoint != null
        ? await cubit._checkpointDelegate.restoreCheckpoint(checkpoint!)
        : null;
    if (restored != null && restored < 0) {
      return _SmokeRollback(
        PluginSmokeTestRollback.failed,
        error:
            '$error The saved preset reloaded but the pre-test parameter '
            'snapshot could not be restored.',
      );
    }
    return _SmokeRollback(
      PluginSmokeTestRollback.reloadedSavedPreset,
      error: hadUnsavedChanges
          ? '$error Reloaded the saved preset and reapplied the pre-test '
                'parameter snapshot. Edits made during the test and unsaved '
                'non-parameter edits were discarded.'
          : '$error Reloaded the saved preset, which had no unsaved edits.',
      restoredParameterValues: restored,
    );
  }

  /// Null when the device reports exactly [baselineGuids], otherwise why
  /// not.
  Future<String?> _lineupError() async {
    final count = await _readSlotCount();
    if (count == null) return 'The device did not answer a slot-count read.';
    if (count != baselineGuids.length) {
      return 'The device reports $count slot(s); expected '
          '${baselineGuids.length}.';
    }
    for (var i = 0; i < baselineGuids.length; i++) {
      final reported = await _read(
        () => disting.requestAlgorithmGuid(
          i,
          timeout: options.requestTimeout,
          maxRetries: 1,
        ),
      );
      if (reported?.guid != baselineGuids[i]) {
        if (reported != null) {
          _userChanges = true;
          _structureChanged = true;
        }
        return 'Slot $i holds ${reported?.guid ?? 'no answer'}; expected '
            '${baselineGuids[i]}.';
      }
    }
    return null;
  }

  /// The confirmed removal restores the original preset, so the dirty flag
  /// the add raised goes back to what it was.
  void _restoreDirtyFlag() {
    final state = cubit.state;
    _observeChanges(state);
    final dirty = wasDirty || _userChanges;
    if (state is DistingStateSynchronized && state.isDirty != dirty) {
      cubit._emitState(state.copyWith(isDirty: dirty));
    }
  }

  Future<int?> _readSlotCount() => _read(
    () => disting.requestNumAlgorithmsInPreset(
      timeout: options.requestTimeout,
      maxRetries: 1,
    ),
  );

  /// Runs [request] with a deadline; null on timeout or error.
  Future<T?> _read<T>(Future<T?> Function() request) async {
    try {
      return await request().timeout(options.requestTimeout * 2);
    } catch (_) {
      return null;
    }
  }

  PluginSmokeTestReport _report(
    _SmokeFailure? failure,
    PluginSmokeTestRollback rollback, {
    String? rollbackError,
    int? restoredParameterValues,
  }) => PluginSmokeTestReport(
    guid: algorithm.guid,
    name: algorithm.name,
    slotIndex: slotIndex,
    loadedPlugin: loadedPlugin,
    checks: List.unmodifiable(checks),
    cpu: cpu,
    failure: failure?.code,
    failureDetail: failure?.detail,
    rollback: rollback,
    rollbackError: rollbackError,
    restoredParameterValues: restoredParameterValues,
  );
}

class _SmokeFailure {
  const _SmokeFailure(this.code, this.detail);

  final PluginSmokeTestFailure code;
  final String detail;
}

class _SmokeRollback {
  const _SmokeRollback(this.status, {this.error, this.restoredParameterValues});

  final PluginSmokeTestRollback status;
  final String? error;
  final int? restoredParameterValues;
}
