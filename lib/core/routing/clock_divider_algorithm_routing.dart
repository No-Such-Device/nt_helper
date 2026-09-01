import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'es5_direct_output_algorithm_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Specialized routing implementation for the Clock Divider algorithm.
///
/// The Clock Divider algorithm supports ES-5 direct output routing with per-channel
/// enable/disable filtering. Only enabled channels (Enable=1) appear in the routing editor.
///
/// See [Es5DirectOutputAlgorithmRouting] for details on the dual-mode behavior.
class ClockDividerAlgorithmRouting extends Es5DirectOutputAlgorithmRouting {
  /// Creates a new ClockDividerAlgorithmRouting instance.
  ClockDividerAlgorithmRouting({
    required super.slot,
    required super.config,
    super.validator,
  });

  @override
  String get algorithmName => 'ClockDividerAlgorithmRouting';

  /// Checks if this routing implementation can handle the given slot.
  ///
  /// Returns true only for Clock Divider algorithm (guid: 'clkd').
  static bool canHandle(Slot slot) {
    return slot.algorithm.guid == 'clkd';
  }

  /// Creates a ClockDividerAlgorithmRouting instance from a slot.
  ///
  /// This factory method creates the specialized routing for Clock Divider algorithm.
  /// It processes normal input parameters (Clock input, Reset input) using
  /// the base routing extraction, but customizes output generation for ES-5 support
  /// and channel filtering.
  static ClockDividerAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    return Es5DirectOutputAlgorithmRouting.createFromSlotWithConfig(
      slot,
      deviceIoProfile: deviceIoProfile,
      ioParameters: ioParameters,
      modeParameters: modeParameters,
      modeParametersWithNumbers: modeParametersWithNumbers,
      algorithmUuid: algorithmUuid,
      debugName: 'ClockDividerAlgorithmRouting',
      builder: (slot, config) =>
          ClockDividerAlgorithmRouting(slot: slot, config: config),
    );
  }

  /// Generates output ports based on ES-5 configuration for each channel.
  ///
  /// Clock Divider adds channel filtering: only channels with Enable=1 are visible.
  ///
  /// For each enabled channel:
  /// - If ES-5 Expander > 0: Create ES-5 direct output port (ignoring Output parameter)
  /// - If ES-5 Expander = 0: Create normal output port using Output parameter
  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];

    for (int channel = 1; channel <= config.channelCount; channel++) {
      // Check if channel is enabled (Clock Divider specific)
      final enableValue = getChannelParameter(channel, 'Enable');

      if (enableValue == null || enableValue == 0) {
        continue;
      }

      // Get ES-5 Expander value (0=Off, 1-6=Active)
      final es5ExpanderValue = getChannelParameter(
        channel,
        Es5DirectOutputAlgorithmRouting.es5ExpanderParamName,
      );

      if (es5ExpanderValue != null && es5ExpanderValue > 0) {
        // ES-5 MODE: Ignore Output parameter completely
        final es5OutputValue =
            getChannelParameter(
              channel,
              Es5DirectOutputAlgorithmRouting.es5OutputParamName,
            ) ??
            channel;

        ports.add(
          buildEs5DirectOutputPort(
            channel: channel,
            es5OutputValue: es5OutputValue,
          ),
        );
      } else {
        // NORMAL MODE: Use Output parameter
        // Need to get both the bus value AND the parameter number for updates
        final outputParam = getParameterValueAndNumber(
          channel,
          Es5DirectOutputAlgorithmRouting.outputParamName,
        );

        if (outputParam != null && outputParam.value > 0) {
          ports.add(
            buildNormalOutputPort(
              channel: channel,
              busValue: outputParam.value,
              parameterNumber: outputParam.parameterNumber,
              portName: 'Channel $channel',
              description: 'Gate output for channel $channel',
            ),
          );
        } else {}
      }
    }

    return ports;
  }
}
