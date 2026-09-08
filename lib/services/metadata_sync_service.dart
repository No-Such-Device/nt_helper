import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart'; // Import the DAO type
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show AlgorithmInfo, Specification;

import 'package:nt_helper/domain/i_disting_midi_manager.dart'
    show IDistingMidiManager;
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';
import 'package:nt_helper/services/algorithm_repeat_inference_service.dart';
import 'package:nt_helper/services/algorithm_guid_utils.dart';
import 'package:nt_helper/services/elf_guid_extractor.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';

/// Service to synchronize static algorithm metadata from the device to the local database.
class MetadataSyncService {
  final IDistingMidiManager _distingManager;
  final AppDatabase _database;

  MetadataSyncService(this._distingManager, this._database);

  Future<FirmwareVersion> _requestFirmwareVersionSafe() async {
    try {
      return FirmwareVersion(
        await _distingManager.requestVersionString() ?? '',
      );
    } catch (_) {
      return FirmwareVersion('');
    }
  }

  bool _isUsefulOfflineCountSpec(Specification spec) {
    return AlgorithmRepeatInferenceService.isRepeatCandidate(spec);
  }

  int _scanSpecValue(Specification spec) {
    if (!_isUsefulOfflineCountSpec(spec)) return spec.safeDefaultValue;

    final usefulValue = (spec.max >= 2 ? 2 : 1).clamp(spec.min, spec.max);
    if (spec.defaultValue >= usefulValue && spec.defaultValue <= spec.max) {
      return spec.defaultValue;
    }
    return usefulValue;
  }

  /// Compute representative spec values for metadata scanning.
  ///
  /// The database stores one metadata shape per algorithm, so scan count-like
  /// channel specs with a useful small value instead of a boring single channel.
  List<int> _scanSpecValues(AlgorithmInfo algoInfo) {
    return algoInfo.specifications.map(_scanSpecValue).toList();
  }

  String _describeSpecificationVector(
    AlgorithmInfo algoInfo,
    List<int> values,
  ) => [
    for (final (index, value) in values.indexed)
      '${algoInfo.specifications[index].name}=$value',
  ].join(', ');

  /// Poll until the preset count matches [expected], or [maxAttempts] is reached.
  Future<int> _pollPresetCount({
    required int expected,
    required int maxAttempts,
    bool Function()? checkCancel,
  }) async {
    var numInPreset = -1;
    var attempts = 0;
    while (numInPreset != expected &&
        attempts < maxAttempts &&
        !(checkCancel?.call() ?? false)) {
      await Future.delayed(const Duration(milliseconds: 500));
      numInPreset = await _distingManager.requestNumAlgorithmsInPreset() ?? -1;
      attempts++;
    }
    return numInPreset;
  }

  /// For plugins, reload AlgorithmInfo after instantiation; otherwise return as-is.
  Future<AlgorithmInfo> _resolveAlgorithmForQuery(
    AlgorithmInfo algoInfo,
  ) async {
    if (!algoInfo.isPlugin) return algoInfo;
    return await _distingManager.requestAlgorithmInfo(
          algoInfo.algorithmIndex,
        ) ??
        algoInfo;
  }

  /// Check if an error is a timeout-related error that may require device reboot.
  bool _isTimeoutError(Object error) {
    final errorString = error.toString();
    return errorString.contains('TimeoutException') ||
        errorString.contains('No response after') ||
        error is TimeoutException;
  }

