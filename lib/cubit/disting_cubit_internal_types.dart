part of 'disting_cubit.dart';

// A helper class to track each parameter's polling state.
class _PollingTask {
  bool active = true;
  int noChangeCount = 0;

  _PollingTask();
}

final class _RespecificationLifetime {
  _RespecificationLifetime({
    required DistingStateSynchronized state,
    required this.slotIndex,
    required this.algorithmGuid,
  }) : disting = state.disting,
       inputDevice = state.inputDevice,
       outputDevice = state.outputDevice;

  final IDistingMidiManager disting;
  final MidiDevice? inputDevice;
  final MidiDevice? outputDevice;
  final int slotIndex;
  final String algorithmGuid;
  final DistingRequestCancellation cancellation = DistingRequestCancellation();

  bool matches(DistingState candidate) {
    if (cancellation.isCancelled ||
        candidate is! DistingStateSynchronized ||
        !identical(candidate.disting, disting) ||
        !identical(candidate.inputDevice, inputDevice) ||
        !identical(candidate.outputDevice, outputDevice) ||
        slotIndex < 0 ||
        slotIndex >= candidate.slots.length) {
      return false;
    }

    final algorithm = candidate.slots[slotIndex].algorithm;
    return algorithm.algorithmIndex == slotIndex &&
        algorithm.guid == algorithmGuid;
  }
}

final class _RespecificationObservation {
  _RespecificationObservation(
    this.status, {
    List<int>? authoritativeSpecifications,
  }) : authoritativeSpecifications = authoritativeSpecifications == null
           ? null
           : List<int>.unmodifiable(authoritativeSpecifications);

  final AlgorithmRespecificationStatus status;
  final List<int>? authoritativeSpecifications;
}

// Retry request types for background parameter retry queue
enum _ParameterRetryType { info, enumStrings, mappings, valueStrings }

// Retry request data structure for background parameter retry queue
class _ParameterRetryRequest {
  final IDistingMidiManager disting;
  final String? algorithmGuid;
  final int slotIndex;
  final int paramIndex;
  final _ParameterRetryType type;
  final _RespecificationLifetime? respecificationLifetime;

  _ParameterRetryRequest({
    required this.disting,
    required this.algorithmGuid,
    required this.slotIndex,
    required this.paramIndex,
    required this.type,
    this.respecificationLifetime,
  });
}
