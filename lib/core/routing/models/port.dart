import 'package:freezed_annotation/freezed_annotation.dart';

part 'port.freezed.dart';
part 'port.g.dart';

/// Enum representing the different types of ports in the routing system
///
/// In Eurorack systems, all signals are voltage-based. The distinction between
/// audio and CV is cosmetic only - it affects visualization (port colors) but
/// not connectivity or signal processing.
///
/// - audio: Displayed with warm colors (e.g., orange), typically shown as VU meters on hardware
/// - cv: Displayed with cool colors (e.g., blue), typically shown as voltage values on hardware
@JsonEnum()
enum PortType {
  /// Audio signal port (warm color visualization)
  audio,

  /// Control Voltage (CV) port (cool color visualization)
  cv,
}

/// Enum representing the output mode for output ports
@JsonEnum()
enum OutputMode {
  /// Add mode - output is mixed with other outputs on the same bus
  add,

  /// Replace mode - output replaces any previous output on the same bus
  replace,
}

/// Enum representing the direction of a port
///
/// Deprecated: Use [PortRole] instead. PortDirection conflates signal direction
/// with hardware topology. Physical input jacks are "output" (sources) and
/// physical output jacks are "input" (sinks), which inverts the natural meaning.
@JsonEnum()
enum PortDirection {
  /// Input port - receives signals
  input,

  /// Output port - sends signals
  output,

  /// Bidirectional port - can send and receive
  bidirectional,
}

/// The role a port plays in the bus-assignment routing model.
///
/// The Disting NT routing system is fundamentally bus-based:
/// - Physical jacks ARE buses (inputs = bus 1-12, outputs = bus 13-20)
/// - Algorithm parameters are assigned to bus numbers
/// - A "connection" is just a bus number shared between ports
/// - Evaluation order (slot index) determines signal flow, not port direction
@JsonEnum()
enum PortRole {
  /// Algorithm parameter that reads a value from a bus each evaluation pass.
  busReader,

  /// Algorithm parameter that writes a value to a bus each evaluation pass.
  busWriter,

  /// Physical input jack that IS a bus (bus 1-12).
  physicalInputBus,

  /// Physical output jack that IS a bus (bus 13-20).
  physicalOutputBus,

  /// ES-5 expansion port that IS a bus.
  /// L = bus 29, R = bus 30, direct outputs 1-8.
  es5Bus,

  /// Read-only NTX-8CV tap of an existing bus.
  expanderOutputBus,
}

/// Immutable data class representing a port in the routing system.
///
/// A port is a connection point that can send or receive signals.
/// Each port has a unique identifier, name, type, and direction.
///
/// Example:
/// ```dart
/// final port = Port(
///   id: 'audio_in_1',
///   name: 'Audio Input 1',
///   type: PortType.audio,
///   direction: PortDirection.input,
/// );
/// ```
@freezed
sealed class Port with _$Port {
  const factory Port({
    /// Unique identifier for this port
    required String id,

    /// Human-readable name of the port
    required String name,

    /// The type of signal this port handles
    required PortType type,

    /// The direction of signal flow for this port
    required PortDirection direction,

    /// Optional description of the port's purpose
    String? description,

    /// Optional constraints for this port (e.g., voltage range, frequency)
    Map<String, dynamic>? constraints,

    /// Whether this port is currently active/enabled
    @Default(true) bool isActive,

    /// Optional output mode for output ports (add or replace)
    OutputMode? outputMode,

    // Direct properties for polyphonic routing
    /// Whether this port represents a polyphonic voice
    @Default(false) bool isPolyVoice,

    /// The voice number for polyphonic ports (1-based indexing)
    int? voiceNumber,

    /// Whether this port is a virtual CV port
    @Default(false) bool isVirtualCV,

    // Direct properties for multi-channel routing
    /// Whether this port is part of a multi-channel configuration
    @Default(false) bool isMultiChannel,

    /// The channel number for multi-channel ports (0-based indexing)
    int? channelNumber,

    /// Whether this port is part of a stereo channel pair
    @Default(false) bool isStereoChannel,

    /// The stereo side for stereo channel ports ('left' or 'right')
    String? stereoSide,

    /// Whether this port represents the master mix output
    @Default(false) bool isMasterMix,

    // Direct properties for bus and parameter routing
    /// The bus number this port is connected to (1-20)
    int? busValue,

    /// The parameter name associated with this port's bus assignment
    String? busParam,

    /// The parameter number associated with this port
    int? parameterNumber,

    /// The mode parameter number for this port's output mode (Add/Replace)
    int? modeParameterNumber,

    /// The hardware index for physical/ES-5 ports (1-based).
    /// For physical ports this equals the bus number for inputs (1-12)
    /// or the jack number for outputs (1-8, mapped to buses 13-20).
    int? hardwareIndex,

    /// The node identifier for grouping related ports
    String? nodeId,

    /// The role this port plays in the bus-assignment routing model.
    /// If not set, derived from [direction] and port ID conventions.
    PortRole? role,
  }) = _Port;

