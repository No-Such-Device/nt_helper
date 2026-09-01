import 'package:collection/collection.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'algorithm_routing.dart';
import 'models/port.dart';

/// Configuration data for multi-channel algorithm routing.
///
/// Defines the properties needed to configure width-based routing behavior,
/// including the number of channels and channel-specific properties.
@immutable
class MultiChannelAlgorithmConfig {
  /// Number of channels supported by this algorithm
  /// Default is 1 for normal algorithms, N for width-based algorithms
  final int channelCount;

  /// Whether this algorithm supports stereo channel pairing
  final bool supportsStereoChannels;

  /// Whether channels can be independently routed
  final bool allowsIndependentChannels;

  /// Port types supported by this algorithm
  final List<PortType> supportedPortTypes;

  /// Base name prefix for generated ports
  final String portNamePrefix;

  /// Whether to create a master mix output
  final bool createMasterMix;

  /// Additional algorithm-specific properties
  final Map<String, dynamic> algorithmProperties;

  const MultiChannelAlgorithmConfig({
    this.channelCount = 1,
    this.supportsStereoChannels = false,
    this.allowsIndependentChannels = true,
    this.supportedPortTypes = const [PortType.audio, PortType.cv],
    this.portNamePrefix = 'Ch',
    this.createMasterMix = true,
    this.algorithmProperties = const {},
  });

  /// Factory constructor for normal (single-channel) algorithms
  factory MultiChannelAlgorithmConfig.normal({
    String portNamePrefix = 'Main',
    List<PortType> supportedPortTypes = const [PortType.audio, PortType.cv],
  }) {
    return MultiChannelAlgorithmConfig(
      channelCount: 1,
      supportsStereoChannels: false,
      allowsIndependentChannels: true,
      supportedPortTypes: supportedPortTypes,
      portNamePrefix: portNamePrefix,
      createMasterMix: false,
    );
  }

  /// Factory constructor for width-based (multi-channel) algorithms
  factory MultiChannelAlgorithmConfig.widthBased({
    required int width,
    bool supportsStereo = true,
    String portNamePrefix = 'Ch',
    List<PortType> supportedPortTypes = const [PortType.audio, PortType.cv],
  }) {
    return MultiChannelAlgorithmConfig(
      channelCount: width,
      supportsStereoChannels: supportsStereo,
      allowsIndependentChannels: true,
      supportedPortTypes: supportedPortTypes,
      portNamePrefix: portNamePrefix,
      createMasterMix: true,
    );
  }
}

/// Concrete implementation of AlgorithmRouting for multi-channel routing.
///
/// This class handles width-based routing with configurable channel count.
/// It supports both normal algorithms (default width=1) and width-based
/// algorithms with multiple channels.
///
/// Channel configurations can include:
/// - Single channel for normal algorithms
/// - Multiple independent channels for width-based algorithms
/// - Stereo channel pairing when supported
/// - Master mix outputs for multi-channel setups
///
/// Example usage:
/// ```dart
/// // Normal single-channel algorithm
/// final normalConfig = MultiChannelAlgorithmConfig.normal();
/// final normalRouting = MultiChannelAlgorithmRouting(config: normalConfig);
///
/// // Width-based multi-channel algorithm
/// final widthConfig = MultiChannelAlgorithmConfig.widthBased(width: 4);
/// final widthRouting = MultiChannelAlgorithmRouting(config: widthConfig);
/// ```
class MultiChannelAlgorithmRouting extends CachedAlgorithmRouting {
  /// Configuration for this multi-channel routing instance
  final MultiChannelAlgorithmConfig config;

  /// Creates a new MultiChannelAlgorithmRouting instance.
  ///
  /// Parameters:
  /// - [config]: Configuration defining the multi-channel routing behavior
  /// - [validator]: Optional port compatibility validator (uses default if not provided)
  /// - [initialState]: Optional initial routing state
  MultiChannelAlgorithmRouting({
    required this.config,
    super.validator,
    super.initialState,
  }) : super(
         algorithmUuid: config.algorithmProperties['algorithmUuid'] as String?,
       );

