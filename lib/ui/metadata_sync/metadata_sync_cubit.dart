import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show AlgorithmInfo, Specification;
import 'package:nt_helper/domain/i_disting_midi_manager.dart'
    show IDistingMidiManager;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/metadata_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'metadata_sync_cubit.freezed.dart';
part 'metadata_sync_state.dart';

class _PreparedPresetSlot {
  const _PreparedPresetSlot({
    required this.details,
    required this.specificationValues,
  });

  final FullAlgorithmDetails details;
  final List<int> specificationValues;

  AlgorithmInfo algorithmInfoAt(int algorithmIndex) => AlgorithmInfo(
    algorithmIndex: algorithmIndex,
    guid: details.algorithm.guid,
    name: details.algorithm.name,
    specifications: details.specifications
        .map(
          (spec) => Specification(
            name: spec.name,
            min: spec.minValue,
            max: spec.maxValue,
            defaultValue: spec.defaultValue,
            type: spec.type,
          ),
        )
        .toList(growable: false),
  );
}

class MetadataSyncCubit extends Cubit<MetadataSyncState> {
  final AppDatabase _database;
  final DistingCubit? _distingCubit;
  late final MetadataDao _metadataDao;
  late final PresetsDao _presetsDao;

  // Cancellation flag for metadata sync
  bool _isMetadataSyncCancelled = false;

  // Cancellation flag for template injection
  bool _isInjectionCancelled = false;
  // Re-entrance guard for device-side template apply. The UI also disables
  // the apply button, but this catches MCP/UI races where both paths could
  // call applyTemplateToDevice concurrently.
  bool _isInjectionRunning = false;

  // Checkpoint keys for SharedPreferences
  static const String _checkpointAlgorithmName =
      'metadata_sync_checkpoint_name';
  static const String _checkpointAlgorithmIndex =
      'metadata_sync_checkpoint_index';

  MetadataSyncCubit(this._database, [this._distingCubit])
    : super(const MetadataSyncState.idle()) {
    _metadataDao = _database.metadataDao;
    _presetsDao = _database.presetsDao;
  }

  // --- Metadata Sync Methods ---

  Future<void> startMetadataSync(
    IDistingMidiManager manager, {
    int? resumeFromIndex,
  }) async {
    if (switch (state) {
      SyncingMetadata() => true,
      _ => false,
    }) {
      return;
    }

    _isMetadataSyncCancelled = false; // Reset cancellation flag

    // Pause CPU monitoring during sync to prevent interference
    _distingCubit?.pauseCpuMonitoring();

    emit(
      const MetadataSyncState.syncingMetadata(
        progress: 0.0,
        mainMessage: "Initializing sync...",
        subMessage: "Preparing...",
      ),
    );

    bool errorOccurred = false;
    String finalMessage = "Metadata sync completed successfully.";

    final syncService = MetadataSyncService(manager, _database);

    await syncService.syncAllAlgorithmMetadata(
      resumeFromIndex: resumeFromIndex,
      onProgress: (progress, processed, total, mainMsg, subMsg) {
        if (!isClosed && !_isMetadataSyncCancelled) {
          emit(
            MetadataSyncState.syncingMetadata(
              progress: progress,
              mainMessage: mainMsg,
              subMessage: subMsg,
              algorithmsProcessed: processed,
              totalAlgorithms: total,
            ),
          );
        }
      },
      onError: (error) {
        if (!_isMetadataSyncCancelled) {
          errorOccurred = true;
          finalMessage = "Metadata Sync Failed: $error";
        }
      },
      onCheckpoint: (algorithmName, algorithmIndex) async {
        await _saveCheckpoint(algorithmName, algorithmIndex);
      },
      isCancelled: () => _isMetadataSyncCancelled,
    );

    // Clear checkpoint on successful completion
    if (!errorOccurred && !_isMetadataSyncCancelled) {
      await _clearCheckpoint();
    }

    // Always resume CPU monitoring when sync completes, regardless of outcome
    _distingCubit?.resumeCpuMonitoring();

    if (!isClosed) {
      if (_isMetadataSyncCancelled) {
        emit(
          const MetadataSyncState.metadataSyncFailure(
            "Metadata sync cancelled by user.",
          ),
        );
      } else if (errorOccurred) {
        emit(MetadataSyncState.metadataSyncFailure(finalMessage));
      } else {
        emit(MetadataSyncState.metadataSyncSuccess(finalMessage));
        await loadLocalData();
      }
    }
  }

