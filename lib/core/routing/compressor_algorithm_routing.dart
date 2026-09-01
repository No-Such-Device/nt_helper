import 'package:nt_helper/cubit/disting_cubit.dart';
import 'multi_channel_algorithm_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Routing implementation for the Compressor algorithm (`comp`).
///
/// Compressor is an insert effect: each Left/mono and Right input is also an
/// output on the same bus (Replace mode). Sidechain inputs are read-only and
/// do NOT produce a virtual output. The Reduction output is a normal
/// `isOutput` parameter and uses standard Add/Replace mode handling via the
/// base [MultiChannelAlgorithmRouting] logic.
class CompressorAlgorithmRouting extends MultiChannelAlgorithmRouting {
  final Slot slot;

  static bool canHandle(Slot slot) => slot.algorithm.guid == 'comp';

  CompressorAlgorithmRouting({
    required this.slot,
    required super.config,
    super.validator,
  });

  static CompressorAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    final base = MultiChannelAlgorithmRouting.createFromSlot(
      slot,
      deviceIoProfile: deviceIoProfile,
      ioParameters: ioParameters,
      modeParameters: modeParameters,
      modeParametersWithNumbers: modeParametersWithNumbers,
      algorithmUuid: algorithmUuid,
    );

    final newOutputs = _addVirtualInPlaceOutputs(base);

    final newConfig = MultiChannelAlgorithmConfig(
      channelCount: base.config.channelCount,
      supportsStereoChannels: base.config.supportsStereoChannels,
      allowsIndependentChannels: base.config.allowsIndependentChannels,
      supportedPortTypes: base.config.supportedPortTypes,
      portNamePrefix: base.config.portNamePrefix,
      createMasterMix: base.config.createMasterMix,
      algorithmProperties: {
        ...base.config.algorithmProperties,
        'outputs': newOutputs,
      },
    );

    final routing = CompressorAlgorithmRouting(slot: slot, config: newConfig);
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }

  /// Returns a new outputs list that contains the original outputs plus a
  /// virtual Replace-mode output on the same bus as each non-sidechain input.
  static List<Map<String, Object?>> _addVirtualInPlaceOutputs(
    MultiChannelAlgorithmRouting base,
  ) {
    final inputs =
        (base.config.algorithmProperties['inputs'] as List?)
            ?.cast<Map<String, Object?>>() ??
        const [];
    final outputs =
        (base.config.algorithmProperties['outputs'] as List?)
            ?.cast<Map<String, Object?>>()
            .toList() ??
        <Map<String, Object?>>[];

    for (final inputPort in inputs) {
      final name = (inputPort['name'] as String? ?? '').toLowerCase();
      if (name.contains('sidechain')) continue;

      final busValue = inputPort['busValue'] as int? ?? 0;
      if (busValue <= 0) continue;

      final originalName = inputPort['name'] as String? ?? 'Output';
      final outputName = originalName.replaceFirst(
        RegExp(r'input', caseSensitive: false),
        'output',
      );

      outputs.add({
        'id': '${inputPort['id']}_virtual_replace',
        'name': outputName,
        'type': inputPort['type'],
        'busParam': null,
        'busValue': busValue,
        'parameterNumber':
            -(inputPort['parameterNumber'] as int? ?? 0).abs() - 2000,
        'outputMode': 'replace',
      });
    }

    return outputs;
  }
}
