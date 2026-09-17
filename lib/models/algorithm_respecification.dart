import 'package:nt_helper/domain/disting_nt_sysex.dart';

/// Owner-provided minimum for in-place algorithm respecification.
///
/// Public upstream sources have not independently established this threshold.
const ownerProvidedRespecifyMinimumFirmwareVersion = '1.19.0';

/// The bounded observation available after sending SysEx 0x3A once.
enum AlgorithmRespecificationStatus {
  /// Fresh extended 0x40 state for the captured slot and GUID exactly matched.
  ///
  /// This establishes current device state only. It does not prove that an
  /// unchanged submission caused a mutation or that slot hydration completed.
  observedMatchingState,

  /// Fresh extended 0x40 state for the captured slot and GUID differed.
  observedDifferingState,

  /// No valid fresh extended 0x40 state was observed inside the time window.
  unverifiable,
}

/// One authoritative current value paired with its matching 0x31 metadata.
final class PreparedAlgorithmSpecification {
  const PreparedAlgorithmSpecification({
    required this.metadata,
    required this.currentValue,
  });

  final Specification metadata;
  final int currentValue;
}

/// Metadata needed to present and validate an in-place respecification.
final class PreparedAlgorithmRespecification {
  PreparedAlgorithmRespecification({
    required this.slotIndex,
    required this.algorithmGuid,
    required this.algorithmName,
    required List<PreparedAlgorithmSpecification> specifications,
  }) : specifications = List.unmodifiable(specifications);

  final int slotIndex;
  final String algorithmGuid;
  final String algorithmName;
  final List<PreparedAlgorithmSpecification> specifications;
}

/// Indicates that an in-place respecification could not be admitted.
final class AlgorithmRespecificationException implements Exception {
  const AlgorithmRespecificationException(this.message);

  final String message;

  @override
  String toString() => message;
}
