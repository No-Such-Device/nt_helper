import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart' as core_routing;
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/services/algorithm_connection_service.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/services/connection_validator.dart';
import 'package:nt_helper/ui/widgets/routing/connection_validator.dart'
    as ui_validator;
import 'package:nt_helper/core/routing/node_layout_algorithm.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nt_helper/core/routing/models/es5_hardware_node.dart';
import 'package:nt_helper/core/routing/bus_flow_solver.dart';
import 'package:nt_helper/core/routing/slot_reorder_planner.dart';
import 'package:nt_helper/core/routing/aux_bus_consolidation.dart';
import 'package:nt_helper/models/device_io_profile.dart';

import 'routing_editor_state.dart';

/// Outcome of a slot reorder, carrying enough to describe and undo it.
class ReorderResult {
  /// Algorithm ids in slot order before the reorder.
  final List<String> previousOrder;

  /// Algorithm ids in slot order after the reorder.
  final List<String> newOrder;

  /// Human-readable summary, e.g. "Moved 'Reverb' up to keep signal flowing".
  final String description;

  /// Whether any slot actually moved.
  final bool changed;

  const ReorderResult({
    required this.previousOrder,
    required this.newOrder,
    required this.description,
    required this.changed,
  });
}

/// Outcome of [RoutingEditorCubit.assignBusAndSolve], with the data needed to
/// undo both the bus assignment and any auto-reorder it triggered.
class BusAssignmentResult {
  final int algorithmIndex;
  final int parameterNumber;
  final int previousBusValue;
  final int newBusValue;

  /// The reorder that was applied to keep the flow valid, if any.
  final ReorderResult? reorder;

  const BusAssignmentResult({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.previousBusValue,
    required this.newBusValue,
    required this.reorder,
  });
}

/// Cubit that manages the state of the routing editor.
///
/// Watches the DistingCubit's synchronized state and processes routing
/// information into a visual representation for the routing canvas.
class RoutingEditorCubit extends Cubit<RoutingEditorState> {
  final DistingCubit? _distingCubit;
  Future<SharedPreferences>? _prefs;
  StreamSubscription<DistingState>? _distingStateSubscription;
  NodeLayoutAlgorithm? _layoutAlgorithm;
  List<Slot>? _lastProcessedSlots;
  DeviceIoProfile? _lastProcessedProfile;
  int _batchDepth = 0;
  List<Slot>? _deferredSlots;
  DeviceIoProfile? _deferredProfile;

  RoutingEditorCubit(
    this._distingCubit, {
    AlgorithmConnectionService? algorithmConnectionService,
  }) : super(const RoutingEditorState.initial()) {
    if (_distingCubit != null) {
      _prefs = SharedPreferences.getInstance();
      _initializeStateWatcher();
      _loadPersistedState();
    }
  }

  /// Initialize watching the disting cubit state changes
  void _initializeStateWatcher() {
    if (_distingCubit == null) return;

    _distingStateSubscription = _distingCubit.stream.listen((distingState) {
      _processDistingState(distingState);
    });

    // Process current state if already synchronized
    final currentState = _distingCubit.state;
    _processDistingState(currentState);
  }

  /// Generate stable algorithm IDs based on GUID and instance counter
  ///
  /// Creates IDs in the format `algo_${guid}_${instanceCounter}` where
  /// instanceCounter increments for duplicate algorithms to ensure uniqueness.
  /// These IDs remain stable regardless of slot position changes.
  List<String> generateStableAlgorithmIds(List<Slot> slots) {
    final algorithmIds = <String>[];
    final guidCounters = <String, int>{};

    for (final slot in slots) {
      final guid = slot.algorithm.guid;
      final counter = guidCounters[guid] ?? 0;
      guidCounters[guid] = counter + 1;

      // Create stable ID without slot index
      algorithmIds.add('algo_${guid}_${counter + 1}');
    }

    return algorithmIds;
  }

  /// Generate a stable port ID using algorithm UUID and parameter number
  ///
  /// Creates simple, opaque IDs with semantic information in metadata
  String generatePortId({
    required String algorithmId,
    required int parameterNumber,
    required String portType,
  }) {
    return '${algorithmId}_port_$parameterNumber';
  }

  /// Process incoming DistingState and update routing editor state accordingly
  void _processDistingState(DistingState distingState) {
    distingState.when(
      initial: () => emit(const RoutingEditorState.initial()),
      selectDevice:
          (
            inputDevices,
            outputDevices,
            canWorkOffline,
            selectedInputDevice,
            selectedOutputDevice,
            selectedSysExId,
          ) => emit(const RoutingEditorState.disconnected()),
      connected:
          (
            disting,
            inputDevice,
            outputDevice,
            offline,
            loading,
            syncStatus,
            syncProgress,
          ) => emit(const RoutingEditorState.disconnected()),
      synchronized:
          (
            disting,
            distingVersion,
            firmwareVersion,
            deviceIoProfile,
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
          ) {
            _processSynchronizedState(slots, deviceIoProfile);
          },
    );
  }

