import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'algorithm_routing.dart';
import 'models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

typedef _GateCvParameterPair = ({ParameterInfo gate, ParameterInfo count});

/// Configuration data for polyphonic algorithm routing.
///
/// Defines the properties needed to configure polyphonic routing behavior,
/// including the number of voices and gate/CV requirements.
@immutable
class PolyAlgorithmConfig {
  /// Number of polyphonic voices supported by this algorithm
  final int voiceCount;

  /// Whether this algorithm requires gate inputs for each voice
  final bool requiresGateInputs;

  /// Whether this algorithm uses virtual CV ports for modulation
  final bool usesVirtualCvPorts;

  /// Number of virtual CV ports to generate per voice
  final int virtualCvPortsPerVoice;

  /// Optional explicit gate bus assignments for poly algorithms that follow
  /// the Disting NT polysynth pattern (Gate + N CVs on consecutive busses).
  ///
  /// Each entry is the selected bus for Gate N (0 means 'None').
  /// Only non-zero (connected) gates will produce CV input ports.
  final List<int>? gateInputs;

  /// Optional CV counts for each gate (same indexing as [gateInputs]).
  /// Determines how many CV inputs are available on consecutive busses
  /// immediately after the gate bus for that gate. If omitted, defaults to 0.
  final List<int>? gateCvCounts;

  /// Base name prefix for generated ports
  final String portNamePrefix;

  /// Additional algorithm-specific properties
  final Map<String, dynamic> algorithmProperties;

  const PolyAlgorithmConfig({
    required this.voiceCount,
    this.requiresGateInputs = true,
    this.usesVirtualCvPorts = true,
    this.virtualCvPortsPerVoice = 2,
    this.gateInputs,
    this.gateCvCounts,
    this.portNamePrefix = 'Voice',
    this.algorithmProperties = const {},
  });
}

/// Concrete implementation of AlgorithmRouting for polyphonic routing.
///
/// This class handles polyphonic routing with gate input and virtual CV ports
/// based on algorithm properties. It dynamically generates ports based on the
/// number of voices and routing requirements of the polyphonic algorithm.
///
/// Each voice typically includes:
/// - Audio input/output ports
/// - Gate input for triggering
/// - CV inputs for modulation (if enabled)
///
/// Example usage:
/// ```dart
/// final config = PolyAlgorithmConfig(
///   voiceCount: 4,
///   requiresGateInputs: true,
///   usesVirtualCvPorts: true,
/// );
///
/// final polyRouting = PolyAlgorithmRouting(config: config);
/// final inputPorts = polyRouting.generateInputPorts();
/// ```
class PolyAlgorithmRouting extends CachedAlgorithmRouting {
  static final RegExp _gateInputNamePattern = RegExp(
    r'^Gate input (\d+)$',
    caseSensitive: false,
  );
  static final RegExp _gateCvCountNamePattern = RegExp(
    r'^Gate (\d+) CV count$',
    caseSensitive: false,
  );

  /// Configuration for this polyphonic routing instance
  final PolyAlgorithmConfig config;

  /// Creates a new PolyAlgorithmRouting instance.
  ///
  /// Parameters:
  /// - [config]: Configuration defining the polyphonic routing behavior
  /// - [validator]: Optional port compatibility validator (uses default if not provided)
  /// - [initialState]: Optional initial routing state
  PolyAlgorithmRouting({
    required this.config,
    super.validator,
    super.initialState,
  }) : super(
         algorithmUuid: config.algorithmProperties['algorithmUuid'] as String?,
       );