  void cancelInjection() {
    _isInjectionCancelled = true;
  }

  void cancelMetadataSync() {
    final wasCancelled = switch (state) {
      SyncingMetadata() => true,
      SavingPreset() => true,
      DeletingPreset() => true,
      _ => false,
    };

    if (wasCancelled) {
      _isMetadataSyncCancelled = true;

      // Resume CPU monitoring when cancelling
      _distingCubit?.resumeCpuMonitoring();

      // Emit cancelled state immediately for better UX
      emit(
        const MetadataSyncState.metadataSyncFailure("Sync cancelled by user."),
      );

      // Load local data to return to normal state
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!isClosed) {
          loadLocalData();
        }
      });
    }
  }

  // --- Preset Management Methods ---

  Future<void> saveCurrentPreset(IDistingMidiManager manager) async {
    if (switch (state) {
      SavingPreset() => true,
      LoadingPreset() => true,
      _ => false,
    }) {
      return;
    }

    emit(const MetadataSyncState.savingPreset());
    try {
      // 1. Fetch full preset details directly from the manager (online or offline)
      final FullPresetDetails? managerDetails = await manager
          .requestCurrentPresetDetails();

      if (managerDetails == null) {
        throw Exception(
          "Failed to retrieve current preset details from the manager.",
        );
      }

      final detailsToSave = _mergeAttachedSpecificationValues(
        managerDetails,
        manager,
      );

      final name = detailsToSave.preset.name; // Get name for success message

      // 2. Save to Database using the details obtained from the manager
      await _presetsDao.saveFullPreset(detailsToSave);

      emit(
        MetadataSyncState.presetSaveSuccess("Preset '$name' saved locally."),
      );
      // Reload data after successful save
      loadLocalData();
    } catch (e) {
      emit(
        MetadataSyncState.presetSaveFailure(
          "Failed to save preset: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> loadPresetToDevice(
    FullPresetDetails preset,
    IDistingMidiManager manager,
  ) async {
    emit(const MetadataSyncState.loadingPreset());
    if (kDebugMode) {}
    try {
      _validateTemplateMappingsForAttachedFirmware(preset.slots);
      final preparedSlots = await _preparePresetSlots(preset.slots);

      // 0. Clear the current preset on the device
      if (kDebugMode) {}
      await manager.requestNewPreset();
      await Future.delayed(
        const Duration(milliseconds: 200),
      ); // Allow time to process

      // 1. Add all algorithms first
      if (kDebugMode) {}
      for (int i = 0; i < preparedSlots.length; i++) {
        final preparedSlot = preparedSlots[i];
        if (kDebugMode) {}

        if (kDebugMode) {}
        await manager.requestAddAlgorithm(
          preparedSlot.algorithmInfoAt(i),
          preparedSlot.specificationValues,
        );
        // Add delay after adding each algorithm
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // 2. Set parameters and mappings for each slot
      if (kDebugMode) {}
      for (int i = 0; i < preset.slots.length; i++) {
        final slot = preset.slots[i];
        final algoDetails = preparedSlots[i].details;
        if (kDebugMode) {}

        // Send the saved slot display name to the device, falling back to the
        // canonical algorithm name for older presets without custom names.
        await manager.requestSendSlotName(
          i,
          slot.slot.customName ?? slot.algorithm.name,
        );

        // 2a. Send Parameter Values
        if (kDebugMode) {}
        for (final paramEntry in slot.parameterValues.entries) {
          final parameterNumber = paramEntry.key;
          final value = paramEntry.value;

          // Find parameter name for logging (optional, but helpful)
          final paramMetadata = algoDetails.parameters.firstWhereOrNull(
            (p) => p.parameter.parameterNumber == parameterNumber,
          );
          paramMetadata?.parameter.name ?? 'Unnamed';

          // NOTE: ParameterAccess check removed as access level isn't stored
          // in ParameterEntry from the database.

          if (kDebugMode) {}
          // Use setParameterValue
          await manager.setParameterValue(
            i, // slotIndex (use loop index)
            parameterNumber,
            value,
          );
          // Optional small delay between parameter sends
          await Future.delayed(const Duration(milliseconds: 20));
        }

        // 2b. Send Mappings
        if (kDebugMode) {}
        for (final mappingEntry in slot.mappings.entries) {
          final parameterNumber = mappingEntry.key;
          final mappingData = mappingEntry.value;

          if (kDebugMode) {}
          // Use requestSetMapping
          await manager.requestSetMapping(
            i, // slotIndex (use loop index)
            parameterNumber,
            _mappingForAttachedFirmware(mappingData),
          );
          // Optional small delay
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      // 2d. Set the preset name on the device
      final presetName = preset.preset.name.trim();
      if (kDebugMode) {}
      await manager.requestSetPresetName(presetName);
      await Future.delayed(
        const Duration(milliseconds: 50),
      ); // Short delay after name set

      // 2e. Save the preset to finish the process
      await manager.requestSavePreset();

      // 3. Add a final delay after all commands are sent
      await Future.delayed(const Duration(milliseconds: 100));

      final refreshError = await _refreshAttachedDistingCubit(
        manager,
        expectedPresetName: presetName,
      );
      if (refreshError != null) {
        emit(
          MetadataSyncState.presetLoadFailure(
            "Preset '${preset.preset.name}' was sent to device, but the app "
            "could not refresh device state: $refreshError",
          ),
        );
        return;
      }
      _distingCubit?.restoreSlotSpecificationValues(
        _slotsWithPreparedSpecificationValues(preset.slots, preparedSlots),
        startingSlotIndex: 0,
        expectedDisting: manager,
        expectedPresetName: presetName,
      );

      emit(
        MetadataSyncState.presetLoadSuccess(
          "Preset '${preset.preset.name}' sent to device.",
        ),
      );
      // Reload local data after success to ensure UI is in ViewingLocalData state
      await loadLocalData();
    } catch (e) {
      emit(
        MetadataSyncState.presetLoadFailure(
          "Error sending preset: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> loadLocalData() async {
    final isBusy = switch (state) {
      SyncingMetadata() => true,
      SavingPreset() => true,
      LoadingPreset() => true,
      _ => false,
    };
    // Allow proceeding if the state IS deletingPreset, because we want to load data *after* deletion.
    if (isBusy &&
        !switch (state) {
          DeletingPreset() => true,
          _ => false,
        }) {
      return;
    }

    // Use a generic loading state or specific one?
    // Let's reuse loadingPreset for simplicity for now.
    emit(const MetadataSyncState.loadingPreset()); // Indicate general loading

    try {
      // Fetch both metadata and presets
      final results = await Future.wait([
        _metadataDao.getAllAlgorithms(),
        _metadataDao.getAlgorithmParameterCounts(),
        _presetsDao.getAllPresets(),
      ]);

      final algorithms = results[0] as List<AlgorithmEntry>;
      final parameterCounts = results[1] as Map<String, int>;
      final presets = results[2] as List<PresetEntry>;

      // Check for checkpoint after loading data
      final hasCheckpoint = await _hasCheckpoint();

      if (hasCheckpoint) {
        await _checkForCheckpoint();
        // Don't emit ViewingLocalData yet - let CheckpointFound state show first
      } else {
        emit(
          MetadataSyncState.viewingLocalData(
            algorithms: algorithms,
            parameterCounts: parameterCounts,
            presets: presets,
          ),
        );
      }
    } catch (e) {
      emit(
        MetadataSyncState.failure("Failed to load local data: ${e.toString()}"),
      );
    }
  }

  // Check if there's a checkpoint
  Future<bool> _hasCheckpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final algorithmName = prefs.getString(_checkpointAlgorithmName);
    final algorithmIndex = prefs.getInt(_checkpointAlgorithmIndex);
    return algorithmName != null && algorithmIndex != null;
  }

  // Check if there's a checkpoint and emit CheckpointFound state if so
  Future<void> _checkForCheckpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final algorithmName = prefs.getString(_checkpointAlgorithmName);
    final algorithmIndex = prefs.getInt(_checkpointAlgorithmIndex);

    if (algorithmName != null && algorithmIndex != null) {
      emit(
        MetadataSyncState.checkpointFound(
          algorithmName: algorithmName,
          algorithmIndex: algorithmIndex,
        ),
      );
    }
  }

  // Save checkpoint
  Future<void> _saveCheckpoint(String algorithmName, int algorithmIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checkpointAlgorithmName, algorithmName);
    await prefs.setInt(_checkpointAlgorithmIndex, algorithmIndex);
  }

  // Clear checkpoint
  Future<void> _clearCheckpoint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_checkpointAlgorithmName);
    await prefs.remove(_checkpointAlgorithmIndex);
  }

  // Resume from checkpoint
  void resumeFromCheckpoint() {
    if (state is CheckpointFound) {
      emit(const MetadataSyncState.idle());
    }
  }

  // Decline checkpoint and clear it, then load normal data
  Future<void> declineCheckpoint() async {
    await _clearCheckpoint();
    // Load local data normally after declining checkpoint
    await _loadLocalDataOnly();
  }

  // Load data without checkpoint check
  Future<void> _loadLocalDataOnly() async {
    emit(const MetadataSyncState.loadingPreset());

    try {
      final results = await Future.wait([
        _metadataDao.getAllAlgorithms(),
        _metadataDao.getAlgorithmParameterCounts(),
        _presetsDao.getAllPresets(),
      ]);

      final algorithms = results[0] as List<AlgorithmEntry>;
      final parameterCounts = results[1] as Map<String, int>;
      final presets = results[2] as List<PresetEntry>;

      emit(
        MetadataSyncState.viewingLocalData(
          algorithms: algorithms,
          parameterCounts: parameterCounts,
          presets: presets,
        ),
      );
    } catch (e) {
      emit(
        MetadataSyncState.failure("Failed to load local data: ${e.toString()}"),
      );
    }
  }

  void reset() {
    _isMetadataSyncCancelled = false; // Ensure cancelled is reset
    emit(const MetadataSyncState.idle());
  }

  Future<void> deletePreset(int presetId) async {
    emit(const MetadataSyncState.deletingPreset());
    try {
      await _presetsDao.deletePreset(presetId);
      await loadLocalData(); // Reload data after deletion
    } catch (e) {
      emit(MetadataSyncState.presetDeleteFailure("Error deleting preset: $e"));
    }
  }

  Future<void> togglePresetTemplate(int presetId, bool isTemplate) async {
    try {
      await _presetsDao.toggleTemplateStatus(presetId, isTemplate);

      // Optimistically update the state without full reload
      if (state is ViewingLocalData) {
        final currentState = state as ViewingLocalData;
        final updatedPresets = currentState.presets.map((preset) {
          if (preset.id == presetId) {
            // Create a new PresetEntry with updated isTemplate flag
            return PresetEntry(
              id: preset.id,
              name: preset.name,
              lastModified: DateTime.now(), // Updated timestamp
              isTemplate: isTemplate,
            );
          }
          return preset;
        }).toList();

        emit(
          MetadataSyncState.viewingLocalData(
            algorithms: currentState.algorithms,
            parameterCounts: currentState.parameterCounts,
            presets: updatedPresets,
          ),
        );
      }
    } catch (e) {
      emit(
        MetadataSyncState.failure(
          "Error toggling template status: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> syncNewAlgorithmsOnly(IDistingMidiManager manager) async {
    if (switch (state) {
      SyncingMetadata() => true,
      _ => false,
    }) {
      return;
    }

    _isMetadataSyncCancelled = false; // Reset cancellation flag

    // Pause CPU monitoring during sync to prevent interference
    _distingCubit?.pauseCpuMonitoring();

    emit(
      const MetadataSyncState.syncingMetadata(
        progress: 0.0,
        mainMessage: "Checking for new algorithms...",
        subMessage: "Comparing device and local lists...",
      ),
    );

    bool errorOccurred = false;
    String finalMessage = "Incremental sync completed successfully.";

    final syncService = MetadataSyncService(manager, _database);

    await syncService.syncNewAlgorithmsOnly(
      onProgress: (progress, processed, total, mainMsg, subMsg) {
        if (!isClosed && !_isMetadataSyncCancelled) {
          emit(
            MetadataSyncState.syncingMetadata(
              progress: progress,
              mainMessage: mainMsg,
              subMessage: subMsg,
              algorithmsProcessed: processed,
              totalAlgorithms: total,
            ),
          );
        }
      },
      onError: (error) {
        if (!_isMetadataSyncCancelled) {
          errorOccurred = true;
          finalMessage = "Incremental Sync Failed: $error";
        }
      },
      isCancelled: () => _isMetadataSyncCancelled,
    );

    // Always resume CPU monitoring when sync completes, regardless of outcome
    _distingCubit?.resumeCpuMonitoring();

    if (!isClosed) {
      if (_isMetadataSyncCancelled) {
        emit(
          const MetadataSyncState.metadataSyncFailure(
            "Incremental sync cancelled by user.",
          ),
        );
      } else if (errorOccurred) {
        emit(MetadataSyncState.metadataSyncFailure(finalMessage));
      } else {
        emit(MetadataSyncState.metadataSyncSuccess(finalMessage));
        await loadLocalData();
      }
    }
  }

  Future<void> rescanSingleAlgorithm(
    IDistingMidiManager manager,
    String algorithmGuid,
  ) async {
    emit(
      const MetadataSyncState.syncingMetadata(
        progress: 0.0,
        mainMessage: "Rescanning algorithm...",
        subMessage: "Preparing...",
      ),
    );

    try {
      // Find the algorithm info from the database
      final algorithm = await _metadataDao.getAlgorithmByGuid(algorithmGuid);
      if (algorithm == null) {
        throw Exception("Algorithm not found in database");
      }

      // Get all algorithm info to find the one we need
      final numAlgoTypes = await manager.requestNumberOfAlgorithms();
      if (numAlgoTypes == null) {
        throw Exception("Failed to get algorithm count from device");
      }

      AlgorithmInfo? targetAlgoInfo;
      for (int i = 0; i < numAlgoTypes; i++) {
        final algoInfo = await manager.requestAlgorithmInfo(i);
        if (algoInfo?.guid == algorithmGuid) {
          targetAlgoInfo = algoInfo;
          break;
        }
      }

      if (targetAlgoInfo == null) {
        throw Exception("Algorithm not found on device");
      }

      emit(
        MetadataSyncState.syncingMetadata(
          progress: 0.5,
          mainMessage: targetAlgoInfo.name,
          subMessage: "Starting rescan...",
        ),
      );

      // Use the metadata sync service to rescan
      final syncService = MetadataSyncService(manager, _database);
      await syncService.rescanSingleAlgorithm(
        targetAlgoInfo,
        onStatus: (status) {
          if (!isClosed) {
            emit(
              MetadataSyncState.syncingMetadata(
                progress: 0.5,
                mainMessage: targetAlgoInfo!.name,
                subMessage: status,
              ),
            );
          }
        },
      );

      emit(
        const MetadataSyncState.metadataSyncSuccess(
          "Algorithm rescanned successfully",
        ),
      );

      // Reload data to show updated parameter count
      await loadLocalData();
    } catch (e) {
      emit(
        MetadataSyncState.metadataSyncFailure("Failed to rescan algorithm: $e"),
      );

      // Return to data view after error
      Future.delayed(const Duration(seconds: 2), () {
        if (!isClosed) {
          loadLocalData();
        }
      });
    }
  }

  /// Injects a template preset into the current device preset by appending
  /// its algorithms to the end without clearing the existing preset.
  ///
  /// Delegates to [applyTemplateToDevice] with all slot indices selected.
  Future<void> injectTemplateToDevice(
    FullPresetDetails template,
    IDistingMidiManager manager,
  ) {
    return applyTemplateToDevice(
      template: template,
      templateSlotIndices: List<int>.generate(template.slots.length, (i) => i),
      manager: manager,
    );
  }

  /// Applies a selected subset of [template] slots to the connected device.
  ///
  /// The slots in [templateSlotIndices] (positions within
  /// `template.slots`, 0-based) are appended after the device's current
  /// slots in the order given. Duplicates are honoured. The method emits
  /// [InjectingTemplate] progress states between each algorithm-add.
  ///
  /// The supplied [template] is captured by value — concurrent edits to the
  /// source preset are invisible to the in-flight apply.
  Future<void> applyTemplateToDevice({
    required FullPresetDetails template,
    required List<int> templateSlotIndices,
    required IDistingMidiManager manager,
  }) async {
    if (_isInjectionRunning) {
      throw StateError(
        'A template apply is already in progress; cannot start another.',
      );
    }
    _isInjectionRunning = true;
    _isInjectionCancelled = false;

    final total = templateSlotIndices.length;
    emit(MetadataSyncState.injectingTemplate(applied: 0, total: total));
    final attachedStateAtStart = _distingCubit?.state;
    final expectedAttachedPresetName =
        attachedStateAtStart is DistingStateSynchronized &&
            identical(attachedStateAtStart.disting, manager)
        ? attachedStateAtStart.presetName
        : null;

    try {
      if (template.slots.isEmpty) {
        throw Exception('Cannot inject empty template');
      }
      if (templateSlotIndices.isEmpty) {
        throw Exception('Cannot inject empty template');
      }
      for (final i in templateSlotIndices) {
        if (i < 0 || i >= template.slots.length) {
          throw Exception(
            'Template slot index $i out of range [0, ${template.slots.length}).',
          );
        }
      }

      if (_isInjectionCancelled) {
        throw Exception(
          'Injection cancelled. Preset may be partially modified.',
        );
      }

      // Pre-flight metadata and specification validation on every slot we will
      // apply. This must complete before the first device mutation.
      final preparedSlots = <_PreparedPresetSlot>[];
      for (final i in templateSlotIndices) {
        preparedSlots.add(await _preparePresetSlot(template.slots[i]));
      }
      _validateTemplateMappingsForAttachedFirmware(
        templateSlotIndices.map((i) => template.slots[i]),
      );

      // Slot limit check.
      int currentSlotCount = 0;
      try {
        currentSlotCount = await manager.requestNumAlgorithmsInPreset() ?? 0;
      } catch (_) {
        currentSlotCount = 0;
      }
      final totalSlots = currentSlotCount + total;
      if (totalSlots > DistingLimits.maxPresetSlots) {
        throw Exception(
          'Cannot inject: Would exceed ${DistingLimits.maxPresetSlots} slot limit '
          '(current: $currentSlotCount, template: $total)',
        );
      }

      final startingSlotIndex = currentSlotCount;
      int appliedCount = 0;

      for (var i = 0; i < templateSlotIndices.length; i++) {
        if (_isInjectionCancelled) {
          throw Exception(
            'Injection cancelled after adding $appliedCount of $total algorithms. '
            'Preset may be partially modified.',
          );
        }

        final sourceIndex = templateSlotIndices[i];
        final slot = template.slots[sourceIndex];
        final preparedSlot = preparedSlots[i];

        try {
          final targetSlotIndex = startingSlotIndex + i;
          await manager.requestAddAlgorithm(
            preparedSlot.algorithmInfoAt(targetSlotIndex),
            preparedSlot.specificationValues,
          );
          await Future.delayed(const Duration(milliseconds: 150));

          appliedCount++;
          emit(
            MetadataSyncState.injectingTemplate(
              applied: appliedCount,
              total: total,
            ),
          );
        } catch (algorithmError) {
          throw Exception(
            'Failed to inject algorithm "${slot.algorithm.name}" '
            '(${i + 1} of $total). '
            'Preset may be partially modified after $appliedCount slot(s). '
            'Error: ${algorithmError.toString()}',
          );
        }
      }

      // Set parameters and mappings for each injected slot, mirroring source
      // slot data 1:1.
      for (var i = 0; i < templateSlotIndices.length; i++) {
        final sourceIndex = templateSlotIndices[i];
        final slot = template.slots[sourceIndex];
        final targetSlotIndex = startingSlotIndex + i;
        final details = preparedSlots[i].details;

        await manager.requestSendSlotName(
          targetSlotIndex,
          slot.slot.customName ?? slot.algorithm.name,
        );

        for (final paramEntry in slot.parameterValues.entries) {
          final parameterNumber = paramEntry.key;
          final value = paramEntry.value;

          final paramMetadata = details.parameters.firstWhereOrNull(
            (p) => p.parameter.parameterNumber == parameterNumber,
          );
          paramMetadata?.parameter.name ?? 'Unnamed';

          await manager.setParameterValue(
            targetSlotIndex,
            parameterNumber,
            value,
          );
          await Future.delayed(const Duration(milliseconds: 20));
        }

        for (final mappingEntry in slot.mappings.entries) {
          final parameterNumber = mappingEntry.key;
          final mappingData = mappingEntry.value;
          await manager.requestSetMapping(
            targetSlotIndex,
            parameterNumber,
            _mappingForAttachedFirmware(mappingData),
          );
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));

      final refreshError = await _refreshAttachedDistingCubit(
        manager,
        expectedPresetName: expectedAttachedPresetName,
      );
      if (refreshError != null) {
        emit(
          MetadataSyncState.presetLoadFailure(
            "Template '${template.preset.name}' was injected to device, but "
            "the app could not refresh device state: $refreshError",
          ),
        );
        return;
      }
      if (expectedAttachedPresetName != null) {
        final selectedSlots = [
          for (final index in templateSlotIndices) template.slots[index],
        ];
        _distingCubit?.restoreSlotSpecificationValues(
          _slotsWithPreparedSpecificationValues(selectedSlots, preparedSlots),
          startingSlotIndex: startingSlotIndex,
          expectedDisting: manager,
          expectedPresetName: expectedAttachedPresetName,
        );
      }

      emit(
        MetadataSyncState.presetLoadSuccess(
          "Template '${template.preset.name}' injected to device. "
          "Save manually when ready.",
        ),
      );
      await loadLocalData();
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('connection') ||
          e.toString().contains('Connection') ||
          e.toString().contains('disconnect') ||
          e.toString().contains('MIDI') ||
          e.toString().contains('timeout')) {
        errorMessage =
            'Connection lost during injection. Preset may be partially modified. '
            'Reconnect your device and check the preset.';
      } else if (e.toString().contains('metadata') ||
          e.toString().contains('not found locally')) {
        errorMessage =
            'Template missing algorithm metadata. '
            'Go to Settings > Sync Algorithms to download latest metadata.';
      } else {
        errorMessage = "Error injecting template: ${e.toString()}";
      }
      emit(MetadataSyncState.presetLoadFailure(errorMessage));
    } finally {
      _isInjectionRunning = false;
    }
  }

  Future<Object?> _refreshAttachedDistingCubit(
    IDistingMidiManager expectedDisting, {
    String? expectedPresetName,
  }) async {
    final distingCubit = _distingCubit;
    if (distingCubit == null) return null;
    final beforeRefresh = distingCubit.state;
    if (beforeRefresh is! DistingStateSynchronized ||
        !identical(beforeRefresh.disting, expectedDisting)) {
      return StateError(
        'Attached device state changed before it could be refreshed.',
      );
    }
    try {
      await distingCubit.refresh();
      final afterRefresh = distingCubit.state;
      if (afterRefresh is! DistingStateSynchronized ||
          !identical(afterRefresh.disting, expectedDisting) ||
          (expectedPresetName != null &&
              afterRefresh.presetName != expectedPresetName)) {
        return StateError(
          'Attached device or preset changed while it was being refreshed.',
        );
      }
      return null;
    } catch (error) {
      return error;
    }
  }

  FullPresetDetails _mergeAttachedSpecificationValues(
    FullPresetDetails details,
    IDistingMidiManager manager,
  ) {
    final attachedState = _distingCubit?.state;
    if (attachedState is! DistingStateSynchronized ||
        !identical(attachedState.disting, manager) ||
        attachedState.presetName != details.preset.name) {
      return details;
    }

    var changed = false;
    final mergedSlots = details.slots
        .map((slot) {
          final slotIndex = slot.slot.slotIndex;
          if (slotIndex < 0 || slotIndex >= attachedState.slots.length) {
            return slot;
          }
          final attachedSlot = attachedState.slots[slotIndex];
          final values = attachedSlot.algorithm.specifications;
          if (attachedSlot.algorithm.guid != slot.algorithm.guid ||
              values.isEmpty ||
              const ListEquality<int>().equals(
                values,
                slot.specificationValues,
              )) {
            return slot;
          }

          changed = true;
          return FullPresetSlot(
            slot: slot.slot,
            algorithm: slot.algorithm,
            specificationValues: List<int>.unmodifiable(values),
            parameterValues: slot.parameterValues,
            parameterStringValues: slot.parameterStringValues,
            mappings: slot.mappings,
            routing: slot.routing,
          );
        })
        .toList(growable: false);

    return changed
        ? FullPresetDetails(preset: details.preset, slots: mergedSlots)
        : details;
  }

  Future<List<_PreparedPresetSlot>> _preparePresetSlots(
    Iterable<FullPresetSlot> slots,
  ) async {
    final prepared = <_PreparedPresetSlot>[];
    for (final slot in slots) {
      prepared.add(await _preparePresetSlot(slot));
    }
    return prepared;
  }

  Future<_PreparedPresetSlot> _preparePresetSlot(FullPresetSlot slot) async {
    final details = await _metadataDao.getFullAlgorithmDetails(
      slot.algorithm.guid,
    );
    if (details == null) {
      throw Exception(
        "Algorithm metadata for GUID '${slot.algorithm.guid}' not found locally.",
      );
    }

    final values = slot.specificationValues.isEmpty
        ? details.specifications.map((spec) => spec.defaultValue).toList()
        : List<int>.from(slot.specificationValues);
    if (values.length != details.specifications.length) {
      throw Exception(
        'Algorithm "${details.algorithm.name}" requires '
        '${details.specifications.length} specification value(s), but the '
        'saved slot contains ${values.length}.',
      );
    }
    for (final (index, specification) in details.specifications.indexed) {
      final value = values[index];
      if (value < specification.minValue || value > specification.maxValue) {
        throw Exception(
          'Specification "${specification.name}" for '
          '"${details.algorithm.name}" must be between '
          '${specification.minValue} and ${specification.maxValue}; got $value.',
        );
      }
    }

    return _PreparedPresetSlot(
      details: details,
      specificationValues: List<int>.unmodifiable(values),
    );
  }

  List<FullPresetSlot> _slotsWithPreparedSpecificationValues(
    List<FullPresetSlot> slots,
    List<_PreparedPresetSlot> preparedSlots,
  ) => [
    for (final (index, slot) in slots.indexed)
      FullPresetSlot(
        slot: slot.slot,
        algorithm: slot.algorithm,
        specificationValues: preparedSlots[index].specificationValues,
        parameterValues: slot.parameterValues,
        parameterStringValues: slot.parameterStringValues,
        mappings: slot.mappings,
        routing: slot.routing,
      ),
  ];

  void _validateTemplateMappingsForAttachedFirmware(
    Iterable<FullPresetSlot> slots,
  ) {
    for (final slot in slots) {
      for (final mapping in slot.mappings.values) {
        _mappingForAttachedFirmware(mapping);
      }
    }
  }

  PackedMappingData _mappingForAttachedFirmware(PackedMappingData mapping) {
    final state = _distingCubit?.state;
    if (state is! DistingStateSynchronized) {
      return mapping;
    }

    final supportsExpressiveMidiMapping =
        state.firmwareVersion.hasExpressiveMidiMapping;
    final isExpressive = _isExpressiveMidiType(mapping.midiMappingType);
    if (isExpressive && !supportsExpressiveMidiMapping) {
      throw Exception(
        'Pitch bend and channel pressure mappings require firmware 1.17.0 or newer.',
      );
    }

    final supportsV8 = state.firmwareVersion.hasBypassAwareMappings;
    mapping.validateForFirmware(state.firmwareVersion);
    final baseVersion = mapping.version < 1
        ? supportsExpressiveMidiMapping
              ? 7
              : 6
        : mapping.version;
    final version = isExpressive && supportsExpressiveMidiMapping
        ? (baseVersion == 8 && supportsV8 ? 8 : 7)
        : baseVersion
              .clamp(
                1,
                supportsV8
                    ? 8
                    : supportsExpressiveMidiMapping
                    ? 7
                    : 6,
              )
              .toInt();

    if (!isExpressive) {
      return mapping.copyWith(version: version);
    }

    return mapping.copyWith(version: version, midiCC: 0, isMidiRelative: false);
  }

  bool _isExpressiveMidiType(MidiMappingType type) {
    return type == MidiMappingType.pitchBend ||
        type == MidiMappingType.channelPressure;
  }

  /// Copies a subset of slots from a saved template into another saved
  /// preset (the *target*), without touching the connected device. Thin
  /// orchestration over [PresetsDao.applyTemplateSlots].
  ///
  /// On success the cubit emits [ViewingLocalData] so list-driven UIs
  /// refresh. [TemplateSpaceException] from the DAO is caught and
  /// re-emitted as [MetadataSyncFailure] with a human-readable message.
  Future<ApplyTemplateSlotsResult> applyTemplateToPreset({
    required int templateId,
    required int targetPresetId,
    required List<int> templateSlotIndices,
    required int insertionOffset,
    bool overwrite = false,
  }) async {
    try {
      final result = await _presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetPresetId,
        templateSlotIndices: templateSlotIndices,
        insertionOffset: insertionOffset,
        overwrite: overwrite,
      );
      await loadLocalData();
      return result;
    } on TemplateSpaceException catch (e) {
      emit(
        MetadataSyncState.metadataSyncFailure(
          'Cannot apply template: ${e.current} existing + ${e.applied} new '
          'would exceed the ${e.limit}-slot limit.',
        ),
      );
      rethrow;
    } catch (e) {
      emit(
        MetadataSyncState.metadataSyncFailure('Failed to apply template: $e'),
      );
      rethrow;
    }
  }
}
