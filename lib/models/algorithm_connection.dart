import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/bus_label_formatter.dart';

part 'algorithm_connection.freezed.dart';
part 'algorithm_connection.g.dart';

/// Represents a connection between two algorithm slots in the Disting NT.
///
/// An AlgorithmConnection describes how the output of one algorithm feeds
/// into the input of another algorithm through the internal bus system.
/// This is distinct from physical connections (hardware I/O) and virtual
/// connections in the routing editor UI.
///
/// These connections are discovered by analyzing parameter values across
/// algorithm slots to identify when one algorithm's output is configured
/// to feed another algorithm's input via the same bus number.
///
/// Example:
/// ```dart
/// final connection = AlgorithmConnection(
///   id: 'alg_0_out->alg_1_in_bus_5',
///   sourceAlgorithmIndex: 0,
///   sourcePortId: 'main_output',
///   targetAlgorithmIndex: 1,
///   targetPortId: 'audio_input',
///   busNumber: 5,
///   connectionType: AlgorithmConnectionType.audioSignal,
/// );
/// ```
@freezed
sealed class AlgorithmConnection with _$AlgorithmConnection {
  const factory AlgorithmConnection({
    /// Unique identifier for this connection using format: alg_${source}_${sourcePort}->alg_${target}_${targetPort}_bus_${busNumber}
    required String id,

    /// Index of the source algorithm slot (0-7)
    required int sourceAlgorithmIndex,

    /// ID of the source port/parameter that outputs to this bus
    required String sourcePortId,

    /// Index of the target algorithm slot (0-7)
    required int targetAlgorithmIndex,

    /// ID of the target port/parameter that receives from this bus
    required String targetPortId,

    /// Bus number used for this connection (1-28)
    /// 1-12: Input/CV buses, 13-20: Output buses, 21-28: Audio buses
    required int busNumber,

    /// Type of connection based on signal flow and bus usage
    required AlgorithmConnectionType connectionType,

    /// Whether this connection is currently valid based on algorithm states
    @Default(true) bool isValid,

    /// Optional validation message if connection is invalid
    String? validationMessage,

    /// Human-readable label for the connection edge (e.g., "Bus 5", "CV 3")
    String? edgeLabel,
  }) = _AlgorithmConnection;

  /// Creates an AlgorithmConnection from JSON
  factory AlgorithmConnection.fromJson(Map<String, dynamic> json) =>
      _$AlgorithmConnectionFromJson(json);

  /// Creates an AlgorithmConnection with auto-generated deterministic ID
  factory AlgorithmConnection.withGeneratedId({
    required int sourceAlgorithmIndex,
    required String sourcePortId,
    required int targetAlgorithmIndex,
    required String targetPortId,
    required int busNumber,
    required AlgorithmConnectionType connectionType,
    bool isValid = true,
    String? validationMessage,
    String? edgeLabel,
  }) {
    final id =
        'alg_${sourceAlgorithmIndex}_$sourcePortId->alg_${targetAlgorithmIndex}_${targetPortId}_bus_$busNumber';

    return AlgorithmConnection(
      id: id,
      sourceAlgorithmIndex: sourceAlgorithmIndex,
      sourcePortId: sourcePortId,
      targetAlgorithmIndex: targetAlgorithmIndex,
      targetPortId: targetPortId,
      busNumber: busNumber,
      connectionType: connectionType,
      isValid: isValid,
      validationMessage: validationMessage,
      edgeLabel: edgeLabel,
    );
  }
}

/// Types of algorithm-to-algorithm connections based on signal flow
enum AlgorithmConnectionType {
  /// Audio signal connection (typically buses 21-28 or output buses)
  audioSignal,

  /// Control voltage (CV) connection (typically buses 1-12)
  controlVoltage,

  /// Gate/trigger signal connection
  gateTrigger,

  /// Clock/timing signal connection
  clockTiming,

  /// Mixed or unknown signal type
  mixed,
}

extension AlgorithmConnectionHelpers on AlgorithmConnection {
  /// Check if this connection violates execution order constraints
  ///
  /// Note: Bus-mediated connections in the Disting NT are valid in both directions
  /// because they use the internal bus system (1-28) rather than direct signal flow.
  /// Only self-connections are invalid.
  bool get violatesExecutionOrder {
    // Bus-mediated connections are valid in both directions
    // Only self-connections are invalid
    return sourceAlgorithmIndex == targetAlgorithmIndex;
  }

