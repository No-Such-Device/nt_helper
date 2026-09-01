import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'multi_channel_algorithm_routing.dart';
import 'models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Specialized routing implementation for the ES-5 Encoder algorithm.
///
/// The ES-5 Encoder algorithm has a unique structure where it supports
/// multiple channels (1-8 based on specification), but each channel can be
/// individually enabled or disabled. This class overrides the input port
/// generation to only create ports for enabled channels.
///
/// The algorithm parameters are organized in channel pages:
/// - Channel 1, Channel 2, ... Channel N (where N is from specification)
/// - Each channel page contains 4 parameters:
///   1. Enable (0 or 1)
///   2. Input (bus 1-28)
///   3. Expander (1-6)
///   4. Output (1-8)
///
/// Only channels with Enable = 1 will have input ports created.
class ES5EncoderAlgorithmRouting extends MultiChannelAlgorithmRouting {
  /// Special marker for ES-5 encoder mirror connections
  static const String mirrorBusParam = 'es5_encoder_mirror';

  /// Default algorithm UUID when none provided
  static const String defaultAlgorithmUuid = 'es5e';

  /// Pattern for extracting channel number from port ID
  static const String channelIdPattern = r'channel_(\d+)_input';

  /// The slot containing all algorithm data
  final Slot slot;

  /// Creates a new ES5EncoderAlgorithmRouting instance.
  ES5EncoderAlgorithmRouting({
    required this.slot,
    required super.config,
    super.validator,
  });

  int _getValue(int parameterNumber, {required int defaultValue}) {
    return slot.values
        .firstWhere(
          (v) => v.parameterNumber == parameterNumber,
          orElse: () => ParameterValue(
            algorithmIndex: 0,
            parameterNumber: parameterNumber,
            value: defaultValue,
          ),
        )
        .value;
  }

  /// Generates input ports only for enabled channels.
  ///
  /// This method examines each channel page in the slot and creates
  /// input ports only for channels where the Enable parameter is set to 1.
  @override
  List<Port> generateInputPorts() {
    final ports = <Port>[];

    // Find all channel pages
    final channelPages = slot.pages.pages
        .where((page) => page.name.startsWith('Channel '))
        .toList();

    if (channelPages.isEmpty) {
      return ports;
    }

    // Process each channel page
    for (final page in channelPages) {
      // Extract channel number from page name (e.g., "Channel 1" -> 1)
      final channelMatch = RegExp(r'Channel (\d+)').firstMatch(page.name);
      if (channelMatch == null) continue;

      final channelNumber = int.parse(channelMatch.group(1)!);

      // Channel pages should have 4 parameters
      if (page.parameters.length < 4) {
        continue;
      }

      // Get parameter numbers for this channel
      final enableParamNum = page.parameters[0];
      final inputParamNum = page.parameters[1];
      final expanderParamNum = page.parameters[2];
      final outputParamNum = page.parameters[3];

      // Get the Enable parameter value
      final enableValue = _getValue(enableParamNum, defaultValue: 0);

      // Only create port if channel is enabled
      if (enableValue == 1) {
        // Get the Input bus value
        final inputBusValue = _getValue(inputParamNum, defaultValue: 0);

        // Get Expander and Output values for metadata
        final expanderValue = _getValue(expanderParamNum, defaultValue: 1);
        final outputValue = _getValue(
          outputParamNum,
          defaultValue: channelNumber,
        );

        // Create the input port for this enabled channel
        final port = Port(
          id: '${algorithmUuid ?? defaultAlgorithmUuid}_channel_${channelNumber}_input',
          name: 'Channel $channelNumber',
          type: PortType
              .cv, // All gate/trigger signals are CV (Story 7.5) // ES-5 handles gates/triggers
          direction: PortDirection.input,
          description:
              'ES-5 Channel $channelNumber (Expander $expanderValue, Output $outputValue)',
          // Direct properties
          busValue: inputBusValue,
          channelNumber: channelNumber,
          parameterNumber: inputParamNum,
          // Store expander and output as metadata
          isMultiChannel: true,
        );

        ports.add(port);
      } else {}
    }

    return ports;
  }

  /// Generates output ports for the ES-5 Encoder.
  ///
  /// Each enabled input channel creates a corresponding output port that mirrors
  /// to the physical ES-5 expander output based on the Output parameter (1-8).
  /// This creates the visual flow: Input Bus → ES-5 Encoder → ES-5 Port
  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];

    // Find all channel pages to access Output parameter values
    final channelPages = slot.pages.pages
        .where((page) => page.name.startsWith('Channel '))
        .toList();

    // inputPorts already contains only enabled channels
    for (final inputPort in inputPorts) {
      // Input ID format: '${algorithmUuid}_channel_${channelNumber}_input'
      final channelMatch = RegExp(channelIdPattern).firstMatch(inputPort.id);

      if (channelMatch != null) {
        final channelNumber = int.parse(channelMatch.group(1)!);

        // Find the channel page for this channel to get Output parameter
        final channelPage = channelPages.firstWhere(
          (page) => page.name == 'Channel $channelNumber',
          orElse: () => throw StateError(
            'No channel page found for channel $channelNumber',
          ),
        );

        // Get the Output parameter number (index 3: Enable, Input, Expander, Output)
        final outputParamNum = channelPage.parameters.length >= 4
            ? channelPage.parameters[3]
            : -1;

        // Read the Output parameter value (1-8) - defaults to channel number
        final outputValue = outputParamNum >= 0
            ? _getValue(outputParamNum, defaultValue: channelNumber)
            : channelNumber;

        final outputLabel = outputValue <= 0 ? 'None' : outputValue.toString();

        ports.add(
          Port(
            id: '${algorithmUuid ?? defaultAlgorithmUuid}_channel_${channelNumber}_output',
            name: 'To ES-5 $outputLabel',
            type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
            direction: PortDirection.output,
            description: 'Channel $channelNumber → ES-5 Output $outputLabel',
            channelNumber: outputValue > 0 ? outputValue : null,
            busParam: mirrorBusParam, // Special marker for connection discovery
          ),
        );
      }
    }

    return ports;
  }

  /// Checks if this routing implementation can handle the given slot.
  ///
  /// Returns true only for ES-5 Encoder algorithm (guid: 'es5e').
  static bool canHandle(Slot slot) {
    return slot.algorithm.guid == 'es5e';
  }

  /// Creates an ES5EncoderAlgorithmRouting instance from a slot.
  ///
  /// This factory method creates the specialized routing for ES-5 Encoder,
  /// configuring it based on the slot's specifications and parameters.
  static ES5EncoderAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    String? algorithmUuid,
  }) {
    // Determine the number of channels from the channel pages
    final channelPages = slot.pages.pages
        .where((page) => page.name.startsWith('Channel '))
        .toList();
    final channelCount = channelPages.length;

    // Create configuration for the ES-5 Encoder
    final config = MultiChannelAlgorithmConfig(
      channelCount: channelCount > 0 ? channelCount : 1,
      supportsStereoChannels: false, // ES-5 handles gates, not stereo audio
      allowsIndependentChannels: true,
      supportedPortTypes: [PortType.cv], // Gate signals are CV (Story 7.5)
      portNamePrefix: 'Channel',
      createMasterMix: false, // No master mix for gate outputs
      algorithmProperties: {
        'algorithmGuid': slot.algorithm.guid,
        'algorithmName': slot.algorithm.name,
        'algorithmUuid': algorithmUuid,
        'channelCount': channelCount,
      },
    );

    final routing = ES5EncoderAlgorithmRouting(slot: slot, config: config);
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }
}
