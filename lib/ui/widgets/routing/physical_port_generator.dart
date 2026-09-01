import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Utility class for generating physical I/O port configurations.
///
/// This class provides methods to generate the port configurations
/// for the Disting NT's 12 physical inputs and 8 physical outputs.
class PhysicalPortGenerator {
  /// Number of physical input jacks on the Disting NT hardware.
  static const int physicalInputCount = 12;

  /// Number of physical output jacks on the Disting NT hardware.
  static const int physicalOutputCount = 8;

  /// Generates a list of ports representing the 12 physical inputs.
  ///
  /// Physical inputs are hardware jacks that receive external signals.
  /// In the routing system, they act as sources (output ports) because
  /// they provide signals to algorithm inputs.
  ///
  /// Returns a list of 12 Port objects configured as physical inputs.
  static List<Port> generatePhysicalInputPorts({
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    return List.generate(deviceIoProfile.inputBusCount, (index) {
      final portNumber = index + 1;
      return Port(
        id: 'hw_in_$portNumber',
        name: 'Input $portNumber',
        type: _getPortTypeForInput(portNumber),
        direction: PortDirection.output,
        description: 'Hardware input jack $portNumber',
        hardwareIndex: portNumber,
        nodeId: 'hw_inputs',
        role: PortRole.physicalInputBus,
      );
    });
  }

  /// Generates a list of ports representing the 8 physical outputs.
  ///
  /// Physical outputs are hardware jacks that send processed signals.
  /// In the routing system, they act as targets (input ports) because
  /// they receive signals from algorithm outputs.
  ///
  /// Returns a list of 8 Port objects configured as physical outputs.
  static List<Port> generatePhysicalOutputPorts({
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    return List.generate(deviceIoProfile.outputBusCount, (index) {
      final portNumber = index + 1;
      return Port(
        id: 'hw_out_$portNumber',
        name: 'O$portNumber',
        type: _getPortTypeForOutput(portNumber),
        direction: PortDirection.input,
        description: 'Hardware output jack $portNumber',
        hardwareIndex: portNumber,
        nodeId: 'hw_outputs',
        role: PortRole.physicalOutputBus,
      );
    });
  }

  /// Generates a single physical input port with the specified index.
  ///
  /// [index] should be between 1 and 12 inclusive.
  /// Throws [ArgumentError] if index is out of range.
  static Port generatePhysicalInputPort(
    int index, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    if (index < 1 || index > deviceIoProfile.inputBusCount) {
      throw ArgumentError(
        'Physical input index must be between 1 and ${deviceIoProfile.inputBusCount}, got $index',
      );
    }

    return Port(
      id: 'hw_in_$index',
      name: 'Input $index',
      type: _getPortTypeForInput(index),
      direction: PortDirection.output,
      description: 'Hardware input jack $index',
      hardwareIndex: index,
      nodeId: 'hw_inputs',
      role: PortRole.physicalInputBus,
    );
  }

  /// Generates a single physical output port with the specified index.
  ///
  /// [index] should be between 1 and 8 inclusive.
  /// Throws [ArgumentError] if index is out of range.
  static Port generatePhysicalOutputPort(
    int index, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    if (index < 1 || index > deviceIoProfile.outputBusCount) {
      throw ArgumentError(
        'Physical output index must be between 1 and ${deviceIoProfile.outputBusCount}, got $index',
      );
    }

    return Port(
      id: 'hw_out_$index',
      name: 'O$index',
      type: _getPortTypeForOutput(index),
      direction: PortDirection.input,
      description: 'Hardware output jack $index',
      hardwareIndex: index,
      nodeId: 'hw_outputs',
      role: PortRole.physicalOutputBus,
    );
  }

  /// Determines the port type for a specific physical input.
  ///
  /// This method can be customized to assign different port types
  /// to specific inputs based on hardware configuration or user preferences.
  /// Currently defaults all inputs to audio type.
  static PortType _getPortTypeForInput(int portNumber) {
    // Default all inputs to audio type
    // This can be customized based on specific hardware configurations
    // For example:
    // - Inputs 1-8 could be audio
    // - Inputs 9-10 could be CV
    // - Inputs 11-12 could be gate/trigger

    // For now, keep it simple - all audio
    return PortType.audio;
  }

  /// Determines the port type for a specific physical output.
  ///
  /// This method can be customized to assign different port types
  /// to specific outputs based on hardware configuration or user preferences.
  /// Currently defaults all outputs to audio type.
  static PortType _getPortTypeForOutput(int portNumber) {
    // Default all outputs to audio type
    // This can be customized based on specific hardware configurations
    // For example:
    // - Outputs 1-4 could be audio
    // - Outputs 5-6 could be CV
    // - Outputs 7-8 could be gate/trigger

    // For now, keep it simple - all audio
    return PortType.audio;
  }

  /// Validates that a port is a physical input port.
  static bool isPhysicalInputPort(Port port) => port.isPhysicalInput;

  /// Validates that a port is a physical output port.
  static bool isPhysicalOutputPort(Port port) => port.isPhysicalOutput;

  /// Validates that a port is any physical port (input or output).
  static bool isPhysicalPort(Port port) =>
      port.isPhysicalInput || port.isPhysicalOutput;

  /// Gets the hardware index from a physical port.
  ///
  /// Returns null if the port is not a physical port or lacks the index.
  static int? getHardwareIndex(Port port) {
    if (!isPhysicalPort(port)) return null;
    return port.hardwareIndex;
  }

  /// Gets a human-readable label for a physical port.
  static String getPhysicalPortLabel(Port port) {
    final index = getHardwareIndex(port);
    if (index == null) return port.name;

    if (port.isPhysicalInput) {
      return 'I$index';
    } else if (port.isPhysicalOutput) {
      return 'O$index';
    }

    return port.name;
  }
}
