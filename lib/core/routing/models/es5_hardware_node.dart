import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Utility class for generating ES-5 Eurorack hardware node port configurations.
///
/// The Expert Sleepers ES-5 is a Eurorack expander module that receives signals
/// from a computer/synthesizer and outputs them to CV/gate jacks in the modular system.
///
/// Hardware Configuration:
/// - 10 input ports (from the algorithm's perspective, these receive signals to output to hardware)
/// - 0 output ports (ES-5 is a sink - it only outputs to hardware, doesn't send back to algorithms)
///
/// Port Configuration:
/// - L and R ports: Audio signals for Silent Way encoding
///   (buses 29-30 on legacy firmware, 65-66 on firmware 1.15+)
/// - Numbered ports 1-8: Gate/trigger outputs (dynamic bus assignment based on algorithm)
///
/// This class follows the pattern established in PhysicalPortGenerator for
/// generating hardware node port configurations.
class ES5HardwareNode {
  /// Unique identifier for the ES-5 hardware node.
  static const String id = 'es5_hardware_node';

  /// Human-readable name for the ES-5 hardware node.
  static const String name = 'ES-5';

  /// Type identifier for the ES-5 hardware node.
  static const String type = 'es5_expander';

  /// Number of ES-5 input ports (L, R, and 1-8).
  static const int inputPortCount = 10;

  /// Returns the firmware-aware bus number for the L (left) audio port.
  static int? leftAudioBus(DeviceIoProfile deviceIoProfile) {
    final buses = deviceIoProfile.contextualEs5Buses;
    return buses.isEmpty ? null : buses.first;
  }

  /// Returns the firmware-aware bus number for the R (right) audio port.
  static int? rightAudioBus(DeviceIoProfile deviceIoProfile) =>
      deviceIoProfile.contextualEs5Buses.length == 2
      ? deviceIoProfile.contextualEs5Buses[1]
      : null;

  /// Compatibility helper for callers that have not yet resolved a profile.
  static int leftAudioBusForFirmware({required bool hasExtendedAuxBuses}) =>
      leftAudioBus(
        hasExtendedAuxBuses
            ? DeviceIoProfile.distingExtended
            : DeviceIoProfile.distingLegacy,
      )!;

  /// Compatibility helper for callers that have not yet resolved a profile.
  static int rightAudioBusForFirmware({required bool hasExtendedAuxBuses}) =>
      rightAudioBus(
        hasExtendedAuxBuses
            ? DeviceIoProfile.distingExtended
            : DeviceIoProfile.distingLegacy,
      )!;

  /// Generates a list of all ES-5 input ports.
  ///
  /// Creates 10 ports:
  /// - L port: Audio input for Silent Way encoding
  /// - R port: Audio input for Silent Way encoding
  /// - Ports 1-8: Gate/trigger outputs (no fixed bus assignment)
  ///
  /// Returns a list of 10 Port objects configured as ES-5 inputs.
  static List<Port> createInputPorts({
    DeviceIoProfile? deviceIoProfile,
    bool? hasExtendedAuxBuses,
  }) {
    deviceIoProfile ??= hasExtendedAuxBuses == false
        ? DeviceIoProfile.distingLegacy
        : DeviceIoProfile.distingExtended;
    final ports = <Port>[];

    final leftBus = leftAudioBus(deviceIoProfile);
    final rightBus = rightAudioBus(deviceIoProfile);
    if (leftBus != null && rightBus != null) {
      ports
        ..add(
          Port(
            id: 'es5_L',
            name: 'L',
            type: PortType.audio,
            direction: PortDirection.input,
            description: 'ES-5 Left (Silent Way)',
            busValue: leftBus,
            nodeId: id,
            role: PortRole.es5Bus,
          ),
        )
        ..add(
          Port(
            id: 'es5_R',
            name: 'R',
            type: PortType.audio,
            direction: PortDirection.input,
            description: 'ES-5 Right (Silent Way)',
            busValue: rightBus,
            nodeId: id,
            role: PortRole.es5Bus,
          ),
        );
    }

    // Create numbered ports 1-8 (gate, no fixed bus)
    for (int i = 1; i <= 8; i++) {
      ports.add(
        Port(
          id: 'es5_$i',
          name: '$i',
          type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
          direction: PortDirection.input,
          description: 'ES-5 Output $i',
          nodeId: id,
          role: PortRole.es5Bus,
        ),
      );
    }

    return ports;
  }

  /// Generates an empty list of output ports.
  ///
  /// The ES-5 is a sink device - it only receives signals from algorithms
  /// and outputs them to hardware. It does not send signals back to algorithms.
  ///
  /// Returns an empty list.
  static List<Port> createOutputPorts() {
    return [];
  }

  /// Validates that a port belongs to the ES-5 hardware node.
  static bool isES5Port(Port port) {
    return port.nodeId == id;
  }

  /// Gets the L (left) audio port.
  static Port getLeftAudioPort({
    DeviceIoProfile? deviceIoProfile,
    bool? hasExtendedAuxBuses,
  }) {
    deviceIoProfile ??= hasExtendedAuxBuses == false
        ? DeviceIoProfile.distingLegacy
        : DeviceIoProfile.distingExtended;
    return Port(
      id: 'es5_L',
      name: 'L',
      type: PortType.audio,
      direction: PortDirection.input,
      description: 'ES-5 Left (Silent Way)',
      busValue: leftAudioBus(deviceIoProfile),
      nodeId: id,
      role: PortRole.es5Bus,
    );
  }

  /// Gets the R (right) audio port.
  static Port getRightAudioPort({
    DeviceIoProfile? deviceIoProfile,
    bool? hasExtendedAuxBuses,
  }) {
    deviceIoProfile ??= hasExtendedAuxBuses == false
        ? DeviceIoProfile.distingLegacy
        : DeviceIoProfile.distingExtended;
    return Port(
      id: 'es5_R',
      name: 'R',
      type: PortType.audio,
      direction: PortDirection.input,
      description: 'ES-5 Right (Silent Way)',
      busValue: rightAudioBus(deviceIoProfile),
      nodeId: id,
      role: PortRole.es5Bus,
    );
  }

  /// Gets a numbered gate port (1-8).
  ///
  /// [portNumber] should be between 1 and 8 inclusive.
  /// Throws [ArgumentError] if portNumber is out of range.
  static Port getNumberedPort(int portNumber) {
    if (portNumber < 1 || portNumber > 8) {
      throw ArgumentError(
        'ES-5 numbered port must be between 1 and 8, got $portNumber',
      );
    }

    return Port(
      id: 'es5_$portNumber',
      name: '$portNumber',
      type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
      direction: PortDirection.input,
      description: 'ES-5 Output $portNumber',
      nodeId: id,
      role: PortRole.es5Bus,
    );
  }
}
