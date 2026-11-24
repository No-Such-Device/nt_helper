import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/device_io_profile.dart';

import 'algorithm_routing.dart';
import 'bus_session_resolver.dart';

/// A configured parameter modulation, not an editable signal-routing port.
@immutable
class CvModulation {
  final String id;
  final String destinationAlgorithmId;
  final int destinationSlot;
  final int parameterNumber;
  final String parameterName;
  final int bus;
  final String busLabel;
  final int source;
  final String snapshot;
  final List<String> contributorPortIds;
  final List<String> caveats;

  CvModulation({
    required this.destinationAlgorithmId,
    required this.destinationSlot,
    required this.parameterNumber,
    required this.parameterName,
    required this.bus,
    required this.busLabel,
    required this.source,
    required this.snapshot,
    required Iterable<String> contributorPortIds,
    required Iterable<String> caveats,
  }) : id = 'cv_${destinationAlgorithmId}_${parameterNumber}_${bus}_$source',
       contributorPortIds = List.unmodifiable(contributorPortIds),
       caveats = List.unmodifiable(caveats);

  String get label => 'CV → $parameterName';
  String get description => [
    '$busLabel → Slot ${destinationSlot + 1}: $parameterName (parameter $parameterNumber)',
    snapshot,
    'Configured modulation; cached state, not voltage telemetry',
    ...caveats,
  ].join('\n');

  Map<String, dynamic> toJson() => {
    'parameter_number': parameterNumber,
    'parameter_name': parameterName,
    'bus': bus,
    'bus_label': busLabel,
    'source': source,
    'snapshot': snapshot,
    'contributor_port_ids': contributorPortIds,
    'caveats': caveats,
    'cached': true,
  };

  @override
  bool operator ==(Object other) =>
      other is CvModulation &&
      id == other.id &&
      destinationSlot == other.destinationSlot &&
      parameterName == other.parameterName &&
      busLabel == other.busLabel &&
      snapshot == other.snapshot &&
      listEquals(contributorPortIds, other.contributorPortIds) &&
      listEquals(caveats, other.caveats);

  @override
  int get hashCode => Object.hash(
    id,
    destinationSlot,
    parameterName,
    busLabel,
    snapshot,
    Object.hashAll(contributorPortIds),
    Object.hashAll(caveats),
  );
}

