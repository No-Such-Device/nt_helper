import 'package:nt_helper/cubit/disting_cubit.dart';
import 'es5_direct_output_algorithm_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Specialized routing implementation for the Euclidean algorithm.
///
/// The Euclidean algorithm supports ES-5 direct output routing.
/// See [Es5DirectOutputAlgorithmRouting] for details on the dual-mode behavior.
class EuclideanAlgorithmRouting extends Es5DirectOutputAlgorithmRouting {
  /// Creates a new EuclideanAlgorithmRouting instance.
  EuclideanAlgorithmRouting({
    required super.slot,
    required super.config,
    super.validator,
  });

  @override
  String get algorithmName => 'EuclideanAlgorithmRouting';

  /// Checks if this routing implementation can handle the given slot.
  ///
  /// Returns true only for Euclidean algorithm (guid: 'eucp').
  static bool canHandle(Slot slot) {
    return slot.algorithm.guid == 'eucp';
  }

  /// Creates a EuclideanAlgorithmRouting instance from a slot.
  ///
  /// This factory method creates the specialized routing for Euclidean algorithm.
  /// It processes normal input parameters (Clock input, Reset input) using
  /// the base routing extraction, but customizes output generation for ES-5 support.
  static EuclideanAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, int>? modeParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    return Es5DirectOutputAlgorithmRouting.createFromSlotWithConfig(
      slot,
      deviceIoProfile: deviceIoProfile,
      ioParameters: ioParameters,
      modeParameters: modeParameters,
      modeParametersWithNumbers: modeParametersWithNumbers,
      algorithmUuid: algorithmUuid,
      debugName: 'EuclideanAlgorithmRouting',
      builder: (slot, config) =>
          EuclideanAlgorithmRouting(slot: slot, config: config),
    );
  }
}
