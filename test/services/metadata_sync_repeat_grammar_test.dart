import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';
import 'package:nt_helper/services/metadata_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Quantizer captures 2/1 and persists one canonical shape plus grammar',
    () async {
      final algorithm = _algorithm('quan', [_spec('Channels', 1, 12)]);
      final manager = _ShapeProbeManager(
        algorithm,
        (specs) => [
          _parameter(0, 'Mode'),
          for (var channel = 1; channel <= specs[0]; channel++)
            _parameter(channel, 'Ch $channel'),
        ],
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedAlgorithm(database, algorithm);
      final statuses = <String>[];

      await MetadataSyncService(
        manager,
        database,
      ).rescanSingleAlgorithm(algorithm, onStatus: statuses.add);

      expect(manager.requestedVectors, [
        [2],
        [1],
      ]);
      expect(statuses, [
        'Capturing canonical repeat witness (Channels=2)...',
        'Capturing lower repeat witness (Channels=1)...',
        'Repeat grammar proven from 2 hardware shapes.',
      ]);
      expect(await database.metadataDao.getAllParameters(), hasLength(3));
      final row = await database.metadataDao.getAlgorithmRepeatGrammar('quan');
      final grammar = AlgorithmRepeatGrammar.fromCompactJson(
        jsonDecode(row!.grammarJson),
      );
      expect(
        grammar.expand(await _snapshotFromDb(database, 'quan', [2]), [
          4,
        ]).parameters,
        hasLength(5),
      );
    },
  );

  test('Mixer captures only the four adjacent interaction witnesses', () async {
    final algorithm = _algorithm('mix1', [
      _spec('Channels', 1, 8),
      _spec('Sends', 0, 4),
    ]);
    final manager = _ShapeProbeManager(
      algorithm,
      (specs) => [
        for (var channel = 1; channel <= specs[0]; channel++) ...[
          _parameter(0, 'Channel $channel'),
          for (var send = 1; send <= specs[1]; send++)
            _parameter(0, 'Channel $channel Send $send'),
        ],
      ],
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedAlgorithm(database, algorithm);

    await MetadataSyncService(
      manager,
      database,
    ).rescanSingleAlgorithm(algorithm);

    expect(manager.requestedVectors, [
      [2, 1],
      [1, 1],
      [2, 0],
      [1, 0],
    ]);
    expect(
      await database.metadataDao.getAlgorithmRepeatGrammar('mix1'),
      isNotNull,
    );
  });

  test('allocation-only specification takes one fallback probe', () async {
    final algorithm = _algorithm('delm', [
      Specification(
        name: 'Max delay time',
        min: 1,
        max: 30,
        defaultValue: 30,
        type: 0,
      ),
    ]);
    final manager = _ShapeProbeManager(
      algorithm,
      (_) => [_parameter(0, 'Delay')],
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedAlgorithm(database, algorithm);

    await MetadataSyncService(
      manager,
      database,
    ).rescanSingleAlgorithm(algorithm);

    expect(manager.requestedVectors, [
      [30],
    ]);
    expect(
      await database.metadataDao.getAlgorithmRepeatGrammar('delm'),
      isNull,
    );
  });

  test(
    'probe succeeds when the slot response omits specification values',
    () async {
      final algorithm = _algorithm('quan', [_spec('Channels', 1, 12)]);
      final manager = _ShapeProbeManager(
        algorithm,
        (specs) => [
          _parameter(0, 'Mode'),
          for (var channel = 1; channel <= specs[0]; channel++)
            _parameter(channel, 'Ch $channel'),
        ],
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedAlgorithm(database, algorithm);

      await MetadataSyncService(
        manager,
        database,
      ).rescanSingleAlgorithm(algorithm);

      expect(await database.metadataDao.getAllParameters(), hasLength(3));
      expect(
        await database.metadataDao.getAlgorithmRepeatGrammar('quan'),
        isNotNull,
      );
    },
  );

  test('an unproven rescan removes a stale grammar', () async {
    final algorithm = _algorithm('flat', [_spec('Channels', 1, 8)]);
    final manager = _ShapeProbeManager(
      algorithm,
      (_) => [_parameter(0, 'Fixed')],
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedAlgorithm(database, algorithm);
    await database
        .into(database.algorithmRepeatGrammars)
        .insert(
          AlgorithmRepeatGrammarEntry(
            algorithmGuid: 'flat',
            grammarVersion: 1,
            grammarJson: jsonEncode([
              1,
              [2],
              [],
            ]),
          ),
        );

    await MetadataSyncService(
      manager,
      database,
    ).rescanSingleAlgorithm(algorithm);

    expect(
      await database.metadataDao.getAlgorithmRepeatGrammar('flat'),
      isNull,
    );
  });
}

final class _ShapeProbeManager implements IDistingMidiManager {
  _ShapeProbeManager(this.algorithm, this.parametersFor);

  final AlgorithmInfo algorithm;
  final List<ParameterInfo> Function(List<int>) parametersFor;
  final List<List<int>> requestedVectors = [];
  List<int>? _activeSpecifications;

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    requestedVectors.add(List<int>.from(specifications));
    _activeSpecifications = List<int>.from(specifications);
  }

  @override
  Future<void> requestRemoveAlgorithm(int algorithmIndex) async {
    _activeSpecifications = null;
  }

  @override
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  }) async => _activeSpecifications == null ? 0 : 1;

  /// Mirrors the firmware's algorithm-in-slot response, which carries the
  /// slot index, GUID and name but never the specification values.
  @override
  Future<Algorithm?> requestAlgorithmGuid(int algorithmIndex) async {
    if (algorithmIndex != 0 || _activeSpecifications == null) return null;
    return Algorithm(
      algorithmIndex: 0,
      guid: algorithm.guid,
      name: algorithm.name,
    );
  }

  @override
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex) async {
    return NumParameters(
      algorithmIndex: algorithmIndex,
      numParameters: parametersFor(_activeSpecifications!).length,
    );
  }

  @override
  Future<ParameterInfo?> requestParameterInfo(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    final source = parametersFor(_activeSpecifications!)[parameterNumber];
    return ParameterInfo(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      min: source.min,
      max: source.max,
      defaultValue: source.defaultValue,
      unit: source.unit,
      name: source.name,
      powerOfTen: source.powerOfTen,
      ioFlags: source.ioFlags,
    );
  }

  @override
  Future<ParameterPages?> requestParameterPages(int algorithmIndex) async =>
      ParameterPages(algorithmIndex: algorithmIndex, pages: const []);

  @override
  Future<ParameterEnumStrings?> requestParameterEnumStrings(
    int algorithmIndex,
    int parameterNumber,
  ) async => null;

  @override
  Future<OutputModeUsage?> requestOutputModeUsage(
    int algorithmIndex,
    int parameterNumber,
  ) async => null;

  @override
  Future<String?> requestVersionString() async => '1.13.0';

  @override
  Future<void> requestLoadPlugin(String guid) async {}

  @override
  Future<void> requestWake() async {}

  @override
  Future<void> requestNewPreset() async {
    _activeSpecifications = null;
  }

  @override
  Future<void> dispose() async {}

  @override
  void noSuchMethod(Invocation invocation) {}
}

