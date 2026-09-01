import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'multi_channel_algorithm_routing.dart';
import 'models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Base class for algorithms that support ES-5 direct output routing.
///
/// Algorithms extending this class support multiple output channels that can route to either:
/// 1. Normal Output buses (when ES-5 Expander = 0)
/// 2. Direct ES-5 expander ports (when ES-5 Expander > 0)
///
/// When ES-5 Expander is active (1-6), the Output parameter is completely ignored
/// and the ES-5 Output parameter (1-8) determines which ES-5 port receives the signal.
abstract class Es5DirectOutputAlgorithmRouting
    extends MultiChannelAlgorithmRouting {
  /// Special marker for ES-5 direct output connections
  static const String es5DirectBusParam = 'es5_direct';

  /// Parameter name constants for ES-5 algorithms
  static const String outputParamName = 'Output';
  static const String es5ExpanderParamName = 'ES-5 Expander';
  static const String es5OutputParamName = 'ES-5 Output';

  /// The slot containing all algorithm data
  final Slot slot;

  /// The name of the algorithm (for debug messages)
  String get algorithmName;

  /// Creates a new Es5DirectOutputAlgorithmRouting instance.
  Es5DirectOutputAlgorithmRouting({
    required this.slot,
    required super.config,
    super.validator,
  });

  /// Generates output ports based on ES-5 configuration for each channel.
  ///
  /// For each channel:
  /// - If ES-5 Expander > 0: Create ES-5 direct output port (ignoring Output parameter)
  /// - If ES-5 Expander = 0: Create normal output port using Output parameter
  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];

    for (int channel = 1; channel <= config.channelCount; channel++) {
      // Get ES-5 Expander value (0=Off, 1-6=Active)
      final es5ExpanderValue = getChannelParameter(
        channel,
        es5ExpanderParamName,
      );

      if (es5ExpanderValue != null && es5ExpanderValue > 0) {
        // ES-5 MODE: Ignore Output parameter completely
        final configuredEs5OutputValue =
            getChannelParameter(channel, es5OutputParamName) ?? channel;

        ports.add(
          buildEs5DirectOutputPort(
            channel: channel,
            es5OutputValue: configuredEs5OutputValue,
          ),
        );
      } else {
        // NORMAL MODE: Use Output parameter
        // Try 'Output' first, then fall back to any parameter ending with 'output' (e.g., 'Clock output')
        final outputBusResult = _getOutputBusWithName(channel);

        if (outputBusResult != null) {
          // For single-channel algorithms, use the actual parameter name (e.g., "Clock output")
          // For multi-channel, use "Channel N" format
          final portName =
              config.channelCount == 1 && outputBusResult.paramName != null
              ? outputBusResult.paramName!
              : 'Channel $channel';

          ports.add(
            buildNormalOutputPort(
              channel: channel,
              busValue: outputBusResult.busValue,
              parameterNumber: outputBusResult.parameterNumber,
              portName: portName,
              description: 'Gate output for channel $channel',
            ),
          );
        } else {}
      }
    }

    return ports;
  }

  /// Helper to get output bus value along with parameter name and number.
  ///
  /// Returns a record with the bus value, parameter name, and parameter number.
  ({int busValue, String? paramName, int parameterNumber})?
  _getOutputBusWithName(int channel) {
    // Try 'Output' first
    final outputParam = getParameterValueAndNumber(channel, outputParamName);
    if (outputParam != null) {
      return (
        busValue: outputParam.value,
        paramName: outputParamName,
        parameterNumber: outputParam.parameterNumber,
      );
    }

    // Fall back to pattern matching (e.g., 'Clock output')
    // Also find the actual parameter name
    final regex = RegExp(r'(?:.*\s)?[Oo]utput$');

    // For single-channel, look for non-prefixed parameter
    if (config.channelCount == 1) {
      final param = slot.parameters.firstWhere(
        (p) => regex.hasMatch(p.name),
        orElse: () => ParameterInfo.filler(),
      );

      if (param.parameterNumber >= 0) {
        final value = slot.values
            .firstWhere(
              (v) => v.parameterNumber == param.parameterNumber,
              orElse: () => ParameterValue(
                algorithmIndex: 0,
                parameterNumber: param.parameterNumber,
                value: param.defaultValue,
              ),
            )
            .value;

        return (
          busValue: value,
          paramName: param.name,
          parameterNumber: param.parameterNumber,
        );
      }
    }

    return null;
  }

  @protected
  ({int parameterNumber, int value})? getOutputModeFromMap(
    int? outputParamNumber,
  ) {
    if (outputParamNumber == null) {
      return null;
    }

    for (final entry in slot.outputModeMap.entries) {
      final modeParamNumber = entry.key;
      final affectedOutputParams = entry.value;

      if (affectedOutputParams.contains(outputParamNumber)) {
        final modeValue = slot.values
            .firstWhere(
              (v) => v.parameterNumber == modeParamNumber,
              orElse: () => ParameterValue(
                algorithmIndex: 0,
                parameterNumber: modeParamNumber,
                value: 0,
              ),
            )
            .value;

        return (parameterNumber: modeParamNumber, value: modeValue);
      }
    }

    return null;
  }

  @protected
  Port buildEs5DirectOutputPort({
    required int channel,
    required int es5OutputValue,
  }) {
    final es5OutputLabel = es5OutputValue <= 0
        ? 'None'
        : es5OutputValue.toString();

    return Port(
      id: '${algorithmUuid}_channel_${channel}_es5_output',
      name: 'Ch$channel → ES-5 $es5OutputLabel',
      type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
      direction: PortDirection.output,
      description: 'Direct to ES-5 Output $es5OutputLabel',
      busParam: es5DirectBusParam, // Special marker
      channelNumber: es5OutputValue > 0 ? es5OutputValue : null,
    );
  }

  @protected
  Port buildNormalOutputPort({
    required int channel,
    required int busValue,
    required int parameterNumber,
    required String portName,
    required String description,
  }) {
    final modeResult = getOutputModeFromMap(parameterNumber);
    final outputMode = modeResult != null
        ? (modeResult.value == 1 ? OutputMode.replace : OutputMode.add)
        : null;

    return Port(
      id: '${algorithmUuid}_channel_${channel}_output',
      name: portName,
      type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
      direction: PortDirection.output,
      description: description,
      busValue: busValue > 0 ? busValue : null,
      channelNumber: channel,
      parameterNumber: parameterNumber,
      outputMode: outputMode,
      modeParameterNumber: modeResult?.parameterNumber,
    );
  }

  /// Gets a parameter's value and number by name for a specific channel.
  ///
  /// This is the canonical method for retrieving parameter metadata used across
  /// all ES-5 algorithm implementations.
  ///
  /// Parameters:
  /// - [channel]: The channel number (1-based)
  /// - [paramName]: The parameter name to find (without channel prefix)
  ///
  /// Returns a record with the parameter number and current value, or null if not found.
  @protected
  ({int parameterNumber, int value})? getParameterValueAndNumber(
    int channel,
    String paramName,
  ) {
    // Look for parameter with channel prefix (e.g., "1:Output")
    final prefixedName = '$channel:$paramName';

    var param = slot.parameters.firstWhere(
      (p) => p.name == prefixedName,
      orElse: () => ParameterInfo.filler(),
    );

    // For single-channel algorithms, fall back to non-prefixed parameter name
    if (param.parameterNumber < 0 && config.channelCount == 1) {
      param = slot.parameters.firstWhere(
        (p) => p.name == paramName,
        orElse: () => ParameterInfo.filler(),
      );

      if (param.parameterNumber < 0) {
        return null;
      }
    }

    if (param.parameterNumber < 0) {
      return null;
    }

    // Get the parameter value
    final value = slot.values
        .firstWhere(
          (v) => v.parameterNumber == param.parameterNumber,
          orElse: () => ParameterValue(
            algorithmIndex: 0,
            parameterNumber: param.parameterNumber,
            value: param.defaultValue,
          ),
        )
        .value;

    return (parameterNumber: param.parameterNumber, value: value);
  }

  /// Gets the value of a parameter for a specific channel by regex pattern.
  ///
  /// Similar to getChannelParameter but matches parameter names using a regex pattern.
  /// Useful for finding parameters with varying names like "Clock output", "Output", etc.
  ///
  /// Parameters:
  /// - [channel]: The channel number (1-based)
  /// - [paramPattern]: The regex pattern to match parameter names
  ///
  /// Returns the parameter value, or null if not found
  @protected
  int? getChannelParameterByPattern(int channel, String paramPattern) {
    final regex = RegExp(paramPattern);

    // Look for parameter with channel prefix first (e.g., "1:Clock output")
    final prefixedMatch = slot.parameters.firstWhere((p) {
      if (!p.name.startsWith('$channel:')) return false;
      final nameWithoutPrefix = p.name.substring('$channel:'.length);
      return regex.hasMatch(nameWithoutPrefix);
    }, orElse: () => ParameterInfo.filler());

    if (prefixedMatch.parameterNumber >= 0) {
      final value = slot.values
          .firstWhere(
            (v) => v.parameterNumber == prefixedMatch.parameterNumber,
            orElse: () => ParameterValue(
              algorithmIndex: 0,
              parameterNumber: prefixedMatch.parameterNumber,
              value: prefixedMatch.defaultValue,
            ),
          )
          .value;
      return value;
    }

    // For single-channel algorithms, try non-prefixed parameter names
    if (config.channelCount == 1) {
      final nonPrefixedMatch = slot.parameters.firstWhere(
        (p) => regex.hasMatch(p.name),
        orElse: () => ParameterInfo.filler(),
      );

      if (nonPrefixedMatch.parameterNumber >= 0) {
        final value = slot.values
            .firstWhere(
              (v) => v.parameterNumber == nonPrefixedMatch.parameterNumber,
              orElse: () => ParameterValue(
                algorithmIndex: 0,
                parameterNumber: nonPrefixedMatch.parameterNumber,
                value: nonPrefixedMatch.defaultValue,
              ),
            )
            .value;
        return value;
      }
    }

    return null;
  }

  /// Gets the value of a parameter for a specific channel.
  ///
  /// Parameters are prefixed with channel number (e.g., "1:Output", "2:ES-5 Expander").
  /// For single-channel algorithms, falls back to non-prefixed parameter names.
  ///
  /// Parameters:
  /// - [channel]: The channel number (1-based)
  /// - [paramName]: The parameter name to find (without channel prefix)
  ///
  /// Returns the parameter value, or null if not found
  @protected
  int? getChannelParameter(int channel, String paramName) {
    // Look for parameter with channel prefix (e.g., "1:Output")
    final prefixedName = '$channel:$paramName';

    var param = slot.parameters.firstWhere(
      (p) => p.name == prefixedName,
      orElse: () => ParameterInfo.filler(),
    );

    // For single-channel algorithms, fall back to non-prefixed parameter name
    if (param.parameterNumber < 0 && config.channelCount == 1) {
      param = slot.parameters.firstWhere(
        (p) => p.name == paramName,
        orElse: () => ParameterInfo.filler(),
      );

      if (param.parameterNumber < 0) {
        return null;
      }

      // Get the parameter value
      final value = slot.values
          .firstWhere(
            (v) => v.parameterNumber == param.parameterNumber,
            orElse: () => ParameterValue(
              algorithmIndex: 0,
              parameterNumber: param.parameterNumber,
              value: param.defaultValue,
            ),
          )
          .value;

      return value;
    }

    if (param.parameterNumber < 0) {
      return null;
    }

    // Get the parameter value
    final value = slot.values
        .firstWhere(
          (v) => v.parameterNumber == param.parameterNumber,
          orElse: () => ParameterValue(
            algorithmIndex: 0,
            parameterNumber: param.parameterNumber,
            value: param.defaultValue,
          ),
        )
        .value;

    return value;
  }

  /// Creates an instance from a slot using the common pattern.
  ///
  /// This static method provides shared creation logic for ES-5 direct output algorithms.
  /// It counts channels, extracts input ports, and creates the configuration.
  ///
  /// Subclasses should call this and then construct their specific instance type.
  static ({
    int channelCount,
    List inputPorts,
    MultiChannelAlgorithmConfig config,
  })
  createConfigFromSlot(
    Slot slot, {
    required DeviceIoProfile deviceIoProfile,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
    required String debugName,
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

    // Use base class to process normal inputs (non-channel-prefixed parameters)
    final baseRouting = MultiChannelAlgorithmRouting.createFromSlot(
      slot,
      deviceIoProfile: deviceIoProfile,
      ioParameters: ioParameters,
      modeParameters: modeParameters,
      modeParametersWithNumbers: modeParametersWithNumbers,
      algorithmUuid: algorithmUuid,
    );

    // Extract input ports from base routing
    final inputPorts = baseRouting.config.algorithmProperties['inputs'] as List;

    // Create configuration, preserving inputs
    final config = MultiChannelAlgorithmConfig(
      channelCount: channelCount > 0 ? channelCount : 1,
      supportsStereoChannels: false, // Gate outputs, not stereo
      allowsIndependentChannels: true,
      supportedPortTypes: [PortType.cv], // Gate signals are CV (Story 7.5)
      portNamePrefix: 'Channel',
      createMasterMix: false, // No master mix for gate outputs
      algorithmProperties: {
        'algorithmGuid': slot.algorithm.guid,
        'algorithmName': slot.algorithm.name,
        'algorithmUuid': algorithmUuid,
        'channelCount': channelCount,
        'inputs': inputPorts, // Preserve normal input ports
        'outputs': [], // Will be generated by generateOutputPorts()
      },
    );

    return (channelCount: channelCount, inputPorts: inputPorts, config: config);
  }

  @protected
  static T createFromSlotWithConfig<T extends Es5DirectOutputAlgorithmRouting>(
    Slot slot, {
    required DeviceIoProfile deviceIoProfile,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
    required String debugName,
    required T Function(Slot slot, MultiChannelAlgorithmConfig config) builder,
  }) {
    final configData = createConfigFromSlot(
      slot,
      deviceIoProfile: deviceIoProfile,
      ioParameters: ioParameters,
      modeParameters: modeParameters,
      modeParametersWithNumbers: modeParametersWithNumbers,
      algorithmUuid: algorithmUuid,
      debugName: debugName,
    );

    final routing = builder(slot, configData.config);
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }
}