/// The roster is unfiltered: a mapping source names a real preset slot.
List<CvModulation> projectCvModulations({
  required List<Slot> slots,
  required List<AlgorithmRouting> routings,
  required List<String> algorithmIds,
  required DeviceIoProfile profile,
}) {
  assert(
    slots.length == routings.length && slots.length == algorithmIds.length,
  );
  final builder = BusSessionBuilder();
  final writes = <({int slot, int bus})>[];
  for (var i = 0; i < slots.length; i++) {
    for (final port in routings[i].outputPorts) {
      final bus = port.busValue;
      if (!port.isActive || bus == null || !profile.contains(bus)) continue;
      if (slots[i].values.any(
        (v) => v.parameterNumber == port.parameterNumber && v.isDisabled,
      )) {
        continue;
      }
      writes.add((slot: i, bus: bus));
      builder.addWrite(
        bus: bus,
        slot: i,
        portId: port.id,
        mode: port.outputMode,
      );
    }
  }
  final resolver = builder.build(totalSlots: slots.length);
  final result = <CvModulation>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    for (var p = 0; p < slot.mappings.length; p++) {
      final mapping = slot.mappings[p];
      final data = mapping.packedMappingData;
      if (data.cvInput <= 0) continue;
      // Live/offline storage is positional. A contradictory explicit identity
      // cannot safely be attributed to either parameter.
      final identityValid =
          (mapping.parameterNumber < 0 || mapping.parameterNumber == p) &&
          (mapping.algorithmIndex < 0 || mapping.algorithmIndex == i) &&
          data.version > 0;
      final metadata = slot.parameters
          .where((v) => v.parameterNumber == p)
          .firstOrNull;
      final page = slot.pages.pages
          .where((v) => v.parameters.contains(p))
          .firstOrNull;
      final name = metadata == null || metadata.name.isEmpty
          ? 'Parameter $p'
          : '${page == null || page.name.isEmpty ? '' : '${page.name}: '}${metadata.name}';
      final source = data.version > 0 && data.version < 4 ? 0 : data.source;
      final sourceSlot = source - 2;
      final validBus = profile.contains(data.cvInput);
      final caveats = <String>[
        if (!identityValid) 'Conflicting mapping parameter identity',
        if (metadata == null) 'Parameter metadata unavailable',
        if (!validBus) 'Bus outside this device profile',
        if (data.delta == 0) 'Zero depth',
        if (slot.values.any((v) => v.parameterNumber == p && v.isDisabled))
          'Parameter disabled',
      ];
      final snapshot = source == 0
          ? 'Own inputs (before Slot ${i + 1})'
          : source == 1
          ? 'Module inputs (original physical inputs)'
          : source >= 2 && sourceSlot < slots.length
          ? 'Slot ${sourceSlot + 1} outputs (${slots[sourceSlot].algorithm.name})'
          : 'Unknown source $source';
      final contributors = <String>{};
      final boundary = source == 0 ? i : sourceSlot + 1;
      if (identityValid &&
          validBus &&
          source == 1 &&
          profile.isInput(data.cvInput)) {
        contributors.add('hw_in_${data.cvInput}');
      } else if (identityValid &&
          validBus &&
          (source == 0 ||
              (source >= 2 &&
                  sourceSlot >= 0 &&
                  sourceSlot < slots.length &&
                  sourceSlot <= i))) {
        final ambiguousWrite = <int, int>{};
        for (final write in writes.where(
          (w) => w.bus == data.cvInput && w.slot < boundary,
        )) {
          ambiguousWrite.update(write.slot, (n) => n + 1, ifAbsent: () => 1);
        }
        if (ambiguousWrite.values.any((n) => n > 1)) {
          caveats.add('Same-slot write order unknown');
        } else {
          contributors.addAll(
            resolver.contributorsForReader(data.cvInput, boundary),
          );
          if (profile.isInput(data.cvInput) &&
              resolver.hardwareSeedContributes(data.cvInput, boundary)) {
            contributors.add('hw_in_${data.cvInput}');
          }
          if (contributors.isNotEmpty) {
            caveats.add('Contributors inferred from Add/Replace order');
          }
        }
      }
      if (contributors.isEmpty) {
        caveats.add('Bus/snapshot only; contributor unresolved');
      }
      result.add(
        CvModulation(
          destinationAlgorithmId: algorithmIds[i],
          destinationSlot: i,
          parameterNumber: p,
          parameterName: name,
          bus: data.cvInput,
          busLabel: profile.labelForBus(data.cvInput) ?? 'Bus ${data.cvInput}',
          source: source,
          snapshot: snapshot,
          contributorPortIds: contributors,
          caveats: caveats,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

Set<int> cvMappingBuses(Iterable<Slot> slots) => {
  for (final slot in slots)
    for (final mapping in slot.mappings)
      if (mapping.packedMappingData.cvInput > 0)
        mapping.packedMappingData.cvInput,
};

bool hasCompleteMappingCoverage(Iterable<Slot> slots) => slots.every((slot) {
  if (!slot.parameterCountFromDevice) return false;
  return slot.parameters.every((p) {
    if (p.parameterNumber < 0 || p.parameterNumber >= slot.mappings.length) {
      return false;
    }
    final mapping = slot.mappings[p.parameterNumber];
    return mapping.packedMappingData.version > 0 &&
        (mapping.parameterNumber < 0 ||
            mapping.parameterNumber == p.parameterNumber) &&
        (mapping.algorithmIndex < 0 ||
            mapping.algorithmIndex == slot.algorithm.algorithmIndex);
  });
});

List<String> routingAlgorithmIds(List<Slot> slots) {
  final counts = <String, int>{};
  return [
    for (final slot in slots)
      'algo_${slot.algorithm.guid}_${counts.update(slot.algorithm.guid, (n) => n + 1, ifAbsent: () => 1)}',
  ];
}

String? cvRoutingOptimizationBlockReason(Iterable<Slot> slots) {
  if (!hasCompleteMappingCoverage(slots)) {
    return 'Refresh all parameter mappings before optimizing routing';
  }
  if (cvMappingBuses(slots).isNotEmpty) {
    return 'Routing order changes cannot yet preserve CV mapping snapshots';
  }
  return null;
}