  @override
  List<Port> generateInputPorts() {
    final ports = <Port>[];

    // If explicit gate inputs are provided (either directly or via algorithmProperties),
    // follow the gate + CV-per-gate pattern.
    List<int>? gateInputsFromProps;
    List<int>? gateCvCountsFromProps;
    final props = config.algorithmProperties;
    if (config.gateInputs == null && props.containsKey('gateInputs')) {
      final raw = props['gateInputs'];
      if (raw is List) {
        gateInputsFromProps = raw
            .map((e) => (e is num) ? e.toInt() : 0)
            .toList();
      }
    }
    if (config.gateCvCounts == null && props.containsKey('gateCvCounts')) {
      final raw = props['gateCvCounts'];
      if (raw is List) {
        gateCvCountsFromProps = raw
            .map((e) => (e is num) ? e.toInt() : 0)
            .toList();
      }
    }

    final effectiveGateInputs = config.gateInputs ?? gateInputsFromProps;
    final effectiveGateCvCounts = config.gateCvCounts ?? gateCvCountsFromProps;
    final hasGateDrivenSpec =
        (effectiveGateInputs != null && effectiveGateInputs.isNotEmpty) &&
        config.requiresGateInputs;
    if (hasGateDrivenSpec) {
      final gateInputs =
          effectiveGateInputs; // Non-null due to hasGateDrivenSpec
      final gateCvCounts = effectiveGateCvCounts ?? const [];

      for (int gateIndex = 0; gateIndex < gateInputs.length; gateIndex++) {
        final gateNumber = gateIndex + 1; // 1-based
        final gateBus = gateInputs[gateIndex];

        // Only connected gates (bus > 0) produce Gate and CV ports
        if (gateBus > 0) {
          // Gate input port with algorithm UUID for uniqueness
          final algUuid =
              config.algorithmProperties['algorithmUuid'] as String?;
          final gatePortId = algUuid != null
              ? '${algUuid}_gate_$gateNumber'
              : 'poly_gate_in_$gateNumber';

          ports.add(
            Port(
              id: gatePortId,
              name: 'Gate $gateNumber',
              type: PortType.cv, // All gate/trigger signals are CV (Story 7.5)
              direction: PortDirection.input,
              description: 'Gate/trigger input for gate $gateNumber',
              // Direct properties
              isPolyVoice: true,
              voiceNumber: gateNumber,
              busValue: gateBus,
            ),
          );

          // CV inputs for this connected gate, on consecutive busses after the gate bus
          final cvCount = gateIndex < gateCvCounts.length
              ? gateCvCounts[gateIndex]
              : 0;
          for (int cv = 0; cv < cvCount; cv++) {
            final cvNumber = cv + 1;
            final algUuid =
                config.algorithmProperties['algorithmUuid'] as String?;
            final cvPortId = algUuid != null
                ? '${algUuid}_gate_${gateNumber}_cv_$cvNumber'
                : 'poly_gate_${gateNumber}_cv_$cvNumber';
            final cvBus = gateBus + cvNumber; // Bus mapping rule

            ports.add(
              Port(
                id: cvPortId,
                name: 'Gate $gateNumber CV$cvNumber',
                type: PortType.cv,
                direction: PortDirection.input,
                description: 'CV input $cvNumber for gate $gateNumber',
                // Direct properties
                isPolyVoice: true,
                voiceNumber: gateNumber,
                busValue: cvBus,
              ),
            );
          }
        }
      }
    }

    // Append any extra declared inputs (e.g., Wave input, Pitchbend input, Audio input)
    final extras = props['extraInputs'];
    if (extras is List) {
      for (final item in extras) {
        if (item is Map) {
          final port = buildPortFromDeclaration(
            item,
            direction: PortDirection.input,
            defaultId: 'extra_${ports.length + 1}',
            defaultName: 'Extra Input',
            defaultType: PortType.cv,
          ).copyWith(isVirtualCV: item['isVirtualCV'] == true);

          ports.add(port);
        }
      }
    }

    return ports;
  }

  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];

    // If outputs are explicitly defined in algorithm properties, use them.
    final outputs = config.algorithmProperties['outputs'];
    if (outputs is List && outputs.isNotEmpty) {
      for (final item in outputs) {
        if (item is Map) {
          final port =
              buildPortFromDeclaration(
                item,
                direction: PortDirection.output,
                defaultId: 'out_${ports.length + 1}',
                defaultName: 'Output',
                defaultType: PortType.audio,
                includeOutputMode: true,
              ).copyWith(
                channelNumber: coerceInt(item['channel']),
                isStereoChannel: item['channel'] != null,
                stereoSide: item['channel']?.toString(),
                isPolyVoice: item['voiceNumber'] != null,
                voiceNumber: coerceInt(item['voiceNumber']),
              );

          ports.add(port);
        }
      }
      return ports;
    }

    // No declared outputs; return empty and let higher layers decide or provide outputs via properties
    return ports;
  }

  @override
  bool validateConnection(Port source, Port destination) {
    // Virtual CV connections need special handling
    if (_isVirtualCvPort(source) || _isVirtualCvPort(destination)) {
      if (!_validateVirtualCvConnection(source, destination)) {
        return false;
      }
    }
    // For other connections, use base validation
    else if (!super.validateConnection(source, destination)) {
      return false;
    }

    // Additional polyphonic-specific validation
    if (_isPolyVoicePort(source) && _isPolyVoicePort(destination)) {
      // Voice-to-voice connections should be between same voice numbers
      final sourceVoice = _getVoiceNumber(source);
      final destVoice = _getVoiceNumber(destination);

      if (sourceVoice != null &&
          destVoice != null &&
          sourceVoice != destVoice) {
        return false;
      }
    }

    return true;
  }

  /// Validates virtual CV connections
  bool _validateVirtualCvConnection(Port source, Port destination) {
    // Virtual CV ports should only connect to CV or audio ports
    // Note: In Eurorack, all signals are voltage-based, so CV and audio are compatible
    if (_isVirtualCvPort(source)) {
      return destination.type == PortType.cv ||
          destination.type == PortType.audio;
    }

    if (_isVirtualCvPort(destination)) {
      return source.type == PortType.cv || source.type == PortType.audio;
    }

    return true;
  }

  /// Checks if a port belongs to a polyphonic voice
  bool _isPolyVoicePort(Port port) {
    return port.isPolyVoice;
  }

  /// Gets the voice number from a polyphonic voice port
  int? _getVoiceNumber(Port port) {
    return port.voiceNumber;
  }

  /// Checks if a port is a virtual CV port
  bool _isVirtualCvPort(Port port) {
    return port.isVirtualCV;
  }

  /// Updates the voice count and regenerates ports
  void updateVoiceCount(int newVoiceCount) {
    if (newVoiceCount != config.voiceCount) {
      // Clear cached ports to force regeneration
      // Note: Config is immutable, so this only clears caches for when
      // a new instance would be created with different config
      clearPortCaches();
    }
  }

  /// Determines if this routing implementation can handle the given slot.
  ///
  /// Returns true if the algorithm GUID starts with 'py' (polysynth algorithms)
  /// or is 'gran' (Granulator algorithm), or when an ordered parameter page
  /// contains a confirmed gate-input/CV-count pattern.
  static bool canHandle(Slot slot) {
    return _isKnownPolyGuid(slot.algorithm.guid) ||
        _findPageOrderedGateCvPairs(slot).isNotEmpty;
  }

  /// Resolves gate/count pairs from parameter numbers in each page's declared
  /// order. The slot's parameter-list order is deliberately irrelevant.
  ///
  /// The ordered shape is the primary signal. A known factory poly GUID or
  /// matching numbered names confirms that the structural match is polyphonic.
  static List<_GateCvParameterPair> _findPageOrderedGateCvPairs(Slot slot) {
    final parametersByNumber = <int, ParameterInfo>{
      for (final parameter in slot.parameters)
        parameter.parameterNumber: parameter,
    };

    for (final page in slot.pages.pages) {
      final orderedParameters = <ParameterInfo>[];
      for (final number in page.parameters) {
        final parameter = parametersByNumber[number];
        if (parameter == null) {
          orderedParameters.clear();
          break;
        }
        orderedParameters.add(parameter);
      }
      if (orderedParameters.isEmpty) continue;

      final candidates = <List<_GateCvParameterPair>>[
        _findInterleavedGateCvPairs(orderedParameters),
        ..._findGateThenCountBlocks(orderedParameters),
      ]..sort((left, right) => right.length.compareTo(left.length));

      for (final pairs in candidates) {
        if (pairs.isNotEmpty &&
            (_isKnownPolyGuid(slot.algorithm.guid) ||
                pairs.every(
                  (pair) => _namesConfirmGateCvPair(pair.gate, pair.count),
                ))) {
          return pairs;
        }
      }
    }

    return const [];
  }

  static List<_GateCvParameterPair> _findInterleavedGateCvPairs(
    List<ParameterInfo> orderedParameters,
  ) {
    final pairs = <_GateCvParameterPair>[];
    for (var index = 0; index + 1 < orderedParameters.length; index++) {
      final gate = orderedParameters[index];
      final count = orderedParameters[index + 1];
      if (_isGateInputCandidate(gate) && _isCvCountCandidate(count)) {
        pairs.add((gate: gate, count: count));
      }
    }
    return pairs;
  }

  static List<List<_GateCvParameterPair>> _findGateThenCountBlocks(
    List<ParameterInfo> orderedParameters,
  ) {
    final candidates = <List<_GateCvParameterPair>>[];
    for (var start = 0; start < orderedParameters.length; start++) {
      if (!_isGateInputCandidate(orderedParameters[start])) continue;

      var countStart = start;
      while (countStart < orderedParameters.length &&
          _isGateInputCandidate(orderedParameters[countStart])) {
        countStart++;
      }
      final gateCount = countStart - start;
      if (countStart + gateCount > orderedParameters.length) continue;

      final counts = orderedParameters.sublist(
        countStart,
        countStart + gateCount,
      );
      if (!counts.every(_isCvCountCandidate)) continue;

      candidates.add([
        for (var offset = 0; offset < gateCount; offset++)
          (gate: orderedParameters[start + offset], count: counts[offset]),
      ]);
    }
    return candidates;
  }

  static bool _isKnownPolyGuid(String guid) =>
      guid.startsWith('py') || guid == 'gran';

  static bool _isGateInputCandidate(ParameterInfo parameter) =>
      parameter.isInput && !parameter.isOutput && !parameter.isAudio;

  static bool _isCvCountCandidate(ParameterInfo parameter) =>
      !parameter.isInput &&
      !parameter.isOutput &&
      parameter.unit == 0 &&
      parameter.min == 0 &&
      parameter.max >= 0;

  static bool _namesConfirmGateCvPair(ParameterInfo gate, ParameterInfo count) {
    final gateMatch = _gateInputNamePattern.firstMatch(
      AlgorithmRouting.stripPagePrefix(gate.name),
    );
    final countMatch = _gateCvCountNamePattern.firstMatch(
      AlgorithmRouting.stripPagePrefix(count.name),
    );
    return gateMatch != null &&
        countMatch != null &&
        gateMatch.group(1) == countMatch.group(1);
  }

  /// Creates a PolyAlgorithmRouting instance from a slot.
  ///
  /// Extracts gate configuration following the CV/Gate Setup specification:
  /// - Up to 6 gates, each with a bus assignment (0 = None)
  /// - Each gate has a CV count (0-11)
  /// - CVs follow immediately after gate bus (e.g., gate on bus 1, CVs on buses 2-3)
  ///
  /// All other routing parameters are converted to regular input/output ports.
  ///
  /// Parameters:
  /// - [slot]: The slot containing algorithm and parameter information
  /// - [ioParameters]: Pre-extracted routing parameters (bus assignments)
  /// - [modeParameters]: Pre-extracted mode parameters (Add/Replace modes)
  /// - [modeParametersWithNumbers]: Mode parameters with their parameter numbers
  /// - [algorithmUuid]: Optional UUID for the algorithm instance
  static PolyAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    // Ensure we have a valid algorithm UUID
    final algId =
        algorithmUuid ??
        'algo_${slot.algorithm.guid}_${DateTime.now().millisecondsSinceEpoch}';

    // Build a lookup that strips page prefixes (e.g., "1:Gate input 1" → "Gate input 1")
    // so gate detection works regardless of prefix presence.
    final strippedIoParameters = <String, int>{};
    for (final entry in ioParameters.entries) {
      final key = entry.key;
      final colonIndex = key.indexOf(':');
      final stripped = colonIndex >= 0 ? key.substring(colonIndex + 1) : key;
      strippedIoParameters[stripped] = entry.value;
    }

    // Extract gate configuration per CV/Gate Setup spec
    final gateInputs = <int>[];
    final gateCvCounts = <int>[];
    final pageOrderedGateCvPairs = _findPageOrderedGateCvPairs(slot);

    if (pageOrderedGateCvPairs.isNotEmpty) {
      for (final pair in pageOrderedGateCvPairs) {
        gateInputs.add(
          AlgorithmRouting.getParameterValueByNumber(
            slot,
            pair.gate.parameterNumber,
            defaultValue: pair.gate.defaultValue,
          ),
        );
        gateCvCounts.add(
          AlgorithmRouting.getParameterValueByNumber(
            slot,
            pair.count.parameterNumber,
            defaultValue: pair.count.defaultValue,
          ),
        );
      }
    } else {
      // Legacy/offline fallback for slots without parameter-page metadata.
      for (int i = 1; i <= 6; i++) {
        final gateBus = strippedIoParameters['Gate input $i'] ?? 0;
        gateInputs.add(gateBus);
        gateCvCounts.add(
          AlgorithmRouting.getParameterValue(slot, 'Gate $i CV count'),
        );
      }
    }

    // Trim trailing unconnected gates
    while (gateInputs.isNotEmpty && gateInputs.last == 0) {
      gateInputs.removeLast();
      gateCvCounts.removeLast();
    }

    // Process remaining routing parameters as regular ports
    final inputPorts = <Map<String, Object?>>[];
    final outputPorts = <Map<String, Object?>>[];

    // Find parameter info for each io parameter to get parameter numbers
    final paramsByName = <String, ParameterInfo>{
      for (final p in slot.parameters) p.name: p,
    };
    final pageOrderedGateCvParameterNumbers = {
      for (final pair in pageOrderedGateCvPairs) ...[
        pair.gate.parameterNumber,
        pair.count.parameterNumber,
      ],
    };

    for (final entry in ioParameters.entries) {
      final paramName = entry.key;
      final busValue = entry.value;

      // Strip page prefix for matching (e.g., "1:Gate input 1" → "Gate input 1")
      final colonIndex = paramName.indexOf(':');
      final baseName = colonIndex >= 0
          ? paramName.substring(colonIndex + 1)
          : paramName;

      // Skip gate-specific parameters (handled above)
      // Also skip Poly CV configuration parameters that aren't actual ports
      if (baseName.startsWith('Gate input ') ||
          (baseName.startsWith('Gate ') && baseName.contains(' CV count')) ||
          baseName == 'First output' ||
          baseName == 'Voices' ||
          baseName == 'Gate outputs' ||
          baseName == 'Pitch outputs' ||
          baseName == 'Velocity outputs' ||
          baseName == 'Paraphonic gate' ||
          baseName == 'Para gate mode') {
        continue;
      }

      // Get parameter info to access I/O flags
      final paramInfo = paramsByName[paramName];
      if (paramInfo == null) continue;

      if (pageOrderedGateCvParameterNumbers.contains(
        paramInfo.parameterNumber,
      )) {
        continue;
      }

      // Use I/O flags from hardware metadata to determine direction
      final isOutput = paramInfo.isOutput;
      final isInput = paramInfo.isInput;

      // Skip parameters that are not I/O parameters (no I/O flags set)
      if (!isOutput && !isInput) continue;

      final paramNumber = paramInfo.parameterNumber;

      // Determine port type from isAudio flag (cosmetic only - affects port color)
      String portType = paramInfo.isAudio ? 'audio' : 'cv';

      final port = {
        'id':
            '${algId}_param_$paramNumber', // Unique ID with algorithm UUID and parameter number
        'name': paramName,
        'type': portType,
        'busParam': paramName,
        'busValue': int.tryParse(busValue.toString()),
        'parameterNumber': int.tryParse(paramNumber.toString()),
      };

      if (isOutput) {
        // Add channel metadata for stereo outputs (still uses name pattern - not I/O related)
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

        outputPorts.add(port);
      } else {
        inputPorts.add(port);
      }
    }

    // Get voice count if available
    int voiceCount = 1;
    final maxVoices = AlgorithmRouting.getParameterValue(slot, 'Max voices');
    if (maxVoices > 0) {
      voiceCount = maxVoices;
    } else {
      final voices = AlgorithmRouting.getParameterValue(slot, 'Voices');
      if (voices > 0) voiceCount = voices;
    }

    // Determine if this algorithm actually has gate inputs
    final hasGateInputs = gateInputs.any((bus) => bus > 0);

    // Check if this algorithm uses the Poly CV output pattern
    // (has "First output", "Gate outputs", "Pitch outputs", "Velocity outputs" parameters)
    final firstOutput = AlgorithmRouting.getParameterValue(
      slot,
      'First output',
    );
    final gateOutputsParam = slot.parameters.firstWhere(
      (p) =>
          p.name == 'Gate outputs' ||
          AlgorithmRouting.stripPagePrefix(p.name) == 'Gate outputs',
      orElse: () => ParameterInfo.filler(),
    );
    final hasPolyCvOutputPattern =
        firstOutput > 0 && gateOutputsParam.parameterNumber >= 0;

    if (hasPolyCvOutputPattern) {
      // Handle Poly CV output pattern
      // Get boolean parameters (these are checkboxes, so 1 = enabled, 0 = disabled)
      final gateOutputs = AlgorithmRouting.getParameterValue(
        slot,
        'Gate outputs',
      );
      final pitchOutputs = AlgorithmRouting.getParameterValue(
        slot,
        'Pitch outputs',
      );
      final velocityOutputs = AlgorithmRouting.getParameterValue(
        slot,
        'Velocity outputs',
      );

      // Get ES-5 parameters for gate routing
      final es5ExpanderValue = AlgorithmRouting.getParameterValue(
        slot,
        'ES-5 Expander',
      );
      final es5OutputValue = AlgorithmRouting.getParameterValue(
        slot,
        'ES-5 Output',
      );

      // Get ES-5 Expander parameter number for UI toggle synchronization
      final es5ExpanderParam = slot.parameters.firstWhere(
        (p) =>
            p.name == 'ES-5 Expander' ||
            AlgorithmRouting.stripPagePrefix(p.name) == 'ES-5 Expander',
        orElse: () => ParameterInfo.filler(),
      );
      final es5ExpanderParamNumber = es5ExpanderParam.parameterNumber >= 0
          ? es5ExpanderParam.parameterNumber
          : null;

      final useEs5ForGates = es5ExpanderValue > 0 && gateOutputs > 0;

      // Generate output ports for each voice
      for (int voice = 0; voice < voiceCount; voice++) {
        // Voice numbering is 1-based for display
        final voiceNum = voice + 1;

        if (gateOutputs > 0) {
          // Get Gate mode if available
          String? gateMode;
          if (modeParameters != null &&
              modeParameters.containsKey('Gate mode')) {
            gateMode = modeParameters['Gate mode'] == 1 ? 'replace' : 'add';
          }

          if (useEs5ForGates) {
            // ES-5 MODE: Gates route to ES-5 expander ports
            final es5Port = es5OutputValue + voice;

            // Handle edge case: If voice count > 8, clip to ES-5 port range (1-8)
            if (es5Port <= 8) {
              final portMap = <String, dynamic>{
                'id': '${algId}_gate_output_$voiceNum',
                'name': 'Voice $voiceNum Gate → ES-5 $es5Port',
                'type': 'gate',
                'busParam': 'es5_direct', // Special marker for ES-5 routing
                'channel':
                    es5Port, // ES-5 port number (using 'channel' key for Port.fromJson)
                'parameterNumber': 0,
                'voiceNumber': voiceNum,
              };

              if (gateMode != null) {
                portMap['outputMode'] = gateMode;
              }

              // Only include es5ExpanderParamNumber if valid
              if (es5ExpanderParamNumber != null) {
                portMap['es5ExpanderParamNumber'] = es5ExpanderParamNumber;
              }

              outputPorts.add(portMap);
            } else {}
          } else {
            // NORMAL MODE: Gates use normal bus allocation
            // Bus calculation: firstOutput + (voice * total_outputs_per_voice) + offset_within_voice
            int outputsPerVoice = 0;
            if (gateOutputs > 0) outputsPerVoice++;
            if (pitchOutputs > 0) outputsPerVoice++;
            if (velocityOutputs > 0) outputsPerVoice++;

            final currentBus = firstOutput + (voice * outputsPerVoice);

            outputPorts.add({
              'id': '${algId}_gate_output_$voiceNum',
              'name': 'Gate output $voiceNum',
              'type': 'gate',
              'busValue': currentBus,
              'busParam': 'Gate output',
              'parameterNumber': 0,
              'voiceNumber': voiceNum,
              'outputMode': gateMode,
            });
          }
        }

        // Pitch and Velocity CVs ALWAYS use normal bus allocation
        // (ES-5 does not affect CV outputs)
        // Bus allocation: Each voice occupies busOutputsPerVoice buses
        // When gates use ES-5, they don't consume a bus
        int busOutputsPerVoice = 0;
        if (gateOutputs > 0 && !useEs5ForGates) busOutputsPerVoice++;
        if (pitchOutputs > 0) busOutputsPerVoice++;
        if (velocityOutputs > 0) busOutputsPerVoice++;

        int cvBusOffset = 0;
        // When gates use normal buses, CVs come after gates within this voice's allocation
        // When gates use ES-5, CVs start from firstOutput (gates don't consume buses)
        if (!useEs5ForGates && gateOutputs > 0) {
          cvBusOffset = 1; // Skip gate bus within this voice's bus allocation
        }

        final cvBaseBus =
            firstOutput + (voice * busOutputsPerVoice) + cvBusOffset;
        int currentCvOffset = 0;

        if (pitchOutputs > 0) {
          // Get Pitch mode if available
          String? pitchMode;
          if (modeParameters != null &&
              modeParameters.containsKey('Pitch mode')) {
            pitchMode = modeParameters['Pitch mode'] == 1 ? 'replace' : 'add';
          }

          outputPorts.add({
            'id': '${algId}_pitch_output_$voiceNum',
            'name': 'Pitch output $voiceNum',
            'type': 'cv',
            'busValue': cvBaseBus + currentCvOffset,
            'busParam': 'Pitch output',
            'parameterNumber': 0,
            'voiceNumber': voiceNum,
            'outputMode': pitchMode,
          });

          currentCvOffset++;
        }

        if (velocityOutputs > 0) {
          // Get Velocity mode if available
          String? velocityMode;
          if (modeParameters != null &&
              modeParameters.containsKey('Velocity mode')) {
            velocityMode = modeParameters['Velocity mode'] == 1
                ? 'replace'
                : 'add';
          }

          outputPorts.add({
            'id': '${algId}_velocity_output_$voiceNum',
            'name': 'Velocity output $voiceNum',
            'type': 'cv',
            'busValue': cvBaseBus + currentCvOffset,
            'busParam': 'Velocity output',
            'parameterNumber': 0,
            'voiceNumber': voiceNum,
            'outputMode': velocityMode,
          });

          currentCvOffset++;
        }
      }
    }

    // Handle Paraphonic gate as a dedicated single output (not per-voice, never ES-5)
    final paraphonicGateParam = slot.parameters.firstWhere(
      (p) =>
          p.name == 'Paraphonic gate' ||
          AlgorithmRouting.stripPagePrefix(p.name) == 'Paraphonic gate',
      orElse: () => ParameterInfo.filler(),
    );
    final hasParaphonicGate = paraphonicGateParam.parameterNumber >= 0;
    final paraphonicGateBus = hasParaphonicGate
        ? AlgorithmRouting.getParameterValue(slot, 'Paraphonic gate')
        : 0;
    if (hasParaphonicGate) {
      String? paraGateMode;
      if (modeParameters != null &&
          modeParameters.containsKey('Para gate mode')) {
        paraGateMode = modeParameters['Para gate mode'] == 1
            ? 'replace'
            : 'add';
      }

      // Get mode from outputModeMap if available
      final paraGateModeParam = slot.parameters.firstWhere(
        (p) =>
            p.name == 'Para gate mode' ||
            AlgorithmRouting.stripPagePrefix(p.name) == 'Para gate mode',
        orElse: () => ParameterInfo.filler(),
      );

      int? modeParameterNumber;
      if (paraGateModeParam.parameterNumber >= 0) {
        modeParameterNumber = paraGateModeParam.parameterNumber;
      }

      // Check outputModeMap for mode value
      if (paraphonicGateParam.parameterNumber >= 0) {
        for (final entry in slot.outputModeMap.entries) {
          if (entry.value.contains(paraphonicGateParam.parameterNumber)) {
            final modeValue = AlgorithmRouting.getParameterValueByNumber(
              slot,
              entry.key,
              defaultValue: 0,
            );
            paraGateMode = (modeValue == 1) ? 'replace' : 'add';
            modeParameterNumber = entry.key;
            break;
          }
        }
      }

      outputPorts.add({
        'id': '${algId}_paraphonic_gate',
        'name': 'Paraphonic gate',
        'type': 'gate',
        'busValue': paraphonicGateBus > 0 ? paraphonicGateBus : null,
        'busParam': 'Paraphonic gate',
        'parameterNumber': paraphonicGateParam.parameterNumber,
        'outputMode': paraGateMode,
        'modeParameterNumber': modeParameterNumber,
      });
    }

    // Create configuration for poly routing
    final config = PolyAlgorithmConfig(
      voiceCount: voiceCount,
      requiresGateInputs: hasGateInputs,
      usesVirtualCvPorts: false, // Real CV ports based on gate configuration
      gateInputs: gateInputs.isNotEmpty ? gateInputs : null,
      gateCvCounts: gateCvCounts.isNotEmpty ? gateCvCounts : null,
      algorithmProperties: {
        'algorithmGuid': slot.algorithm.guid,
        'algorithmName': slot.algorithm.name,
        'algorithmUuid': algId, // Use the ensured algorithm ID
        'extraInputs': inputPorts, // Non-gate routing inputs
        'outputs': outputPorts, // All output routing parameters
        'gateInputs': gateInputs, // Store for gate port generation
        'gateCvCounts': gateCvCounts, // Store for CV port generation
      },
    );

    final routing = PolyAlgorithmRouting(config: config);
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }
}