  /// Reboot the device and wait for it to reconnect.
  ///
  /// Sends requestReboot(), waits 30s in 1-second increments (checking cancel),
  /// then wakes the device and verifies communication.
  Future<void> _rebootAndWaitForReconnection({
    void Function(String message)? onStatus,
    bool Function()? checkCancel,
  }) async {
    onStatus?.call('Sending reboot command...');
    try {
      await _distingManager.requestReboot();
    } catch (_) {
      // Fire-and-forget — device may disconnect immediately
    }

    // Wait 30 seconds in 1-second increments
    for (int i = 0; i < 30; i++) {
      if (checkCancel?.call() ?? false) return;
      onStatus?.call('Waiting for device to reboot... ${30 - i}s remaining');
      await Future.delayed(const Duration(seconds: 1));
    }

    if (checkCancel?.call() ?? false) return;

    // Wake the device
    onStatus?.call('Waking device...');
    await _distingManager.requestWake();
    await Future.delayed(const Duration(milliseconds: 500));

    // Verify communication — poll up to 5 times with 2s gaps
    for (int attempt = 0; attempt < 5; attempt++) {
      if (checkCancel?.call() ?? false) return;
      onStatus?.call('Verifying communication... (attempt ${attempt + 1}/5)');
      try {
        final numAlgos = await _distingManager.requestNumberOfAlgorithms();
        if (numAlgos != null && numAlgos > 0) {
          // Communication restored — clear preset
          await _distingManager.requestNewPreset();
          await Future.delayed(const Duration(milliseconds: 500));
          onStatus?.call('Device reconnected successfully.');
          return;
        }
      } catch (_) {
        // Not ready yet
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    throw Exception('Failed to reconnect to device after reboot.');
  }

  /// Try to scan a single algorithm: add → poll → query → remove → poll.
  ///
  /// Returns true on success. Throws on failure.
  Future<void> _tryScanAlgorithm({
    required AlgorithmInfo algoInfo,
    required MetadataDao metadataDao,
    required Map<String, int> unitIdMap,
    required List<String> dbUnitStrings,
    required FirmwareVersion firmwareVersion,
    bool Function()? checkCancel,
    void Function(String status)? onStatus,
  }) async {
    // Load plugin if needed
    if (algoInfo.isPlugin && !algoInfo.isLoaded) {
      await _distingManager.requestLoadPlugin(algoInfo.guid);
      await Future.delayed(const Duration(milliseconds: 1000));
      if (checkCancel?.call() ?? false) return;
    }

    final inference = AlgorithmRepeatInferenceService();
    final plan = inference.buildInitialPlan(algoInfo.specifications);
    final hasCountAxes = plan.lowerWitnessByAxis.isNotEmpty;
    AlgorithmShapeSnapshot? canonical;
    AlgorithmRepeatGrammar? grammar;
    var status = 'no repeats';

    if (hasCountAxes) {
      try {
        final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{};
        onStatus?.call(
          'Capturing canonical repeat witness '
          '(${_describeSpecificationVector(algoInfo, plan.canonical.values)})...',
        );
        canonical = await _probeAlgorithmShape(
          algoInfo: algoInfo,
          specificationValues: plan.canonical.values,
          firmwareVersion: firmwareVersion,
          checkCancel: checkCancel,
        );
        if (canonical.parameters.isEmpty) {
          throw const _MetadataProbeException(
            'Canonical witness returned incomplete metadata',
          );
        }
        snapshots[plan.canonical] = canonical;
        for (final witness in plan.lowerWitnessByAxis.values) {
          onStatus?.call(
            'Capturing lower repeat witness '
            '(${_describeSpecificationVector(algoInfo, witness.values)})...',
          );
          final snapshot = await _probeAlgorithmShape(
            algoInfo: algoInfo,
            specificationValues: witness.values,
            firmwareVersion: firmwareVersion,
            checkCancel: checkCancel,
          );
          if (snapshot.parameters.isEmpty) {
            throw const _MetadataProbeException(
              'Lower witness returned incomplete metadata',
            );
          }
          snapshots[witness] = snapshot;
        }
        final analysis = inference.analyzeInitial(
          specifications: algoInfo.specifications,
          plan: plan,
          snapshots: snapshots,
        );
        for (final witness in inference.interactionWitnesses(analysis)) {
          onStatus?.call(
            'Capturing interaction witness '
            '(${_describeSpecificationVector(algoInfo, witness.values)})...',
          );
          final snapshot = await _probeAlgorithmShape(
            algoInfo: algoInfo,
            specificationValues: witness.values,
            firmwareVersion: firmwareVersion,
            checkCancel: checkCancel,
          );
          if (snapshot.parameters.isEmpty) {
            throw const _MetadataProbeException(
              'Interaction witness returned incomplete metadata',
            );
          }
          snapshots[witness] = snapshot;
        }
        switch (inference.compile(analysis: analysis, snapshots: snapshots)) {
          case ProvenAlgorithmRepeatGrammar(grammar: final provenGrammar):
            grammar = provenGrammar;
            status =
                'Repeat grammar proven from ${snapshots.length} hardware shapes.';
          case NoAlgorithmRepeats():
            status =
                'No repeat topology found across ${snapshots.length} hardware shapes.';
          case UnprovenAlgorithmRepeats(reason: final reason):
            status =
                'Repeat topology unproven across ${snapshots.length} hardware shapes: $reason';
        }
      } catch (error) {
        status =
            'Repeat topology unproven; using a conservative flat shape ($error).';
        grammar = null;
      }
      debugPrint('[metadata-sync] ${algoInfo.guid}: $status');
    }

    if (canonical == null || grammar == null) {
      final fallbackValues = _scanSpecValues(algoInfo);
      if (canonical == null ||
          !_sameSpecificationVector(
            canonical.specificationValues,
            fallbackValues,
          )) {
        canonical = await _probeAlgorithmShape(
          algoInfo: algoInfo,
          specificationValues: fallbackValues,
          firmwareVersion: firmwareVersion,
          checkCancel: checkCancel,
        );
      }
      grammar = null;
    }

    if (checkCancel?.call() ?? false) return;
    await _persistCanonicalAlgorithmShape(
      metadataDao,
      algoInfo,
      canonical,
      unitIdMap,
      dbUnitStrings,
      grammar,
    );
    onStatus?.call(status);
  }

  bool _sameSpecificationVector(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  Future<AlgorithmShapeSnapshot> _probeAlgorithmShape({
    required AlgorithmInfo algoInfo,
    required List<int> specificationValues,
    required FirmwareVersion firmwareVersion,
    bool Function()? checkCancel,
  }) async {
    var added = false;
    try {
      await _distingManager.requestAddAlgorithm(algoInfo, specificationValues);
      added = true;
      final numInPreset = await _pollPresetCount(
        expected: 1,
        maxAttempts: algoInfo.isPlugin ? 15 : 10,
        checkCancel: checkCancel,
      );
      if (checkCancel?.call() ?? false) {
        throw const _MetadataProbeException('Metadata scan cancelled');
      }
      if (numInPreset != 1) {
        throw _MetadataProbeException(
          'Failed to add algorithm to preset (expected 1, found $numInPreset)',
        );
      }
      final instantiated = await _distingManager.requestAlgorithmGuid(0);
      if (instantiated == null || instantiated.guid != algoInfo.guid) {
        throw const _MetadataProbeException(
          'Hardware did not instantiate the requested GUID',
        );
      }
      final algorithmToQuery = await _resolveAlgorithmForQuery(algoInfo);
      return await _captureInstantiatedAlgorithmShape(
        algorithmToQuery,
        specificationValues,
        firmwareVersion,
      );
    } finally {
      if (added) {
        try {
          await _distingManager.requestRemoveAlgorithm(0);
          await _pollPresetCount(
            expected: 0,
            maxAttempts: 8,
            checkCancel: checkCancel,
          );
        } catch (_) {
          // Preserve the original capture failure. Outer recovery clears preset.
        }
      }
    }
  }

  /// Clean up a failed algorithm from DB and device.
  Future<void> _cleanupFailedAlgorithm(
    MetadataDao metadataDao,
    String guid,
  ) async {
    // DB cleanup
    try {
      await metadataDao.clearAlgorithmMetadata(guid);
      await (metadataDao.delete(
        metadataDao.specifications,
      )..where((s) => s.algorithmGuid.equals(guid))).go();
      await (metadataDao.delete(
        metadataDao.algorithms,
      )..where((a) => a.guid.equals(guid))).go();
    } catch (_) {
      // Best effort
    }

    // Device cleanup
    try {
      await _distingManager.requestNewPreset();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {
      // Best effort
    }
  }

  /// Fetches all static algorithm metadata from the connected device
  /// by temporarily manipulating a preset, and caches it in the database.
  ///
  /// [onProgress] callback reports progress (0.0-1.0), counts, and messages.
  /// [onError] callback reports errors encountered during the process.
  /// [onCheckpoint] callback saves checkpoint with algorithm name and index.
  /// [resumeFromIndex] optional algorithm index to resume from.
  /// [isCancelled] callback allows checking if cancellation has been requested.
  Future<void> syncAllAlgorithmMetadata({
    Function(
      double progress,
      int processed,
      int total,
      String mainMessage,
      String subMessage,
    )?
    onProgress,
    Function(String error)? onError,
    Future<void> Function(String algorithmName, int algorithmIndex)?
    onCheckpoint,
    int? resumeFromIndex,
    bool Function()? isCancelled,
  }) async {
    final metadataDao = _database.metadataDao;
    int totalAlgorithms = 0;
    int algorithmsProcessed = 0;
    late final FirmwareVersion firmwareVersion;

    void reportProgress(
      String mainMessage,
      String subMessage, {
      bool incrementCount = false,
    }) {
      if (incrementCount) {
        algorithmsProcessed++;
      }
      final progress = totalAlgorithms == 0
          ? 0.0
          : algorithmsProcessed / totalAlgorithms;
      onProgress?.call(
        progress,
        algorithmsProcessed,
        totalAlgorithms,
        mainMessage,
        subMessage,
      );
    }

    // Helper to check cancellation
    bool checkCancel() => isCancelled?.call() ?? false;

    try {
      reportProgress("Initializing Sync", "Starting...");
      if (checkCancel()) return;

      // Ensure device is awake
      reportProgress("Initializing Sync", "Waking device...");
      await _distingManager.requestWake();
      await Future.delayed(const Duration(milliseconds: 200));
      if (checkCancel()) return;

      firmwareVersion = await _requestFirmwareVersionSafe();

      // Clear device preset and DB cache (only if not resuming)
      if (resumeFromIndex == null) {
        reportProgress(
          "Initializing Sync",
          "Clearing device preset and local cache...",
        );
        await metadataDao.clearAllMetadata(); // Clear DB first
        await _distingManager.requestNewPreset(); // Clear on device
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Allow device time
        if (checkCancel()) return;
      } else {
        reportProgress("Resuming Sync", "Clearing device preset...");
        await _distingManager.requestNewPreset(); // Clear on device
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Allow device time
        if (checkCancel()) return;
      }

      // Verify preset is empty
      var numInPreset =
          await _distingManager.requestNumAlgorithmsInPreset() ?? -1;
      if (numInPreset != 0) {
        throw Exception(
          "Failed to clear device preset (expected 0 algorithms, found $numInPreset).",
        );
      }

      // 1. Sync Unit Strings
      reportProgress(
        "Fetching Prerequisite Data",
        "Requesting unit strings...",
      );
      final unitStrings = await _distingManager.requestUnitStrings() ?? [];
      final unitIdMap = <String, int>{};
      final unitFutures = <Future<void>>[];
      for (final unitStr in unitStrings) {
        if (unitStr.isNotEmpty) {
          unitFutures.add(
            metadataDao.upsertUnit(unitStr).then((id) {
              unitIdMap[unitStr] = id;
            }),
          );
        }
      }
      await Future.wait(unitFutures);
      reportProgress(
        "Fetching Prerequisite Data",
        "Cached ${unitIdMap.length} unit strings.",
      );
      if (checkCancel()) return;

      // --- NEW: Save the ordered list to the cache ---
      try {
        await metadataDao.saveOrderedUnitStrings(unitStrings);
      } catch (e) {
        // Decide if this is a fatal error - maybe not, if reconstruction can fall back?
        // For now, we just log a warning.
      }
      // --- END NEW ---

      // 2. Get All Algorithm Basic Info
      reportProgress(
        "Fetching Algorithm List",
        "Requesting number of algorithms...",
      );
      final numAlgoTypes = await _distingManager.requestNumberOfAlgorithms();
      if (numAlgoTypes == null || numAlgoTypes == 0) {
        reportProgress(
          "Fetching Algorithm List",
          "No algorithm types found on device.",
        );
        throw Exception("No algorithm types found on device.");
      }
      totalAlgorithms = numAlgoTypes;
      reportProgress(
        "Fetching Algorithm List ($totalAlgorithms total)",
        "Requesting basic info...",
      );

      final allAlgorithmInfo = <AlgorithmInfo>[];
      final algoEntries = <AlgorithmEntry>[];
      final specEntries = <SpecificationEntry>[];

      for (
        int globalAlgoIndex = 0;
        globalAlgoIndex < totalAlgorithms;
        globalAlgoIndex++
      ) {
        if (checkCancel()) break;
        final algoInfo = await _distingManager.requestAlgorithmInfo(
          globalAlgoIndex,
        );
        if (algoInfo != null) {
          allAlgorithmInfo.add(algoInfo);
          algoEntries.add(
            AlgorithmEntry(
              guid: algoInfo.guid,
              name: algoInfo.name,
              numSpecifications: algoInfo.numSpecifications,
            ),
          );

          if (algoInfo.specifications.isNotEmpty) {
            specEntries.addAll(
              algoInfo.specifications.asMap().entries.map((entry) {
                final index = entry.key;
                final spec = entry.value;
                return SpecificationEntry(
                  algorithmGuid: algoInfo.guid,
                  specIndex: index,
                  name: spec.name,
                  minValue: spec.min,
                  maxValue: spec.max,
                  defaultValue: spec.defaultValue,
                  type: spec.type,
                );
              }),
            );
          }
        } else {}
        final fetchProgressMsg =
            "Fetched basic info ${globalAlgoIndex + 1}/$totalAlgorithms";
        reportProgress(
          "Fetching Algorithm List ($totalAlgorithms total)",
          fetchProgressMsg,
        );
      }
      if (checkCancel()) return;

      // Upsert basic info *before* instantiation loop
      await metadataDao.upsertAlgorithms(algoEntries);
      await metadataDao.upsertSpecifications(specEntries);
      reportProgress(
        "Fetching Algorithm List ($totalAlgorithms total)",
        "Cached basic info for ${allAlgorithmInfo.length} algorithms.",
      );
      if (checkCancel()) return;

      // Reset processed count before starting instantiation phase
      algorithmsProcessed = resumeFromIndex ?? 0;

      // 3. Process Factory Algorithms (skip community plugins)
      reportProgress(
        "Processing Algorithms",
        "Starting algorithm processing...",
      );

      // Filter to factory algorithms only (lowercase alphanumeric GUIDs).
      // Community plugins (uppercase GUIDs) cause memory issues during sync
      // and are skipped here — their basic info is already cached above.
      final orderedAlgorithms = allAlgorithmInfo
          .where((a) => AlgorithmGuidUtils.isFactoryGuid(a.guid))
          .toList();
      totalAlgorithms = orderedAlgorithms.length;

      final dbUnits = await metadataDao.getAllUnits();
      final dbUnitStrings = dbUnits.map((u) => u.unitString).toList();

      // 4. Process All Algorithms in Single Loop
      final failedPlugins = <AlgorithmInfo>[];

      for (int i = 0; i < orderedAlgorithms.length; i++) {
        if (checkCancel()) break;

        // Skip if resuming and haven't reached resume point
        if (resumeFromIndex != null && i < resumeFromIndex) {
          algorithmsProcessed++;
          continue;
        }

        final algoInfo = orderedAlgorithms[i];
        final mainProgressMsg = algoInfo.name;

        // Save checkpoint before processing each algorithm
        await onCheckpoint?.call(algoInfo.name, i);

        reportProgress(mainProgressMsg, "Starting...", incrementCount: true);

        try {
          await _tryScanAlgorithm(
            algoInfo: algoInfo,
            metadataDao: metadataDao,
            unitIdMap: unitIdMap,
            dbUnitStrings: dbUnitStrings,
            firmwareVersion: firmwareVersion,
            checkCancel: checkCancel,
            onStatus: (status) => reportProgress(mainProgressMsg, status),
          );
          reportProgress(mainProgressMsg, "Done.");
        } catch (instantiationError, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);

          if (_isTimeoutError(instantiationError)) {
            // Timeout — auto-reboot and retry
            reportProgress(
              mainProgressMsg,
              "Timeout detected — rebooting device...",
            );
            try {
              await _rebootAndWaitForReconnection(
                onStatus: (msg) => reportProgress(mainProgressMsg, msg),
                checkCancel: checkCancel,
              );
              if (checkCancel()) break;

              reportProgress(mainProgressMsg, "Retrying after reboot...");
              await _tryScanAlgorithm(
                algoInfo: algoInfo,
                metadataDao: metadataDao,
                unitIdMap: unitIdMap,
                dbUnitStrings: dbUnitStrings,
                firmwareVersion: firmwareVersion,
                checkCancel: checkCancel,
                onStatus: (status) => reportProgress(mainProgressMsg, status),
              );
              reportProgress(mainProgressMsg, "Retry succeeded.");
            } catch (retryError) {
              // Retry failed — defer to end-of-scan pass
              failedPlugins.add(algoInfo);
              await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
              reportProgress(
                mainProgressMsg,
                "Deferred for end-of-scan retry.",
              );
            }
          } else {
            // Non-timeout error — report and clean up
            onError?.call(
              "Error processing ${algoInfo.name}: $instantiationError",
            );
            await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
          }
        }
      }

      // 4b. End-of-scan retry pass for failed plugins
      if (failedPlugins.isNotEmpty && !checkCancel()) {
        reportProgress(
          "Retrying Failed Plugins",
          "Rescanning plugins and rebooting...",
        );
        try {
          await _distingManager.requestRescanPlugins();
          // Wait 5 seconds for rescan to complete
          for (int i = 0; i < 5; i++) {
            if (checkCancel()) break;
            await Future.delayed(const Duration(seconds: 1));
          }
          if (!checkCancel()) {
            await _rebootAndWaitForReconnection(
              onStatus: (msg) => reportProgress("Retrying Failed Plugins", msg),
              checkCancel: checkCancel,
            );
          }
        } catch (e) {
          reportProgress("Retrying Failed Plugins", "Rescan/reboot failed: $e");
        }

        if (!checkCancel()) {
          for (final algoInfo in failedPlugins) {
            if (checkCancel()) break;
            final retryMsg = "${algoInfo.name} (final retry)";
            reportProgress(retryMsg, "Starting final retry...");
            try {
              await _tryScanAlgorithm(
                algoInfo: algoInfo,
                metadataDao: metadataDao,
                unitIdMap: unitIdMap,
                dbUnitStrings: dbUnitStrings,
                firmwareVersion: firmwareVersion,
                checkCancel: checkCancel,
                onStatus: (status) => reportProgress(retryMsg, status),
              );
              reportProgress(retryMsg, "Final retry succeeded.");
            } catch (finalError) {
              onError?.call(
                "Failed to scan ${algoInfo.name} after all retries: $finalError",
              );
              await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
            }
          }
        }
      }

      // 5. Final pass: Retry algorithms with 0 parameters
      if (!checkCancel()) {
        reportProgress(
          "Final Verification",
          "Checking for algorithms with missing parameters...",
        );

        final algorithmsWithZeroParams = <AlgorithmInfo>[];
        try {
          final parameterCounts = await metadataDao
              .getAlgorithmParameterCounts();

          for (final algoInfo in orderedAlgorithms) {
            final paramCount = parameterCounts[algoInfo.guid] ?? 0;
            if (paramCount == 0) {
              algorithmsWithZeroParams.add(algoInfo);
            }
          }
        } catch (e) {
          // Intentionally empty
        }

        if (algorithmsWithZeroParams.isNotEmpty && !checkCancel()) {
          reportProgress(
            "Final Verification",
            "Retrying ${algorithmsWithZeroParams.length} algorithms with missing parameters...",
          );

          for (final algoInfo in algorithmsWithZeroParams) {
            if (checkCancel()) break;

            final mainProgressMsg = "${algoInfo.name} (retry)";
            reportProgress(mainProgressMsg, "Starting retry...");

            try {
              await _tryScanAlgorithm(
                algoInfo: algoInfo,
                metadataDao: metadataDao,
                unitIdMap: unitIdMap,
                dbUnitStrings: dbUnitStrings,
                firmwareVersion: firmwareVersion,
                checkCancel: checkCancel,
              );
              reportProgress(mainProgressMsg, "Retry completed.");
            } catch (retryError, stackTrace) {
              debugPrintStack(stackTrace: stackTrace);

              // Clean up if retry fails
              try {
                await _distingManager.requestNewPreset();
                await Future.delayed(const Duration(milliseconds: 500));
              } catch (cleanupError) {
                // Intentionally empty
              }
            }
          }
        } else {
          reportProgress(
            "Final Verification",
            "All algorithms have parameters - verification complete.",
          );
        }
      }

      // Check cancellation one last time before final success message
      if (checkCancel()) {
        reportProgress("Synchronization Cancelled", "Process stopped by user.");
      } else {
        reportProgress("Synchronization Complete", "Finished all algorithms.");
      }
    } catch (e, stackTrace) {
      final errorMsg = "Synchronization failed: $e";
      debugPrintStack(stackTrace: stackTrace);
      // Avoid reporting progress if cancelled, let the main error handler do it
      if (!checkCancel()) {
        reportProgress("Synchronization Failed", "Error: $e");
      }
      onError?.call(errorMsg);
    }
  }

  Future<AlgorithmShapeSnapshot> _captureInstantiatedAlgorithmShape(
    AlgorithmInfo algoInfo,
    List<int> requestedSpecifications,
    FirmwareVersion firmwareVersion,
  ) async {
    final numParamsResult = await _distingManager.requestNumberOfParameters(0);
    final numParams = numParamsResult?.numParameters ?? 0;
    if (numParams == 0) {
      return AlgorithmShapeSnapshot(
        specificationValues: requestedSpecifications,
        parameters: const [],
        pages: const [],
        pageMemberships: const [],
        outputUsage: const [],
      );
    }

    final parameterPagesResult = await _distingManager.requestParameterPages(0);
    final parameters = <ShapeParameterAtom>[];
    final outputUsage = <ShapeOutputUsageAtom>[];
    for (
      var parameterNumber = 0;
      parameterNumber < numParams;
      parameterNumber++
    ) {
      final paramInfo = await _distingManager.requestParameterInfo(
        0,
        parameterNumber,
      );
      if (paramInfo == null || paramInfo.parameterNumber != parameterNumber) {
        throw _MetadataProbeException(
          'Missing parameter metadata at $parameterNumber',
        );
      }
      var enumStrings = const <String>[];
      if (paramInfo.unit == 1 &&
          !(firmwareVersion.isExactly('1.12.0') &&
              algoInfo.guid == 'maco' &&
              parameterNumber == 1)) {
        enumStrings =
            (await _distingManager.requestParameterEnumStrings(
              0,
              parameterNumber,
            ))?.values ??
            const [];
      }
      parameters.add(
        ShapeParameterAtom(
          name: paramInfo.name,
          min: paramInfo.min,
          max: paramInfo.max,
          defaultValue: paramInfo.defaultValue,
          rawUnitIndex: paramInfo.unit,
          powerOfTen: paramInfo.powerOfTen,
          ioFlags: paramInfo.ioFlags,
          enumStrings: enumStrings,
        ),
      );
      if (paramInfo.isOutputMode) {
        try {
          final usage = await _distingManager.requestOutputModeUsage(
            0,
            parameterNumber,
          );
          for (final affected in usage?.affectedParameterNumbers ?? const []) {
            if (affected < 0 || affected >= numParams) {
              throw const _MetadataProbeException(
                'Output usage contains a dangling parameter reference',
              );
            }
            outputUsage.add(
              ShapeOutputUsageAtom(
                parameterNumber: parameterNumber,
                affectedParameterNumber: affected,
              ),
            );
          }
        } on _MetadataProbeException {
          rethrow;
        } catch (_) {
          // Supplementary usage may be unavailable on older firmware.
        }
      }
    }

    final pages = <ShapePageAtom>[];
    final memberships = <ShapePageMembershipAtom>[];
    for (final (pageIndex, page)
        in (parameterPagesResult?.pages ?? const []).indexed) {
      pages.add(ShapePageAtom(name: page.name));
      for (final parameterNumber in page.parameters) {
        if (parameterNumber < 0 || parameterNumber >= numParams) {
          throw const _MetadataProbeException(
            'Page contains a dangling parameter reference',
          );
        }
        memberships.add(
          ShapePageMembershipAtom(
            pageIndex: pageIndex,
            parameterNumber: parameterNumber,
          ),
        );
      }
    }

    return AlgorithmShapeSnapshot(
      specificationValues: requestedSpecifications,
      parameters: parameters,
      pages: pages,
      pageMemberships: memberships,
      outputUsage: outputUsage,
    );
  }

  Future<void> _persistCanonicalAlgorithmShape(
    MetadataDao metadataDao,
    AlgorithmInfo algoInfo,
    AlgorithmShapeSnapshot snapshot,
    Map<String, int> unitIdMap,
    List<String> dbUnitStrings,
    AlgorithmRepeatGrammar? grammar,
  ) async {
    String? unitString(int rawUnitIndex) {
      if (rawUnitIndex <= 0 || rawUnitIndex > dbUnitStrings.length) return null;
      return dbUnitStrings[rawUnitIndex - 1];
    }

    final paramEntries = <ParameterEntry>[];
    final enumEntries = <ParameterEnumEntry>[];
    for (final (parameterNumber, parameter) in snapshot.parameters.indexed) {
      final unit = unitString(parameter.rawUnitIndex);
      paramEntries.add(
        ParameterEntry(
          algorithmGuid: algoInfo.guid,
          parameterNumber: parameterNumber,
          name: parameter.name,
          minValue: parameter.min,
          maxValue: parameter.max,
          defaultValue: parameter.defaultValue,
          unitId: unit == null ? null : unitIdMap[unit],
          powerOfTen: parameter.powerOfTen,
          ioFlags: parameter.ioFlags,
          rawUnitIndex: parameter.rawUnitIndex,
        ),
      );
      for (final (enumIndex, enumString) in parameter.enumStrings.indexed) {
        enumEntries.add(
          ParameterEnumEntry(
            algorithmGuid: algoInfo.guid,
            parameterNumber: parameterNumber,
            enumIndex: enumIndex,
            enumString: enumString,
          ),
        );
      }
    }

    final pageEntries = [
      for (final (pageIndex, page) in snapshot.pages.indexed)
        ParameterPageEntry(
          algorithmGuid: algoInfo.guid,
          pageIndex: pageIndex,
          name: page.name,
        ),
    ];
    final pageItemEntries = [
      for (final membership in snapshot.pageMemberships)
        ParameterPageItemEntry(
          algorithmGuid: algoInfo.guid,
          pageIndex: membership.pageIndex,
          parameterNumber: membership.parameterNumber,
        ),
    ];
    final groupedUsage = <int, List<int>>{};
    for (final usage in snapshot.outputUsage) {
      (groupedUsage[usage.parameterNumber] ??= []).add(
        usage.affectedParameterNumber,
      );
    }
    final outputUsageEntries = [
      for (final entry in groupedUsage.entries)
        ParameterOutputModeUsageEntry(
          algorithmGuid: algoInfo.guid,
          parameterNumber: entry.key,
          affectedOutputNumbers: [...entry.value]..sort(),
        ),
    ];

    await metadataDao.replaceAlgorithmShapeAndGrammar(
      guid: algoInfo.guid,
      parameters: paramEntries,
      enums: enumEntries,
      pages: pageEntries,
      pageItems: pageItemEntries,
      outputUsage: outputUsageEntries,
      grammar: grammar,
    );
  }

  /// Rescan a single algorithm's parameters
  Future<void> rescanSingleAlgorithm(
    AlgorithmInfo algoInfo, {
    void Function(String status)? onStatus,
  }) async {
    final metadataDao = _database.metadataDao;
    final firmwareVersion = await _requestFirmwareVersionSafe();
    final dbUnits = await metadataDao.getAllUnits();
    final dbUnitStrings = dbUnits.map((u) => u.unitString).toList();
    final unitIdMap = <String, int>{};
    for (final unit in dbUnits) {
      unitIdMap[unit.unitString] = unit.id;
    }

    try {
      await _tryScanAlgorithm(
        algoInfo: algoInfo,
        metadataDao: metadataDao,
        unitIdMap: unitIdMap,
        dbUnitStrings: dbUnitStrings,
        firmwareVersion: firmwareVersion,
        onStatus: onStatus,
      );
    } catch (error) {
      if (_isTimeoutError(error)) {
        // Timeout — reboot and retry once
        await _rebootAndWaitForReconnection(onStatus: onStatus);
        await _tryScanAlgorithm(
          algoInfo: algoInfo,
          metadataDao: metadataDao,
          unitIdMap: unitIdMap,
          dbUnitStrings: dbUnitStrings,
          firmwareVersion: firmwareVersion,
          onStatus: onStatus,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Incrementally sync only new algorithms not present in the database
  Future<void> syncNewAlgorithmsOnly({
    Function(
      double progress,
      int processed,
      int total,
      String mainMessage,
      String subMessage,
    )?
    onProgress,
    Function(String error)? onError,
    bool Function()? isCancelled,
  }) async {
    final metadataDao = _database.metadataDao;
    late final FirmwareVersion firmwareVersion;

    void reportProgress(
      String mainMessage,
      String subMessage, {
      int processed = 0,
      int total = 0,
    }) {
      final progress = total == 0 ? 0.0 : processed / total;
      onProgress?.call(progress, processed, total, mainMessage, subMessage);
    }

    // Helper to check cancellation
    bool checkCancel() => isCancelled?.call() ?? false;

    try {
      reportProgress("Checking for New Algorithms", "Connecting to device...");
      if (checkCancel()) return;

      // Ensure device is awake
      await _distingManager.requestWake();
      await Future.delayed(const Duration(milliseconds: 200));
      if (checkCancel()) return;

      firmwareVersion = await _requestFirmwareVersionSafe();

      // Get current algorithm list from device
      reportProgress(
        "Checking for New Algorithms",
        "Getting device algorithm list...",
      );
      final numAlgoTypes = await _distingManager.requestNumberOfAlgorithms();
      if (numAlgoTypes == null || numAlgoTypes == 0) {
        throw Exception("No algorithm types found on device.");
      }

      final deviceAlgorithms = <AlgorithmInfo>[];
      for (int i = 0; i < numAlgoTypes; i++) {
        if (checkCancel()) break;
        final algoInfo = await _distingManager.requestAlgorithmInfo(i);
        if (algoInfo != null) {
          deviceAlgorithms.add(algoInfo);
        }
        reportProgress(
          "Checking for New Algorithms",
          "Found ${deviceAlgorithms.length}/$numAlgoTypes algorithms on device...",
        );
      }
      if (checkCancel()) return;

      // Get current algorithm list from database
      reportProgress(
        "Checking for New Algorithms",
        "Getting local algorithm list...",
      );
      final localAlgorithms = await metadataDao.getAllAlgorithms();
      final localGuids = localAlgorithms.map((a) => a.guid).toSet();

      // Find new algorithms (present on device but not in database)
      final newAlgorithms = deviceAlgorithms
          .where((deviceAlgo) => !localGuids.contains(deviceAlgo.guid))
          .toList();

      if (newAlgorithms.isEmpty) {
        reportProgress(
          "Incremental Sync Complete",
          "No new algorithms found.",
          processed: 0,
          total: 0,
        );
        return;
      }

      for (final _ in newAlgorithms) {}

      // Process community plugins first, then factory algorithms
      final newCommunityAlgorithms = newAlgorithms
          .where((a) => a.isPlugin)
          .toList();
      final newFactoryAlgorithms = newAlgorithms
          .where((a) => !a.isPlugin)
          .toList();
      final orderedNewAlgorithms = [
        ...newCommunityAlgorithms,
        ...newFactoryAlgorithms,
      ];

      // Sync unit strings if needed (in case new algorithms introduce new units)
      reportProgress(
        "Syncing Prerequisites",
        "Updating unit strings...",
        processed: 0,
        total: orderedNewAlgorithms.length,
      );
      final unitStrings = await _distingManager.requestUnitStrings() ?? [];
      final unitIdMap = <String, int>{};
      final unitFutures = <Future<void>>[];
      for (final unitStr in unitStrings) {
        if (unitStr.isNotEmpty) {
          unitFutures.add(
            metadataDao.upsertUnit(unitStr).then((id) {
              unitIdMap[unitStr] = id;
            }),
          );
        }
      }
      await Future.wait(unitFutures);
      if (checkCancel()) return;

      // Get existing units for parameter processing
      final dbUnits = await metadataDao.getAllUnits();
      final dbUnitStrings = dbUnits.map((u) => u.unitString).toList();

      // Clear device preset before starting
      reportProgress(
        "Syncing Prerequisites",
        "Clearing device preset...",
        processed: 0,
        total: orderedNewAlgorithms.length,
      );
      await _distingManager.requestNewPreset();
      await Future.delayed(const Duration(milliseconds: 500));
      if (checkCancel()) return;

      // Process new algorithms
      final failedPlugins = <AlgorithmInfo>[];

      for (int i = 0; i < orderedNewAlgorithms.length; i++) {
        if (checkCancel()) break;

        final algoInfo = orderedNewAlgorithms[i];
        final mainProgressMsg = "${algoInfo.name} (new)";

        reportProgress(
          mainProgressMsg,
          "Starting sync...",
          processed: i,
          total: orderedNewAlgorithms.length,
        );

        try {
          // Store basic algorithm info first
          await metadataDao.upsertAlgorithms([
            AlgorithmEntry(
              guid: algoInfo.guid,
              name: algoInfo.name,
              numSpecifications: algoInfo.numSpecifications,
            ),
          ]);

          if (algoInfo.specifications.isNotEmpty) {
            final specEntries = algoInfo.specifications.asMap().entries.map((
              entry,
            ) {
              final index = entry.key;
              final spec = entry.value;
              return SpecificationEntry(
                algorithmGuid: algoInfo.guid,
                specIndex: index,
                name: spec.name,
                minValue: spec.min,
                maxValue: spec.max,
                defaultValue: spec.defaultValue,
                type: spec.type,
              );
            }).toList();
            await metadataDao.upsertSpecifications(specEntries);
          }

          await _tryScanAlgorithm(
            algoInfo: algoInfo,
            metadataDao: metadataDao,
            unitIdMap: unitIdMap,
            dbUnitStrings: dbUnitStrings,
            firmwareVersion: firmwareVersion,
            checkCancel: checkCancel,
          );

          reportProgress(
            mainProgressMsg,
            "Completed.",
            processed: i + 1,
            total: orderedNewAlgorithms.length,
          );
        } catch (error, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);

          if (_isTimeoutError(error)) {
            // Timeout — auto-reboot and retry
            reportProgress(
              mainProgressMsg,
              "Timeout detected — rebooting device...",
              processed: i,
              total: orderedNewAlgorithms.length,
            );
            try {
              await _rebootAndWaitForReconnection(
                onStatus: (msg) => reportProgress(
                  mainProgressMsg,
                  msg,
                  processed: i,
                  total: orderedNewAlgorithms.length,
                ),
                checkCancel: checkCancel,
              );
              if (checkCancel()) break;

              reportProgress(
                mainProgressMsg,
                "Retrying after reboot...",
                processed: i,
                total: orderedNewAlgorithms.length,
              );
              await _tryScanAlgorithm(
                algoInfo: algoInfo,
                metadataDao: metadataDao,
                unitIdMap: unitIdMap,
                dbUnitStrings: dbUnitStrings,
                firmwareVersion: firmwareVersion,
                checkCancel: checkCancel,
              );
              reportProgress(
                mainProgressMsg,
                "Retry succeeded.",
                processed: i + 1,
                total: orderedNewAlgorithms.length,
              );
            } catch (retryError) {
              // Retry failed — defer to end-of-scan pass
              failedPlugins.add(algoInfo);
              await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
              reportProgress(
                mainProgressMsg,
                "Deferred for end-of-scan retry.",
                processed: i,
                total: orderedNewAlgorithms.length,
              );
            }
          } else {
            // Non-timeout error — report and clean up
            onError?.call(
              "Error syncing new algorithm ${algoInfo.name}: $error",
            );
            await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
          }
        }
      }

      // End-of-scan retry pass for failed plugins
      if (failedPlugins.isNotEmpty && !checkCancel()) {
        reportProgress(
          "Retrying Failed Plugins",
          "Rescanning plugins and rebooting...",
          processed: orderedNewAlgorithms.length - failedPlugins.length,
          total: orderedNewAlgorithms.length,
        );
        try {
          await _distingManager.requestRescanPlugins();
          for (int i = 0; i < 5; i++) {
            if (checkCancel()) break;
            await Future.delayed(const Duration(seconds: 1));
          }
          if (!checkCancel()) {
            await _rebootAndWaitForReconnection(
              onStatus: (msg) => reportProgress(
                "Retrying Failed Plugins",
                msg,
                processed: orderedNewAlgorithms.length - failedPlugins.length,
                total: orderedNewAlgorithms.length,
              ),
              checkCancel: checkCancel,
            );
          }
        } catch (e) {
          reportProgress(
            "Retrying Failed Plugins",
            "Rescan/reboot failed: $e",
            processed: orderedNewAlgorithms.length - failedPlugins.length,
            total: orderedNewAlgorithms.length,
          );
        }

        if (!checkCancel()) {
          for (final algoInfo in failedPlugins) {
            if (checkCancel()) break;
            final retryMsg = "${algoInfo.name} (final retry)";
            reportProgress(
              retryMsg,
              "Starting final retry...",
              processed: orderedNewAlgorithms.length - failedPlugins.length,
              total: orderedNewAlgorithms.length,
            );
            try {
              await _tryScanAlgorithm(
                algoInfo: algoInfo,
                metadataDao: metadataDao,
                unitIdMap: unitIdMap,
                dbUnitStrings: dbUnitStrings,
                firmwareVersion: firmwareVersion,
                checkCancel: checkCancel,
              );
              reportProgress(
                retryMsg,
                "Final retry succeeded.",
                processed: orderedNewAlgorithms.length,
                total: orderedNewAlgorithms.length,
              );
            } catch (finalError) {
              onError?.call(
                "Failed to scan ${algoInfo.name} after all retries: $finalError",
              );
              await _cleanupFailedAlgorithm(metadataDao, algoInfo.guid);
            }
          }
        }
      }

      if (checkCancel()) {
        reportProgress(
          "Incremental Sync Cancelled",
          "Process stopped by user.",
          processed: orderedNewAlgorithms.length,
          total: orderedNewAlgorithms.length,
        );
      } else {
        reportProgress(
          "Incremental Sync Complete",
          "Synced ${orderedNewAlgorithms.length} new algorithms.",
          processed: orderedNewAlgorithms.length,
          total: orderedNewAlgorithms.length,
        );
      }
    } catch (e, stackTrace) {
      final errorMsg = "Incremental sync failed: $e";
      debugPrintStack(stackTrace: stackTrace);
      if (!checkCancel()) {
        reportProgress("Incremental Sync Failed", "Error: $e");
      }
      onError?.call(errorMsg);
    }
  }

  /// Scan plugin directory and update algorithm records with file paths
  Future<void> scanAndUpdatePluginFilePaths({
    Function(String status)? onProgress,
    Function(String error)? onError,
  }) async {
    try {
      onProgress?.call("Scanning plugin directory...");

      // Create PresetFileSystemImpl with the MIDI manager
      final fileSystem = PresetFileSystemImpl(_distingManager);

      // Scan the plugin directory for .o files and extract GUIDs
      final pluginDirectory = "/programs/plug-ins";
      final guidToFilePathMap = await ElfGuidExtractor.scanPluginDirectory(
        fileSystem,
        pluginDirectory,
      );

      if (guidToFilePathMap.isEmpty) {
        onProgress?.call("No plugin files found.");
        return;
      }

      onProgress?.call("Updating algorithm records...");

      final metadataDao = _database.metadataDao;
      int updatedCount = 0;

      for (final entry in guidToFilePathMap.entries) {
        final guid = entry.key;
        final filePath = entry.value;

        try {
          // Check if algorithm exists in database
          final algorithm = await metadataDao.getAlgorithmByGuid(guid);
          if (algorithm != null) {
            // Update the plugin file path
            await metadataDao.updateAlgorithmPluginFilePath(guid, filePath);
            updatedCount++;
          } else {}
        } catch (e) {
          onError?.call("Error updating algorithm $guid: $e");
        }
      }

      final message =
          "Updated $updatedCount algorithm records with plugin file paths.";
      onProgress?.call(message);
    } catch (e) {
      final errorMsg = "Plugin scan failed: $e";
      onError?.call(errorMsg);
    }
  }
}

final class _MetadataProbeException implements Exception {
  const _MetadataProbeException(this.message);

  final String message;

  @override
  String toString() => message;
}
