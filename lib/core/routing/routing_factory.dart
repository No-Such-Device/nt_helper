import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/poly_algorithm_routing.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/algorithm_routing_metadata.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/port_compatibility_validator.dart';

/// Exception thrown when the RoutingFactory cannot create a routing instance
class RoutingFactoryException implements Exception {
  final String message;
  final AlgorithmRoutingMetadata metadata;
  final Object? cause;

  const RoutingFactoryException(this.message, this.metadata, this.cause);

  @override
  String toString() {
    return 'RoutingFactoryException: $message for algorithm ${metadata.algorithmGuid}';
  }
}

/// Factory class responsible for creating appropriate AlgorithmRouting instances
/// based on AlgorithmRoutingMetadata.
///
/// This class implements the Factory Method pattern and provides a clean separation
/// between algorithm metadata and routing implementation details. It analyzes the
/// metadata to determine whether to create PolyAlgorithmRouting or
/// MultiChannelAlgorithmRouting instances.
///
/// The factory is designed to be easily extensible for future routing types by:
/// 1. Using a clear decision structure based on metadata properties
/// 2. Providing documented extension points
/// 3. Maintaining clean separation of concerns
///
/// Example usage:
/// ```dart
/// final factory = RoutingFactory();
///
/// // Create routing for a polyphonic algorithm
/// final polyMetadata = AlgorithmRoutingMetadataFactory.polyphonic(
///   algorithmGuid: 'synth-v1',
///   voiceCount: 8,
/// );
/// final polyRouting = factory.createRouting(polyMetadata);
///
/// // Create routing for a width-based algorithm
/// final widthMetadata = AlgorithmRoutingMetadataFactory.widthBased(
///   algorithmGuid: 'stereo-delay-v1',
///   channelCount: 2,
/// );
/// final multiRouting = factory.createRouting(widthMetadata);
/// ```
class RoutingFactory {
  /// Optional port compatibility validator to use for created routing instances.
  /// If not provided, routing instances will use their default validator.
  final PortCompatibilityValidator? _validator;

  /// Creates a new RoutingFactory instance.
  ///
  /// Parameters:
  /// - [_validator]: Optional port compatibility validator to use for all created
  ///   routing instances. If not provided, each routing instance will use its
  ///   default validator.
  const RoutingFactory({this._validator});

  /// Creates an appropriate AlgorithmRouting instance based on the provided metadata.
  ///
  /// This is the main factory method that analyzes the [metadata] to determine
  /// which routing implementation to instantiate. The decision is based on the
  /// [RoutingType] specified in the metadata:
  ///
  /// - [RoutingType.polyphonic]: Creates a [PolyAlgorithmRouting] instance
  /// - [RoutingType.multiChannel]: Creates a [MultiChannelAlgorithmRouting] instance
  ///
  /// Parameters:
  /// - [metadata]: The algorithm routing metadata specifying routing requirements
  /// - [validator]: Optional validator to override the factory's default validator
  ///
  /// Returns: An [AlgorithmRouting] instance configured according to the metadata
  ///
  /// Throws: [RoutingFactoryException] if the routing type is unsupported or
  /// if there's an error creating the routing instance
  AlgorithmRouting createRouting(
    AlgorithmRoutingMetadata metadata, {
    PortCompatibilityValidator? validator,
  }) {
    try {
      // Use provided validator, factory default, or null (routing will create its own)
      final effectiveValidator = validator ?? _validator;

      // === EXTENSION POINT ===
      // To add support for new routing types:
      // 1. Add the new RoutingType to the enum in algorithm_routing_metadata.dart
      // 2. Create the new routing implementation extending AlgorithmRouting
      // 3. Add a new case to this switch statement
      // 4. Update the factory tests to cover the new routing type
      switch (metadata.routingType) {
        case RoutingType.polyphonic:
          return _createPolyphonicRouting(metadata, effectiveValidator);

        case RoutingType.multiChannel:
          return _createMultiChannelRouting(metadata, effectiveValidator);

        // === Add new routing types here ===
        // case RoutingType.newType:
        //   return _createNewTypeRouting(metaeffectiveValidator);
      }
    } catch (e) {
      throw RoutingFactoryException(
        'Failed to create routing instance',
        metadata,
        e,
      );
    }
  }

  /// Creates a PolyAlgorithmRouting instance for polyphonic algorithms.
  ///
  /// This method converts the generic AlgorithmRoutingMetadata into the specific
  /// PolyAlgorithmConfig needed by PolyAlgorithmRouting.
  PolyAlgorithmRouting _createPolyphonicRouting(
    AlgorithmRoutingMetadata metadata,
    PortCompatibilityValidator? validator,
  ) {
    final config = PolyAlgorithmConfig(
      voiceCount: metadata.voiceCount,
      requiresGateInputs: metadata.requiresGateInputs,
      usesVirtualCvPorts: metadata.usesVirtualCvPorts,
      virtualCvPortsPerVoice: metadata.virtualCvPortsPerVoice,
      portNamePrefix: metadata.effectivePortNamePrefix,
      algorithmProperties: {
        ...metadata.customProperties,
        'algorithmGuid': metadata.algorithmGuid,
        if (metadata.algorithmName != null)
          'algorithmName': metadata.algorithmName!,
      },
    );

    return PolyAlgorithmRouting(config: config, validator: validator);
  }

