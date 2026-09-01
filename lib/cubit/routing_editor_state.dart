import 'dart:ui' show Offset;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/node_layout_algorithm.dart';
import 'package:nt_helper/models/device_io_profile.dart';

part 'routing_editor_state.freezed.dart';

/// Holds per-bus usage data for AUX bus visualization.
class AuxBusUsageInfo {
  final int busNumber;
  final Set<String> algorithmIds;
  final List<String> sourceNames;
  final List<String> destNames;

  AuxBusUsageInfo({
    required this.busNumber,
    Set<String>? algorithmIds,
    List<String>? sourceNames,
    List<String>? destNames,
  }) : algorithmIds = algorithmIds ?? {},
       sourceNames = sourceNames ?? [],
       destNames = destNames ?? [];

  int get sessionCount => algorithmIds.length;
}

/// Represents status of a routing bus
enum BusStatus {
  /// Bus is available for assignment
  available,

  /// Bus is assigned and active
  assigned,

  /// Bus has an error
  error,
}

enum SubState { refreshing, persisting, syncing, error, idle }

/// Represents a routing bus for signal distribution
@freezed
sealed class RoutingBus with _$RoutingBus {
  const factory RoutingBus({
    required String id,
    required String name,
    required BusStatus status,
    @Default([]) List<String> connectionIds,
    @Default(OutputMode.replace) OutputMode defaultOutputMode,
    @Default(1.0) double masterGain,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) = _RoutingBus;
}

/// Represents an algorithm with its routing ports
@freezed
sealed class RoutingAlgorithm with _$RoutingAlgorithm {
  const factory RoutingAlgorithm({
    /// Stable unique identifier for this algorithm instance
    required String id,

    /// Current slot index (0-7), can change when algorithms are reordered
    required int index,

    /// The algorithm definition
    required Algorithm algorithm,

    /// Input ports for this algorithm
    required List<Port> inputPorts,

    /// Output ports for this algorithm
    required List<Port> outputPorts,
  }) = _RoutingAlgorithm;
}

/// State of the routing editor
@freezed
sealed class RoutingEditorState with _$RoutingEditorState {
  /// Initial state when routing editor is first created
  const factory RoutingEditorState.initial() = RoutingEditorStateInitial;

  /// State when hardware is disconnected
  const factory RoutingEditorState.disconnected() =
      RoutingEditorStateDisconnected;

  /// State when routing data is loaded and ready for visualization
  const factory RoutingEditorState.loaded({
    @Default(DeviceIoProfile.distingExtended) DeviceIoProfile deviceIoProfile,
    required List<Port> physicalInputs, // 12 physical input ports
    required List<Port> physicalOutputs, // 8 physical output ports
    @Default([])
    List<Port> es5Inputs, // ES-5 expander input ports (conditional)
    required List<RoutingAlgorithm> algorithms, // Algorithms with their ports
    required List<Connection> connections, // All routing connections
    @Default([]) List<RoutingBus> buses, // Available routing buses
    @Default({})
    Map<String, OutputMode> portOutputModes, // Output modes per port
    @Default({})
    Map<String, NodePosition> nodePositions, // Node positions for layout
    @Default(1.0) double zoomLevel, // Current zoom level (1.0 = 100%)
    @Default(Offset.zero) Offset panOffset, // Current pan offset
    @Default(false) bool isHardwareSynced, // Hardware sync status
    @Default(false) bool isPersistenceEnabled, // State persistence status
    DateTime? lastSyncTime, // Last hardware sync timestamp
    DateTime? lastPersistTime, // Last persistence save timestamp
    String? lastError, // Last error message
    @Default(SubState.idle) SubState subState, // Current sub-state
    @Default({})
    Set<String> focusedAlgorithmIds, // IDs of algorithms in focus mode
    Offset?
    cascadeScrollTarget, // Target position to scroll to after cascade layout
    @Default({})
    Map<int, AuxBusUsageInfo> auxBusUsage, // Per-AUX-bus usage info
    @Default(false) bool hasExtendedAuxBuses, // Firmware 1.15+ extended AUX
  }) = RoutingEditorStateLoaded;
}
