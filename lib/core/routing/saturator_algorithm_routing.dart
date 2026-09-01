import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'models/port.dart';
import 'multi_channel_algorithm_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Routing implementation for Saturator algorithm.
///
/// Saturator uses in-place processing where each input bus is also an output bus.
/// For each channel's Input parameter, we create:
/// - An input port on the specified bus
/// - A virtual output port on the same bus with OutputMode.replace
class SaturatorAlgorithmRouting extends MultiChannelAlgorithmRouting {
  /// The slot containing all algorithm data
  final Slot slot;

  static bool canHandle(Slot slot) {
    return slot.algorithm.guid == 'satu';
  }

  SaturatorAlgorithmRouting({
    required this.slot,
    required super.config,
    super.validator,
  });

  /// Creates a SaturatorAlgorithmRouting instance from a slot.
  static SaturatorAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    // Count channels by finding highest channel prefix in parameter names
    int channelCount = 0;
    for (final param in slot.parameters) {
      final match = RegExp(r'^(\d+):').firstMatch(param.name);
      if (match != null) {
        final channelNum = int.parse(match.group(1)!);
        if (channelNum > channelCount) {
          channelCount = channelNum;
        }
      }
    }

    // Build input and output port lists
    final inputPorts = <Map<String, Object?>>[];
    final outputPorts = <Map<String, Object?>>[];

    // Process each channel
    for (int channel = 1; channel <= channelCount; channel++) {
      // Find Input parameter for this channel
      final inputParam = slot.parameters.firstWhere(
        (p) => p.name == '$channel:Input',
        orElse: () => ParameterInfo.filler(),
      );

      if (inputParam.parameterNumber < 0) {
        continue; // Skip if parameter not found
      }

      // Get the input bus value
      final inputBusValue = slot.values
          .firstWhere(
            (v) => v.parameterNumber == inputParam.parameterNumber,
            orElse: () => ParameterValue(
              algorithmIndex: 0,
              parameterNumber: inputParam.parameterNumber,
              value: inputParam.defaultValue,
            ),
          )
          .value;

      // Find Width parameter for this channel
      final widthParam = slot.parameters.firstWhere(
        (p) => p.name == '$channel:Width',
        orElse: () => ParameterInfo.filler(),
      );

      // Get width value (default to 1 if not found)
      final width = widthParam.parameterNumber >= 0
          ? slot.values
                .firstWhere(
                  (v) => v.parameterNumber == widthParam.parameterNumber,
                  orElse: () => ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: widthParam.parameterNumber,
                    value: widthParam.defaultValue,
                  ),
                )
                .value
          : 1;

      // Generate ports based on width
      if (width == 1) {
        // Single port without numeric suffix
        inputPorts.add({
          'id': '${algorithmUuid ?? 'satu'}_channel_${channel}_input',
          'name': '$channel:Input',
          'type': 'audio',
          'busParam': '$channel:Input',
          'busValue': inputBusValue,
          'parameterNumber': inputParam.parameterNumber,
        });

        outputPorts.add({
          'id': '${algorithmUuid ?? 'satu'}_channel_${channel}_output',
          'name': '$channel:Output',
          'type': 'audio',
          'busParam': null,
          'busValue': inputBusValue,
          'parameterNumber': -channel,
          'outputMode': 'replace',
        });
      } else {
        // Multiple numbered ports for width > 1
        for (int w = 1; w <= width; w++) {
          final busValue = inputBusValue + (w - 1);

          inputPorts.add({
            'id': '${algorithmUuid ?? 'satu'}_channel_${channel}_input_$w',
            'name': '$channel:Input $w',
            'type': 'audio',
            'busParam': '$channel:Input',
            'busValue': busValue,
            'parameterNumber': inputParam.parameterNumber,
          });

          outputPorts.add({
            'id': '${algorithmUuid ?? 'satu'}_channel_${channel}_output_$w',
            'name': '$channel:Output $w',
            'type': 'audio',
            'busParam': null,
            'busValue': busValue,
            'parameterNumber': -(channel * 100 + w), // Unique negative number
            'outputMode': 'replace',
          });
        }
      }
    }

    // Create configuration
    final config = MultiChannelAlgorithmConfig(
      channelCount: channelCount > 0 ? channelCount : 1,
      supportsStereoChannels: false,
      allowsIndependentChannels: true,
      supportedPortTypes: [PortType.audio],
      portNamePrefix: 'Channel',
      createMasterMix: false,
      algorithmProperties: {
        'algorithmGuid': slot.algorithm.guid,
        'algorithmName': slot.algorithm.name,
        'algorithmUuid': algorithmUuid,
        'channelCount': channelCount,
        'inputs': inputPorts,
        'outputs': outputPorts,
      },
    );

    final routing = SaturatorAlgorithmRouting(slot: slot, config: config);
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }
}