  /// Creates a MultiChannelAlgorithmRouting instance for multi-channel algorithms.
  ///
  /// This method converts the generic AlgorithmRoutingMetadata into the specific
  /// MultiChannelAlgorithmConfig needed by MultiChannelAlgorithmRouting.
  MultiChannelAlgorithmRouting _createMultiChannelRouting(
    AlgorithmRoutingMetadata metadata,
    PortCompatibilityValidator? validator,
  ) {
    // Convert string port types to PortType enum
    final supportedPortTypes = _convertPortTypes(metadata.supportedPortTypes);

    final config = MultiChannelAlgorithmConfig(
      channelCount: metadata.channelCount,
      supportsStereoChannels: metadata.supportsStereo,
      allowsIndependentChannels: metadata.allowsIndependentChannels,
      supportedPortTypes: supportedPortTypes,
      portNamePrefix: metadata.effectivePortNamePrefix,
      createMasterMix: metadata.createMasterMix,
      algorithmProperties: {
        ...metadata.customProperties,
        'algorithmGuid': metadata.algorithmGuid,
        if (metadata.algorithmName != null)
          'algorithmName': metadata.algorithmName!,
      },
    );

    return MultiChannelAlgorithmRouting(config: config, validator: validator);
  }

  /// Converts string port type names to PortType enums.
  ///
  /// This method handles the conversion from the string-based port types
  /// in AlgorithmRoutingMetadata to the PortType enum used by the routing
  /// implementations.
  List<PortType> _convertPortTypes(List<String> portTypeNames) {
    if (portTypeNames.isEmpty) {
      // Default port types if none specified
      return [PortType.audio, PortType.cv];
    }

    final supportedTypes = <PortType>[];

    for (final typeName in portTypeNames) {
      final portType = _parsePortType(typeName);
      if (portType != null) {
        supportedTypes.add(portType);
      } else {}
    }

    return supportedTypes.isNotEmpty
        ? supportedTypes
        : [PortType.audio, PortType.cv]; // fallback
  }

  /// Parses a port type name string to a PortType enum.
  ///
  /// This method provides a centralized way to convert string port type names
  /// to PortType enums, with case-insensitive matching.
  ///
  /// === EXTENSION POINT ===
  /// To add support for new port types:
  /// 1. Add the new PortType to the enum in port.dart
  /// 2. Add the corresponding case to this method
  /// 3. Update tests to cover the new port type
  PortType? _parsePortType(String typeName) {
    switch (typeName.toLowerCase()) {
      case 'audio':
        return PortType.audio;
      case 'cv':
        return PortType.cv;
      // Note: gate and clock types were removed in Story 7.5
      // They were artificial types not present in hardware
      // All gate/clock ports are now CV type (isAudio=false)
      case 'gate':
      case 'clock':
        return PortType.cv;
      default:
        return null;
    }
  }

  /// Validates that the metadata is suitable for routing creation.
  ///
  /// This method performs pre-creation validation to catch common issues
  /// early and provide helpful error messages.
  bool validateMetadata(AlgorithmRoutingMetadata metadata) {
    // Basic validation
    if (metadata.algorithmGuid.isEmpty) {
      return false;
    }

    // Routing-specific validation
    switch (metadata.routingType) {
      case RoutingType.polyphonic:
        return _validatePolyphonicMetadata(metadata);
      case RoutingType.multiChannel:
        return _validateMultiChannelMetadata(metadata);
    }
  }

  /// Validates polyphonic routing metadata.
  bool _validatePolyphonicMetadata(AlgorithmRoutingMetadata metadata) {
    if (metadata.voiceCount <= 0) {
      return false;
    }

    if (metadata.virtualCvPortsPerVoice < 0) {
      return false;
    }

    return true;
  }

  /// Validates multi-channel routing metadata.
  bool _validateMultiChannelMetadata(AlgorithmRoutingMetadata metadata) {
    if (metadata.channelCount <= 0) {
      return false;
    }

    return true;
  }

  /// Creates a routing instance with validation.
  ///
  /// This is a convenience method that validates metadata before creating
  /// the routing instance, providing a more robust API.
  AlgorithmRouting createValidatedRouting(
    AlgorithmRoutingMetadata metadata, {
    PortCompatibilityValidator? validator,
  }) {
    if (!validateMetadata(metadata)) {
      throw RoutingFactoryException(
        'Metadata validation failed',
        metadata,
        null,
      );
    }

    return createRouting(metadata, validator: validator);
  }

  /// Analyzes metadata and suggests optimizations or potential issues.
  ///
  /// This method can be used during development to identify potential
  /// performance or configuration issues with routing metadata.
  List<String> analyzeMetadata(AlgorithmRoutingMetadata metadata) {
    final suggestions = <String>[];

    // Check for potentially excessive voice/channel counts
    if (metadata.isPolyphonic && metadata.voiceCount > 16) {
      suggestions.add(
        'High voice count (${metadata.voiceCount}) may impact performance',
      );
    }

    if (metadata.isMultiChannel && metadata.channelCount > 32) {
      suggestions.add(
        'High channel count (${metadata.channelCount}) may impact performance',
      );
    }

    // Check for unused features
    if (metadata.isPolyphonic &&
        metadata.usesVirtualCvPorts &&
        metadata.virtualCvPortsPerVoice == 0) {
      suggestions.add('Virtual CV ports are enabled but count per voice is 0');
    }

    // Check for potential stereo configuration issues
    if (metadata.isMultiChannel &&
        metadata.supportsStereo &&
        metadata.channelCount % 2 != 0) {
      suggestions.add(
        'Stereo support is enabled but channel count (${metadata.channelCount}) is odd',
      );
    }

    return suggestions;
  }
}