  /// Run [operation] while suppressing intermediate routing rebuilds.
  /// A single rebuild happens after the operation completes.
  Future<T> runBatched<T>(Future<T> Function() operation) async {
    _batchDepth++;
    try {
      return await operation();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _deferredSlots != null && !isClosed) {
        final slots = _deferredSlots!;
        final profile =
            _deferredProfile ??
            _lastProcessedProfile ??
            DeviceIoProfile.distingExtended;
        _deferredSlots = null;
        _deferredProfile = null;
        _processSynchronizedState(slots, profile);
      }
    }
  }

  /// Check if ES-5 node should be displayed based on algorithm GUIDs
  bool shouldShowEs5Node(List<Slot> slots) {
    const es5AlgorithmGuids = {
      'usbf',
      'clck',
      'eucp',
      'es5e',
      'clkm', // Clock Multiplier
      'clkd', // Clock Divider
      'pycv', // Poly CV
    };

    for (final slot in slots) {
      if (es5AlgorithmGuids.contains(slot.algorithm.guid)) {
        return true;
      }
    }

    return false;
  }

  /// Extract routing data from synchronized state and build visual representation.
  ///
  /// Only skips processing when the slots list is the exact same reference
  /// (meaning a non-slot field changed, like loading or screenshot). Otherwise,
  /// always recalculates — Bloc's emit() deduplicates via Freezed equality,
  /// so unchanged routing results won't trigger UI rebuilds.
  void _processSynchronizedState(
    List<Slot> slots,
    DeviceIoProfile deviceIoProfile,
  ) {
    // Identical slots and profile means only unrelated state changed.
    if (identical(slots, _lastProcessedSlots) &&
        deviceIoProfile == _lastProcessedProfile) {
      return;
    }

    // During batch operations, stash the latest slots and skip rebuild
    if (_batchDepth > 0) {
      _deferredSlots = slots;
      _deferredProfile = deviceIoProfile;
      return;
    }

    _lastProcessedSlots = slots;
    _lastProcessedProfile = deviceIoProfile;

    try {
      // Compute firmware capability early — needed for ES-5 ports and connection discovery
      final distingState = _distingCubit?.state;
      final hasExtended =
          distingState is DistingStateSynchronized &&
          distingState.firmwareVersion.hasExtendedAuxBuses;

      // Create physical hardware ports
      final physicalInputs = _createPhysicalInputPorts(deviceIoProfile);
      final physicalOutputs = _createPhysicalOutputPorts(deviceIoProfile);

      // Conditionally create ES-5 ports based on algorithm presence
      final es5Inputs = shouldShowEs5Node(slots)
          ? ES5HardwareNode.createInputPorts(deviceIoProfile: deviceIoProfile)
          : <Port>[];

      // Build algorithm representations with ports determined by AlgorithmRouting
      final algorithms = <RoutingAlgorithm>[];
      final routings = <core_routing.AlgorithmRouting>[];

      // Generate stable UUIDs for each algorithm instance
      final algorithmUuids = generateStableAlgorithmIds(slots);

      for (int i = 0; i < slots.length; i++) {
        final slot = slots[i];
        final algorithmUuid = algorithmUuids[i];

        // Create routing using the AlgorithmRouting factory method
        final routing = core_routing.AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: deviceIoProfile,
          algorithmUuid: algorithmUuid,
        );

        final inputPorts = routing.inputPorts;
        final outputPorts = routing.outputPorts;

        // Filter out algorithms with no ports (e.g., the 'note' algorithm)
        if (inputPorts.isEmpty && outputPorts.isEmpty) {
          continue;
        }

        // Add routing to list for connection discovery
        routings.add(routing);

        // Create visual representation
        final routingAlgorithm = RoutingAlgorithm(
          id: algorithmUuid,
          index: i,
          algorithm: slot.algorithm,
          // Convert core ports to UI model ports
          inputPorts: inputPorts
              .map(
                (p) => Port(
                  id: p.id,
                  name: p.name,
                  type: _toUiPortType(p.type),
                  direction: PortDirection.input,
                  busValue: p.busValue,
                  busParam: p.busParam,
                  parameterNumber: p.parameterNumber,
                  isPolyVoice: p.isPolyVoice,
                  voiceNumber: p.voiceNumber,
                  isVirtualCV: p.isVirtualCV,
                ),
              )
              .toList(),
          outputPorts: outputPorts
              .map(
                (p) => Port(
                  id: p.id,
                  name: p.name,
                  type: _toUiPortType(p.type),
                  direction: PortDirection.output,
                  busValue: p.busValue,
                  busParam: p.busParam,
                  parameterNumber: p.parameterNumber,
                  modeParameterNumber: p.modeParameterNumber,
                  outputMode: p.outputMode,
                  channelNumber: p.channelNumber,
                ),
              )
              .toList(),
        );
        algorithms.add(routingAlgorithm);
      }

      // Use the ConnectionDiscoveryService to discover connections from AlgorithmRouting instances
      final discoveredConnections =
          ConnectionDiscoveryService.discoverConnections(
            routings,
            deviceIoProfile: deviceIoProfile,
            hasExtendedAuxBuses: hasExtended,
          );

      // Validate connections for slot ordering violations
      final connections = ConnectionValidator.validateConnections(
        discoveredConnections,
        algorithms,
      );

      // Preserve zoom level and pan offset from current state if it exists
      final currentState = state;
      final zoomLevel = currentState is RoutingEditorStateLoaded
          ? currentState.zoomLevel
          : 1.0;
      final panOffset = currentState is RoutingEditorStateLoaded
          ? currentState.panOffset
          : Offset.zero;
      final auxBusUsage = _computeAuxBusUsage(
        algorithms,
        slots,
        deviceIoProfile,
      );

      emit(
        RoutingEditorState.loaded(
          deviceIoProfile: deviceIoProfile,
          physicalInputs: physicalInputs,
          physicalOutputs: physicalOutputs,
          es5Inputs: es5Inputs,
          algorithms: algorithms,
          connections: connections,
          zoomLevel: zoomLevel,
          panOffset: panOffset,
          isHardwareSynced: true,
          lastSyncTime: DateTime.now(),
          auxBusUsage: auxBusUsage,
          hasExtendedAuxBuses: hasExtended,
        ),
      );

      // Initialize default buses after loading (fire and forget)
      initializeDefaultBuses();

      // Load saved node positions for this preset
      loadNodePositions();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Routing processing error: $e\n$stackTrace');
      }
    }
  }

  /// Convert core port type (routing) to UI port type
  PortType _toUiPortType(PortType type) {
    // After Story 7.5, only audio and CV types exist
    // Both are directly mapped
    switch (type) {
      case PortType.audio:
        return PortType.audio;
      case PortType.cv:
        return PortType.cv;
    }
  }

  /// Create the firmware-reported physical input ports.
  List<Port> _createPhysicalInputPorts(DeviceIoProfile profile) {
    return List.generate(profile.inputBusCount, (i) {
      final n = i + 1;
      return Port(
        id: 'hw_in_$n',
        name: 'I$n',
        type: PortType.cv,
        direction: PortDirection.output,
        hardwareIndex: n,
        role: PortRole.physicalInputBus,
      );
    });
  }

  /// Create the firmware-reported physical output ports.
  List<Port> _createPhysicalOutputPorts(DeviceIoProfile profile) {
    return List.generate(profile.outputBusCount, (i) {
      final n = i + 1;
      return Port(
        id: 'hw_out_$n',
        name: 'O$n',
        type: PortType.audio,
        direction: PortDirection.input,
        hardwareIndex: n,
        role: PortRole.physicalOutputBus,
      );
    });
  }

  /// Create a new connection between source and target ports with automatic bus assignment
  Future<void> createConnection({
    required String sourcePortId,
    required String targetPortId,
    String? busId,
    OutputMode outputMode = OutputMode.add,
    double gain = 1.0,
  }) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    if (_distingCubit == null) {
      return;
    }

    try {
      final sourcePort = _findPortById(currentState, sourcePortId);
      final targetPort = _findPortById(currentState, targetPortId);

      if (sourcePort == null) {
        throw ArgumentError('Source port not found: $sourcePortId');
      }

      if (targetPort == null) {
        throw ArgumentError('Target port not found: $targetPortId');
      }

      // Validate connection using symmetric ConnectionValidator
      if (!ui_validator.ConnectionValidator.isValidConnection(
        sourcePort,
        targetPort,
      )) {
        throw ArgumentError(
          'Invalid connection: ${ui_validator.ConnectionValidator.getValidationError(sourcePort, targetPort)}',
        );
      }

      // Check for duplicate connections
      final existingConnection = _findExistingConnection(
        currentState,
        sourcePortId,
        targetPortId,
      );
      if (existingConnection != null) {
        throw StateError('Connection already exists between these ports');
      }

      // Dispatch bus assignment based on port roles.
      // The ConnectionValidator has already ensured one port is an algorithm
      // port and the other is either a bus or a complementary algorithm port.
      int? busNumber;

      final sourceRole = sourcePort.effectiveRole;
      final targetRole = targetPort.effectiveRole;

      if (sourcePort.isBus && targetPort.isBusReader) {
        // Bus -> algorithm input: assign bus number to the reader
        if (sourceRole == PortRole.physicalInputBus) {
          busNumber = await _assignBusForHardwareInput(
            sourcePortId,
            targetPort,
            currentState,
          );
        } else if (sourceRole == PortRole.physicalOutputBus) {
          busNumber = await _assignBusForPhysicalOutputToAlgorithmInput(
            sourcePortId,
            targetPort,
            currentState,
          );
        } else {
          // ES-5 bus -> algorithm input
          busNumber = await _assignBusForHardwareOutput(
            targetPort,
            sourcePortId,
            currentState,
          );
        }
      } else if (targetPort.isBus && sourcePort.isBusWriter) {
        // Algorithm output -> bus: assign bus number to the writer
        if (ui_validator.ConnectionValidator.isGhostConnection(
          sourcePort,
          targetPort,
        )) {
          busNumber = await _assignBusForGhostConnection(
            sourcePort,
            targetPortId,
            currentState,
          );
        } else {
          busNumber = await _assignBusForHardwareOutput(
            sourcePort,
            targetPortId,
            currentState,
          );
        }
      } else if (sourcePort.isBus && targetPort.isBusWriter) {
        // Physical bus -> algorithm output (ghost in reverse drag direction)
        if (ui_validator.ConnectionValidator.isGhostConnection(
          sourcePort,
          targetPort,
        )) {
          busNumber = await _assignBusForGhostConnection(
            targetPort,
            sourcePortId,
            currentState,
          );
        } else {
          busNumber = await _assignBusForHardwareOutput(
            targetPort,
            sourcePortId,
            currentState,
          );
        }
      } else if (targetPort.isBus && sourcePort.isBusReader) {
        // Algorithm input -> bus: assign bus number to the reader
        if (targetRole == PortRole.physicalInputBus) {
          busNumber = await _assignBusForHardwareInput(
            targetPortId,
            sourcePort,
            currentState,
          );
        } else if (targetRole == PortRole.physicalOutputBus) {
          busNumber = await _assignBusForPhysicalOutputToAlgorithmInput(
            targetPortId,
            sourcePort,
            currentState,
          );
        } else {
          // Algorithm input -> ES-5 bus
          busNumber = await _assignBusForHardwareOutput(
            sourcePort,
            targetPortId,
            currentState,
          );
        }
      } else if (sourceRole == PortRole.busWriter &&
          targetRole == PortRole.busReader) {
        // Algorithm output -> algorithm input: aux buses
        busNumber = await _assignBusForAlgorithmConnection(
          sourcePort,
          targetPort,
          currentState,
        );
      } else if (sourceRole == PortRole.busReader &&
          targetRole == PortRole.busWriter) {
        // Algorithm input -> algorithm output (reverse drag): aux buses
        busNumber = await _assignBusForAlgorithmConnection(
          targetPort,
          sourcePort,
          currentState,
        );
      } else {
        return;
      }

      if (busNumber == null) {
        throw StateError('Failed to assign bus');
      }

      // The connection will appear automatically via ConnectionDiscoveryService
      // when the bus parameters are updated

      // Mark hardware as out of sync after parameter changes
      await _autoSyncToHardware();
    } catch (e) {
      rethrow;
    }
  }

  /// Assign bus for hardware input connection (hardware input -> algorithm input)
  Future<int?> _assignBusForHardwareInput(
    String hardwareInputPortId,
    Port algorithmInputPort,
    RoutingEditorStateLoaded state,
  ) async {
    // Hardware input ids are local to the current firmware profile.
    final hardwareInputNumber = int.tryParse(
      hardwareInputPortId.replaceAll('hw_in_', ''),
    );
    if (hardwareInputNumber == null ||
        hardwareInputNumber < 1 ||
        hardwareInputNumber > state.deviceIoProfile.inputBusCount) {
      return null;
    }

    final busNumber = hardwareInputNumber; // Bus 1 for hw_in_1, etc.

    // Virtual ports (negative parameterNumber) have firmware-implicit bus values
    // that can't be reassigned to a hardware input bus.
    if (algorithmInputPort.parameterNumber != null &&
        algorithmInputPort.parameterNumber! < 0) {
      return null;
    }

    // Find the algorithm that owns this input port and update its parameter
    if (algorithmInputPort.parameterNumber != null) {
      final algorithmIndex = _findAlgorithmIndexForPort(
        state,
        algorithmInputPort.id,
      );
      if (algorithmIndex != null) {
        final clampedBusNumber = _clampBusAssignment(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmInputPort.parameterNumber!,
          busValue: busNumber,
        );
        await _distingCubit!.updateParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmInputPort.parameterNumber!,
          value: clampedBusNumber,
          userIsChangingTheValue: false,
        );
        return clampedBusNumber;
      }
    }

    return null;
  }

  /// Assign bus for ghost connection (algorithm output -> physical input)
  ///
  /// Ghost connections route an algorithm's output to a physical input bus,
  /// making the signal available to other algorithms reading from that input.
  Future<int?> _assignBusForGhostConnection(
    Port algorithmOutputPort,
    String hardwareInputPortId,
    RoutingEditorStateLoaded state,
  ) async {
    final hardwareInputNumber = int.tryParse(
      hardwareInputPortId.replaceAll('hw_in_', ''),
    );
    if (hardwareInputNumber == null ||
        hardwareInputNumber < 1 ||
        hardwareInputNumber > state.deviceIoProfile.inputBusCount) {
      return null;
    }

    final busNumber = hardwareInputNumber;

    if (algorithmOutputPort.parameterNumber != null) {
      final algorithmIndex = _findAlgorithmIndexForPort(
        state,
        algorithmOutputPort.id,
      );
      if (algorithmIndex != null) {
        final clampedBusNumber = _clampBusAssignment(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmOutputPort.parameterNumber!,
          busValue: busNumber,
        );
        await _distingCubit!.updateParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmOutputPort.parameterNumber!,
          value: clampedBusNumber,
          userIsChangingTheValue: false,
        );
        return clampedBusNumber;
      }
    }

    return null;
  }

  /// Assign bus for physical output -> algorithm input connection
  ///
  /// The algorithm input reads from the selected physical output bus.
  Future<int?> _assignBusForPhysicalOutputToAlgorithmInput(
    String hardwareOutputPortId,
    Port algorithmInputPort,
    RoutingEditorStateLoaded state,
  ) async {
    final hardwareOutputNumber = int.tryParse(
      hardwareOutputPortId.replaceAll('hw_out_', ''),
    );
    if (hardwareOutputNumber == null ||
        hardwareOutputNumber < 1 ||
        hardwareOutputNumber > state.deviceIoProfile.outputBusCount) {
      return null;
    }

    final busNumber = state.deviceIoProfile.busForLocalNumber(
      DeviceBusGroup.output,
      hardwareOutputNumber,
    )!;

    // Virtual ports (negative parameterNumber) have firmware-implicit bus values
    // that can't be reassigned to an output bus.
    if (algorithmInputPort.parameterNumber != null &&
        algorithmInputPort.parameterNumber! < 0) {
      return null;
    }

    if (algorithmInputPort.parameterNumber != null) {
      final algorithmIndex = _findAlgorithmIndexForPort(
        state,
        algorithmInputPort.id,
      );
      if (algorithmIndex != null) {
        final clampedBusNumber = _clampBusAssignment(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmInputPort.parameterNumber!,
          busValue: busNumber,
        );
        await _distingCubit!.updateParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmInputPort.parameterNumber!,
          value: clampedBusNumber,
          userIsChangingTheValue: false,
        );
        return clampedBusNumber;
      }
    }

    return null;
  }

  /// Assign bus for hardware output connection (algorithm output -> hardware output)
  Future<int?> _assignBusForHardwareOutput(
    Port algorithmOutputPort,
    String hardwareOutputPortId,
    RoutingEditorStateLoaded state,
  ) async {
    int? busNumber;

    // ES-5 L/R ports — only UsbAudioFromHost ('usbf') can connect to these
    if (hardwareOutputPortId == 'es5_L' || hardwareOutputPortId == 'es5_R') {
      final algorithmIndex = _findAlgorithmIndexForPort(
        state,
        algorithmOutputPort.id,
      );
      if (algorithmIndex == null) return null;
      final distingState = _distingCubit?.state;
      if (distingState is! DistingStateSynchronized) return null;
      if (algorithmIndex >= distingState.slots.length) return null;
      final guid = distingState.slots[algorithmIndex].algorithm.guid;
      if (guid != 'usbf') return null;

      final es5Buses = state.deviceIoProfile.contextualEs5Buses;
      if (es5Buses.length != 2) return null;
      busNumber = hardwareOutputPortId == 'es5_L'
          ? es5Buses.first
          : es5Buses.last;
    } else if (hardwareOutputPortId.startsWith('es5_') &&
        hardwareOutputPortId.length == 5) {
      // ES-5 direct output ports (es5_1 through es5_8)
      final es5PortNumber = int.tryParse(hardwareOutputPortId.substring(4));
      if (es5PortNumber != null && es5PortNumber >= 1 && es5PortNumber <= 8) {
        // Check if this is ES-5 Encoder output (busParam = 'es5_encoder_mirror')
        if (algorithmOutputPort.busParam == 'es5_encoder_mirror') {
          return await _assignEs5EncoderOutput(
            algorithmOutputPort,
            es5PortNumber,
            state,
          );
        }
        // Check if this is ES-5 direct output (busParam = 'es5_direct')
        if (algorithmOutputPort.busParam == 'es5_direct') {
          return await _assignEs5DirectOutput(
            algorithmOutputPort,
            es5PortNumber,
            state,
          );
        }
        // Otherwise, this is a normal algorithm output being dragged to an ES-5 port
        // Fall through to normal bus assignment logic below
        return null;
      }
      return null;
    } else {
      final hardwareOutputNumber = int.tryParse(
        hardwareOutputPortId.replaceAll('hw_out_', ''),
      );
      if (hardwareOutputNumber == null ||
          hardwareOutputNumber < 1 ||
          hardwareOutputNumber > state.deviceIoProfile.outputBusCount) {
        return null;
      }

      busNumber = state.deviceIoProfile.busForLocalNumber(
        DeviceBusGroup.output,
        hardwareOutputNumber,
      );
    }

    if (busNumber == null) return null;

    // Find the algorithm that owns this output port and update its parameter
    if (algorithmOutputPort.parameterNumber != null) {
      final algorithmIndex = _findAlgorithmIndexForPort(
        state,
        algorithmOutputPort.id,
      );
      if (algorithmIndex != null) {
        final assignedBusNumber = hardwareOutputPortId.startsWith('hw_out_')
            ? _clampBusAssignment(
                algorithmIndex: algorithmIndex,
                parameterNumber: algorithmOutputPort.parameterNumber!,
                busValue: busNumber,
              )
            : busNumber;
        await _distingCubit!.updateParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: algorithmOutputPort.parameterNumber!,
          value: assignedBusNumber,
          userIsChangingTheValue: false,
        );
        return assignedBusNumber;
      }
    }

    return null;
  }

  /// Assign ES-5 direct output for Clock/Euclidean algorithms.
  ///
  /// Sets the ES-5 Output parameter for the channel to route to the specified ES-5 port (1-8).
  Future<int?> _assignEs5DirectOutput(
    Port algorithmOutputPort,
    int es5PortNumber,
    RoutingEditorStateLoaded state,
  ) async {
    final algorithmIndex = _findAlgorithmIndexForPort(
      state,
      algorithmOutputPort.id,
    );
    if (algorithmIndex == null) {
      return null;
    }

    // Get the slot from DistingCubit
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return null;
    }

    if (algorithmIndex < 0 || algorithmIndex >= distingState.slots.length) {
      return null;
    }

    final slot = distingState.slots[algorithmIndex];

    // Extract channel/voice number from port ID
    // Formats:
    // - Clock/Euclidean/Clock Multiplier/Clock Divider: {uuid}_channel_{N}_es5_output
    // - Poly CV: {uuid}_gate_output_{N}
    int? channel;

    // Try multi-channel format first
    var channelMatch = RegExp(
      r'_channel_(\d+)_',
    ).firstMatch(algorithmOutputPort.id);
    if (channelMatch != null) {
      channel = int.parse(channelMatch.group(1)!);
    } else {
      // Try Poly CV voice format
      channelMatch = RegExp(
        r'_gate_output_(\d+)',
      ).firstMatch(algorithmOutputPort.id);
      if (channelMatch != null) {
        channel = int.parse(channelMatch.group(1)!);
      }
    }

    if (channel == null) {
      return null;
    }

    // Find the ES-5 Output parameter
    // For multi-channel algorithms (Clock/Euclidean/etc): "$channel:ES-5 Output"
    // For Poly CV: "ES-5 Output" (no channel prefix, controls starting port for all voices)
    String es5OutputParamName = '$channel:ES-5 Output';
    var es5OutputParam = slot.parameters.firstWhere(
      (p) => p.name == es5OutputParamName,
      orElse: () => ParameterInfo.filler(),
    );

    int targetValue = es5PortNumber;
    bool isPolyCv = false;

    // If not found with channel prefix, try without (Poly CV case)
    if (es5OutputParam.parameterNumber < 0) {
      es5OutputParamName = 'ES-5 Output';
      es5OutputParam = slot.parameters.firstWhere(
        (p) => p.name == es5OutputParamName,
        orElse: () => ParameterInfo.filler(),
      );
      isPolyCv = true;
    }

    if (es5OutputParam.parameterNumber < 0) {
      return null;
    }

    // For Poly CV, calculate the starting ES-5 port based on which voice was dragged
    // Voice numbering is 1-based, ES-5 ports are 1-8
    // If Voice 3 is dragged to ES-5 5, then starting port = 5 - (3 - 1) = 3
    if (isPolyCv) {
      final voiceIndex = channel - 1; // Convert to 0-based
      targetValue = es5PortNumber - voiceIndex;

      // Clamp to valid ES-5 port range (1-8)
      if (targetValue < 1) {
        targetValue = 1;
      } else if (targetValue > 8) {
        targetValue = 8;
      }
    }

    // Set the ES-5 Output parameter
    await _distingCubit!.updateParameterValue(
      algorithmIndex: algorithmIndex,
      parameterNumber: es5OutputParam.parameterNumber,
      value: targetValue,
      userIsChangingTheValue: false,
    );

    // Return a dummy bus number to indicate success
    // The actual connection will be discovered via ConnectionDiscoveryService
    return 1; // Non-null indicates success
  }

  /// Assign ES-5 Encoder output for dragged connections.
  ///
  /// Sets the Output parameter for the channel to route to the specified ES-5 port (1-8).
  Future<int?> _assignEs5EncoderOutput(
    Port algorithmOutputPort,
    int es5PortNumber,
    RoutingEditorStateLoaded state,
  ) async {
    final algorithmIndex = _findAlgorithmIndexForPort(
      state,
      algorithmOutputPort.id,
    );
    if (algorithmIndex == null) {
      return null;
    }

    // Get the slot from DistingCubit
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return null;
    }

    if (algorithmIndex < 0 || algorithmIndex >= distingState.slots.length) {
      return null;
    }

    final slot = distingState.slots[algorithmIndex];

    // Extract channel number from port ID (format: {uuid}_channel_{N}_output)
    final channelMatch = RegExp(
      r'_channel_(\d+)_output',
    ).firstMatch(algorithmOutputPort.id);
    if (channelMatch == null) {
      return null;
    }

    final channel = int.parse(channelMatch.group(1)!);

    // Find the Output parameter for this channel (format: "N:Output")
    final outputParamName = '$channel:Output';
    final outputParam = slot.parameters.firstWhere(
      (p) => p.name == outputParamName,
      orElse: () => ParameterInfo.filler(),
    );

    if (outputParam.parameterNumber < 0) {
      return null;
    }

    // Set the Output parameter to the target ES-5 port number
    await _distingCubit!.updateParameterValue(
      algorithmIndex: algorithmIndex,
      parameterNumber: outputParam.parameterNumber,
      value: es5PortNumber,
      userIsChangingTheValue: false,
    );

    // Return a dummy bus number to indicate success
    // The actual connection will be discovered via ConnectionDiscoveryService
    return 1; // Non-null indicates success
  }

  /// Assign bus for algorithm-to-algorithm connection using aux buses
  Future<int?> _assignBusForAlgorithmConnection(
    Port sourceOutputPort,
    Port targetInputPort,
    RoutingEditorStateLoaded state,
  ) async {
    // Get actual parameter values from live slot data, not cached Port.busValue
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return null;
    }

    // Find algorithm indices for the ports
    final sourceAlgorithmIndex = _findAlgorithmIndexForPort(
      state,
      sourceOutputPort.id,
    );
    final targetAlgorithmIndex = _findAlgorithmIndexForPort(
      state,
      targetInputPort.id,
    );

    if (sourceAlgorithmIndex == null || targetAlgorithmIndex == null) {
      return null;
    }

    // Detect virtual ports (negative parameterNumber = firmware-implicit bus)
    final targetIsVirtual =
        targetInputPort.parameterNumber != null &&
        targetInputPort.parameterNumber! < 0;

    // Detect fixed-bus source ports (null parameterNumber with a busValue,
    // e.g. the right channel of a stereo send whose bus = left bus + 1).
    final sourceIsFixed =
        sourceOutputPort.parameterNumber == null &&
        sourceOutputPort.busValue != null;

    // Get actual parameter values from slots
    int? sourceBusValue;
    int? targetBusValue;

    if (sourceIsFixed) {
      // Fixed-bus port — use the firmware-implicit bus value from the Port.
      sourceBusValue = sourceOutputPort.busValue;
    } else if (sourceOutputPort.parameterNumber != null &&
        sourceAlgorithmIndex < distingState.slots.length) {
      final sourceSlot = distingState.slots[sourceAlgorithmIndex];
      final sourceParam = sourceSlot.values.firstWhere(
        (v) => v.parameterNumber == sourceOutputPort.parameterNumber!,
        orElse: () => throw StateError('Source parameter not found in slot'),
      );
      sourceBusValue = sourceParam.value;
    }

    if (targetIsVirtual) {
      // Virtual ports have no real parameter in the slot — use the
      // firmware-implicit bus value carried on the Port object.
      targetBusValue = targetInputPort.busValue;
    } else if (targetInputPort.parameterNumber != null &&
        targetAlgorithmIndex < distingState.slots.length) {
      final targetSlot = distingState.slots[targetAlgorithmIndex];
      final targetParam = targetSlot.values.firstWhere(
        (v) => v.parameterNumber == targetInputPort.parameterNumber!,
        orElse: () => throw StateError('Target parameter not found in slot'),
      );
      targetBusValue = targetParam.value;
    }

    int busToUse;
    if (targetIsVirtual && targetBusValue != null) {
      // Virtual port's bus is fixed by firmware — route source to match it.
      busToUse = targetBusValue;
    } else if (sourceBusValue != null &&
        state.deviceIoProfile.isAux(sourceBusValue)) {
      // Source already on an AUX bus — reuse for fan-out
      busToUse = sourceBusValue;
    } else {
      // Source unassigned or on a physical bus — allocate an AUX bus
      // Add-only sources (no mode parameter) must use an empty bus;
      // sources that support Replace can reuse a bus from lower slots.
      final canReplace = sourceOutputPort.modeParameterNumber != null;
      final availableBus = await _findAvailableAuxBus(
        state,
        sourceAlgorithmIndex,
        allowReuse: canReplace,
        needsStereoPartner:
            sourceOutputPort.isStereoChannel &&
            sourceOutputPort.stereoSide == 'left',
      );
      if (availableBus == null) {
        throw StateError('No free AUX busses');
      }
      busToUse = availableBus.bus;
    }

    // Update both source output and target input bus parameters
    bool sourceUpdated = false;
    bool targetUpdated = false;

    // Update source output port (if it doesn't already have this bus based on actual hardware value)
    if (sourceIsFixed) {
      // Fixed-bus port (e.g. stereo right channel) — no parameter to update.
      sourceUpdated = true;
    } else if (sourceOutputPort.parameterNumber != null &&
        sourceBusValue != busToUse) {
      await _distingCubit!.updateParameterValue(
        algorithmIndex: sourceAlgorithmIndex,
        parameterNumber: sourceOutputPort.parameterNumber!,
        value: busToUse,
        userIsChangingTheValue: false,
      );
      sourceUpdated = true;
    } else if (sourceBusValue == busToUse) {
      sourceUpdated = true; // Already has the correct bus
    }

    // Set output mode to Replace for algorithm-to-algorithm connections
    if (sourceOutputPort.modeParameterNumber != null) {
      await _distingCubit!.updateParameterValue(
        algorithmIndex: sourceAlgorithmIndex,
        parameterNumber: sourceOutputPort.modeParameterNumber!,
        value: 1, // 1 = Replace
        userIsChangingTheValue: false,
      );
    }

    // Update target input port (if it doesn't already have this bus based on actual hardware value)
    if (targetIsVirtual) {
      // Virtual ports have firmware-implicit bus values — no parameter to update.
      targetUpdated = true;
    } else if (targetInputPort.parameterNumber != null &&
        targetBusValue != busToUse) {
      try {
        await _distingCubit!.updateParameterValue(
          algorithmIndex: targetAlgorithmIndex,
          parameterNumber: targetInputPort.parameterNumber!,
          value: busToUse,
          userIsChangingTheValue: false,
        );
        targetUpdated = true;
      } catch (e) {
        // Intentionally empty
      }
    } else if (targetBusValue == busToUse) {
      targetUpdated = true; // Already has the correct bus
    } else {}

    if (sourceUpdated && targetUpdated) {
      return busToUse;
    } else {
      throw StateError(
        'Failed to update bus parameters - algorithms may not be found',
      );
    }
  }

  /// Find the algorithm index for a given port ID
  int? _findAlgorithmIndexForPort(
    RoutingEditorStateLoaded state,
    String portId,
  ) {
    for (int i = 0; i < state.algorithms.length; i++) {
      final algorithm = state.algorithms[i];

      // Check input ports
      for (final port in algorithm.inputPorts) {
        if (port.id == portId) {
          return algorithm.index;
        }
      }

      // Check output ports
      for (final port in algorithm.outputPorts) {
        if (port.id == portId) {
          return algorithm.index;
        }
      }
    }

    return null;
  }

  /// Compute per-AUX-bus usage info from the current algorithms and slots.
  Map<int, AuxBusUsageInfo> _computeAuxBusUsage(
    List<RoutingAlgorithm> algorithms,
    List<Slot> slots,
    DeviceIoProfile deviceIoProfile,
  ) {
    final result = <int, AuxBusUsageInfo>{};

    for (final algorithm in algorithms) {
      if (algorithm.index >= slots.length) continue;
      final slot = slots[algorithm.index];
      final algoName = slot.algorithm.name;

      for (final port in algorithm.outputPorts) {
        final busValue = _resolvePortBusValue(port, slot);
        if (busValue == null) continue;
        if (!deviceIoProfile.isAux(busValue)) continue;
        final info = result.putIfAbsent(
          busValue,
          () => AuxBusUsageInfo(busNumber: busValue),
        );
        info.algorithmIds.add(algorithm.id);
        info.sourceNames.add(algoName);
      }

      for (final port in algorithm.inputPorts) {
        final busValue = _resolvePortBusValue(port, slot);
        if (busValue == null) continue;
        if (!deviceIoProfile.isAux(busValue)) continue;
        final info = result.putIfAbsent(
          busValue,
          () => AuxBusUsageInfo(busNumber: busValue),
        );
        info.algorithmIds.add(algorithm.id);
        info.destNames.add(algoName);
      }
    }

    return result;
  }

  /// Resolves the effective bus value for a port.
  /// For ports with a real hardware parameter, reads the live value from the slot.
  /// For virtual ports (no parameter or negative parameterNumber), falls back
  /// to the port's declared busValue.
  static int? _resolvePortBusValue(Port port, Slot slot) {
    final paramNumber = port.parameterNumber;
    if (paramNumber != null && paramNumber >= 0) {
      try {
        return slot.values
            .firstWhere((v) => v.parameterNumber == paramNumber)
            .value;
      } catch (_) {
        return null;
      }
    }
    return port.busValue;
  }

  /// Focus algorithms using a specific AUX bus (toggle behavior).
  void focusAuxBus(int busNumber) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final info = currentState.auxBusUsage[busNumber];
    if (info == null || info.algorithmIds.isEmpty) return;

    // Toggle: if already focused on exactly this bus's algorithms, clear focus
    if (currentState.focusedAlgorithmIds.isNotEmpty &&
        currentState.focusedAlgorithmIds.length == info.algorithmIds.length &&
        currentState.focusedAlgorithmIds.containsAll(info.algorithmIds)) {
      clearFocus();
    } else {
      emit(currentState.copyWith(focusedAlgorithmIds: info.algorithmIds));
    }
  }

  /// Find an available AUX bus for an algorithm connection.
  ///
  /// A bus is available if it's completely unused, or if all algorithms
  /// currently using it are at slot numbers lower than [sourceSlot]
  /// (i.e., they execute before the source, so a Replace write starts
  /// a clean session).
  Future<_AvailableAuxBus?> _findAvailableAuxBus(
    RoutingEditorStateLoaded state,
    int sourceSlot, {
    bool allowReuse = true,
    bool needsStereoPartner = false,
  }) async {
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) return null;

    final deviceIoProfile = state.deviceIoProfile;

    // Map each AUX bus to the highest slot number that uses it
    final maxSlotPerBus = <int, int>{};
    for (final algorithm in state.algorithms) {
      if (algorithm.index >= distingState.slots.length) continue;
      final slot = distingState.slots[algorithm.index];
      for (final port in [...algorithm.inputPorts, ...algorithm.outputPorts]) {
        if (port.parameterNumber != null) {
          try {
            final paramValue = slot.values
                .firstWhere((v) => v.parameterNumber == port.parameterNumber!)
                .value;
            if (deviceIoProfile.isAux(paramValue)) {
              final current = maxSlotPerBus[paramValue];
              if (current == null || algorithm.index > current) {
                maxSlotPerBus[paramValue] = algorithm.index;
              }
            }
          } catch (_) {}
        }
      }
    }

    // Stereo L ports need b+1 to also be a valid aux bus
    final candidates = needsStereoPartner
        ? deviceIoProfile.auxBuses.where(
            (bus) => deviceIoProfile.isAux(bus + 1),
          )
        : deviceIoProfile.auxBuses;

    // Prefer a completely unused AUX bus first
    for (final b in candidates) {
      if (!maxSlotPerBus.containsKey(b)) {
        return _AvailableAuxBus(bus: b, isReused: false);
      }
    }

    // Fall back to a reusable AUX bus whose users are all at lower slots
    if (allowReuse) {
      for (final b in candidates) {
        final maxSlot = maxSlotPerBus[b];
        if (maxSlot != null && maxSlot < sourceSlot) {
          return _AvailableAuxBus(bus: b, isReused: true);
        }
      }
    }

    return null;
  }

  /// Build a signal-preserving plan that consolidates AUX buses whose usage
  /// spans don't overlap in slot-time. Returns `null` if nothing can be safely
  /// consolidated. See [planAuxBusConsolidation] for the correctness rules.
  AuxBusConsolidationPlan? buildConsolidationPlan() {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return null;

    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) return null;

    final deviceIoProfile = currentState.deviceIoProfile;

    int? valueOf(Slot slot, int? parameterNumber) {
      if (parameterNumber == null) return null;
      for (final v in slot.values) {
        if (v.parameterNumber == parameterNumber) return v.value;
      }
      return null;
    }

    final portsByBus = <int, List<AuxBusPort>>{};
    for (final algorithm in currentState.algorithms) {
      if (algorithm.index >= distingState.slots.length) continue;
      final slot = distingState.slots[algorithm.index];

      for (final port in algorithm.outputPorts) {
        final bus = valueOf(slot, port.parameterNumber);
        if (bus == null || !deviceIoProfile.isAux(bus)) continue;
        final modeParam = port.modeParameterNumber;
        (portsByBus[bus] ??= []).add(
          AuxBusPort(
            slot: algorithm.index,
            busParameterNumber: port.parameterNumber!,
            isSource: true,
            canReplace: modeParam != null,
            isReplace: modeParam != null && valueOf(slot, modeParam) == 1,
            modeParameterNumber: modeParam,
          ),
        );
      }

      for (final port in algorithm.inputPorts) {
        final bus = valueOf(slot, port.parameterNumber);
        if (bus == null || !deviceIoProfile.isAux(bus)) continue;
        (portsByBus[bus] ??= []).add(
          AuxBusPort(
            slot: algorithm.index,
            busParameterNumber: port.parameterNumber!,
            isSource: false,
          ),
        );
      }
    }

    final usages = [
      for (final entry in portsByBus.entries)
        AuxBusUsage(bus: entry.key, ports: entry.value),
    ];

    final plan = planAuxBusConsolidation(usages);
    if (plan.isEmpty) return null;

    String nameOf(int slotIndex) => slotIndex < distingState.slots.length
        ? distingState.slots[slotIndex].algorithm.name
        : 'Slot $slotIndex';

    final merges = [
      for (final merge in plan)
        ConsolidationMerge(
          keepBus: merge.keepBus,
          freeBus: merge.freeBus,
          description:
              'Merge AUX ${deviceIoProfile.localNumber(merge.freeBus) ?? merge.freeBus}'
              ' into AUX ${deviceIoProfile.localNumber(merge.keepBus) ?? merge.keepBus}',
          steps: [
            for (final move in merge.moves)
              ConsolidationStep(
                algorithmIndex: move.slot,
                algorithmName: nameOf(move.slot),
                parameterNumber: move.busParameterNumber,
                fromBus: move.fromBus,
                toBus: move.toBus,
              ),
          ],
          replaceModeSteps: [
            for (final r in merge.replaces)
              ReplaceModeStep(
                algorithmIndex: r.slot,
                algorithmName: nameOf(r.slot),
                parameterNumber: r.modeParameterNumber,
              ),
          ],
        ),
    ];

    final description = merges.length == 1
        ? merges.first.description
        : 'Free ${merges.length} AUX buses';

    return AuxBusConsolidationPlan(description: description, merges: merges);
  }

  /// Execute a previously-built consolidation plan, iterating through each
  /// merge and calling progress callbacks as steps complete.
  ///
  /// Paces parameter updates with short delays to let the parameter queue
  /// drain and the model stay in sync with hardware.
  Future<void> executeConsolidationPlan(
    AuxBusConsolidationPlan plan, {
    void Function(int mergeIndex, int stepIndex)? onStepComplete,
    void Function(int mergeIndex, int replaceModeIndex)? onReplaceModeSet,
  }) async {
    return runBatched(() async {
      const paceDelay = Duration(milliseconds: 150);

      for (int m = 0; m < plan.merges.length; m++) {
        final merge = plan.merges[m];

        for (int r = 0; r < merge.replaceModeSteps.length; r++) {
          final rStep = merge.replaceModeSteps[r];
          await _distingCubit!.updateParameterValue(
            algorithmIndex: rStep.algorithmIndex,
            parameterNumber: rStep.parameterNumber,
            value: 1, // 1 = Replace
            userIsChangingTheValue: false,
          );
          onReplaceModeSet?.call(m, r);
          await Future.delayed(paceDelay);
        }

        for (int i = 0; i < merge.steps.length; i++) {
          final step = merge.steps[i];
          await _distingCubit!.updateParameterValue(
            algorithmIndex: step.algorithmIndex,
            parameterNumber: step.parameterNumber,
            value: merge.keepBus,
            userIsChangingTheValue: false,
          );
          onStepComplete?.call(m, i);
          await Future.delayed(paceDelay);
        }
      }
    });
  }

  /// Delete an existing connection by ID
  Future<void> deleteConnection(String connectionId) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      // Find the connection to delete
      final connectionToDelete = currentState.connections.firstWhere(
        (connection) => connection.id == connectionId,
        orElse: () =>
            throw ArgumentError('Connection not found: $connectionId'),
      );

      // Clear the bus assignments in hardware
      await _clearBusAssignmentsForConnection(connectionToDelete, currentState);

      // Trust the DistingCubit to send us an updated state via the stream subscription
      // The _processSynchronizedState method will rebuild everything from hardware truth
      // DO NOT manually modify the local state here

      _findPortById(currentState, connectionToDelete.sourcePortId);
      _findPortById(currentState, connectionToDelete.destinationPortId);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Delete all connections for a specific port
  Future<void> deleteConnectionsForPort(String portId) async {
    return runBatched(() async {
      final currentState = state;
      if (currentState is! RoutingEditorStateLoaded) {
        return;
      }

      try {
        final connectionsToDelete = currentState.connections
            .where(
              (connection) =>
                  connection.sourcePortId == portId ||
                  connection.destinationPortId == portId,
            )
            .toList();

        if (connectionsToDelete.isEmpty) {
          return;
        }

        // Delete each connection (which will also clear bus assignments)
        for (final connection in connectionsToDelete) {
          await deleteConnection(connection.id);
        }
      } catch (e) {
        // Intentionally empty
      }
    });
  }

  /// Reset all bus connections for a specific algorithm slot.
  ///
  /// Sets all bus parameters with `min == 0` to 0 (disconnected).
  /// Parameters with `min > 0` are left unchanged.
  /// Returns the number of parameters reset, or -1 if state is not ready.
  Future<int> resetAllConnections(int algorithmIndex) async {
    return runBatched(() async {
      final distingState = _distingCubit?.state;
      if (distingState is! DistingStateSynchronized) {
        return -1;
      }
      if (algorithmIndex < 0 || algorithmIndex >= distingState.slots.length) {
        return -1;
      }

      final slot = distingState.slots[algorithmIndex];
      var resetCount = 0;

      for (final param in slot.parameters) {
        final isBusParameter =
            (param.isInput || param.isOutput) && param.unit == 1;

        if (!isBusParameter) continue;
        if (param.min > 0) continue;

        // Look up current value from slot.values
        final currentValue = slot.values
            .where((v) => v.parameterNumber == param.parameterNumber)
            .firstOrNull
            ?.value;
        if (currentValue == null || currentValue == 0) continue;

        await _distingCubit!.updateParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: param.parameterNumber,
          value: 0,
          userIsChangingTheValue: false,
        );
        resetCount++;
      }

      return resetCount;
    });
  }

  /// Move all bus parameter references from [sourceBus] to [destinationBus].
  ///
  /// Iterates every slot's parameters, finds bus parameters currently set to
  /// [sourceBus], and rewrites them to [destinationBus]. The destination must
  /// be an empty (unused) AUX bus. Returns the number of parameters rewritten.
  Future<int> moveAuxBus(int sourceBus, int destinationBus) async {
    return runBatched(() async {
      final distingState = _distingCubit?.state;
      if (distingState is! DistingStateSynchronized) return -1;
      final profile = distingState.deviceIoProfile;
      if (!profile.isAux(sourceBus)) return -1;

      final references = <({int slotIndex, ParameterInfo parameter})>[];
      var commonMinimum = profile.auxStart;
      var commonMaximum = profile.maxBus;

      for (int slotIdx = 0; slotIdx < distingState.slots.length; slotIdx++) {
        final slot = distingState.slots[slotIdx];
        for (final param in slot.parameters) {
          if ((!param.isInput && !param.isOutput) || param.unit != 1) continue;
          final currentValue = slot.values
              .where((v) => v.parameterNumber == param.parameterNumber)
              .firstOrNull
              ?.value;
          if (currentValue != sourceBus) continue;
          references.add((slotIndex: slotIdx, parameter: param));
          if (param.min > commonMinimum) commonMinimum = param.min;
          if (param.max < commonMaximum) commonMaximum = param.max;
        }
      }

      if (references.isEmpty) return 0;
      final assignedDestination = profile.clampBusToRange(
        destinationBus,
        minimum: commonMinimum,
        maximum: commonMaximum,
        allowNone: false,
      );
      if (assignedDestination == null ||
          !profile.isAux(assignedDestination) ||
          assignedDestination == sourceBus) {
        return 0;
      }

      // Guard: the actual clamped destination must be empty.
      final currentState = state;
      if (currentState is RoutingEditorStateLoaded) {
        final destInfo = currentState.auxBusUsage[assignedDestination];
        if (destInfo != null && destInfo.sessionCount > 0) return -1;
      }

      const paceDelay = Duration(milliseconds: 150);
      var writeCount = 0;

      for (final reference in references) {
        await _distingCubit!.updateParameterValue(
          algorithmIndex: reference.slotIndex,
          parameterNumber: reference.parameter.parameterNumber,
          value: assignedDestination,
          userIsChangingTheValue: false,
        );
        writeCount++;
        await Future.delayed(paceDelay);
      }

      if (writeCount > 0) {
        await _autoSyncToHardware();
      }

      return writeCount;
    });
  }

  /// Returns a user-facing reason if the connection cannot be deleted, otherwise null.
  ///
  /// Some parameters (notably certain bus inputs/outputs) have `min > 0` and do not
  /// support a "None" (0) value. Attempting to clear those would immediately be
  /// reverted by hardware truth on the next sync.
  String? deletionBlockReasonForConnection(Connection connection) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return null;
    }

    // Output→physical-output connections are always "deletable" from the editor
    // perspective: if the output doesn't support "None", we can reassign it to a
    // non-physical-output bus instead of clearing it.
    if (connection.destinationPortId.startsWith('hw_out_') ||
        connection.destinationPortId.startsWith('es5_')) {
      return null;
    }

    // For algorithm-input connections, we clear the destination input bus.
    final targetPort = _findPortById(
      currentState,
      connection.destinationPortId,
    );
    final targetParamNumber = targetPort?.parameterNumber;
    if (targetParamNumber == null) {
      return null;
    }

    final algorithmIndex = _findAlgorithmIndexForPort(
      currentState,
      connection.destinationPortId,
    );
    if (algorithmIndex == null) {
      return null;
    }

    final canClear = _canClearBusAssignment(
      algorithmIndex: algorithmIndex,
      parameterNumber: targetParamNumber,
    );
    return canClear ? null : 'required bus assignment';
  }

  /// Returns a user-facing reason if any connection for this port cannot be deleted.
  String? deletionBlockReasonForPortConnections(String portId) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return null;
    }

    final portConnections = currentState.connections
        .where(
          (conn) =>
              conn.sourcePortId == portId || conn.destinationPortId == portId,
        )
        .toList();
    for (final conn in portConnections) {
      final reason = deletionBlockReasonForConnection(conn);
      if (reason != null) return reason;
    }
    return null;
  }

  /// Update an existing connection's properties
  Future<void> updateConnection({
    required String connectionId,
    String? busId,
    OutputMode? outputMode,
    double? gain,
    bool? isMuted,
  }) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      final connectionIndex = currentState.connections.indexWhere(
        (connection) => connection.id == connectionId,
      );

      if (connectionIndex == -1) {
        return;
      }

      final existingConnection = currentState.connections[connectionIndex];
      final updatedConnection = existingConnection.copyWith(
        busId: busId ?? existingConnection.busId,
        outputMode: outputMode ?? existingConnection.outputMode,
        gain: gain ?? existingConnection.gain,
        isMuted: isMuted ?? existingConnection.isMuted,
        modifiedAt: DateTime.now(),
      );

      final updatedConnections = [...currentState.connections];
      updatedConnections[connectionIndex] = updatedConnection;

      emit(
        currentState.copyWith(connections: updatedConnections, lastError: null),
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Helper method to find a port by ID across all port lists
  Port? _findPortById(RoutingEditorStateLoaded state, String portId) {
    // Check physical inputs
    for (final port in state.physicalInputs) {
      if (port.id == portId) return port;
    }

    // Check physical outputs
    for (final port in state.physicalOutputs) {
      if (port.id == portId) return port;
    }

    // Check ES-5 inputs
    for (final port in state.es5Inputs) {
      if (port.id == portId) return port;
    }

    // Check algorithm ports
    for (final algorithm in state.algorithms) {
      for (final port in algorithm.inputPorts) {
        if (port.id == portId) return port;
      }
      for (final port in algorithm.outputPorts) {
        if (port.id == portId) return port;
      }
    }

    return null;
  }

  /// Helper method to find a port by ID and return both the port and its algorithm index
  (Port?, int?) _findPortWithAlgorithmIndex(
    RoutingEditorStateLoaded state,
    String portId,
  ) {
    // Check physical inputs (no algorithm index)
    for (final port in state.physicalInputs) {
      if (port.id == portId) return (port, null);
    }

    // Check physical outputs (no algorithm index)
    for (final port in state.physicalOutputs) {
      if (port.id == portId) return (port, null);
    }

    // Check ES-5 inputs (no algorithm index)
    for (final port in state.es5Inputs) {
      if (port.id == portId) return (port, null);
    }

    // Check algorithm ports
    for (final algorithm in state.algorithms) {
      for (final port in algorithm.inputPorts) {
        if (port.id == portId) return (port, algorithm.index);
      }
      for (final port in algorithm.outputPorts) {
        if (port.id == portId) return (port, algorithm.index);
      }
    }

    return (null, null);
  }

  /// Helper method to check if two ports can be connected

  /// Helper method to determine if a connection is a ghost connection
  /// Ghost connections occur when an algorithm output connects to a physical input

  /// Helper method to determine the type of connection based on port IDs
  ConnectionType _determineConnectionType(
    String sourcePortId,
    String targetPortId,
  ) {
    final isSourceHardwareInput = sourcePortId.startsWith('hw_in_');
    final isSourceHardwareOutput = sourcePortId.startsWith('hw_out_');
    final isTargetHardwareOutput = targetPortId.startsWith('hw_out_');
    final isTargetHardwareInput = targetPortId.startsWith('hw_in_');
    final isTargetEs5 = targetPortId.startsWith('es5_');

    if (isSourceHardwareInput) {
      return ConnectionType.hardwareInput;
    } else if (isSourceHardwareOutput) {
      // Physical output -> algorithm input: algorithm reads from output bus
      return ConnectionType.hardwareOutput;
    } else if (isTargetHardwareOutput || isTargetEs5) {
      return ConnectionType.hardwareOutput;
    } else if (isTargetHardwareInput) {
      // Ghost connection: algorithm output -> physical input
      return ConnectionType.hardwareInput;
    } else {
      return ConnectionType.algorithmToAlgorithm;
    }
  }

  /// Test helper method to expose _determineConnectionType for testing
  @visibleForTesting
  ConnectionType testDetermineConnectionType(
    String sourcePortId,
    String targetPortId,
  ) {
    return _determineConnectionType(sourcePortId, targetPortId);
  }

  /// Helper method to find existing connection between two ports
  Connection? _findExistingConnection(
    RoutingEditorStateLoaded state,
    String sourcePortId,
    String targetPortId,
  ) {
    try {
      return state.connections.firstWhere(
        (connection) =>
            connection.sourcePortId == sourcePortId &&
            connection.destinationPortId == targetPortId,
      );
    } catch (e) {
      return null;
    }
  }

  /// Create a new routing bus
  Future<void> createBus({
    required String name,
    OutputMode defaultOutputMode = OutputMode.add,
    double masterGain = 1.0,
  }) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      // Generate unique bus ID
      final busId = 'bus_${DateTime.now().millisecondsSinceEpoch}';

      // Create new bus
      final newBus = RoutingBus(
        id: busId,
        name: name,
        status: BusStatus.available,
        defaultOutputMode: defaultOutputMode,
        masterGain: masterGain,
        createdAt: DateTime.now(),
      );

      // Update state with new bus
      final updatedBuses = [...currentState.buses, newBus];

      emit(currentState.copyWith(buses: updatedBuses, lastError: null));

      // Mark hardware as out of sync after local changes
      await _autoSyncToHardware();
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Delete a routing bus and reassign its connections
  Future<void> deleteBus(String busId) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      // Find the bus to delete
      currentState.buses.firstWhere(
        (bus) => bus.id == busId,
        orElse: () => throw ArgumentError('Bus not found: $busId'),
      );

      // Remove bus assignment from all connections
      final updatedConnections = currentState.connections.map((connection) {
        if (connection.busId == busId) {
          return connection.copyWith(busId: null, modifiedAt: DateTime.now());
        }
        return connection;
      }).toList();

      // Remove bus from state
      final updatedBuses = currentState.buses
          .where((bus) => bus.id != busId)
          .toList();

      emit(
        currentState.copyWith(
          buses: updatedBuses,
          connections: updatedConnections,
          lastError: null,
        ),
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Assign a connection to a routing bus
  Future<void> assignConnectionToBus({
    required String connectionId,
    required String busId,
    OutputMode? outputMode,
  }) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      // Find the connection
      final connectionIndex = currentState.connections.indexWhere(
        (connection) => connection.id == connectionId,
      );

      if (connectionIndex == -1) {
        return;
      }

      // Find the bus
      final busIndex = currentState.buses.indexWhere((bus) => bus.id == busId);

      if (busIndex == -1) {
        return;
      }

      final existingConnection = currentState.connections[connectionIndex];
      final existingBus = currentState.buses[busIndex];

      // Remove connection from old bus if it was assigned
      List<RoutingBus> updatedBuses = [...currentState.buses];
      if (existingConnection.busId != null) {
        for (int i = 0; i < updatedBuses.length; i++) {
          if (updatedBuses[i].id == existingConnection.busId) {
            final oldBusConnectionIds = updatedBuses[i].connectionIds
                .where((id) => id != connectionId)
                .toList();
            updatedBuses[i] = updatedBuses[i].copyWith(
              connectionIds: oldBusConnectionIds,
              status: oldBusConnectionIds.isEmpty
                  ? BusStatus.available
                  : BusStatus.assigned,
              modifiedAt: DateTime.now(),
            );
            break;
          }
        }
      }

      // Update connection with new bus assignment
      final updatedConnection = existingConnection.copyWith(
        busId: busId,
        outputMode: outputMode ?? existingBus.defaultOutputMode,
        modifiedAt: DateTime.now(),
      );

      final updatedConnections = [...currentState.connections];
      updatedConnections[connectionIndex] = updatedConnection;

      // Add connection to new bus
      final newBusConnectionIds = [...existingBus.connectionIds, connectionId];
      updatedBuses[busIndex] = existingBus.copyWith(
        connectionIds: newBusConnectionIds,
        status: BusStatus.assigned,
        modifiedAt: DateTime.now(),
      );

      emit(
        currentState.copyWith(
          connections: updatedConnections,
          buses: updatedBuses,
          lastError: null,
        ),
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Remove a connection from its assigned bus
  Future<void> unassignConnectionFromBus(String connectionId) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      // Find the connection
      final connectionIndex = currentState.connections.indexWhere(
        (connection) => connection.id == connectionId,
      );

      if (connectionIndex == -1) {
        return;
      }

      final existingConnection = currentState.connections[connectionIndex];

      if (existingConnection.busId == null) {
        return;
      }

      // Update connection to remove bus assignment
      final updatedConnection = existingConnection.copyWith(
        busId: null,
        modifiedAt: DateTime.now(),
      );

      final updatedConnections = [...currentState.connections];
      updatedConnections[connectionIndex] = updatedConnection;

      // Update bus to remove connection
      final updatedBuses = currentState.buses.map((bus) {
        if (bus.id == existingConnection.busId) {
          final updatedConnectionIds = bus.connectionIds
              .where((id) => id != connectionId)
              .toList();
          return bus.copyWith(
            connectionIds: updatedConnectionIds,
            status: updatedConnectionIds.isEmpty
                ? BusStatus.available
                : BusStatus.assigned,
            modifiedAt: DateTime.now(),
          );
        }
        return bus;
      }).toList();

      emit(
        currentState.copyWith(
          connections: updatedConnections,
          buses: updatedBuses,
          lastError: null,
        ),
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Toggle output mode for a specific port
  Future<void> togglePortOutputMode({required String portId}) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    if (_distingCubit == null) {
      return;
    }

    try {
      // Find the port and its algorithm index
      final (port, algorithmIndex) = _findPortWithAlgorithmIndex(
        currentState,
        portId,
      );
      if (port == null) {
        return;
      }

      // Verify it's an output port
      if (port.direction != PortDirection.output) {
        return;
      }

      // Verify we have mode parameter information
      if (port.modeParameterNumber == null || algorithmIndex == null) {
        // For algorithms without mode parameters, we silently ignore the request
        // rather than showing an error to the user
        return;
      }

      // Get current parameter value from the actual slot data
      final distingState = _distingCubit.state;
      if (distingState is! DistingStateSynchronized) {
        return;
      }

      if (algorithmIndex >= distingState.slots.length) {
        return;
      }

      final currentSlot = distingState.slots[algorithmIndex];

      // Find the current value of the mode parameter
      final currentParamValue = currentSlot.values
          .firstWhere(
            (v) => v.parameterNumber == port.modeParameterNumber!,
            orElse: () => throw StateError(
              'Mode parameter ${port.modeParameterNumber} not found in slot',
            ),
          )
          .value;

      // Toggle the parameter value: 0=Add, 1=Replace
      final newParamValue = currentParamValue == 0 ? 1 : 0;
      newParamValue == 1 ? OutputMode.replace : OutputMode.add;

      // Update the hardware parameter via DistingCubit
      await _distingCubit.updateParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: port.modeParameterNumber!,
        value: newParamValue,
        userIsChangingTheValue: true,
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Get output mode for a specific port
  OutputMode getPortOutputMode(String portId) {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      return currentState.portOutputModes[portId] ?? OutputMode.replace;
    }
    return OutputMode.replace;
  }

  /// Current algorithm ids in slot order (ascending index).
  List<String> _currentAlgorithmOrder(RoutingEditorStateLoaded st) {
    final algos = List<RoutingAlgorithm>.from(st.algorithms)
      ..sort((a, b) => a.index.compareTo(b.index));
    return algos.map((a) => a.id).toList();
  }

  String _describeReorder(
    RoutingEditorStateLoaded st,
    List<String> before,
    List<String> after,
  ) {
    final names = {for (final a in st.algorithms) a.id: a.algorithm.name};
    final beforePos = {for (var i = 0; i < before.length; i++) before[i]: i};
    final afterPos = {for (var i = 0; i < after.length; i++) after[i]: i};
    String? movedId;
    int bestDelta = 0;
    for (final id in before) {
      final delta = (afterPos[id] ?? 0) - (beforePos[id] ?? 0);
      if (delta.abs() > bestDelta.abs()) {
        bestDelta = delta;
        movedId = id;
      }
    }
    if (movedId == null || bestDelta == 0) return 'Reordered algorithms';
    final dir = bestDelta > 0 ? 'down' : 'up';
    return "Moved '${names[movedId] ?? movedId}' $dir to keep signal flowing";
  }

  /// Reorders algorithm slots to match [targetOrder] using adjacent swaps.
  ///
  /// Returns a [ReorderResult] whose `previousOrder` can be passed back to
  /// [applyReorder] to undo the change.
  Future<ReorderResult> applyReorder(List<String> targetOrder) async {
    final st = state;
    if (st is! RoutingEditorStateLoaded || _distingCubit == null) {
      return const ReorderResult(
        previousOrder: [],
        newOrder: [],
        description: '',
        changed: false,
      );
    }

    final currentOrder = _currentAlgorithmOrder(st);
    final steps = SlotReorderPlanner.planSwaps(currentOrder, targetOrder);
    if (steps.isEmpty) {
      return ReorderResult(
        previousOrder: currentOrder,
        newOrder: currentOrder,
        description: '',
        changed: false,
      );
    }

    for (final step in steps) {
      if (step.direction == SwapDirection.up) {
        await _distingCubit.moveAlgorithmUp(step.index);
      } else {
        await _distingCubit.moveAlgorithmDown(step.index);
      }
    }

    return ReorderResult(
      previousOrder: currentOrder,
      newOrder: targetOrder,
      description: _describeReorder(st, currentOrder, targetOrder),
      changed: true,
    );
  }

  /// Computes a valid slot order from the current bus connections and applies
  /// it. Returns the [ReorderResult] when a move happened, otherwise null.
  Future<ReorderResult?> autoSolveFlow() async {
    final st = state;
    if (st is! RoutingEditorStateLoaded) return null;
    final solution = BusFlowSolver.fromAlgorithms(
      st.algorithms,
      deviceIoProfile: st.deviceIoProfile,
    ).solve();
    if (!solution.reorderNeeded) return null;
    final result = await applyReorder(solution.order);
    return result.changed ? result : null;
  }

  /// Writes a bus number to a port's bus-assignment parameter.
  Future<void> setPortBus({
    required int algorithmIndex,
    required int parameterNumber,
    required int busValue,
  }) async {
    if (_distingCubit == null) return;
    await _distingCubit.updateParameterValue(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      value: busValue,
      userIsChangingTheValue: true,
    );
  }

  String _channelPrefix(String? busParam) {
    if (busParam == null) return '';
    final colon = busParam.indexOf(':');
    return colon >= 0 ? busParam.substring(0, colon + 1) : '';
  }

  int? _parameterValue(Slot slot, int parameterNumber) {
    for (final value in slot.values) {
      if (value.parameterNumber == parameterNumber) return value.value;
    }
    return null;
  }

  int? _matchingConditionalInPlaceInputBus({
    required Slot slot,
    required int outputParameterNumber,
  }) {
    if (!core_routing.AlgorithmRouting.isConditionalInPlaceGuid(
      slot.algorithm.guid,
    )) {
      return null;
    }

    ParameterInfo? outputParam;
    for (final param in slot.parameters) {
      if (param.parameterNumber == outputParameterNumber) {
        outputParam = param;
        break;
      }
    }
    if (outputParam == null || !outputParam.isOutput) return null;

    final prefix = _channelPrefix(outputParam.name);
    for (final inputParam in slot.parameters) {
      final isInput =
          inputParam.isInput ||
          core_routing.AlgorithmRouting.isHardcodedInput(
            slot.algorithm.guid,
            inputParam.name,
          );
      if (!isInput) continue;
      if (_channelPrefix(inputParam.name) != prefix) continue;

      final inputBus =
          _parameterValue(slot, inputParam.parameterNumber) ??
          inputParam.defaultValue;
      return inputBus > 0 ? inputBus : null;
    }

    return null;
  }

  ({int previousBusValue, int busValue})
  _normalizeConditionalInPlaceAssignment({
    required int algorithmIndex,
    required int parameterNumber,
    required int previousBusValue,
    required int busValue,
  }) {
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized ||
        algorithmIndex < 0 ||
        algorithmIndex >= distingState.slots.length) {
      return (previousBusValue: previousBusValue, busValue: busValue);
    }

    final slot = distingState.slots[algorithmIndex];
    final matchingInputBus = _matchingConditionalInPlaceInputBus(
      slot: slot,
      outputParameterNumber: parameterNumber,
    );
    if (matchingInputBus == null) {
      return (previousBusValue: previousBusValue, busValue: busValue);
    }

    final literalPrevious =
        _parameterValue(slot, parameterNumber) ?? previousBusValue;
    int normalize(int value) => value == matchingInputBus ? 0 : value;

    return (
      previousBusValue: normalize(literalPrevious),
      busValue: normalize(busValue),
    );
  }

  /// Assigns [busValue] to a port's bus parameter.
  /// Does NOT auto-reorder algorithms — use [autoSolveFlow] explicitly for that.
  /// The returned [BusAssignmentResult] can be passed to [undoBusAssignment]
  /// to revert the bus assignment.
  Future<BusAssignmentResult> assignBusAndSolve({
    required int algorithmIndex,
    required int parameterNumber,
    required int previousBusValue,
    required int busValue,
  }) async {
    final clampedBusValue = _clampBusAssignment(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      busValue: busValue,
    );
    final normalized = _normalizeConditionalInPlaceAssignment(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      previousBusValue: previousBusValue,
      busValue: clampedBusValue,
    );

    await setPortBus(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      busValue: normalized.busValue,
    );

    return BusAssignmentResult(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      previousBusValue: normalized.previousBusValue,
      newBusValue: normalized.busValue,
      reorder: null,
    );
  }

  int _clampBusAssignment({
    required int algorithmIndex,
    required int parameterNumber,
    required int busValue,
  }) {
    final state = _distingCubit?.state;
    if (state is! DistingStateSynchronized) return busValue;
    final range = busParameterRange(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
    );
    if (range == null) return busValue;
    final isUsbFromHost =
        algorithmIndex >= 0 &&
        algorithmIndex < state.slots.length &&
        state.slots[algorithmIndex].algorithm.guid == 'usbf';
    final clamped = state.deviceIoProfile.clampBusToRange(
      busValue,
      minimum: range.min,
      maximum: range.max,
      allowNone: range.min <= 0,
      includeContextualEs5: isUsbFromHost,
    );
    if (clamped == null) {
      throw StateError(
        'Parameter $parameterNumber in slot $algorithmIndex has no selectable buses',
      );
    }
    return clamped;
  }

  /// Reverts a previous [assignBusAndSolve]: restores the bus value, then the
  /// prior slot order.
  Future<void> undoBusAssignment(BusAssignmentResult result) async {
    await setPortBus(
      algorithmIndex: result.algorithmIndex,
      parameterNumber: result.parameterNumber,
      busValue: result.previousBusValue,
    );
    final reorder = result.reorder;
    if (reorder != null && reorder.changed) {
      await applyReorder(reorder.previousOrder);
    }
  }

  /// Update bus properties
  Future<void> updateBus({
    required String busId,
    String? name,
    OutputMode? defaultOutputMode,
    double? masterGain,
  }) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      final busIndex = currentState.buses.indexWhere((bus) => bus.id == busId);

      if (busIndex == -1) {
        return;
      }

      final existingBus = currentState.buses[busIndex];
      final updatedBus = existingBus.copyWith(
        name: name ?? existingBus.name,
        defaultOutputMode: defaultOutputMode ?? existingBus.defaultOutputMode,
        masterGain: masterGain ?? existingBus.masterGain,
        modifiedAt: DateTime.now(),
      );

      final updatedBuses = [...currentState.buses];
      updatedBuses[busIndex] = updatedBus;

      emit(currentState.copyWith(buses: updatedBuses, lastError: null));
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Get all connections assigned to a specific bus
  List<Connection> getConnectionsForBus(String busId) {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      return currentState.connections
          .where((connection) => connection.busId == busId)
          .toList();
    }
    return [];
  }

  /// Get bus by ID
  RoutingBus? getBusById(String busId) {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      try {
        return currentState.buses.firstWhere((bus) => bus.id == busId);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Initialize default routing buses
  Future<void> initializeDefaultBuses() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    try {
      final defaultBuses = [
        RoutingBus(
          id: 'bus_audio_main',
          name: 'Audio Main',
          status: BusStatus.available,
          defaultOutputMode: OutputMode.add,
          masterGain: 1.0,
          createdAt: DateTime.now(),
        ),
        RoutingBus(
          id: 'bus_cv_main',
          name: 'CV Main',
          status: BusStatus.available,
          defaultOutputMode: OutputMode.replace,
          masterGain: 1.0,
          createdAt: DateTime.now(),
        ),
        RoutingBus(
          id: 'bus_gate_main',
          name: 'Gate/Trigger Main',
          status: BusStatus.available,
          defaultOutputMode: OutputMode.replace,
          masterGain: 1.0,
          createdAt: DateTime.now(),
        ),
      ];

      // Add default buses if they don't already exist
      final existingBusIds = currentState.buses.map((bus) => bus.id).toSet();
      final newBuses = defaultBuses
          .where((bus) => !existingBusIds.contains(bus.id))
          .toList();

      if (newBuses.isNotEmpty) {
        final updatedBuses = [...currentState.buses, ...newBuses];

        emit(currentState.copyWith(buses: updatedBuses, lastError: null));
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Sync the current routing editor state with hardware
  Future<void> syncToHardware() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    emit(currentState.copyWith(subState: SubState.syncing));

    try {
      // Update sync status
      final syncTime = DateTime.now();

      emit(
        currentState.copyWith(
          isHardwareSynced: true,
          lastSyncTime: syncTime,
          lastError: null,
        ),
      );
    } catch (e) {
      emit(
        currentState.copyWith(
          subState: SubState.error,
          lastError: e.toString(),
        ),
      );
    }
  }

  /// Sync hardware routing data to the routing editor state
  Future<void> syncFromHardware() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    emit(currentState.copyWith(subState: SubState.syncing));

    try {
      // Trigger hardware routing refresh through DistingCubit
      await _distingCubit?.refreshRouting();

      // The state will be updated through the stream subscription
      // when _processSynchronizedState is called
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Check if hardware sync is required
  bool isHardwareSyncRequired() {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return false;
    }

    return !currentState.isHardwareSynced;
  }

  /// Mark hardware as out of sync (called when local changes are made)
  void markHardwareOutOfSync() {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded &&
        currentState.isHardwareSynced) {
      emit(currentState.copyWith(isHardwareSynced: false, lastError: null));
    }
  }

  /// Auto-sync to hardware when changes are made (if enabled)
  Future<void> _autoSyncToHardware() async {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      // Mark as out of sync first
      markHardwareOutOfSync();

      // Auto-save state after changes
      await _autoSaveState();

      // Auto-sync could be enabled/disabled via a setting
      // For now, we'll just mark as out of sync and let the user manually sync
    }
  }

  /// Get hardware sync status information
  Map<String, dynamic> getHardwareSyncStatus() {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      return {
        'isHardwareSynced': currentState.isHardwareSynced,
        'lastSyncTime': currentState.lastSyncTime?.toIso8601String(),
        'connectionCount': currentState.connections.length,
        'busCount': currentState.buses.length,
      };
    }
    return {
      'isHardwareSynced': false,
      'lastSyncTime': null,
      'connectionCount': 0,
      'busCount': 0,
    };
  }

  /// Refresh routing data from hardware
  Future<void> refreshRouting() async {
    if (state is RoutingEditorStateLoaded) {
      emit(
        (state as RoutingEditorStateLoaded).copyWith(
          subState: SubState.refreshing,
        ),
      );
    }

    try {
      await _distingCubit?.refreshRouting();
      // State will be updated through the stream subscription
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Clear the current routing state
  void clearRouting() {
    emit(const RoutingEditorState.initial());
  }

  /// Save current routing editor state to persistent storage
  Future<void> saveState() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    emit(currentState.copyWith(subState: SubState.persisting));

    try {
      if (_prefs == null) {
        return;
      }
      final prefs = await _prefs!;

      // Prepare state data for serialization
      final stateData = {
        'connections': currentState.connections
            .map(
              (connection) => {
                'id': connection.id,
                'sourcePortId': connection.sourcePortId,
                'targetPortId': connection.destinationPortId,
                'busId': connection.busId,
                'outputMode': connection.outputMode?.name,
                'gain': connection.gain,
                'isMuted': connection.isMuted,
                'createdAt': connection.createdAt?.toIso8601String(),
                'modifiedAt': connection.modifiedAt?.toIso8601String(),
              },
            )
            .toList(),
        'buses': currentState.buses
            .map(
              (bus) => {
                'id': bus.id,
                'name': bus.name,
                'status': bus.status.name,
                'connectionIds': bus.connectionIds,
                'defaultOutputMode': bus.defaultOutputMode.name,
                'masterGain': bus.masterGain,
                'createdAt': bus.createdAt?.toIso8601String(),
                'modifiedAt': bus.modifiedAt?.toIso8601String(),
              },
            )
            .toList(),
        'portOutputModes': currentState.portOutputModes.map(
          (key, value) => MapEntry(key, value.name),
        ),
        'lastSyncTime': currentState.lastSyncTime?.toIso8601String(),
        'lastPersistTime': DateTime.now().toIso8601String(),
      };

      // Save to SharedPreferences
      final jsonString = jsonEncode(stateData);
      await prefs.setString('routing_editor_state', jsonString);

      // Update state with persistence timestamp
      final persistTime = DateTime.now();
      emit(
        currentState.copyWith(
          isPersistenceEnabled: true,
          lastPersistTime: persistTime,
          lastError: null,
        ),
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Load routing editor state from persistent storage
  Future<void> _loadPersistedState() async {
    try {
      if (_prefs == null) {
        return;
      }
      final prefs = await _prefs!;
      final jsonString = prefs.getString('routing_editor_state');

      if (jsonString == null) {
        return;
      }

      final stateData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Parse connections
      final connections = <Connection>[];
      for (final connectionData in stateData['connections'] as List) {
        final connectionMap = connectionData as Map<String, dynamic>;
        connections.add(
          Connection(
            id: connectionMap['id'] as String,
            sourcePortId: connectionMap['sourcePortId'] as String,
            destinationPortId: connectionMap['targetPortId'] as String,
            connectionType: ConnectionType.values.firstWhere(
              (type) => type.name == connectionMap['connectionType'],
              orElse: () => ConnectionType.algorithmToAlgorithm,
            ),
            outputMode: OutputMode.values.firstWhere(
              (mode) => mode.name == connectionMap['outputMode'],
              orElse: () => OutputMode.replace,
            ),
            gain: (connectionMap['gain'] as num?)?.toDouble() ?? 1.0,
            isMuted: connectionMap['isMuted'] as bool? ?? false,
            createdAt: connectionMap['createdAt'] != null
                ? DateTime.parse(connectionMap['createdAt'] as String)
                : null,
            modifiedAt: connectionMap['modifiedAt'] != null
                ? DateTime.parse(connectionMap['modifiedAt'] as String)
                : null,
          ),
        );
      }

      // Parse buses
      final buses = <RoutingBus>[];
      for (final busData in stateData['buses'] as List) {
        final busMap = busData as Map<String, dynamic>;
        buses.add(
          RoutingBus(
            id: busMap['id'] as String,
            name: busMap['name'] as String,
            status: BusStatus.values.firstWhere(
              (status) => status.name == busMap['status'],
              orElse: () => BusStatus.available,
            ),
            connectionIds: (busMap['connectionIds'] as List).cast<String>(),
            defaultOutputMode: OutputMode.values.firstWhere(
              (mode) => mode.name == busMap['defaultOutputMode'],
              orElse: () => OutputMode.replace,
            ),
            masterGain: (busMap['masterGain'] as num?)?.toDouble() ?? 1.0,
            createdAt: busMap['createdAt'] != null
                ? DateTime.parse(busMap['createdAt'] as String)
                : null,
            modifiedAt: busMap['modifiedAt'] != null
                ? DateTime.parse(busMap['modifiedAt'] as String)
                : null,
          ),
        );
      }

      // Parse port output modes
      final portOutputModes = <String, OutputMode>{};
      final portModeData =
          stateData['portOutputModes'] as Map<String, dynamic>?;
      if (portModeData != null) {
        for (final entry in portModeData.entries) {
          portOutputModes[entry.key] = OutputMode.values.firstWhere(
            (mode) => mode.name == entry.value,
            orElse: () => OutputMode.replace,
          );
        }
      }

      // Parse timestamps (kept for future use, currently unused)
      // final lastSyncTime = stateData['lastSyncTime'] != null
      //     ? DateTime.parse(stateData['lastSyncTime'] as String)
      //     : null;
      // final lastPersistTime = stateData['lastPersistTime'] != null
      //     ? DateTime.parse(stateData['lastPersistTime'] as String)
      //     : null;
    } catch (e) {
      // Don't emit error state here, just log and continue with empty state
    }
  }

  /// Clear all persisted state data
  Future<void> clearPersistedState() async {
    try {
      if (_prefs == null) {
        return;
      }
      final prefs = await _prefs!;
      await prefs.remove('routing_editor_state');

      final currentState = state;
      if (currentState is RoutingEditorStateLoaded) {
        emit(
          currentState.copyWith(
            isPersistenceEnabled: false,
            lastPersistTime: null,
            lastError: null,
          ),
        );
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Get persistence status information
  Map<String, dynamic> getPersistenceStatus() {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      return {
        'isPersistenceEnabled': currentState.isPersistenceEnabled,
        'lastPersistTime': currentState.lastPersistTime?.toIso8601String(),
        'connectionCount': currentState.connections.length,
        'busCount': currentState.buses.length,
      };
    }
    return {
      'isPersistenceEnabled': false,
      'lastPersistTime': null,
      'connectionCount': 0,
      'busCount': 0,
    };
  }

  /// Auto-save state after changes (if enabled)
  Future<void> _autoSaveState() async {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded &&
        currentState.isPersistenceEnabled) {
      await saveState();
    }
  }

  /// Enhanced error recovery method
  Future<void> recoverFromError() async {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded &&
        currentState.lastError != null) {
      try {
        // Try to reload the last known good state
        await _loadPersistedState();

        // If no persisted state, return to initial state
        emit(const RoutingEditorState.initial());
      } catch (e) {
        // Intentionally empty
      }
    }
  }

  // Connection Deletion Business Logic (UI-agnostic)

  /// Delete a connection by ID with smart bus assignment logic
  /// This method handles the core business logic for connection deletion
  /// including bus clearing for different connection types
  Future<void> deleteConnectionWithSmartBusLogic(String connectionId) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    try {
      // Validate connection exists
      if (!currentState.connections.any((conn) => conn.id == connectionId)) {
        throw ArgumentError('Connection not found: $connectionId');
      }

      // Get connection details before deletion
      currentState.connections.firstWhere((conn) => conn.id == connectionId);

      // This just calls deleteConnection which already handles clearing bus assignments
      await deleteConnection(connectionId);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Clear bus assignments for a connection by setting parameter values to 0
  Future<void> _clearBusAssignmentsForConnection(
    Connection connection,
    RoutingEditorStateLoaded state,
  ) async {
    if (_distingCubit == null) return;

    try {
      // Find the source and destination ports
      final sourcePort = _findPortById(state, connection.sourcePortId);
      final targetPort = _findPortById(state, connection.destinationPortId);

      if (sourcePort == null || targetPort == null) {
        return;
      }

      // Clear both sides of the connection if possible.
      // Physical ports (hw_in/hw_out/es5) don't have parameters to clear.
      await _clearAlgorithmPortBus(sourcePort, state);
      await _clearAlgorithmPortBus(targetPort, state);
    } catch (e) {
      // Don't rethrow - we still want to delete the connection from UI
    }
  }

  /// Clear the bus assignment for an algorithm port, setting it to 0 (None)
  /// if the parameter supports it. Skips physical/ES-5 ports.
  Future<void> _clearAlgorithmPortBus(
    Port port,
    RoutingEditorStateLoaded state,
  ) async {
    if (_distingCubit == null) return;
    if (port.parameterNumber == null) return;
    if (port.isBus) return; // Physical/ES-5 ports don't have parameters

    for (final algorithm in state.algorithms) {
      final match = [
        ...algorithm.inputPorts,
        ...algorithm.outputPorts,
      ].where((p) => p.id == port.id && p.parameterNumber != null).firstOrNull;
      if (match == null) continue;

      if (!_canClearBusAssignment(
        algorithmIndex: algorithm.index,
        parameterNumber: match.parameterNumber!,
      )) {
        // Output can't be set to None — move to an unused non-physical bus
        if (port.isBusWriter) {
          final newBus = await _findFirstAvailableNonPhysicalOutputBus(
            state,
            algorithmIndex: algorithm.index,
            parameterNumber: match.parameterNumber!,
            needsStereoPartner:
                port.isStereoChannel && port.stereoSide == 'left',
          );
          if (newBus != null) {
            await _distingCubit.updateParameterValue(
              algorithmIndex: algorithm.index,
              parameterNumber: match.parameterNumber!,
              value: newBus,
              userIsChangingTheValue: false,
            );
          }
        }
        return;
      }

      await _distingCubit.updateParameterValue(
        algorithmIndex: algorithm.index,
        parameterNumber: match.parameterNumber!,
        value: 0,
        userIsChangingTheValue: false,
      );
      return;
    }
  }

  bool _canClearBusAssignment({
    required int algorithmIndex,
    required int parameterNumber,
  }) {
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return true;
    }
    if (algorithmIndex < 0 || algorithmIndex >= distingState.slots.length) {
      return true;
    }
    final slot = distingState.slots[algorithmIndex];
    for (final p in slot.parameters) {
      if (p.parameterNumber == parameterNumber) {
        // If min > 0, parameter doesn't support "None" (0).
        return p.min <= 0;
      }
    }
    return true;
  }

  ({int min, int max})? busParameterRange({
    required int algorithmIndex,
    required int parameterNumber,
  }) {
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return null;
    }
    if (algorithmIndex < 0 || algorithmIndex >= distingState.slots.length) {
      return null;
    }
    final slot = distingState.slots[algorithmIndex];
    for (final p in slot.parameters) {
      if (p.parameterNumber == parameterNumber) {
        return (min: p.min, max: p.max);
      }
    }
    return null;
  }

  Future<int?> _findFirstAvailableNonPhysicalOutputBus(
    RoutingEditorStateLoaded state, {
    required int algorithmIndex,
    required int parameterNumber,
    bool needsStereoPartner = false,
  }) async {
    final range = busParameterRange(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
    );
    if (range == null) return null;

    // Determine currently-used bus numbers from live hardware values.
    final distingState = _distingCubit?.state;
    if (distingState is! DistingStateSynchronized) {
      return null;
    }

    final usedBuses = <int>{};
    for (final algorithm in state.algorithms) {
      if (algorithm.index >= distingState.slots.length) continue;
      final slot = distingState.slots[algorithm.index];

      for (final port in algorithm.inputPorts) {
        final paramNumber = port.parameterNumber;
        if (paramNumber == null) continue;
        final v = slot.values
            .firstWhere(
              (pv) => pv.parameterNumber == paramNumber,
              orElse: () => ParameterValue(
                algorithmIndex: algorithm.index,
                parameterNumber: paramNumber,
                value: 0,
              ),
            )
            .value;
        if (v > 0) usedBuses.add(v);
      }

      for (final port in algorithm.outputPorts) {
        final paramNumber = port.parameterNumber;
        if (paramNumber == null) continue;
        final v = slot.values
            .firstWhere(
              (pv) => pv.parameterNumber == paramNumber,
              orElse: () => ParameterValue(
                algorithmIndex: algorithm.index,
                parameterNumber: paramNumber,
                value: 0,
              ),
            )
            .value;
        if (v > 0) usedBuses.add(v);
      }
    }

    bool inRange(int b) => b >= range.min && b <= range.max;
    final deviceIoProfile = state.deviceIoProfile;

    // Prefer auxiliary buses, then fall back to input buses, always avoiding
    // physical output buses.
    for (final b in deviceIoProfile.auxBuses) {
      if (needsStereoPartner && !deviceIoProfile.isAux(b + 1)) continue;
      if (inRange(b) && !usedBuses.contains(b)) return b;
    }
    for (final b in deviceIoProfile.inputBuses) {
      if (inRange(b) && !usedBuses.contains(b)) return b;
    }

    // As a last resort, scan the parameter's allowed range for any unused bus
    // that isn't a physical output bus.
    for (int b = range.min; b <= range.max; b++) {
      if (!deviceIoProfile.contains(b) || deviceIoProfile.isOutput(b)) continue;
      if (!usedBuses.contains(b)) return b;
    }

    return null;
  }

  /// Inject the layout algorithm service
  void injectLayoutAlgorithm(NodeLayoutAlgorithm layoutAlgorithm) {
    if (_layoutAlgorithm != null) {
      throw StateError('Layout algorithm service already injected');
    }
    _layoutAlgorithm = layoutAlgorithm;
  }

  /// Apply the layout algorithm to optimize node positions
  /// If nodes are focused, applies cascade layout to just those nodes
  Future<void> applyLayoutAlgorithm() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) {
      return;
    }

    // If nodes are focused, apply cascade layout to just those nodes
    if (currentState.focusedAlgorithmIds.isNotEmpty) {
      await _applyCascadeLayout(currentState);
      return;
    }

    // Full layout algorithm for all nodes
    _layoutAlgorithm ??= NodeLayoutAlgorithm();

    try {
      // Show loading state
      emit(currentState.copyWith(subState: SubState.syncing));

      // Calculate optimal layout using the algorithm
      final layoutResult = _layoutAlgorithm!.calculateLayout(
        physicalInputs: currentState.physicalInputs,
        physicalOutputs: currentState.physicalOutputs,
        es5Inputs: currentState.es5Inputs,
        algorithms: currentState.algorithms,
        connections: currentState.connections,
      );

      // Merge existing node positions with new calculated positions
      // This preserves any custom-positioned nodes not managed by the layout algorithm
      final updatedNodePositions = Map<String, NodePosition>.from(
        currentState.nodePositions,
      );

      // Update physical input positions
      updatedNodePositions.addAll(layoutResult.physicalInputPositions);

      // Update physical output positions
      updatedNodePositions.addAll(layoutResult.physicalOutputPositions);

      // Update ES-5 input positions
      updatedNodePositions.addAll(layoutResult.es5InputPositions);

      // Update algorithm positions
      updatedNodePositions.addAll(layoutResult.algorithmPositions);

      // Emit updated state with new positions
      emit(
        currentState.copyWith(
          nodePositions: updatedNodePositions,
          subState: SubState.idle,
          lastError: null,
        ),
      );

      // Save the new positions to preferences
      await saveNodePositions();
    } catch (e) {
      emit(
        currentState.copyWith(
          subState: SubState.error,
          lastError: 'Layout calculation failed: $e',
        ),
      );
    }
  }

  /// Apply cascade layout to focused nodes only
  /// Arranges nodes in a diagonal stair-step pattern (down-right), sorted by slot
  Future<void> _applyCascadeLayout(
    RoutingEditorStateLoaded currentState,
  ) async {
    final focusedIds = currentState.focusedAlgorithmIds;

    // Find centroid of focused nodes using node centers (not left edges)
    // This ensures applying cascade multiple times doesn't drift
    final focusedPositions = currentState.nodePositions.entries
        .where((e) => focusedIds.contains(e.key))
        .toList();

    if (focusedPositions.isEmpty) return;

    double sumX = 0, sumY = 0;
    for (final pos in focusedPositions) {
      // Use center of node for centroid calculation
      sumX += pos.value.x + pos.value.width / 2;
      sumY += pos.value.y + pos.value.height / 2;
    }
    final centroidX = sumX / focusedPositions.length;
    final centroidY = sumY / focusedPositions.length;

    // Sort focused algorithms by slot number (lower slots first)
    final sortedFocused =
        currentState.algorithms.where((a) => focusedIds.contains(a.id)).toList()
          ..sort((a, b) => a.index.compareTo(b.index));

    // Gap between right edge of one node and left edge of next (2 grid squares)
    const horizontalGap = 100.0;
    const verticalOffset = 100.0;

    final updatedPositions = Map<String, NodePosition>.from(
      currentState.nodePositions,
    );

    // First pass: position nodes starting at x=0, y=0 to build cascade shape
    final tempPositions = <String, (double x, double y, double w, double h)>{};
    double currentX = 0;
    for (int i = 0; i < sortedFocused.length; i++) {
      final algoId = sortedFocused[i].id;
      final existingPos = currentState.nodePositions[algoId];
      final nodeWidth = existingPos?.width ?? 200.0;
      final nodeHeight = existingPos?.height ?? 100.0;

      tempPositions[algoId] = (
        currentX,
        i * verticalOffset,
        nodeWidth,
        nodeHeight,
      );
      currentX += nodeWidth + horizontalGap;
    }

    // Calculate the average center of the cascade at origin
    double sumCascadeCenterX = 0, sumCascadeCenterY = 0;
    for (final entry in tempPositions.entries) {
      final (x, y, w, h) = entry.value;
      sumCascadeCenterX += x + w / 2;
      sumCascadeCenterY += y + h / 2;
    }
    final cascadeCenterX = sumCascadeCenterX / tempPositions.length;
    final cascadeCenterY = sumCascadeCenterY / tempPositions.length;

    // Calculate offset to move cascade center to original centroid
    final offsetX = centroidX - cascadeCenterX;
    final offsetY = centroidY - cascadeCenterY;

    // Apply offset to all node positions
    for (final entry in tempPositions.entries) {
      final (x, y, w, h) = entry.value;
      updatedPositions[entry.key] = NodePosition(
        x: x + offsetX,
        y: y + offsetY,
        width: w,
        height: h,
      );
    }

    emit(
      currentState.copyWith(
        nodePositions: updatedPositions,
        cascadeScrollTarget: Offset(centroidX, centroidY),
      ),
    );
    await saveNodePositions();
  }

  /// Save node positions to SharedPreferences for the current preset
  Future<void> saveNodePositions() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final distingState = _distingCubit?.state;
    if (distingState == null) return;

    // Get preset name from synchronized state directly
    if (distingState is! DistingStateSynchronized) return;
    final presetName = distingState.presetName;
    if (presetName.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'routing_positions_$presetName';

      // Convert NodePosition map to JSON-serializable format
      final positionsMap = <String, Map<String, double>>{};
      for (final entry in currentState.nodePositions.entries) {
        positionsMap[entry.key] = {'x': entry.value.x, 'y': entry.value.y};
      }
      positionsMap['_viewport'] = {
        'scrollH': currentState.panOffset.dx,
        'scrollV': currentState.panOffset.dy,
        'zoom': currentState.zoomLevel,
      };

      final json = jsonEncode(positionsMap);
      await prefs.setString(key, json);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Load node positions from SharedPreferences for the current preset
  Future<void> loadNodePositions() async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final distingState = _distingCubit?.state;
    if (distingState == null) return;

    if (distingState is! DistingStateSynchronized) return;
    final presetName = distingState.presetName;
    if (presetName.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'routing_positions_$presetName';
      final json = prefs.getString(key);

      if (json != null) {
        final positionsMap = jsonDecode(json) as Map<String, dynamic>;

        // Extract viewport state before processing node positions
        final viewportData = positionsMap['_viewport'] as Map<String, dynamic>?;
        final scrollH = (viewportData?['scrollH'] as num?)?.toDouble() ?? 0.0;
        final scrollV = (viewportData?['scrollV'] as num?)?.toDouble() ?? 0.0;
        final zoom = (viewportData?['zoom'] as num?)?.toDouble() ?? 1.0;

        final nodePositions = <String, NodePosition>{};
        for (final entry in positionsMap.entries) {
          if (entry.key == '_viewport') continue;
          final pos = entry.value as Map<String, dynamic>;
          nodePositions[entry.key] = NodePosition(
            x: (pos['x'] as num).toDouble(),
            y: (pos['y'] as num).toDouble(),
          );
        }

        emit(
          currentState.copyWith(
            nodePositions: nodePositions,
            panOffset: Offset(scrollH, scrollV),
            zoomLevel: zoom,
          ),
        );
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Update a single node position and save to preferences
  Future<void> updateNodePosition(String nodeId, double x, double y) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final updatedPositions = Map<String, NodePosition>.from(
      currentState.nodePositions,
    );
    updatedPositions[nodeId] = NodePosition(x: x, y: y);

    emit(currentState.copyWith(nodePositions: updatedPositions));

    // Save positions after update
    await saveNodePositions();
  }

  /// Update multiple node positions at once (for multi-drag)
  Future<void> updateMultipleNodePositions(Map<String, Offset> updates) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final updatedPositions = Map<String, NodePosition>.from(
      currentState.nodePositions,
    );
    for (final entry in updates.entries) {
      updatedPositions[entry.key] = NodePosition(
        x: entry.value.dx,
        y: entry.value.dy,
      );
    }

    emit(currentState.copyWith(nodePositions: updatedPositions));

    // Save positions after update
    await saveNodePositions();
  }

  /// Update a node's size (called when widget reports its actual rendered size)
  void updateNodeSize(String nodeId, double width, double height) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final existingPos = currentState.nodePositions[nodeId];
    if (existingPos == null) return;

    // Only update if size actually changed
    if (existingPos.width == width && existingPos.height == height) return;

    final updatedPositions = Map<String, NodePosition>.from(
      currentState.nodePositions,
    );
    updatedPositions[nodeId] = existingPos.copyWith(
      width: width,
      height: height,
    );

    emit(currentState.copyWith(nodePositions: updatedPositions));
  }

  /// Update zoom level with bounds checking
  void setZoomLevel(double zoomLevel) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    // Clamp zoom level between 0.1x and 2.0x
    final clampedZoom = zoomLevel.clamp(0.1, 2.0);

    emit(currentState.copyWith(zoomLevel: clampedZoom));
    saveNodePositions();
  }

  /// Zoom in by a factor
  void zoomIn([double factor = 1.2]) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    setZoomLevel(currentState.zoomLevel * factor);
  }

  /// Zoom out by a factor
  void zoomOut([double factor = 1.2]) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    setZoomLevel(currentState.zoomLevel / factor);
  }

  /// Reset zoom to 100%
  void resetZoom() {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    emit(currentState.copyWith(zoomLevel: 1.0));
  }

  /// Update viewport scroll position and persist alongside node positions
  Future<void> updateViewport(Offset scrollOffset) async {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    emit(currentState.copyWith(panOffset: scrollOffset));
    await saveNodePositions();
  }

  /// Get available zoom levels for dropdown
  static List<double> get availableZoomLevels => [
    0.25,
    0.33,
    0.5,
    0.67,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// Get zoom percentage as integer
  int get zoomPercentage {
    final currentState = state;
    if (currentState is RoutingEditorStateLoaded) {
      return (currentState.zoomLevel * 100).round();
    }
    return 100;
  }

  // Focus Mode Methods

  /// Toggle focus on an algorithm (add/remove from focused set)
  void toggleAlgorithmFocus(String algorithmId) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final updatedFocused = Set<String>.from(currentState.focusedAlgorithmIds);
    if (updatedFocused.contains(algorithmId)) {
      updatedFocused.remove(algorithmId);
    } else {
      updatedFocused.add(algorithmId);
    }

    emit(currentState.copyWith(focusedAlgorithmIds: updatedFocused));
  }

  /// Set focus to exactly one algorithm (replaces current focus set)
  void setFocusedAlgorithm(String algorithmId) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    Offset? scrollTarget;
    if (SettingsService().autoCenterOnSelection) {
      final nodePos = currentState.nodePositions[algorithmId];
      scrollTarget = nodePos != null
          ? Offset(
              nodePos.x + nodePos.width / 2,
              nodePos.y + nodePos.height / 2,
            )
          : null;
    }

    emit(
      currentState.copyWith(
        focusedAlgorithmIds: {algorithmId},
        cascadeScrollTarget: scrollTarget,
      ),
    );
  }

  /// Set focus by slot index - finds the algorithm at that slot and focuses it
  void setFocusedAlgorithmBySlotIndex(int slotIndex) {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    final algorithm = currentState.algorithms
        .where((a) => a.index == slotIndex)
        .firstOrNull;
    if (algorithm != null) {
      setFocusedAlgorithm(algorithm.id);
    }
  }

  /// Clear all focused algorithms (exit focus mode)
  void clearFocus() {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    if (currentState.focusedAlgorithmIds.isNotEmpty) {
      emit(currentState.copyWith(focusedAlgorithmIds: const {}));
    }
  }

  /// Check if focus mode is active (any algorithms focused)
  bool get isFocusModeActive {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return false;
    return currentState.focusedAlgorithmIds.isNotEmpty;
  }

  /// Clear the cascade scroll target (called after scrolling is complete)
  void clearCascadeScrollTarget() {
    final currentState = state;
    if (currentState is! RoutingEditorStateLoaded) return;

    if (currentState.cascadeScrollTarget != null) {
      emit(currentState.copyWith(cascadeScrollTarget: null));
    }
  }

  @override
  Future<void> close() {
    _distingStateSubscription?.cancel();
    _lastProcessedSlots = null;
    return super.close();
  }
}

