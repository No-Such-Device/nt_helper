import 'dart:convert';
import 'dart:io';

import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

final _metadata =
    (jsonDecode(File('assets/metadata/full_metadata.json').readAsStringSync())
            as Map<String, dynamic>)['tables']
        as Map<String, dynamic>;

/// Dense, real spsq metadata rather than the unrelated seven-parameter demo slot.
Slot stepSequencerSlot({
  int index = 0,
  int sequence = 1,
  int sequenceMin = 1,
  int sequenceMax = 32,
}) {
  final rows =
      (_metadata['parameters'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => p['algorithmGuid'] == 'spsq')
          .toList()
        ..sort(
          (a, b) => (a['parameterNumber'] as int).compareTo(
            b['parameterNumber'] as int,
          ),
        );
  final parameters = [
    for (final row in rows)
      ParameterInfo(
        algorithmIndex: index,
        parameterNumber: row['parameterNumber'] as int,
        name: row['name'] as String,
        min: row['name'] == 'Sequence' ? sequenceMin : row['minValue'] as int,
        max: row['name'] == 'Sequence' ? sequenceMax : row['maxValue'] as int,
        defaultValue: row['name'] == 'Sequence'
            ? sequenceMin
            : row['defaultValue'] as int,
        unit: row['rawUnitIndex'] as int,
        powerOfTen: row['powerOfTen'] as int,
        ioFlags: row['ioFlags'] as int? ?? 0,
      ),
  ];
  final enumRows = (_metadata['parameterEnums'] as List)
      .cast<Map<String, dynamic>>()
      .where((p) => p['algorithmGuid'] == 'spsq')
      .toList();
  final pages =
      (_metadata['parameterPages'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => p['algorithmGuid'] == 'spsq')
          .toList()
        ..sort(
          (a, b) => (a['pageIndex'] as int).compareTo(b['pageIndex'] as int),
        );
  final pageItems = (_metadata['parameterPageItems'] as List)
      .cast<Map<String, dynamic>>()
      .where((p) => p['algorithmGuid'] == 'spsq');
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: index,
      guid: 'spsq',
      name: 'Step Sequencer',
    ),
    routing: RoutingInfo(algorithmIndex: index, routingInfo: const []),
    parameters: parameters,
    values: [
      for (final p in parameters)
        ParameterValue(
          algorithmIndex: index,
          parameterNumber: p.parameterNumber,
          value: p.name == 'Sequence' ? sequence : p.defaultValue,
        ),
    ],
    enums: [
      for (final p in parameters)
        ParameterEnumStrings(
          algorithmIndex: index,
          parameterNumber: p.parameterNumber,
          values:
              (enumRows
                      .where((e) => e['parameterNumber'] == p.parameterNumber)
                      .toList()
                    ..sort(
                      (a, b) => (a['enumIndex'] as int).compareTo(
                        b['enumIndex'] as int,
                      ),
                    ))
                  .map((e) => (e['enumString'] as String).trim())
                  .toList(),
        ),
    ],
    pages: ParameterPages(
      algorithmIndex: index,
      pages: [
        for (final page in pages)
          ParameterPage(
            name: page['name'] as String,
            parameters: pageItems
                .where((p) => p['pageIndex'] == page['pageIndex'])
                .map((p) => p['parameterNumber'] as int)
                .toList(),
          ),
      ],
    ),
    mappings: [for (final _ in parameters) Mapping.filler()],
    valueStrings: [
      for (final p in parameters)
        ParameterValueString(
          algorithmIndex: index,
          parameterNumber: p.parameterNumber,
          value: '',
        ),
    ],
  );
}