AlgorithmInfo _algorithm(String guid, List<Specification> specifications) =>
    AlgorithmInfo(
      algorithmIndex: 0,
      name: guid,
      guid: guid,
      specifications: specifications,
    );

Specification _spec(String name, int min, int max) =>
    Specification(name: name, min: min, max: max, defaultValue: min, type: 0);

ParameterInfo _parameter(int number, String name) => ParameterInfo(
  algorithmIndex: 0,
  parameterNumber: number,
  min: 0,
  max: 1,
  defaultValue: 0,
  unit: 0,
  name: name,
  powerOfTen: 0,
);

Future<void> _seedAlgorithm(
  AppDatabase database,
  AlgorithmInfo algorithm,
) async {
  await database
      .into(database.algorithms)
      .insert(
        AlgorithmEntry(
          guid: algorithm.guid,
          name: algorithm.name,
          numSpecifications: algorithm.specifications.length,
          pluginFilePath: null,
        ),
      );
  for (final (index, specification) in algorithm.specifications.indexed) {
    await database
        .into(database.specifications)
        .insert(
          SpecificationEntry(
            algorithmGuid: algorithm.guid,
            specIndex: index,
            name: specification.name,
            minValue: specification.min,
            maxValue: specification.max,
            defaultValue: specification.defaultValue,
            type: specification.type,
          ),
        );
  }
}

Future<AlgorithmShapeSnapshot> _snapshotFromDb(
  AppDatabase database,
  String guid,
  List<int> specifications,
) async {
  final parameters =
      await (database.select(database.parameters)
            ..where((row) => row.algorithmGuid.equals(guid))
            ..orderBy([(row) => OrderingTerm.asc(row.parameterNumber)]))
          .get();
  return AlgorithmShapeSnapshot(
    specificationValues: specifications,
    parameters: [
      for (final parameter in parameters)
        ShapeParameterAtom(
          name: parameter.name,
          min: parameter.minValue ?? 0,
          max: parameter.maxValue ?? 0,
          defaultValue: parameter.defaultValue ?? 0,
          rawUnitIndex: parameter.rawUnitIndex ?? 0,
          powerOfTen: parameter.powerOfTen ?? 0,
          ioFlags: parameter.ioFlags ?? 0,
          enumStrings: const [],
        ),
    ],
    pages: const [],
    pageMemberships: const [],
    outputUsage: const [],
  );
}
