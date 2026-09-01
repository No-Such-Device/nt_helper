import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/routing/bus_label_formatter.dart';
import 'package:nt_helper/models/device_io_profile.dart';

part 'connection.freezed.dart';
part 'connection.g.dart';

@freezed
sealed class Connection with _$Connection {
  const factory Connection({
    required String id,
    required int sourceAlgorithmIndex,
    required String sourcePortId,
    required int targetAlgorithmIndex,
    required String targetPortId,
    required int assignedBus, // Bus number (1-28)
    required bool replaceMode, // true = Replace, false = Add
    @Default(false) bool isValid,
    String? edgeLabel, // e.g., "A1", "O3 R", "I2"
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}

extension ConnectionHelpers on Connection {
  // Helper to generate edge label
  String getEdgeLabel({
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    final label = BusLabelFormatter.formatBusLabelWithMode(
      assignedBus,
      replaceMode ? OutputMode.replace : OutputMode.add,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: deviceIoProfile,
    );
    return label ?? 'Bus$assignedBus';
  }

  /// Check if this connection violates execution order
  /// Source must come before target in slot order for signal flow to work
  /// (Disting NT processes algorithms in slot order)
  /// Physical nodes are exempt from execution order constraints
  bool get violatesExecutionOrder {
    // Physical nodes don't have execution order constraints
    if (isPhysicalInput || isPhysicalOutput) {
      return false;
    }

    // Algorithm connections via buses are valid in both directions
    // Only self-connections are invalid
    return sourceAlgorithmIndex == targetAlgorithmIndex;
  }

  /// Check if this connection involves a physical input node (algorithmIndex -2)
  bool get isPhysicalInput =>
      sourceAlgorithmIndex == -2 || targetAlgorithmIndex == -2;

  /// Check if this connection involves a physical output node (algorithmIndex -3)
  bool get isPhysicalOutput =>
      sourceAlgorithmIndex == -3 || targetAlgorithmIndex == -3;

  /// Check if this is a physical I/O connection (involves either physical input or output)
  bool get isPhysicalIO => isPhysicalInput || isPhysicalOutput;

  /// Check if source is a physical input node
  bool get sourceIsPhysicalInput => sourceAlgorithmIndex == -2;

  /// Check if source is a physical output node
  bool get sourceIsPhysicalOutput => sourceAlgorithmIndex == -3;

  /// Check if target is a physical input node
  bool get targetIsPhysicalInput => targetAlgorithmIndex == -2;

  /// Check if target is a physical output node
  bool get targetIsPhysicalOutput => targetAlgorithmIndex == -3;

  /// Get a human-readable description of the connection
  String get description {
    final sourceDesc = sourceIsPhysicalInput
        ? 'Physical Input $sourcePortId'
        : sourceIsPhysicalOutput
        ? 'Physical Output $sourcePortId'
        : 'Algorithm $sourceAlgorithmIndex:$sourcePortId';

    final targetDesc = targetIsPhysicalInput
        ? 'Physical Input $targetPortId'
        : targetIsPhysicalOutput
        ? 'Physical Output $targetPortId'
        : 'Algorithm $targetAlgorithmIndex:$targetPortId';

    return '$sourceDesc → $targetDesc';
  }
}
