import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'models/routing_state.dart';
import 'models/port.dart';
import 'models/connection.dart';
import 'port_compatibility_validator.dart';
import 'poly_algorithm_routing.dart';
import 'multi_channel_algorithm_routing.dart';
import 'usb_from_algorithm_routing.dart';
import 'es5_encoder_algorithm_routing.dart';
import 'clock_algorithm_routing.dart';
import 'clock_multiplier_algorithm_routing.dart';
import 'clock_divider_algorithm_routing.dart';
import 'euclidean_algorithm_routing.dart';
import 'saturator_algorithm_routing.dart';
import 'compressor_algorithm_routing.dart';
import 'noise_gate_algorithm_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Abstract base class for algorithm routing implementations.
///
/// This class defines the core interface that all routing algorithms must implement.
/// It provides a standardized way to generate ports, validate connections, and manage
/// routing state while allowing concrete implementations to define their own logic.
///
/// Example usage:
/// ```dart
/// class MyRoutingAlgorithm extends AlgorithmRouting {
///   @override
///   List<Port> generateInputPorts() {
///     return [Port(id: 'input1', name: 'Audio In', type: PortType.audio)];
///   }
///
///   @override
///   List<Port> generateOutputPorts() {
///     return [Port(id: 'output1', name: 'Audio Out', type: PortType.audio)];
///   }
///
///   @override
///   bool validateConnection(Port source, Port destination) {
///     return source.type == destination.type;
///   }
/// }
/// ```
abstract class AlgorithmRouting {
  static const DeviceIoProfile defaultDeviceIoProfile =
      DeviceIoProfile.distingExtended;

  /// Bus topology used to classify every routing value for this instance.
  DeviceIoProfile deviceIoProfile;

  /// The port compatibility validator for this algorithm
  late final PortCompatibilityValidator _validator;

  /// Mode parameters with their numbers for output mode switching
  Map<String, ({int parameterNumber, int value})>? _modeParametersWithNumbers;

  /// Stable UUID for this algorithm instance
  String? algorithmUuid;

  /// Creates a new AlgorithmRouting instance
  AlgorithmRouting({
    PortCompatibilityValidator? validator,
    this.algorithmUuid,
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    _validator = validator ?? PortCompatibilityValidator();
  }

  /// The current routing state
  RoutingState get state;

  /// List of input ports available for this routing algorithm
  List<Port> get inputPorts;

  /// List of output ports available for this routing algorithm
  List<Port> get outputPorts;

  /// List of active connections between ports
  List<Connection> get connections;

  /// The port compatibility validator
  PortCompatibilityValidator get validator => _validator;

  /// Sets the mode parameters for this routing algorithm
  @protected
  void setModeParameters(
    Map<String, ({int parameterNumber, int value})> modeParameters,
  ) {
    _modeParametersWithNumbers = modeParameters;
  }

  /// Gets the mode parameter number for the given output parameter name
  /// If the output parameter is named "Blah", looks for "Blah mode"
  @protected
  int? getModeParameterNumber(String outputParameterName) {
    final modeParameterName = '$outputParameterName mode';
    return _modeParametersWithNumbers?[modeParameterName]?.parameterNumber;
  }

  /// Generates the list of input ports for this algorithm.
  ///
  /// This method should be implemented by concrete classes to define
  /// what input ports are available for the routing algorithm.
  ///
  /// Returns a list of [Port] objects representing input ports.
  @protected
  List<Port> generateInputPorts();

  /// Generates the list of output ports for this algorithm.
  ///
  /// This method should be implemented by concrete classes to define
  /// what output ports are available for the routing algorithm.
  ///
  /// Returns a list of [Port] objects representing output ports.
  @protected
  List<Port> generateOutputPorts();

  /// Validates whether a connection between two ports is valid.
  ///
  /// This method checks if a connection can be made between the [source]
  /// port and the [destination] port based on their types, directions,
  /// and any other algorithm-specific constraints.
  ///
  /// The default implementation uses the port compatibility validator,
  /// but concrete classes can override this for custom validation logic.
  ///
  /// Parameters:
  /// - [source]: The port where the connection originates
  /// - [destination]: The port where the connection terminates
  ///
  /// Returns `true` if the connection is valid, `false` otherwise.
  bool validateConnection(Port source, Port destination) {
    final result = _validator.validateConnection(
      source,
      destination,
      existingConnections: connections,
    );
    return result.isValid;
  }

  /// Validates a connection with detailed results.
  ///
  /// This method provides detailed validation results including errors
  /// and warnings, which can be useful for providing user feedback.
  ///
  /// Parameters:
  /// - [source]: The port where the connection originates
  /// - [destination]: The port where the connection terminates
  ///
  /// Returns a [ValidationResult] with detailed validation information.
  ValidationResult validateConnectionDetailed(Port source, Port destination) {
    return _validator.validateConnection(
      source,
      destination,
      existingConnections: connections,
    );
  }

  /// Updates the routing state with a new state.
  ///
  /// This method allows updating the internal routing state and should
  /// trigger any necessary state change notifications.
  ///
  /// Parameters:
  /// - [newState]: The new routing state to apply
  void updateState(RoutingState newState);

  @protected
  int? coerceInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  @protected
  OutputMode? parseOutputMode(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is OutputMode) {
      return value;
    }
    final modeStr = value.toString().toLowerCase();
    if (modeStr == 'replace') {
      return OutputMode.replace;
    }
    if (modeStr == 'add') {
      return OutputMode.add;
    }
    return null;
  }

