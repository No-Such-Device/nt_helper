import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/core/routing/bus_spec.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart'; // Added
import 'package:nt_helper/db/daos/presets_dao.dart'; // Added
import 'package:nt_helper/db/database.dart'; // Added
import 'package:nt_helper/domain/cc_reverse_lookup.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/midi_command_factory.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/mock_disting_midi_manager.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/domain/parameter_update_queue.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/package_file.dart';
import 'package:nt_helper/models/plugin_info.dart';
import 'package:nt_helper/models/routing_information.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/startup_log_service.dart';
import 'package:nt_helper/util/extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart'; // Add collection package import
import 'package:nt_helper/domain/video/video_stream_state.dart';
import 'package:nt_helper/domain/video/usb_video_manager.dart';

part 'disting_cubit.freezed.dart';

part 'disting_state.dart';
part 'disting_cubit_algorithm_ops.dart';
part 'disting_cubit_preset_ops.dart';
part 'disting_cubit_slot_ops.dart';
part 'disting_cubit_offline_demo_delegate.dart';
part 'disting_cubit_parameter_fetch_delegate.dart';
part 'disting_cubit_plugin_delegate.dart';
part 'disting_cubit_connection_delegate.dart';
part 'disting_cubit_parameter_refresh_delegate.dart';
part 'disting_cubit_monitoring_delegate.dart';
part 'disting_cubit_slot_state_delegate.dart';
part 'disting_cubit_algorithm_library_delegate.dart';
part 'disting_cubit_sd_card_delegate.dart';
part 'disting_cubit_lua_reload_delegate.dart';
part 'disting_cubit_parameter_string_delegate.dart';
part 'disting_cubit_mapping_delegate.dart';
part 'disting_cubit_state_refresh_delegate.dart';
part 'disting_cubit_slot_maintenance_delegate.dart';
part 'disting_cubit_parameter_value_delegate.dart';
part 'disting_cubit_hardware_commands_delegate.dart';
part 'disting_cubit_state_helpers_delegate.dart';
part 'disting_cubit_refresh_delegate.dart';
part 'disting_cubit_perf_page_delegate.dart';
part 'disting_cubit_cc_notification_delegate.dart';
part 'disting_cubit_checkpoint_delegate.dart';
part 'disting_cubit_internal_types.dart';

abstract class _DistingCubitBase extends Cubit<DistingState> {
  _DistingCubitBase(super.initialState);

  IDistingMidiManager requireDisting();
  Future<Slot> fetchSlot(IDistingMidiManager disting, int algorithmIndex);
  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int completed, int total)? onSlotProgress,
  });
  Future<void> _refreshStateFromManager({Duration delay});
  void _rebuildCcLookup();
  Slot _fixAlgorithmIndex(Slot slot, int algorithmIndex);
  List<Slot> updateSlot(
    int algorithmIndex,
    List<Slot> slots,
    Slot Function(Slot) updateFunction,
  );
  Slot _preserveKnownSlotSpecifications({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required int slotIndex,
    required Slot refreshedSlot,
  });
  List<Slot> _preserveKnownSlotSpecificationsForRefresh({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required List<Slot> refreshedSlots,
  });
}