  /// Check if this is a forward edge (source runs before target)
  /// Forward edges follow the natural execution order: slot N → slot M where N < M
  bool get isForwardEdge {
    return sourceAlgorithmIndex < targetAlgorithmIndex;
  }

  /// Check if this is a backward edge (source runs after target)
  /// Backward edges go against execution order: slot N → slot M where N >= M
  /// These are highlighted to show execution order implications
  /// Physical output connections (-3) are always considered forward edges
  bool get isBackwardEdge {
    if (isPhysicalOutput) return false; // Physical outputs are always forward
    return sourceAlgorithmIndex >= targetAlgorithmIndex;
  }

  /// Check if this connection targets a physical output
  bool get isPhysicalOutput {
    return targetAlgorithmIndex == -3;
  }

  /// Get a human-readable description of the connection
  String get description {
    return 'Algorithm $sourceAlgorithmIndex:$sourcePortId → Algorithm $targetAlgorithmIndex:$targetPortId';
  }

  /// Get the connection type as a human-readable string
  String get connectionTypeDisplayName {
    switch (connectionType) {
      case AlgorithmConnectionType.audioSignal:
        return 'Audio';
      case AlgorithmConnectionType.controlVoltage:
        return 'CV';
      case AlgorithmConnectionType.gateTrigger:
        return 'Gate';
      case AlgorithmConnectionType.clockTiming:
        return 'Clock';
      case AlgorithmConnectionType.mixed:
        return 'Mixed';
    }
  }

  /// Generate a bus label based on the bus number and connection type
  String busLabelForFirmware({
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    return BusLabelFormatter.formatBusNumber(
          busNumber,
          hasExtendedAuxBuses: hasExtendedAuxBuses,
          deviceIoProfile: deviceIoProfile,
        ) ??
        'Bus$busNumber';
  }

  /// Get the edge label for display on the connection line
  String getEdgeLabel({
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    return edgeLabel ??
        busLabelForFirmware(
          hasExtendedAuxBuses: hasExtendedAuxBuses,
          deviceIoProfile: deviceIoProfile,
        );
  }

  /// Check if this connection uses an input/CV bus (1-12)
  bool get usesInputBus => DeviceIoProfile.distingExtended.isInput(busNumber);

  /// Check if this connection uses an output bus (13-20)
  bool get usesOutputBus => DeviceIoProfile.distingExtended.isOutput(busNumber);

  /// Check if this connection uses an audio bus (21-64, excluding ES-5)
  bool get usesAudioBus => DeviceIoProfile.distingExtended.isAux(busNumber);

  bool usesInputBusFor(DeviceIoProfile profile) => profile.isInput(busNumber);
  bool usesOutputBusFor(DeviceIoProfile profile) => profile.isOutput(busNumber);
  bool usesAudioBusFor(DeviceIoProfile profile) => profile.isAux(busNumber);

  /// Validate the connection and return validation result
  AlgorithmConnectionValidation validate({
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    // Check for self-connections (the only invalid execution order)
    if (violatesExecutionOrder) {
      errors.add('Algorithm cannot connect to itself');
    }

    // Check bus number validity
    if (!deviceIoProfile.contains(busNumber)) {
      errors.add('Bus number $busNumber is not available on this device');
    }

    // Check algorithm index validity
    if (sourceAlgorithmIndex < 0 || sourceAlgorithmIndex > 7) {
      errors.add(
        'Source algorithm index $sourceAlgorithmIndex is outside valid range (0-7)',
      );
    }
    if (targetAlgorithmIndex != -3 &&
        (targetAlgorithmIndex < 0 || targetAlgorithmIndex > 7)) {
      errors.add(
        'Target algorithm index $targetAlgorithmIndex is outside valid range (0-7)',
      );
    }

    // Check for self-connection
    if (sourceAlgorithmIndex == targetAlgorithmIndex) {
      warnings.add('Algorithm is connecting to itself');
    }

    return AlgorithmConnectionValidation(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}

/// Result of validating an AlgorithmConnection
class AlgorithmConnectionValidation {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const AlgorithmConnectionValidation({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  /// Get all validation messages (errors + warnings)
  List<String> get allMessages => [...errors, ...warnings];

  /// Get a single summary message for display
  String get summaryMessage {
    if (errors.isNotEmpty) {
      return errors.first;
    } else if (warnings.isNotEmpty) {
      return warnings.first;
    } else {
      return 'Connection is valid';
    }
  }
}
