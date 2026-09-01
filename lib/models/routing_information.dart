/// Suppose you have a Dart model like this:
class RoutingInformation {
  final int algorithmIndex; // same as "slot" in JS
  final List<int>
  routingInfo; // 6 packed 32-bit values: [r0, r1, r2, r3, r4, r5]
  final String algorithmName; // to display in the table
  final Set<int>? explicitInputBuses;
  final Set<int>? explicitOutputBuses;
  final Set<int>? explicitReplaceBuses;
  final Set<int>? explicitMappingBuses;

  RoutingInformation({
    required this.algorithmIndex,
    required this.routingInfo,
    required this.algorithmName,
    Set<int>? inputBuses,
    Set<int>? outputBuses,
    Set<int>? replaceBuses,
    Set<int>? mappingBuses,
  }) : explicitInputBuses = inputBuses == null
           ? null
           : Set.unmodifiable(inputBuses),
       explicitOutputBuses = outputBuses == null
           ? null
           : Set.unmodifiable(outputBuses),
       explicitReplaceBuses = replaceBuses == null
           ? null
           : Set.unmodifiable(replaceBuses),
       explicitMappingBuses = mappingBuses == null
           ? null
           : Set.unmodifiable(mappingBuses);

  bool readsSignalBus(int bus) =>
      explicitInputBuses?.contains(bus) ?? _maskContains(0, bus);

  bool writesBus(int bus) =>
      explicitOutputBuses?.contains(bus) ?? _maskContains(1, bus);

  bool replacesBus(int bus) =>
      explicitReplaceBuses?.contains(bus) ?? _maskContains(2, bus);

  bool readsMappingBus(int bus) =>
      explicitMappingBuses?.contains(bus) ?? _maskContains(5, bus);

  bool readsBus(int bus, {required bool signals, required bool mappings}) =>
      (signals && readsSignalBus(bus)) || (mappings && readsMappingBus(bus));

  bool usesBus(int bus) =>
      readsSignalBus(bus) || readsMappingBus(bus) || writesBus(bus);

  Iterable<int> get explicitBuses sync* {
    yield* explicitInputBuses ?? const <int>{};
    yield* explicitOutputBuses ?? const <int>{};
    yield* explicitReplaceBuses ?? const <int>{};
    yield* explicitMappingBuses ?? const <int>{};
  }

  bool _maskContains(int index, int bus) =>
      bus >= 0 &&
      bus < 64 &&
      index < routingInfo.length &&
      (routingInfo[index] & (1 << bus)) != 0;

  /// Serializes this RoutingInformation instance to a JSON map.
  Map<String, dynamic> toJson() => {
    'algorithmIndex': algorithmIndex,
    'routingInfo': routingInfo,
    'algorithmName': algorithmName,
  };
}

/// Utility function that replicates netInputMask(r) logic from JS.
int netInputMask(RoutingInformation r, bool showSignals, bool showMappings) {
  final inputMask = r.routingInfo[0];
  final mappingMask = r.routingInfo[5];
  if (showSignals && showMappings) return inputMask | mappingMask;
  if (showSignals) return inputMask;
  if (showMappings) return mappingMask;
  return 0;
}