  @protected
  PortType? parsePortType(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is PortType) {
      return value;
    }

    final typeStr = value.toString().toLowerCase();
    switch (typeStr) {
      case 'audio':
        return PortType.audio;
      case 'cv':
        return PortType.cv;
      case 'gate':
      case 'clock':
        return PortType.cv;
    }
    return null;
  }

  @protected
  Port buildPortFromDeclaration(
    Map item, {
    required PortDirection direction,
    required String defaultId,
    required String defaultName,
    required PortType defaultType,
    String? defaultDescription,
    bool includeOutputMode = false,
  }) {
    final id = item['id']?.toString() ?? defaultId;
    final name = item['name']?.toString() ?? defaultName;
    final type = parsePortType(item['type']) ?? defaultType;
    final description = item['description']?.toString() ?? defaultDescription;

    final busValue = coerceInt(item['busValue']);
    final busParam = item['busParam']?.toString();
    final parameterNumber = coerceInt(item['parameterNumber']);

    final outputMode = includeOutputMode
        ? parseOutputMode(item['outputMode'])
        : null;
    final modeParameterNumber = includeOutputMode
        ? coerceInt(item['modeParameterNumber'])
        : null;

    return Port(
      id: id,
      name: name,
      type: type,
      direction: direction,
      description: description,
      busValue: busValue,
      busParam: busParam,
      parameterNumber: parameterNumber,
      outputMode: outputMode,
      modeParameterNumber: modeParameterNumber,
    );
  }

  /// Adds a connection between two ports if the connection is valid.
  ///
  /// This method validates the connection using [validateConnection] and
  /// adds it to the list of active connections if valid.
  ///
  /// Parameters:
  /// - [source]: The source port for the connection
  /// - [destination]: The destination port for the connection
  ///
  /// Returns the created [Connection] if successful, null if invalid.
  Connection? addConnection(Port source, Port destination) {
    if (!validateConnection(source, destination)) {
      return null;
    }

    final connection = Connection(
      id: '${source.id}_${destination.id}',
      sourcePortId: source.id,
      destinationPortId: destination.id,
      connectionType: ConnectionType.algorithmToAlgorithm,
    );

    return connection;
  }

  /// Removes a connection by its ID.
  ///
  /// This method removes an active connection from the routing system.
  ///
  /// Parameters:
  /// - [connectionId]: The ID of the connection to remove
  ///
  /// Returns `true` if the connection was found and removed, `false` otherwise.
  bool removeConnection(String connectionId) {
    final removed = connections.any((conn) => conn.id == connectionId);
    if (removed) {
    } else {}
    return removed;
  }

  /// Finds a port by its ID in both input and output ports.
  ///
  /// This utility method searches through all available ports to find
  /// one with the specified ID.
  ///
  /// Parameters:
  /// - [portId]: The ID of the port to find
  ///
  /// Returns the [Port] if found, null otherwise.
  Port? findPortById(String portId) {
    // Search in input ports
    for (final port in inputPorts) {
      if (port.id == portId) {
        return port;
      }
    }

    // Search in output ports
    for (final port in outputPorts) {
      if (port.id == portId) {
        return port;
      }
    }

    return null;
  }

  /// Validates the entire routing configuration.
  ///
  /// This method performs a comprehensive validation of the current
  /// routing state, checking all connections for validity and consistency.
  ///
  /// Returns `true` if the routing configuration is valid, `false` otherwise.
  bool validateRouting() {
    for (final connection in connections) {
      final source = findPortById(connection.sourcePortId);
      final destination = findPortById(connection.destinationPortId);

      if (source == null || destination == null) {
        return false;
      }

      if (!validateConnection(source, destination)) {
        return false;
      }
    }

    return true;
  }

  /// Disposes of any resources used by the routing algorithm.
  ///
  /// Concrete implementations should override this method to clean up
  /// any resources, listeners, or subscriptions they may have created.
  @mustCallSuper
  void dispose() {}

  /// Algorithms that always write outputs in Replace mode but expose no Output
  /// mode parameter. The routing editor must show their outputs as Replace.
  static const _alwaysReplaceOutputGuids = {'quan', 'cali'};

  /// Algorithms where setting `Output = None` (busValue 0) makes the firmware
  /// write the result back into the Input bus in Replace mode, regardless of
  /// any Output mode parameter. When Output is a real bus, the existing
  /// Add/Replace behaviour applies.
  static const _conditionalInPlaceGuids = {
    'attn',
    'absv',
    'vcam',
    'enfo',
    'slew',
    'debo',
    'eqpa',
  };

  /// Whether [guid] uses `Output = None` to mean "write to the matching input
  /// bus in Replace mode".
  static bool isConditionalInPlaceGuid(String guid) =>
      _conditionalInPlaceGuids.contains(guid);

  /// Factory method to create the appropriate AlgorithmRouting from a Slot.
  ///
  /// This method asks each concrete implementation if it can handle the slot,
  /// then delegates creation to the appropriate subclass.
  ///
  /// Parameters:
  /// - [slot]: The slot containing algorithm and parameter information
  /// - [algorithmUuid]: Optional UUID for the algorithm instance
  ///
  /// Returns an appropriate AlgorithmRouting implementation
  static AlgorithmRouting fromSlot(
    Slot slot, {
    required DeviceIoProfile deviceIoProfile,
    String? algorithmUuid,
  }) {
    // Extract mode parameters once (used by all implementations)
    final modeParametersWithNumbers = extractModeParametersWithNumbers(slot);

    // Check for USB Audio (From Host) algorithm first and use its own IO extractor
    if (UsbFromAlgorithmRouting.canHandle(slot)) {
      final usbIoParameters = UsbFromAlgorithmRouting.extractIOParameters(slot);
      final routing = UsbFromAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: usbIoParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
      routing.deviceIoProfile = deviceIoProfile;
      return routing;
    }

    // For non-USB algorithms use the generic IO extractor
    final ioParameters = extractIOParameters(slot);

    // For other algorithms, we may need the older modeParameters map
    final modeParameters = extractModeParameters(slot);

    // Ask each implementation if it can handle this slot
    AlgorithmRouting instance;
    if (ES5EncoderAlgorithmRouting.canHandle(slot)) {
      // ES-5 Encoder has special handling for conditional channel inputs
      instance = ES5EncoderAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        algorithmUuid: algorithmUuid,
      );
    } else if (ClockAlgorithmRouting.canHandle(slot)) {
      // Clock algorithm with ES-5 direct output support
      instance = ClockAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (EuclideanAlgorithmRouting.canHandle(slot)) {
      // Euclidean algorithm with ES-5 direct output support
      instance = EuclideanAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (ClockMultiplierAlgorithmRouting.canHandle(slot)) {
      // Clock Multiplier algorithm with ES-5 direct output support
      instance = ClockMultiplierAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (ClockDividerAlgorithmRouting.canHandle(slot)) {
      // Clock Divider algorithm with ES-5 direct output support
      instance = ClockDividerAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (SaturatorAlgorithmRouting.canHandle(slot)) {
      // Saturator algorithm with in-place processing (input bus = output bus)
      instance = SaturatorAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (CompressorAlgorithmRouting.canHandle(slot)) {
      // Compressor with in-place processing (input bus = output bus, except sidechain)
      instance = CompressorAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (NoiseGateAlgorithmRouting.canHandle(slot)) {
      // Noise gate with in-place processing (input bus = output bus, except sidechain)
      instance = NoiseGateAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else if (_alwaysReplaceOutputGuids.contains(slot.algorithm.guid)) {
      // Algorithms that always write outputs in Replace mode but expose
      // no Output mode parameter (e.g. Quantizer, Auto-calibrator).
      instance = MultiChannelAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
        defaultOutputMode: OutputMode.replace,
      );
    } else if (PolyAlgorithmRouting.canHandle(slot)) {
      instance = PolyAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
      );
    } else {
      // MultiChannelAlgorithmRouting is the fallback for everything else
      instance = MultiChannelAlgorithmRouting.createFromSlot(
        slot,
        deviceIoProfile: deviceIoProfile,
        ioParameters: ioParameters,
        modeParameters: modeParameters,
        modeParametersWithNumbers: modeParametersWithNumbers,
        algorithmUuid: algorithmUuid,
        replaceNoneOutputWithInput: isConditionalInPlaceGuid(
          slot.algorithm.guid,
        ),
      );
    }

    // Set the mode parameters in the base class
    instance.setModeParameters(modeParametersWithNumbers);
    instance.deviceIoProfile = deviceIoProfile;

    return instance;
  }

  /// Compute the set of parameter numbers that are visible (i.e., present
  /// in at least one firmware-provided page).  Parameters that are not in
  /// any page are hidden from the parameter editor and should also be
  /// excluded from routing visualizations.
  ///
  /// When `slot.pages.pages` is empty (e.g. test mocks, offline fixtures
  /// without page metadata), falls back to all parameters so existing
  /// tests and callers remain compatible.
  static Set<int> _visibleParameterNumbers(Slot slot) {
    final pageParams = slot.pages.pages.expand((p) => p.parameters).toSet();
    if (pageParams.isNotEmpty) return pageParams;
    return slot.parameters.map((p) => p.parameterNumber).toSet();
  }

  /// Helper method to extract routing-related parameters from a slot.
  ///
  /// Uses IO flags (`ParameterInfo.isInput`, `.isOutput`) to identify
  /// parameters that represent bus assignments for routing.
  ///
  /// Only parameters that appear in at least one firmware-provided page
  /// are considered — hidden parameters are excluded to match the
  /// parameter editor's behaviour.
  ///
  /// Parameters:
  /// - [slot]: The slot to analyze
  ///
  /// Returns a map of parameter names to their bus values
  static Map<String, int> extractIOParameters(Slot slot) {
    // Special case: Notes algorithm (guid: 'note') has no I/O capabilities
    if (slot.algorithm.guid == 'note') {
      return {};
    }

    final visible = _visibleParameterNumbers(slot);
    final ioParameters = <String, int>{};

    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    for (final param in slot.parameters) {
      if (!visible.contains(param.parameterNumber)) continue;
      if (param.isInput ||
          param.isOutput ||
          isHardcodedInput(slot.algorithm.guid, param.name)) {
        final value = valueByParam[param.parameterNumber] ?? param.defaultValue;
        ioParameters[param.name] = value;
      }
    }

    return ioParameters;
  }

  /// Hardcoded input parameters that firmware doesn't flag with isInput.
  /// Remove once OS fixes ioFlags for these algorithms.
  static final _hardcodedInputs = <String, RegExp>{
    'logi': RegExp(r'^\d+:Input [XY]$'),
    'musw': RegExp(
      r'^\d+:(In control source|Out control source|Reset source)$',
    ),
  };

  static bool isHardcodedInput(String guid, String paramName) {
    final pattern = _hardcodedInputs[guid];
    return pattern != null && pattern.hasMatch(paramName);
  }

  /// Helper method to extract mode-related parameters from a slot.
  ///
  /// Identifies parameters that control output modes (Add/Replace).
  /// Mode parameters are identified by:
  /// - Parameter name ending with 'mode' (case-insensitive)
  /// - unit == 1 (enum type)
  /// - enumValues containing 'Add' and 'Replace'
  ///
  /// Only parameters that appear in at least one firmware-provided page
  /// are considered — hidden parameters are excluded.
  ///
  /// Parameters:
  /// - [slot]: The slot to analyze
  ///
  /// Returns a map of parameter names to their mode values (0=Add, 1=Replace)
  static Map<String, int> extractModeParameters(Slot slot) {
    final visible = _visibleParameterNumbers(slot);
    final modeParameters = <String, int>{};

    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    // Build enum lookup map
    final enumsByParam = <int, List<String>>{
      for (final e in slot.enums) e.parameterNumber: e.values,
    };

    for (final param in slot.parameters) {
      if (!visible.contains(param.parameterNumber)) continue;
      // Mode parameters are identified by:
      // - name ending with 'mode' (case-insensitive)
      // - unit == 1 (enum type)
      // - enum values containing 'Add' and 'Replace'
      final enumValues = enumsByParam[param.parameterNumber];
      final isModeParameter =
          param.name.toLowerCase().endsWith('mode') &&
          param.unit == 1 &&
          enumValues != null &&
          enumValues.length >= 2 &&
          enumValues.contains('Add') &&
          enumValues.contains('Replace');

      if (isModeParameter) {
        final value = valueByParam[param.parameterNumber] ?? param.defaultValue;
        modeParameters[param.name] = value;
      }
    }

    return modeParameters;
  }

  /// Extract mode parameters with both their values and parameter numbers.
  ///
  /// Only parameters that appear in at least one firmware-provided page
  /// are considered — hidden parameters are excluded.
  ///
  /// Parameters:
  /// - [slot]: The slot to analyze
  ///
  /// Returns a map of parameter names to (parameterNumber, value) records
  static Map<String, ({int parameterNumber, int value})>
  extractModeParametersWithNumbers(Slot slot) {
    final visible = _visibleParameterNumbers(slot);
    final modeParameters = <String, ({int parameterNumber, int value})>{};

    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    // Build enum lookup map
    final enumsByParam = <int, List<String>>{
      for (final e in slot.enums) e.parameterNumber: e.values,
    };

    for (final param in slot.parameters) {
      if (!visible.contains(param.parameterNumber)) continue;
      // Mode parameters are identified by:
      // - name ending with 'mode' (case-insensitive)
      // - unit == 1 (enum type)
      // - enum values containing 'Add' and 'Replace'
      final enumValues = enumsByParam[param.parameterNumber];
      final isModeParameter =
          param.name.toLowerCase().endsWith('mode') &&
          param.unit == 1 &&
          enumValues != null &&
          enumValues.length >= 2 &&
          enumValues.contains('Add') &&
          enumValues.contains('Replace');

      if (isModeParameter) {
        final value = valueByParam[param.parameterNumber] ?? param.defaultValue;
        modeParameters[param.name] = (
          parameterNumber: param.parameterNumber,
          value: value,
        );
      }
    }

    return modeParameters;
  }

  /// Helper method to get parameter value from a slot.
  ///
  /// Parameters:
  /// - [slot]: The slot to extract value from
  /// - [parameterName]: Name of the parameter to find
  ///
  /// Returns the parameter value or default value if not set
  @protected
  static int getParameterValue(Slot slot, String parameterName) {
    final param = slot.parameters.firstWhere(
      (p) =>
          p.name == parameterName || stripPagePrefix(p.name) == parameterName,
      orElse: () => ParameterInfo.filler(),
    );

    if (param.parameterNumber < 0) return 0;

    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    return valueByParam[param.parameterNumber] ?? param.defaultValue;
  }

  /// Helper method to get parameter value from a slot by parameter number.
  ///
  /// Returns the parameter value or [defaultValue] if not set.
  @protected
  static int getParameterValueByNumber(
    Slot slot,
    int parameterNumber, {
    required int defaultValue,
  }) {
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

  /// Helper method to check if a parameter exists in a slot.
  ///
  /// Parameters:
  /// - [slot]: The slot to check
  /// - [parameterName]: Name of the parameter to find
  ///
  /// Returns true if the parameter exists
  @protected
  static bool hasParameter(Slot slot, String parameterName) {
    return slot.parameters.any(
      (p) =>
          p.name == parameterName || stripPagePrefix(p.name) == parameterName,
    );
  }

  /// Strips a page prefix (e.g., "1:Gate input 1" → "Gate input 1").
  /// Returns the original string if no prefix is found.
  static String stripPagePrefix(String name) {
    final colonIndex = name.indexOf(':');
    return colonIndex >= 0 ? name.substring(colonIndex + 1) : name;
  }
}

/// Common base for routing implementations that cache generated ports.
abstract class CachedAlgorithmRouting extends AlgorithmRouting {
  RoutingState _state;

  List<Port>? _cachedInputPorts;
  List<Port>? _cachedOutputPorts;

  CachedAlgorithmRouting({
    super.validator,
    super.algorithmUuid,
    RoutingState? initialState,
  }) : _state = initialState ?? const RoutingState();

  @override
  RoutingState get state => _state;

  @override
  List<Port> get inputPorts => _cachedInputPorts ??= generateInputPorts();

  @override
  List<Port> get outputPorts => _cachedOutputPorts ??= generateOutputPorts();

  @override
  List<Connection> get connections => _state.connections;

  @protected
  void clearPortCaches() {
    _cachedInputPorts = null;
    _cachedOutputPorts = null;
  }

  @override
  void updateState(RoutingState newState) {
    _state = newState;

    // Clear port caches if ports have changed
    if (_state.inputPorts.isNotEmpty || _state.outputPorts.isNotEmpty) {
      clearPortCaches();
    }
  }

  @override
  void dispose() {
    super.dispose();
    clearPortCaches();
  }
}