  @override
  List<Port> generateInputPorts() {
    final ports = <Port>[];

    // If explicit inputs are defined in algorithm properties, use them.
    final declaredInputs = config.algorithmProperties['inputs'];
    if (declaredInputs is List) {
      // If the list is explicitly empty, return empty ports (no fallback)
      if (declaredInputs.isEmpty) {
        return ports;
      }

      // Process declared inputs
      for (final item in declaredInputs) {
        if (item is Map) {
          final hasChannelNumber = item['channelNumber'] != null;
          final port =
              buildPortFromDeclaration(
                item,
                direction: PortDirection.input,
                defaultId: 'in_${ports.length + 1}',
                defaultName: 'Input',
                defaultType: PortType.audio,
              ).copyWith(
                channelNumber: coerceInt(item['channelNumber']),
                isMultiChannel: hasChannelNumber,
              );

          ports.add(port);
        }
      }
      return ports;
    }

    // Generate ports for each channel
    for (int channel = 0; channel < config.channelCount; channel++) {
      final channelNumber = channel + 1; // 1-based channel numbering

      // Generate ports for each supported type
      for (final portType in config.supportedPortTypes) {
        final portTypeName = _getPortTypeName(portType);

        if (config.supportsStereoChannels && portType == PortType.audio) {
          // Generate stereo pair for audio channels
          ports.add(
            Port(
              id: 'multi_${portType.name}_in_${channelNumber}_l',
              name: '${config.portNamePrefix} $channelNumber $portTypeName L',
              type: portType,
              direction: PortDirection.input,
              description:
                  'Left $portTypeName input for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: true,
              stereoSide: 'left',
            ),
          );

          ports.add(
            Port(
              id: 'multi_${portType.name}_in_${channelNumber}_r',
              name: '${config.portNamePrefix} $channelNumber $portTypeName R',
              type: portType,
              direction: PortDirection.input,
              description:
                  'Right $portTypeName input for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: true,
              stereoSide: 'right',
            ),
          );
        } else {
          // Generate mono port
          ports.add(
            Port(
              id: 'multi_${portType.name}_in_$channelNumber',
              name: '${config.portNamePrefix} $channelNumber $portTypeName In',
              type: portType,
              direction: PortDirection.input,
              description: '$portTypeName input for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: false,
            ),
          );
        }
      }
    }

    return ports;
  }

  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];

    // If outputs are explicitly defined in algorithm properties, use them.
    final declared = config.algorithmProperties['outputs'];
    if (declared is List) {
      // If the list is explicitly empty, return empty ports (no fallback)
      if (declared.isEmpty) {
        return ports;
      }

      // Process declared outputs
      for (final item in declared) {
        if (item is Map) {
          // Get mode parameter number from the item metadata (already stored during createFromSlot)
          var modeParameterNumber = coerceInt(item['modeParameterNumber']);

          // Fallback to looking it up from base class if not in metadata
          if (modeParameterNumber == null) {
            final busParam = item['busParam']?.toString();
            if (busParam != null) {
              modeParameterNumber = getModeParameterNumber(busParam);
            }
          }

          final port =
              buildPortFromDeclaration(
                item,
                direction: PortDirection.output,
                defaultId: 'out_${ports.length + 1}',
                defaultName: 'Output',
                defaultType: PortType.audio,
                includeOutputMode: true,
              ).copyWith(
                modeParameterNumber: modeParameterNumber,
                channelNumber: coerceInt(item['channel']),
                isStereoChannel: item['channel'] != null,
                stereoSide: item['channel']?.toString(),
              );

          ports.add(port);
        }
      }
      return ports;
    }

    // Generate ports for each channel
    for (int channel = 0; channel < config.channelCount; channel++) {
      final channelNumber = channel + 1;

      // Generate ports for each supported type
      for (final portType in config.supportedPortTypes) {
        final portTypeName = _getPortTypeName(portType);

        if (config.supportsStereoChannels && portType == PortType.audio) {
          // Generate stereo pair for audio channels
          ports.add(
            Port(
              id: 'multi_${portType.name}_out_${channelNumber}_l',
              name: '${config.portNamePrefix} $channelNumber $portTypeName L',
              type: portType,
              direction: PortDirection.output,
              description:
                  'Left $portTypeName output for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: true,
              stereoSide: 'left',
            ),
          );

          ports.add(
            Port(
              id: 'multi_${portType.name}_out_${channelNumber}_r',
              name: '${config.portNamePrefix} $channelNumber $portTypeName R',
              type: portType,
              direction: PortDirection.output,
              description:
                  'Right $portTypeName output for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: true,
              stereoSide: 'right',
            ),
          );
        } else {
          // Generate mono port
          ports.add(
            Port(
              id: 'multi_${portType.name}_out_$channelNumber',
              name: '${config.portNamePrefix} $channelNumber $portTypeName Out',
              type: portType,
              direction: PortDirection.output,
              description: '$portTypeName output for channel $channelNumber',
              // Direct properties
              channelNumber: channelNumber,
              isMultiChannel: true,
              isStereoChannel: false,
            ),
          );
        }
      }
    }

    // Create master mix outputs if enabled and we have multiple channels
    if (config.createMasterMix && config.channelCount > 1) {
      for (final portType in config.supportedPortTypes) {
        final portTypeName = _getPortTypeName(portType);

        if (config.supportsStereoChannels && portType == PortType.audio) {
          // Stereo master mix
          ports.add(
            Port(
              id: 'multi_mix_${portType.name}_out_l',
              name: 'Master Mix $portTypeName L',
              type: portType,
              direction: PortDirection.output,
              description: 'Left master mix $portTypeName output',
              // Direct properties
              isMasterMix: true,
              isStereoChannel: true,
              stereoSide: 'left',
            ),
          );

          ports.add(
            Port(
              id: 'multi_mix_${portType.name}_out_r',
              name: 'Master Mix $portTypeName R',
              type: portType,
              direction: PortDirection.output,
              description: 'Right master mix $portTypeName output',
              // Direct properties
              isMasterMix: true,
              isStereoChannel: true,
              stereoSide: 'right',
            ),
          );
        } else {
          // Mono master mix
          ports.add(
            Port(
              id: 'multi_mix_${portType.name}_out',
              name: 'Master Mix $portTypeName Out',
              type: portType,
              direction: PortDirection.output,
              description: 'Master mix $portTypeName output',
              // Direct properties
              isMasterMix: true,
            ),
          );
        }
      }
    }

    return ports;
  }

  @override
  bool validateConnection(Port source, Port destination) {
    // First, use the base validation
    if (!super.validateConnection(source, destination)) {
      return false;
    }

    // Master mix connections have special rules (check first)
    if (_isMasterMixPort(source) || _isMasterMixPort(destination)) {
      return _validateMasterMixConnection(source, destination);
    }

    // Stereo channel validation
    if (_isStereoPort(source) || _isStereoPort(destination)) {
      return _validateStereoConnection(source, destination);
    }

    // Additional multi-channel specific validation
    if (_isMultiChannelPort(source) && _isMultiChannelPort(destination)) {
      return _validateMultiChannelConnection(source, destination);
    }

    return true;
  }

  /// Validates multi-channel specific connections
  bool _validateMultiChannelConnection(Port source, Port destination) {
    // If both ports are from specific channels, they should be compatible
    final sourceChannel = _getChannelNumber(source);
    final destChannel = _getChannelNumber(destination);

    // Allow connections between any channels if independent routing is enabled
    if (config.allowsIndependentChannels) {
      return true;
    }

    // Otherwise, channels must match
    if (sourceChannel != null && destChannel != null) {
      return sourceChannel == destChannel;
    }

    return true;
  }

  /// Validates stereo channel connections
  bool _validateStereoConnection(Port source, Port destination) {
    // If this routing doesn't support stereo, defer to base validation
    if (!config.supportsStereoChannels) {
      return true; // Let base validation handle it
    }

    // Stereo sides should match (left-to-left, right-to-right)
    final sourceSide = _getStereoSide(source);
    final destSide = _getStereoSide(destination);

    // If both have stereo sides, they must match
    if (sourceSide != null && destSide != null) {
      return sourceSide == destSide;
    }

    // Allow mono to stereo connections (source has no side, destination has side)
    // Allow stereo to mono connections (source has side, destination has no side)
    return true;
  }

  /// Validates master mix connections
  bool _validateMasterMixConnection(Port source, Port destination) {
    // Master mix outputs should only connect to external destinations
    if (_isMasterMixPort(source) && _isMultiChannelPort(destination)) {
      return false;
    }

    return true;
  }

  /// Gets a human-readable name for a port type
  String _getPortTypeName(PortType type) {
    switch (type) {
      case PortType.audio:
        return 'Audio';
      case PortType.cv:
        return 'CV';
    }
  }

  /// Checks if a port is a multi-channel port
  bool _isMultiChannelPort(Port port) {
    return port.isMultiChannel;
  }

  /// Checks if a port is a stereo port
  bool _isStereoPort(Port port) {
    return port.isStereoChannel;
  }

  /// Checks if a port is a master mix port
  bool _isMasterMixPort(Port port) {
    return port.isMasterMix;
  }

  /// Gets the channel number from a multi-channel port
  int? _getChannelNumber(Port port) {
    return port.channelNumber;
  }

  /// Gets the stereo side from a stereo port
  String? _getStereoSide(Port port) {
    return port.stereoSide;
  }

  /// Updates the channel count and regenerates ports
  void updateChannelCount(int newChannelCount) {
    if (newChannelCount != config.channelCount && newChannelCount > 0) {
      // Clear cached ports to force regeneration
      clearPortCaches();
    }
  }

  /// Gets all ports for a specific channel
  List<Port> getPortsForChannel(int channelNumber) {
    final allPorts = [...inputPorts, ...outputPorts];
    return allPorts
        .where((port) => _getChannelNumber(port) == channelNumber)
        .toList();
  }

  /// Gets all master mix ports
  List<Port> getMasterMixPorts() {
    return outputPorts.where(_isMasterMixPort).toList();
  }

  /// Checks if the configuration supports the given channel count
  bool supportsChannelCount(int channelCount) {
    return channelCount > 0 && channelCount <= config.channelCount;
  }

  /// Determines if this routing implementation can handle the given slot.
  ///
  /// Returns true for all algorithms (this is the default fallback).
  /// Poly algorithms are handled by PolyAlgorithmRouting first.
  static bool canHandle(Slot slot) {
    // This is the fallback for all non-poly algorithms
    return true;
  }

  /// Get the width/channel count from various possible parameter names
  ///
  /// Checks multiple common parameter names that indicate width or channel count.
  /// Returns 1 if no width parameter is found.
  ///
  /// **IMPORTANT**: This is an exception to the flag-driven approach used for I/O
  /// detection. Width parameters control routing behavior (channel count) but are
  /// not themselves I/O parameters, so they don't have I/O flags. We must use
  /// pattern matching on parameter names to find width/channel count settings.
  static int getWidthFromSlot(Slot slot) {
    // List of possible width parameter names (in priority order)
    final widthParameterNames = [
      'Width',
      'width',
      'Channels',
      'channels',
      'Channel count',
      'channel count',
      'Poly',
      'poly',
      'Voices',
      'voices',
    ];

    for (final paramName in widthParameterNames) {
      if (AlgorithmRouting.hasParameter(slot, paramName)) {
        final value = AlgorithmRouting.getParameterValue(slot, paramName);
        if (value > 0) {
          return value;
        }
      }
    }

    return 1; // Default to 1 if no width parameter found
  }

  /// Creates a MultiChannelAlgorithmRouting instance from a slot.
  ///
  /// Converts all routing parameters to input/output ports based on their names.
  /// Checks for a 'Width' parameter to determine channel count for multi-channel algorithms.
  ///
  /// Parameters:
  /// - [slot]: The slot containing algorithm and parameter information
  /// - [ioParameters]: Pre-extracted routing parameters (bus assignments)
  /// - [modeParameters]: Pre-extracted mode parameters (Add/Replace modes)
  /// - [modeParametersWithNumbers]: Mode parameters with their parameter numbers
  /// - [algorithmUuid]: Optional UUID for the algorithm instance
  /// - [defaultOutputMode]: When an output port has no mode set, use this as default.
  ///   Used for algorithms that always operate in a single mode (e.g. Quantizer always replaces).
  /// - [replaceNoneOutputWithInput]: When true, output ports with busValue == 0
  ///   (Output = None) are displayed as Replace outputs on the matching input
  ///   bus. The real output parameter is preserved so the bus remains editable.
  static MultiChannelAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
    OutputMode? defaultOutputMode,
    bool replaceNoneOutputWithInput = false,
  }) {
    // Process routing parameters as regular ports
    final inputPorts = <Map<String, Object?>>[];
    final outputPorts = <Map<String, Object?>>[];

    // Build parameter lookup for getting parameter numbers
    final paramsByName = <String, ParameterInfo>{
      for (final p in slot.parameters) p.name: p,
    };

    // Build maps of parameter numbers to their page and send page (if any).
    final parameterToPageName = <int, String>{};
    final parameterToSendPage = <int, String>{};
    for (final page in slot.pages.pages) {
      for (final paramNum in page.parameters) {
        parameterToPageName[paramNum] = page.name;
      }

      // Check if this is a send page (e.g., "Send 1", "Send 2")
      if (page.name.startsWith('Send ') &&
          RegExp(r'Send \d+').hasMatch(page.name)) {
        // Map all parameters in this page to the send name
        for (final paramNum in page.parameters) {
          parameterToSendPage[paramNum] = page.name;
        }
      }
    }

    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    // Only consider parameters that appear in at least one firmware-provided
    // page.  Hidden parameters (not in any page) should not appear in the
    // routing views — this matches the parameter editor's behaviour.
    // When pages are empty (test mocks, offline fixtures), fall back to all.
    Set<int> computeVisibleSet(Slot target) {
      final pageParams = target.pages.pages.expand((p) => p.parameters).toSet();
      if (pageParams.isNotEmpty) return pageParams;
      return target.parameters.map((p) => p.parameterNumber).toSet();
    }

    final visible = computeVisibleSet(slot);

    final ioParameterEntries =
        <({String name, int busValue, ParameterInfo? paramInfo})>[];
    final consumedIoParameterNumbers = <int>{};

    // Prefer the slot parameter list so duplicate parameter names on different
    // pages (for example mixer channel inputs) do not collapse into one map key.
    for (final param in slot.parameters) {
      if (!visible.contains(param.parameterNumber)) continue;
      final isIoParameter =
          param.isInput ||
          param.isOutput ||
          AlgorithmRouting.isHardcodedInput(slot.algorithm.guid, param.name);
      if (!isIoParameter) continue;

      ioParameterEntries.add((
        name: param.name,
        busValue: valueByParam[param.parameterNumber] ?? param.defaultValue,
        paramInfo: param,
      ));
      consumedIoParameterNumbers.add(param.parameterNumber);
    }

    // Preserve compatibility with callers/tests that provide synthetic
    // ioParameters not present in the slot metadata.
    for (final entry in ioParameters.entries) {
      final fallbackParamInfo = paramsByName[entry.key];
      if (fallbackParamInfo != null &&
          consumedIoParameterNumbers.contains(
            fallbackParamInfo.parameterNumber,
          )) {
        continue;
      }

      ioParameterEntries.add((
        name: entry.key,
        busValue: entry.value,
        paramInfo: fallbackParamInfo,
      ));
    }

    final ioNameCounts = <String, int>{};
    for (final entry in ioParameterEntries) {
      ioNameCounts[entry.name] = (ioNameCounts[entry.name] ?? 0) + 1;
    }

    // Group send parameters by send number
    final sendGroups = <String, Map<String, dynamic>>{};

    // First pass: collect all send-related parameters (including non-bus ones like width/mode)
    for (final param in slot.parameters) {
      if (!visible.contains(param.parameterNumber)) continue;
      final sendPage = parameterToSendPage[param.parameterNumber];
      if (sendPage != null) {
        sendGroups[sendPage] ??= {};
        final lowerName = param.name.toLowerCase();

        if (lowerName.contains('width')) {
          // Get the actual width value from parameter values
          // Width is an enum: 0 = Mono, 1 = Stereo
          final widthValue = AlgorithmRouting.getParameterValueByNumber(
            slot,
            param.parameterNumber,
            defaultValue: param.defaultValue,
          );
          sendGroups[sendPage]!['width'] = widthValue;
        } else if (lowerName.contains('output mode')) {
          // Get the actual mode value
          final modeValue = AlgorithmRouting.getParameterValueByNumber(
            slot,
            param.parameterNumber,
            defaultValue: param.defaultValue,
          );
          sendGroups[sendPage]!['outputMode'] = modeValue;
          sendGroups[sendPage]!['modeParameterNumber'] = param.parameterNumber;
        }
      }
    }

    // Process routing parameters as regular ports
    for (final entry in ioParameterEntries) {
      final paramName = entry.name;
      final busValue = entry.busValue;

      // Get parameter number for unique ID generation
      final paramInfo = entry.paramInfo;
      final paramNumber = paramInfo?.parameterNumber ?? 0;

      // Check if this parameter belongs to a send page
      final sendPage = parameterToSendPage[paramNumber];
      if (sendPage != null) {
        // This is a send parameter - handle destination
        sendGroups[sendPage] ??= {};
        final lowerName = paramName.toLowerCase();

        if (lowerName.contains('destination')) {
          sendGroups[sendPage]!['destination'] = busValue;
          sendGroups[sendPage]!['destinationParam'] = paramName;
          sendGroups[sendPage]!['destinationNumber'] = paramNumber;
        }
        // Skip normal processing for send parameters
        continue;
      }

      // Determine if this is an input or output based on I/O flags from hardware
      // I/O flags come from firmware SysEx messages (Story 7.3)
      // Bit 0: isInput, Bit 1: isOutput, Bit 2: isAudio, Bit 3: isOutputMode
      final bool isOutputFlag = paramInfo?.isOutput ?? false;
      final bool isInputFlag =
          (paramInfo?.isInput ?? false) ||
          AlgorithmRouting.isHardcodedInput(slot.algorithm.guid, paramName);

      // Fallback logic for offline/mock mode (ioFlags = 0): infer direction
      // from the current firmware's physical output range.
      final bool isOutput =
          isOutputFlag ||
          (!isInputFlag && !isOutputFlag && deviceIoProfile.isOutput(busValue));

      // Infer port type from isAudio flag
      // Audio/CV distinction is cosmetic only - affects port color, not connectivity
      // Audio (isAudio=true): VU meter on hardware, warm color in UI
      // CV (isAudio=false): Voltage value on hardware, cool color in UI
      final bool isAudioFlag = paramInfo?.isAudio ?? false;
      final PortType portType = isAudioFlag ? PortType.audio : PortType.cv;

      // Create a sanitized version of the parameter name for the port ID
      // This preserves numbered prefixes like "1:" in "1:Trigger input"
      final sanitizedName = paramName
          .replaceAll(' ', '_')
          .replaceAll('/', '_')
          .replaceAll('\\', '_')
          .replaceAll('(', '')
          .replaceAll(')', '');

      final pageName = paramInfo == null
          ? null
          : parameterToPageName[paramInfo.parameterNumber];
      final displayName =
          (ioNameCounts[paramName] ?? 0) > 1 &&
              pageName != null &&
              pageName.isNotEmpty
          ? '$pageName: $paramName'
          : paramName;

      final port = {
        'id': '${algorithmUuid ?? 'algo'}_${sanitizedName}_$paramNumber',
        // Use algorithm UUID, sanitized name, and parameter number for uniqueness
        'name': displayName,
        'type': portType == PortType.audio
            ? 'audio'
            : 'cv', // Store as string for parsing
        'busParam': paramName,
        'busValue': busValue,
        // Store bus value for connection discovery
        'parameterNumber': paramNumber,
        // Store parameter number for reference
      };

      if (isOutput) {
        // Add channel metadata for stereo outputs
        // Note: Stereo detection still uses name matching as there's no hardware flag for this
        final lowerName = paramName.toLowerCase();
        if (lowerName.contains('left')) {
          port['channel'] = 'left';
        } else if (lowerName.contains('right')) {
          port['channel'] = 'right';
        } else if (lowerName.contains('mono')) {
          port['channel'] = 'mono';
        }

        // Determine output mode from hardware data (Story 7.6)
        // Use outputModeMap from SysEx 0x55 responses instead of pattern matching
        int? modeParameterNumber;
        String? outputMode;

        // Check if this output parameter is controlled by any mode parameter
        // by iterating through the output mode map
        for (final entry in slot.outputModeMap.entries) {
          final sourceParam = entry.key; // Mode control parameter number
          final affectedParams =
              entry.value; // List of affected output parameters

          if (affectedParams.contains(paramNumber)) {
            // This output is controlled by a mode parameter
            modeParameterNumber = sourceParam;

            // Get the current value of the mode parameter (0 = Add, 1 = Replace)
            final modeValue = AlgorithmRouting.getParameterValueByNumber(
              slot,
              sourceParam,
              defaultValue: 0,
            );

            outputMode = (modeValue == 1) ? 'replace' : 'add';
            break; // Found the mode parameter for this output
          }
        }

        // Apply output mode to port if found
        if (outputMode != null) {
          port['outputMode'] = outputMode;
        }

        // Store mode parameter number if found
        if (modeParameterNumber != null) {
          port['modeParameterNumber'] = modeParameterNumber;
        }

        // Fallback for offline/mock mode when no outputModeMap data (Story 7.6 AC-6)
        // When ioFlags == 0, use pattern matching as temporary fallback
        if (slot.outputModeMap.isEmpty && modeParameters != null) {
          // Offline mode fallback: use pattern matching temporarily
          final List<String> possibleModeNames = [
            '$paramName mode',
            '${paramName.split(' ').first} mode',
            'Output mode',
          ];

          for (final name in possibleModeNames) {
            if (modeParameters.containsKey(name)) {
              final modeValue = modeParameters[name];
              port['outputMode'] = (modeValue == 1) ? 'replace' : 'add';

              // Also try to get the parameter number for offline mode
              if (modeParametersWithNumbers != null &&
                  modeParametersWithNumbers.containsKey(name)) {
                final modeInfo = modeParametersWithNumbers[name];
                port['modeParameterNumber'] = modeInfo!.parameterNumber;
              }
              break;
            }
          }
        }

        // Apply default output mode for algorithms that always use one mode
        // (e.g. Quantizer always replaces, regardless of any mode parameter).
        if (port['outputMode'] == null && defaultOutputMode != null) {
          port['outputMode'] = defaultOutputMode == OutputMode.replace
              ? 'replace'
              : 'add';
        }

        outputPorts.add(port);
      } else {
        inputPorts.add(port);
      }
    }

    // Process send groups to create output ports
    for (final entry in sendGroups.entries) {
      final sendName = entry.key;
      final sendData = entry.value;

      final destination = sendData['destination'] as int?;
      final width = sendData['width'] as int? ?? 0; // Default to 0 (Mono)
      final outputMode = sendData['outputMode'] as int? ?? 0;
      final destinationParam =
          sendData['destinationParam'] as String? ?? sendName;
      final destinationNumber = sendData['destinationNumber'] as int? ?? 0;
      final modeParamNumber = sendData['modeParameterNumber'] as int?;

      if (destination == null) {
        continue;
      }

      // Extract send number from name (e.g., "Send 1" -> "1")
      final sendNumber = sendName.replaceAll(RegExp(r'[^0-9]'), '');

      // Width is an enum: 0 = Mono, 1 = Stereo
      if (width == 1) {
        // Stereo send - create L and R outputs
        outputPorts.add({
          'id': '${algorithmUuid ?? 'algo'}_send_${sendNumber}_l',
          'name': '$sendName L',
          'type': 'audio',
          'busParam': destinationParam,
          'busValue': destination,
          'parameterNumber': destinationNumber,
          'outputMode': outputMode == 1 ? 'replace' : 'add',
          'modeParameterNumber': modeParamNumber,
          'channel': 'left',
        });
        outputPorts.add({
          'id': '${algorithmUuid ?? 'algo'}_send_${sendNumber}_r',
          'name': '$sendName R',
          'type': 'audio',
          'busParam': '$destinationParam R',
          'busValue': destination + 1, // Right channel uses next bus
          'parameterNumber': null,
          'outputMode': outputMode == 1 ? 'replace' : 'add',
          'modeParameterNumber': modeParamNumber,
          'channel': 'right',
        });
      } else {
        // Mono send - create single output
        outputPorts.add({
          'id': '${algorithmUuid ?? 'algo'}_send_$sendNumber',
          'name': sendName,
          'type': 'audio',
          'busParam': destinationParam,
          'busValue': destination,
          'parameterNumber': destinationNumber,
          'outputMode': outputMode == 1 ? 'replace' : 'add',
          'modeParameterNumber': modeParamNumber,
        });
      }
    }

    // For conditional in-place algorithms (Output = None means write to Input
    // bus in Replace mode), keep the real output parameter but use the
    // matching input bus as its effective visual/routing bus.
    if (replaceNoneOutputWithInput) {
      String channelPrefix(String? busParam) {
        if (busParam == null) return '';
        final colon = busParam.indexOf(':');
        return colon >= 0 ? busParam.substring(0, colon + 1) : '';
      }

      for (final outPort in outputPorts) {
        final busValue = outPort['busValue'] as int? ?? 0;
        if (busValue != 0) continue;

        final prefix = channelPrefix(outPort['busParam'] as String?);
        final inputPort = inputPorts.firstWhereOrNull((p) {
          final ipPrefix = channelPrefix(p['busParam'] as String?);
          final ipBus = p['busValue'] as int? ?? 0;
          return ipPrefix == prefix && ipBus > 0;
        });

        if (inputPort != null) {
          outPort['busValue'] = inputPort['busValue'];
          outPort['outputMode'] = 'replace';
          outPort.remove('modeParameterNumber');
        }
      }
    }

    // Check for Width parameter to determine channel count
    final channelCount = getWidthFromSlot(slot);

    // Duplicate I/O ports for width-based algorithms (all ports identified by ioFlags)
    if (channelCount > 1) {
      // Collect insertions first to avoid index corruption during iteration
      final inputInsertions = <int, List<Map<String, Object?>>>{};
      for (int i = 0; i < inputPorts.length; i++) {
        final port = inputPorts[i];
        final baseBusValue = port['busValue'] as int? ?? 0;
        if (baseBusValue > 0) {
          final portName = port['name'] as String? ?? 'Input';
          final virtualPorts = <Map<String, Object?>>[];
          for (int channel = 2; channel <= channelCount; channel++) {
            virtualPorts.add({
              'id': '${algorithmUuid ?? 'algo'}_input_${i}_$channel',
              'name': '$portName $channel',
              'type': port['type'],
              'busParam': null,
              'busValue': baseBusValue + (channel - 1),
              'parameterNumber': -(i * 100 + channel),
              'isVirtualPort': true,
              'channelNumber': channel,
              'basedOn': portName,
            });
          }
          inputInsertions[i] = virtualPorts;
        }
      }
      for (final index in inputInsertions.keys.toList().reversed) {
        inputPorts.insertAll(index + 1, inputInsertions[index]!);
      }

      final outputInsertions = <int, List<Map<String, Object?>>>{};
      for (int i = 0; i < outputPorts.length; i++) {
        final port = outputPorts[i];
        final baseBusValue = port['busValue'] as int? ?? 0;
        if (baseBusValue > 0) {
          final portName = port['name'] as String? ?? 'Output';
          final virtualPorts = <Map<String, Object?>>[];
          for (int channel = 2; channel <= channelCount; channel++) {
            virtualPorts.add({
              'id': '${algorithmUuid ?? 'algo'}_output_${i}_$channel',
              'name': '$portName $channel',
              'type': port['type'],
              'busParam': null,
              'busValue': baseBusValue + (channel - 1),
              'parameterNumber': -(i * 100 + channel + 50),
              'isVirtualPort': true,
              'channelNumber': channel,
              'basedOn': portName,
              if (port['outputMode'] != null) 'outputMode': port['outputMode'],
              if (port['modeParameterNumber'] != null)
                'modeParameterNumber': port['modeParameterNumber'],
            });
          }
          outputInsertions[i] = virtualPorts;
        }
      }
      for (final index in outputInsertions.keys.toList().reversed) {
        outputPorts.insertAll(index + 1, outputInsertions[index]!);
      }
    }

    // Determine if this is a multi-channel algorithm
    final isMultiChannel = channelCount > 1;

    // Create appropriate configuration
    final MultiChannelAlgorithmConfig config;
    if (isMultiChannel) {
      config = MultiChannelAlgorithmConfig.widthBased(
        width: channelCount,
        supportsStereo: outputPorts.any(
          (p) => p['channel'] == 'left' || p['channel'] == 'right',
        ),
      );
    } else {
      config = MultiChannelAlgorithmConfig.normal();
    }

    // Store the ports in algorithm properties
    final properties = {
      'algorithmGuid': slot.algorithm.guid,
      'algorithmName': slot.algorithm.name,
      'algorithmUuid': algorithmUuid,
      'inputs': inputPorts,
      'outputs': outputPorts,
      'channelCount': channelCount,
      'isMultiChannel': isMultiChannel,
    };

    final routing = MultiChannelAlgorithmRouting(
      config: MultiChannelAlgorithmConfig(
        channelCount: config.channelCount,
        supportsStereoChannels: config.supportsStereoChannels,
        allowsIndependentChannels: config.allowsIndependentChannels,
        supportedPortTypes: config.supportedPortTypes,
        portNamePrefix: config.portNamePrefix,
        createMasterMix: config.createMasterMix,
        algorithmProperties: properties,
      ),
    );
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }
}