  /// Creates a Port from JSON
  factory Port.fromJson(Map<String, dynamic> json) => _$PortFromJson(json);

  const Port._();

  /// Returns true if this is an input port
  bool get isInput =>
      direction == PortDirection.input ||
      direction == PortDirection.bidirectional;

  /// Returns true if this is an output port
  bool get isOutput =>
      direction == PortDirection.output ||
      direction == PortDirection.bidirectional;

  /// Returns true if this port is connected (has a bus assignment)
  bool get isConnected => busValue != null && busValue! > 0;

  /// Returns true if this port can be connected to another port based on direction
  bool canConnectTo(Port other) {
    // Can only connect output to input or bidirectional ports
    if (isOutput && other.isInput) return true;
    if (isInput && other.isOutput) return true;

    // Bidirectional ports can connect to any port
    if (direction == PortDirection.bidirectional ||
        other.direction == PortDirection.bidirectional) {
      return true;
    }

    return false;
  }

  /// Returns true if this port is compatible with another port's type
  /// In Eurorack, all connections are voltage-based, so all types are compatible
  bool isCompatibleWith(Port other) {
    // All port types are compatible since everything is voltage in Eurorack
    return true;
  }

  // --- Bus-assignment model (PortRole) ---

  /// The effective role of this port in the bus-assignment model.
  /// Uses the explicit [role] field if set, otherwise derives from legacy fields.
  PortRole get effectiveRole {
    if (role != null) return role!;

    // Derive from port ID conventions
    if (id.startsWith('hw_in_')) return PortRole.physicalInputBus;
    if (id.startsWith('hw_out_')) return PortRole.physicalOutputBus;
    if (id.startsWith('es5_')) return PortRole.es5Bus;

    if (direction == PortDirection.output ||
        direction == PortDirection.bidirectional) {
      return PortRole.busWriter;
    }
    return PortRole.busReader;
  }

  /// Whether this port represents a hardware bus (physical jack or ES-5).
  bool get isBus =>
      effectiveRole == PortRole.physicalInputBus ||
      effectiveRole == PortRole.physicalOutputBus ||
      effectiveRole == PortRole.es5Bus ||
      effectiveRole == PortRole.expanderOutputBus;

  /// Whether this port is an algorithm parameter that reads from a bus.
  bool get isBusReader => effectiveRole == PortRole.busReader;

  /// Whether this port is an algorithm parameter that writes to a bus.
  bool get isBusWriter => effectiveRole == PortRole.busWriter;

  /// Whether this is a physical input jack (bus 1-12).
  bool get isPhysicalInput => effectiveRole == PortRole.physicalInputBus;

  /// Whether this is a physical output jack (bus 13-20).
  bool get isPhysicalOutput => effectiveRole == PortRole.physicalOutputBus;
}