class DistingCubit extends _DistingCubitBase
    with
        _DistingCubitPresetOps,
        _DistingCubitSlotOps,
        _DistingCubitAlgorithmOps {
  final AppDatabase database; // Renamed from _database to make it public
  late final MetadataDao _metadataDao; // Added
  final Future<SharedPreferences> _prefs;
  FirmwareVersion? _lastKnownFirmwareVersion;
  late final _OfflineDemoDelegate _offlineDemoDelegate = _OfflineDemoDelegate(
    this,
  );
  late final _ParameterFetchDelegate _parameterFetchDelegate =
      _ParameterFetchDelegate(this);
  late final _PluginDelegate _pluginDelegate = _PluginDelegate(this);
  late final _ConnectionDelegate _connectionDelegate = _ConnectionDelegate(
    this,
  );
  late final _ParameterRefreshDelegate _parameterRefreshDelegate =
      _ParameterRefreshDelegate(this);
  late final _MonitoringDelegate _monitoringDelegate = _MonitoringDelegate(
    this,
  );
  late final _SlotStateDelegate _slotStateDelegate = _SlotStateDelegate(this);
  late final _AlgorithmLibraryDelegate _algorithmLibraryDelegate =
      _AlgorithmLibraryDelegate(this);
  late final _SdCardDelegate _sdCardDelegate = _SdCardDelegate(this);
  late final _LuaReloadDelegate _luaReloadDelegate = _LuaReloadDelegate(this);
  late final _ParameterStringDelegate _parameterStringDelegate =
      _ParameterStringDelegate(this);
  late final _MappingDelegate _mappingDelegate = _MappingDelegate(this);
  late final _StateRefreshDelegate _stateRefreshDelegate =
      _StateRefreshDelegate(this);
  late final _SlotMaintenanceDelegate _slotMaintenanceDelegate =
      _SlotMaintenanceDelegate(this);
  late final _ParameterValueDelegate _parameterValueDelegate =
      _ParameterValueDelegate(this);
  late final _HardwareCommandsDelegate _hardwareCommandsDelegate =
      _HardwareCommandsDelegate(this);
  late final _StateHelpersDelegate _stateHelpersDelegate =
      _StateHelpersDelegate(this);
  late final _RefreshDelegate _refreshDelegate = _RefreshDelegate(this);
  late final _PerfPageDelegate _perfPageDelegate = _PerfPageDelegate(this);
  late final _CcNotificationDelegate _ccNotificationDelegate =
      _CcNotificationDelegate(this);
  late final _CheckpointDelegate _checkpointDelegate = _CheckpointDelegate(
    this,
  );

  /// Service for checking firmware updates
  final FirmwareVersionService _firmwareVersionService =
      FirmwareVersionService();

  DistingCubit(
    this.database, {
    MidiCommand? midiCommand,
    MidiCommand Function()? midiCommandFactory,
    bool? isWindowsOverride,
  }) : _prefs = SharedPreferences.getInstance(),
       _midiCommandFactory = midiCommandFactory ?? createNativeMidiCommand,
       _isWindows = isWindowsOverride ?? Platform.isWindows,
       super(const DistingState.initial()) {
    _metadataDao =
        database.metadataDao; // Initialize DAO using public database field
    _midiCommand = midiCommand ?? _midiCommandFactory();
  }

  final MidiCommand Function() _midiCommandFactory;
  final bool _isWindows;
  late MidiCommand _midiCommand;

  // MIDI setup change subscription for auto-detecting device connections
  StreamSubscription<MidiSetupChange>? _midiSetupSubscription;

  // Keep track of the offline manager instance when offline
  OfflineDistingMidiManager? _offlineManager;

  // Parameter update queue for consolidated parameter changes
  ParameterUpdateQueue? _parameterQueue;

  /// Wait for all queued parameter updates to be sent to hardware.
  Future<void> flushParameterQueue() async {
    await _parameterQueue?.flush();
  }

  /// Stream of CPU usage updates that polls every 10 seconds when listeners are active
  Stream<CpuUsage?> get cpuUsageStream => _monitoringDelegate.cpuUsageStream;

  /// Stream of video state updates from the cubit's state
  Stream<VideoStreamState?> get videoStreamState => stream.map(
    (state) => state.maybeWhen(
      synchronized:
          (
            disting,
            distingVersion,
            firmwareVersion,
            presetName,
            algorithms,
            slots,
            unitStrings,
            inputDevice,
            outputDevice,
            loading,
            offline,
            screenshot,
            demo,
            videoStream,
            availableFirmwareUpdate,
            perfPageItems,
            isDirty,
            renameConfirmationName,
          ) => videoStream,
      orElse: () => null,
    ),
  );

  // Added: Store last known online connection details
  MidiDevice? _lastOnlineInputDevice;
  MidiDevice? _lastOnlineOutputDevice;
  int? _lastOnlineSysExId;

  @override
  Future<void> close() async {
    _ccNotificationDelegate.stop();
    await _mappingDelegate.dispose();
    disting()?.dispose();
    _offlineManager?.dispose();
    _parameterQueue?.dispose();
    try {
      _midiCommand.teardown();
    } on MissingPluginException {
      // teardown() uses platform channels not available in tests
    }
    _midiCommand.dispose();

    _parameterRefreshDelegate.dispose();

    _midiSetupSubscription?.cancel();

    await _monitoringDelegate.dispose();

    _firmwareVersionService.dispose();

    return super.close();
  }

  Future<void> initialize() async {
    return _connectionDelegate.initialize();
  }

  Future<void> onDemo() async {
    _checkpointDelegate.clearCheckpoints();
    return _offlineDemoDelegate.onDemo();
  }

  // Helper to fetch AlgorithmInfo list from mock/offline manager
  Future<List<AlgorithmInfo>> _fetchMockAlgorithms(
    IDistingMidiManager manager,
  ) async {
    return _algorithmLibraryDelegate.fetchAlgorithmsWithPriority(manager);
  }

  Future<void> loadDevices() async {
    return _connectionDelegate.loadDevices();
  }

  void updateDeviceSelection({
    required MidiDevice? inputDevice,
    required MidiDevice? outputDevice,
    required int sysExId,
  }) {
    _connectionDelegate.updateDeviceSelection(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      sysExId: sysExId,
    );
  }

  void _stopMidiSetupListener() {
    _connectionDelegate.stopMidiSetupListener();
  }

  Future<Uint8List?> getHardwareScreenshot() async {
    return _hardwareCommandsDelegate.getHardwareScreenshot();
  }

  Future<void> updateScreenshot() async {
    return _hardwareCommandsDelegate.updateScreenshot();
  }

  /// Gets the current CPU usage information from the Disting device.
  /// Returns null if the device is not connected or if the request fails.
  /// Only works when connected to a physical device (not in offline or demo mode).
  Future<CpuUsage?> getCpuUsage() async {
    return _monitoringDelegate.getCpuUsage();
  }

  void disconnect() {
    _checkpointDelegate.clearCheckpoints();
    return _connectionDelegate.disconnect();
  }

  // Private helper to perform the full synchronization and emit the state
  Future<void> _performSyncAndEmit() async {
    await _connectionDelegate.performSyncAndEmit();
  }

  Future<void> connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    return _connectionDelegate.connectToDevices(
      inputDevice,
      outputDevice,
      sysExId,
    );
  }

  // --- Offline Mode Handling ---

  Future<void> goOffline() async {
    _checkpointDelegate.clearCheckpoints();
    return _offlineDemoDelegate.goOffline();
  }

  Future<void> goOnline() async {
    return _offlineDemoDelegate.goOnline();
  }

  Future<void> cancelSync() async {
    return _refreshDelegate.cancelSync();
  }

  Future<void> loadPresetOffline(FullPresetDetails presetDetails) async {
    _checkpointDelegate.clearCheckpoints();
    return _offlineDemoDelegate.loadPresetOffline(presetDetails);
  }

  void _emitState(DistingState next) {
    emit(next);
  }

  // Helper to fetch algorithm metadata for offline mode
  Future<List<AlgorithmInfo>> _fetchOfflineAlgorithms() async {
    return _stateHelpersDelegate.fetchOfflineAlgorithms();
  }

  /// Refreshes the state from the current manager (online or offline).
  /// By default, performs a fast refresh of preset data only.
  /// Set [fullRefresh] to true to also re-download the algorithm library (online only).
  Future<void> refresh({bool fullRefresh = false}) async {
    return _refreshDelegate.refresh(fullRefresh: fullRefresh);
  }

  /// Restores specification values that the app supplied while creating
  /// slots. The device's slot query does not return these values, so a refresh
  /// can only retain them from app-owned state or a saved preset/template.
  void restoreSlotSpecificationValues(
    Iterable<FullPresetSlot> sourceSlots, {
    required int startingSlotIndex,
    required IDistingMidiManager expectedDisting,
    required String expectedPresetName,
  }) {
    _stateHelpersDelegate.restoreSlotSpecificationValues(
      sourceSlots,
      startingSlotIndex: startingSlotIndex,
      expectedDisting: expectedDisting,
      expectedPresetName: expectedPresetName,
    );
  }

  @override
  Slot _preserveKnownSlotSpecifications({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required int slotIndex,
    required Slot refreshedSlot,
  }) => _stateHelpersDelegate.preserveKnownSlotSpecifications(
    previousState: previousState,
    refreshedDisting: refreshedDisting,
    refreshedPresetName: refreshedPresetName,
    slotIndex: slotIndex,
    refreshedSlot: refreshedSlot,
  );

  @override
  List<Slot> _preserveKnownSlotSpecificationsForRefresh({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required List<Slot> refreshedSlots,
  }) => _stateHelpersDelegate.preserveKnownSlotSpecificationsForRefresh(
    previousState: previousState,
    refreshedDisting: refreshedDisting,
    refreshedPresetName: refreshedPresetName,
    refreshedSlots: refreshedSlots,
  );

  // Helper to create parameter queue for current manager
  void _createParameterQueue() {
    final manager = disting();
    if (manager != null) {
      _parameterQueue?.dispose();
      _parameterQueue = ParameterUpdateQueue(
        midiManager: manager,
        onParameterStringUpdated:
            _parameterStringDelegate.onParameterStringUpdated,
      );
    }
  }

  void refreshAlgorithms() {
    _algorithmLibraryDelegate.refreshAlgorithms();
  }

  /// Sends rescan plugins command to hardware and refreshes algorithm list.
  /// Used by the Add Algorithm screen's manual rescan button.
  Future<void> rescanPlugins() async {
    return _algorithmLibraryDelegate.rescanPlugins();
  }

  @override
  IDistingMidiManager requireDisting() {
    final d = disting();
    if (d == null) {
      throw Exception("Disting not connected");
    }
    return d;
  }

  IDistingMidiManager? disting() {
    return switch (state) {
      DistingStateConnected(disting: final d) => d,
      DistingStateSynchronized(disting: final d) => d,
      _ => null,
    };
  }

  Map<String, dynamic> get ccNotificationDiagnostics =>
      _ccNotificationDelegate.diagnostics;

  List<T> replaceInList<T>(List<T> original, T element, {required int index}) {
    if (index < 0 || index >= original.length) {
      throw RangeError.index(index, original, "index out of bounds");
    }

    return [
      ...original.sublist(0, index),
      element,
      ...original.sublist(index + 1),
    ];
  }

  @override
  List<Slot> updateSlot(
    int algorithmIndex,
    List<Slot> slots,
    Slot Function(Slot) updateFunction,
  ) {
    return [
      ...slots.sublist(0, algorithmIndex),
      updateFunction(slots[algorithmIndex]),
      ...slots.sublist(algorithmIndex + 1),
    ];
  }

  Future<void> updateParameterValue({
    required int algorithmIndex,
    required int parameterNumber,
    required int value,
    required bool userIsChangingTheValue,
  }) async {
    return _parameterValueDelegate.updateParameterValue(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      value: value,
      userIsChangingTheValue: userIsChangingTheValue,
    );
  }

  /// Schedules a debounced parameter refresh (requestAllParameterValues).
  /// If a refresh is already scheduled, the existing timer is cancelled and restarted.
  /// This ensures only one refresh request is sent after a batch of parameter edits.
  /// The actual refresh occurs 300ms after the last call to this method.
  void scheduleParameterRefresh(int algorithmIndex) {
    return _parameterRefreshDelegate.scheduleParameterRefresh(algorithmIndex);
  }

  Future<void> onAlgorithmSelected(
    AlgorithmInfo algorithm,
    List<int> specifications, {
    bool addBypassed = false,
  }) async {
    return onAlgorithmSelectedImpl(
      algorithm,
      specifications,
      addBypassed: addBypassed,
    );
  }

  Future<void> onRemoveAlgorithm(int algorithmIndex) async {
    return onRemoveAlgorithmImpl(algorithmIndex);
  }

  void renamePreset(String newName) {
    renamePresetAndSave(newName).ignore();
  }

  /// Rename and persist the current preset, completing only after both device
  /// writes succeed. UI callers use [renamePreset], while tool/controller
  /// callers await this method so failures are observable.
  Future<void> renamePresetAndSave(String newName) {
    return renamePresetImpl(newName);
  }

  Future<int> moveAlgorithmUp(int algorithmIndex) async {
    return moveAlgorithmUpImpl(algorithmIndex);
  }

  Future<int> moveAlgorithmDown(int algorithmIndex) async {
    return moveAlgorithmDownImpl(algorithmIndex);
  }

  Future<void> newPreset() async {
    _checkpointDelegate.clearCheckpoints();
    return newPresetImpl();
  }

  /// Save the current preset to persistent device storage and clear
  /// the in-memory dirty flag on success. A failed save leaves the
  /// flag set so the user retains the unsaved-changes indicator.
  Future<void> savePreset() async {
    final s = state;
    if (s is! DistingStateSynchronized) return;
    final disting = s.disting;
    await disting.requestSavePreset();
    final after = state;
    if (after is DistingStateSynchronized) {
      _emitState(after.copyWith(isDirty: false));
    }
  }

  Future<void> loadPreset(String name, bool append) async {
    if (!append) _checkpointDelegate.clearCheckpoints();
    return loadPresetImpl(name, append);
  }

  Future<void> saveMapping(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  ) async {
    return _mappingDelegate.saveMapping(algorithmIndex, parameterNumber, data);
  }

  Future<void> saveMappingImmediately(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  ) async {
    return _mappingDelegate.saveMappingImmediately(
      algorithmIndex,
      parameterNumber,
      data,
    );
  }

  void renameSlot(int algorithmIndex, String newName) async {
    renameSlotImpl(algorithmIndex, newName);
  }

  /// Reorders multiple performance parameters by setting new perfPageIndex values.
  Future<void> reorderPerformanceParameters(
    List<({int slotIndex, int parameterNumber, int perfPageIndex})> assignments,
  ) async {
    return _mappingDelegate.reorderPerformanceParameters(assignments);
  }

  /// Sets the performance page assignment for a parameter.
  ///
  /// - [slotIndex]: Slot index (0-39)
  /// - [parameterNumber]: Parameter number within the algorithm
  /// - [perfPageIndex]: Performance page index (0-30, where 0 = not assigned)
  ///
  /// Uses optimistic update pattern:
  /// 1. Update local state immediately for instant UI feedback
  /// 2. Send update to hardware
  /// 3. Verify by reading back specific parameter mapping
  /// 4. If mismatch, hardware value wins and UI updates again
  Future<void> setPerformancePageMapping(
    int slotIndex,
    int parameterNumber,
    int perfPageIndex,
  ) async {
    return _mappingDelegate.setPerformancePageMapping(
      slotIndex,
      parameterNumber,
      perfPageIndex,
    );
  }

  /// Sets a performance page item (firmware v1.16+).
  Future<void> setPerfPageItem(PerformancePageItem item) async {
    return _perfPageDelegate.setPerfPageItem(item);
  }

  /// Removes a performance page item (firmware v1.16+).
  Future<void> removePerfPageItem(int itemIndex) async {
    return _perfPageDelegate.removePerfPageItem(itemIndex);
  }

  /// Reorders performance page items (firmware v1.16+).
  Future<void> reorderPerfPageItems(
    List<PerformancePageItem> reorderedItems,
  ) async {
    return _perfPageDelegate.reorderPerfPageItems(reorderedItems);
  }

  /// Re-fetches all 30 performance page items from hardware (firmware v1.16+).
  Future<void> refreshPerfPageItems() async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return;
    if (!currentState.firmwareVersion.hasPerfPageItems) return;

    final disting = requireDisting();
    final items = await _perfPageDelegate.fetchAllPerfPageItems(disting);
    final refreshedState = state;
    if (refreshedState is DistingStateSynchronized) {
      _emitState(refreshedState.copyWith(perfPageItems: items));
    }
  }

  // --- Helper Methods ---

  // Helper to refresh state from the current manager (online or offline)
  @override
  Future<void> _refreshStateFromManager({
    Duration delay = const Duration(milliseconds: 50), // Shorter default delay
  }) async {
    return _stateRefreshDelegate.refreshStateFromManager(delay: delay);
  }

  @override
  void _rebuildCcLookup() {
    _ccNotificationDelegate.rebuildLookup();
  }

  List<RoutingInformation> buildRoutingInformation() {
    return _stateHelpersDelegate.buildRoutingInformation();
  }

  bool _isProgramParameter(
    DistingStateSynchronized state,
    int algorithmIndex,
    int parameterNumber,
  ) => _stateHelpersDelegate.isProgramParameter(
    state,
    algorithmIndex,
    parameterNumber,
  );

  @override
  Slot _fixAlgorithmIndex(Slot slot, int algorithmIndex) {
    return _slotMaintenanceDelegate.fixAlgorithmIndex(slot, algorithmIndex);
  }

  // Simple program refresh queue with retry logic
  void _queueProgramRefresh(int algorithmIndex) {
    return _parameterRefreshDelegate.queueProgramRefresh(algorithmIndex);
  }

  void setDisplayMode(DisplayMode displayMode) {
    return _hardwareCommandsDelegate.setDisplayMode(displayMode);
  }

  /// Reboots the Disting NT module.
  /// This will cause the module to restart as if power cycled.
  Future<void> reboot() async {
    return _hardwareCommandsDelegate.reboot();
  }

  /// Remounts the SD card file system.
  /// This refreshes the file system without a full reboot.
  Future<void> remountSd() async {
    return _hardwareCommandsDelegate.remountSd();
  }

  // --- Checkpoint API ---

  List<PresetCheckpoint> get checkpoints => _checkpointDelegate.checkpoints;

  PresetCheckpoint? createCheckpoint({String? label}) =>
      _checkpointDelegate.createCheckpoint(label: label);

  Future<int> restoreCheckpoint(
    PresetCheckpoint checkpoint, {
    void Function(int completed, int total)? onProgress,
  }) =>
      _checkpointDelegate.restoreCheckpoint(checkpoint, onProgress: onProgress);

  void removeCheckpoint(PresetCheckpoint checkpoint) =>
      _checkpointDelegate.removeCheckpoint(checkpoint);

  void clearCheckpoints() => _checkpointDelegate.clearCheckpoints();

  static List<MappedParameter> buildMappedParameterList(DistingState state) {
    switch (state) {
      case DistingStateSynchronized():
        // return a list of parameters that have performance page assignments
        // from the state.
        return state.slots.fold(List<MappedParameter>.empty(growable: true), (
          acc,
          slot,
        ) {
          acc.addAll(
            slot.mappings
                .where(
                  (mapping) =>
                      mapping.parameterNumber != -1 &&
                      mapping.packedMappingData.isPerformance(),
                )
                .map((mapping) {
                  var parameterNumber = mapping.parameterNumber;
                  return MappedParameter(
                    parameter: slot.parameters[parameterNumber],
                    value: slot.values[parameterNumber],
                    enums: slot.enums[parameterNumber],
                    valueString: slot.valueStrings[parameterNumber],
                    mapping: mapping,
                    algorithm: slot.algorithm,
                  );
                })
                .toList(),
          );
          return acc;
        });
      default:
        return [];
    }
  }

  // Starts polling for each mapped parameter.
  void startPollingMappedParameters() {
    return _parameterRefreshDelegate.startPollingMappedParameters();
  }

  // Stops all polling tasks.
  void stopPollingMappedParameters() {
    return _parameterRefreshDelegate.stopPollingMappedParameters();
  }

  Future<void> resetOutputs(Slot slot, int outputIndex) async {
    return _slotMaintenanceDelegate.resetOutputs(slot, outputIndex);
  }

  @override
  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int completed, int total)? onSlotProgress,
  }) async {
    return _parameterFetchDelegate.fetchSlots(
      numAlgorithmsInPreset,
      disting,
      onSlotProgress: onSlotProgress,
    );
  }

  /// Get output mode usage data for a parameter.
  /// Returns list of affected parameter numbers, or null if not available.
  List<int>? getOutputModeUsage(int slotIndex, int parameterNumber) {
    return _slotStateDelegate.getOutputModeUsage(slotIndex, parameterNumber);
  }

  /// Get all output mode usage data for a slot.
  Map<int, List<int>>? getSlotOutputModeUsage(int slotIndex) {
    return _slotStateDelegate.getSlotOutputModeUsage(slotIndex);
  }

  @override
  Future<Slot> fetchSlot(
    IDistingMidiManager disting,
    int algorithmIndex,
  ) async {
    return _parameterFetchDelegate.fetchSlot(disting, algorithmIndex);
  }

  Future<void> refreshRouting() async {
    return _slotStateDelegate.refreshRouting();
  }

  Future<void> _refreshSlotAfterAnomaly(int algorithmIndex) async {
    return _slotMaintenanceDelegate.refreshSlotAfterAnomaly(algorithmIndex);
  }

  Future<List<String>> scanSdCardPresets() async {
    return _sdCardDelegate.scanSdCardPresets();
  }

  /// Scans the SD card on the connected disting for .json files.
  /// Returns a sorted list of relative paths (e.g., "presets/my_preset.json").
  /// Only available if firmware has SD card support.
  Future<List<String>> fetchSdCardPresets() async {
    return _sdCardDelegate.fetchSdCardPresets();
  }

  /// Scans for Lua script plugins in the /programs/lua directory.
  /// Returns a sorted list of .lua files found.
  Future<List<PluginInfo>> fetchLuaPlugins() async {
    return _pluginDelegate.fetchLuaPlugins();
  }

  /// Scans for 3pot plugins in the /programs/3pot directory.
  /// Returns a sorted list of .3pot files found.
  Future<List<PluginInfo>> fetch3potPlugins() async {
    return _pluginDelegate.fetch3potPlugins();
  }

  /// Scans for C++ plugins in the /programs/plug-ins directory.
  /// Returns a sorted list of .o files found.
  Future<List<PluginInfo>> fetchCppPlugins() async {
    return _pluginDelegate.fetchCppPlugins();
  }

  /// Refreshes parameter strings for a specific slot only
  Future<void> refreshSlotParameterStrings(int algorithmIndex) async {
    return _parameterStringDelegate.refreshSlotParameterStrings(algorithmIndex);
  }

  /// Refreshes a single slot's data from the module
  Future<void> refreshSlot(int algorithmIndex) async {
    return _slotMaintenanceDelegate.refreshSlot(algorithmIndex);
  }

  Future<void> updateParameterString({
    required int algorithmIndex,
    required int parameterNumber,
    required String value,
  }) async {
    return _parameterStringDelegate.updateParameterString(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      value: value,
    );
  }

  /// Starts the USB video stream from the Disting NT device
  Future<void> startVideoStream() async {
    return _monitoringDelegate.startVideoStream();
  }

  /// Stops the USB video stream
  Future<void> stopVideoStream() async {
    return _monitoringDelegate.stopVideoStream();
  }

  /// Gets the current video stream state
  VideoStreamState? get currentVideoState =>
      _monitoringDelegate.currentVideoState;

  /// Gets the video manager for direct stream access
  UsbVideoManager? get videoManager => _monitoringDelegate.videoManager;

  /// Temporarily pause CPU usage polling (useful during sync operations)
  void pauseCpuMonitoring() {
    return _monitoringDelegate.pauseCpuMonitoring();
  }

  /// Resume CPU usage polling if there are listeners
  void resumeCpuMonitoring() {
    return _monitoringDelegate.resumeCpuMonitoring();
  }

  /// Sends a delete command for a plugin file on the SD card.
  /// This is a fire-and-forget operation that assumes success.
  /// Only works when connected to a physical device (not offline/demo mode).
  Future<void> deletePlugin(PluginInfo plugin) async {
    return _pluginDelegate.deletePlugin(plugin);
  }

  /// Uploads a plugin file to the appropriate directory on the SD card.
  /// Files are uploaded in 512-byte chunks to stay within SysEx message limits.
  /// Only works when connected to a physical device (not offline/demo mode).
  ///
  /// For gallery plugins, pass [galleryPluginId] and [galleryPluginVersion]
  /// to properly track the installation for update checking.
  Future<void> installPlugin(
    String fileName,
    Uint8List fileData, {
    Function(double)? onProgress,
    String? galleryPluginId,
    String? galleryPluginVersion,
  }) async {
    return _pluginDelegate.installPlugin(
      fileName,
      fileData,
      onProgress: onProgress,
      galleryPluginId: galleryPluginId,
      galleryPluginVersion: galleryPluginVersion,
    );
  }

  /// Installs a sample file to a specific path on the SD card, if it doesn't already exist.
  ///
  /// Returns `true` if the file was installed, `false` if it was skipped (already exists).
  /// Throws an exception on failure.
  ///
  /// This is used by the gallery plugin installation to install sample dependencies.
  Future<bool> installSampleFile(
    String targetPath,
    Uint8List fileData, {
    Function(double)? onProgress,
  }) async {
    return _pluginDelegate.installSampleFile(
      targetPath,
      fileData,
      onProgress: onProgress,
    );
  }

  /// Forces a Lua script reload while preserving all parameter state.
  /// This is specifically designed for development mode where a script file
  /// has been modified and needs to be reloaded without losing user settings.
  ///
  /// The process: Program=0 (unload) → Program=currentValue (reload) → restore all state
  Future<void> forceReloadLuaScriptWithStatePreservation(
    int algorithmIndex,
    int programParameterNumber,
    int currentProgramValue,
  ) async {
    return _luaReloadDelegate.forceReloadLuaScriptWithStatePreservation(
      algorithmIndex,
      programParameterNumber,
      currentProgramValue,
    );
  }

  /// Backs up all plugins from the Disting NT to a local directory.
  /// Maintains the directory structure (/programs/lua, /programs/three_pot, /programs/plug-ins).
  Future<void> backupPlugins(
    String backupDirectory, {
    void Function(double progress, String currentFile)? onProgress,
  }) async {
    return _pluginDelegate.backupPlugins(
      backupDirectory,
      onProgress: onProgress,
    );
  }

  /// Install multiple files from a preset package in batch
  Future<void> installPackageFiles(
    List<PackageFile> files,
    Map<String, Uint8List> fileData, {
    Function(String fileName, int completed, int total)? onFileStart,
    Function(String fileName, double progress)? onFileProgress,
    Function(String fileName)? onFileComplete,
    Function(String fileName, String error)? onFileError,
  }) async {
    return _pluginDelegate.installPackageFiles(
      files,
      fileData,
      onFileStart: onFileStart,
      onFileProgress: onFileProgress,
      onFileComplete: onFileComplete,
      onFileError: onFileError,
    );
  }

  /// Install a single file to a specific path on the SD card
  Future<void> installFileToPath(
    String targetPath,
    Uint8List fileData, {
    Function(double)? onProgress,
  }) async {
    return _pluginDelegate.installFileToPath(
      targetPath,
      fileData,
      onProgress: onProgress,
    );
  }

  /// Load a plugin using the dedicated 0x38 Load Plugin SysEx command
  /// and refresh the specific algorithm info with updated specifications
  Future<AlgorithmInfo?> loadPlugin(String guid) async {
    return _pluginDelegate.loadPlugin(guid);
  }

  /// Check for firmware updates in the background (non-blocking)
  ///
  /// Updates the state with available firmware update if one is found.
  /// Called automatically after successful connection on desktop platforms.
  Future<void> checkForFirmwareUpdate() async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return;
    if (currentState.offline || currentState.demo) return;

    try {
      final versions = await _firmwareVersionService.fetchAvailableVersions();
      final currentVersion = currentState.firmwareVersion.toString();

      if (_firmwareVersionService.isUpdateAvailable(currentVersion, versions)) {
        final latest = _firmwareVersionService.getLatestVersion(versions);
        if (latest != null && state is DistingStateSynchronized) {
          // Re-check state to avoid race condition
          final syncState = state as DistingStateSynchronized;
          _emitState(syncState.copyWith(availableFirmwareUpdate: latest));
        }
      }
    } catch (e) {
      // Silently fail - firmware check is non-critical
    }
  }

  /// Get the firmware version service for UI access
  FirmwareVersionService get firmwareVersionService => _firmwareVersionService;

  /// Probes the firmware version from a device without affecting cubit state.
  /// Uses the cubit's own [_midiCommand] to avoid platform channel conflicts.
  /// Pauses the MIDI setup listener to prevent re-entrancy during connect/disconnect.
  /// Returns the version string or null on failure.
  Future<String?> probeFirmwareVersion(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    _midiSetupSubscription?.pause();
    try {
      await _midiCommand.connectToDevice(inputDevice);
      if (inputDevice.id != outputDevice.id) {
        await _midiCommand.connectToDevice(outputDevice);
      }
      final manager = DistingMidiManager(
        midiCommand: _midiCommand,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
      );
      try {
        final version = await manager.requestVersionString().timeout(
          const Duration(seconds: 3),
        );
        return version;
      } finally {
        manager.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      _midiCommand.disconnectDevice(inputDevice);
      if (inputDevice.id != outputDevice.id) {
        _midiCommand.disconnectDevice(outputDevice);
      }
      _midiSetupSubscription?.resume();
    }
  }

  /// Creates a connected [IDistingMidiManager] for firmware operations.
  ///
  /// Pauses the MIDI setup listener during connection. The caller is
  /// responsible for calling [disposeFirmwareMidiManager] when done.
  Future<IDistingMidiManager> createFirmwareMidiManager(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    _midiSetupSubscription?.pause();
    await _midiCommand.connectToDevice(inputDevice);
    if (inputDevice.id != outputDevice.id) {
      await _midiCommand.connectToDevice(outputDevice);
    }
    return DistingMidiManager(
      midiCommand: _midiCommand,
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      sysExId: sysExId,
    );
  }

  /// Disposes a midi manager created by [createFirmwareMidiManager] and
  /// disconnects the devices.
  ///
  /// Device disconnection is wrapped in try-catch because the USB device may
  /// no longer exist after a firmware update reboot.
  void disposeFirmwareMidiManager(
    IDistingMidiManager manager,
    MidiDevice inputDevice,
    MidiDevice outputDevice,
  ) {
    _ccNotificationDelegate.stop();
    _monitoringDelegate.pauseCpuMonitoring();
    _parameterQueue?.dispose();
    _parameterQueue = null;
    if (identical(disting(), manager)) {
      _emitState(const DistingState.initial());
    }
    try {
      _midiCommand.disconnectDevice(inputDevice);
    } catch (_) {}
    if (inputDevice.id != outputDevice.id) {
      try {
        _midiCommand.disconnectDevice(outputDevice);
      } catch (_) {}
    }
    try {
      manager.dispose();
    } catch (_) {}

    if (_isWindows) {
      // WinMM owns a process-wide NativeCallable. Recreating MidiCommand can
      // leave the native callback pointing at a closed Dart address.
      _midiSetupSubscription?.resume();
    } else {
      // CoreMIDI and ALSA can retain a stale native client after the NT drops
      // off USB during flashing. Recreate the client before polling so every
      // snapshot and reconnection uses fresh platform state.
      _midiSetupSubscription?.cancel();
      _midiSetupSubscription = null;
      try {
        _midiCommand.dispose();
      } catch (_) {}
      _midiCommand = _midiCommandFactory();
      _connectionDelegate.startMidiSetupListener();
    }
  }

  /// Checks a fresh MIDI snapshot for the exact names from the last successful
  /// connection, falling back to the firmware screen's current selection when
  /// no preferences have been saved yet.
  Future<bool> firmwareMidiDevicesAvailable(
    String? fallbackInputName,
    String? fallbackOutputName,
  ) async {
    final prefs = await _prefs;
    final expectedInputName =
        prefs.getString('selectedInputMidiDevice') ?? fallbackInputName;
    final expectedOutputName =
        prefs.getString('selectedOutputMidiDevice') ?? fallbackOutputName;
    return _connectionDelegate.firmwareMidiDevicesAvailable(
      expectedInputName,
      expectedOutputName,
    );
  }

  /// Called after firmware installation and MIDI reacquisition complete.
  /// Clears cached version data and returns to a fresh device-selection list.
  Future<void> onFirmwareUpdateComplete() async {
    _firmwareVersionService.clearCache();

    await _connectionDelegate.loadDevices();
  }
}

extension DistingCubitGetters on DistingCubit {
  IDistingMidiManager? disting() {
    return switch (state) {
      DistingStateConnected(disting: final d) => d,
      DistingStateSynchronized(disting: final d) => d,
      _ => null,
    };
  }

  IDistingMidiManager requireDisting() {
    final d = disting();
    if (d == null) {
      throw Exception("Disting not connected");
    }
    return d;
  }
}