class ConsolidationStep {
  final int algorithmIndex;
  final String algorithmName;
  final int parameterNumber;
  final int fromBus;
  final int toBus;

  const ConsolidationStep({
    required this.algorithmIndex,
    required this.algorithmName,
    required this.parameterNumber,
    required this.fromBus,
    required this.toBus,
  });
}

class ReplaceModeStep {
  final int algorithmIndex;
  final String algorithmName;
  final int parameterNumber;

  const ReplaceModeStep({
    required this.algorithmIndex,
    required this.algorithmName,
    required this.parameterNumber,
  });
}

class ConsolidationMerge {
  final int keepBus;
  final int freeBus;
  final String description;
  final List<ConsolidationStep> steps;
  final List<ReplaceModeStep> replaceModeSteps;

  const ConsolidationMerge({
    required this.keepBus,
    required this.freeBus,
    required this.description,
    required this.steps,
    this.replaceModeSteps = const [],
  });

  bool get hasReplaceModeStep => replaceModeSteps.isNotEmpty;
}

class AuxBusConsolidationPlan {
  final String description;
  final List<ConsolidationMerge> merges;

  const AuxBusConsolidationPlan({
    required this.description,
    required this.merges,
  });
}

/// Result from [_findAvailableAuxBus].
class _AvailableAuxBus {
  final int bus;
  final bool isReused;
  const _AvailableAuxBus({required this.bus, required this.isReused});
}
