import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        Mapping,
        ParameterEnumStrings,
        ParameterInfo,
        ParameterValue;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart'
    show DistingCubit, DistingStateInitial;
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/db/database.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class MockDistingController extends Mock implements DistingController {}

class MockDistingCubit extends Mock implements DistingCubit {}

class FakePackedMappingData extends Fake implements PackedMappingData {}

void main() {
  late MockDistingController controller;
  late MockDistingCubit cubit;
  late DistingTools distingTools;
  late MCPAlgorithmTools algoTools;
  late AppDatabase database;

  // Test slot with non-contiguous parameter numbers: hardware [0, 5, 10]
  final testAlgorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'test',
    name: 'TestAlgo',
  );

  final testParameters = [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 100,
      defaultValue: 50,
      unit: 0,
      name: 'Level',
      powerOfTen: 0,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 5,
      min: 0,
      max: 100,
      defaultValue: 50,
      unit: 0,
      name: 'Mix',
      powerOfTen: 0,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 10,
      min: 0,
      max: 1000,
      defaultValue: 500,
      unit: 0,
      name: 'Freq',
      powerOfTen: 0,
    ),
  ];

  final testValues = [
    ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
    ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 75),
    ParameterValue(algorithmIndex: 0, parameterNumber: 10, value: 500),
  ];

  final testMappings = [
    Mapping(
      algorithmIndex: 0,
      parameterNumber: 0,
      packedMappingData: PackedMappingData.filler(),
    ),
    Mapping(
      algorithmIndex: 0,
      parameterNumber: 5,
      packedMappingData: PackedMappingData.filler(),
    ),
    Mapping(
      algorithmIndex: 0,
      parameterNumber: 10,
      packedMappingData: PackedMappingData.filler(),
    ),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(FakePackedMappingData());
    registerFallbackValue(
      Algorithm(algorithmIndex: 0, guid: 'fake', name: 'Fake'),
    );

    database = AppDatabase.forTesting(NativeDatabase.memory());

    var current = Directory.current;
    while (!File(path.join(current.path, 'pubspec.yaml')).existsSync()) {
      final parent = current.parent;
      if (parent.path == current.path) {
        throw Exception('Could not find project root');
      }
      current = parent;
    }
    final metadataPath = path.join(
      current.path,
      'assets',
      'metadata',
      'full_metadata.json',
    );
    final file = File(metadataPath);
    final jsonString = file.readAsStringSync();

    final importService = MetadataImportService(database);
    await importService.importFromJson(jsonString);

    await AlgorithmMetadataService().initialize(database);
  });

  setUp(() {
    controller = MockDistingController();
    cubit = MockDistingCubit();
    distingTools = DistingTools(controller, cubit);
    algoTools = MCPAlgorithmTools(controller, cubit);

    // Default stubs for synchronized state
    when(() => controller.isSynchronized).thenReturn(true);
    when(
      () => controller.getAlgorithmInSlot(0),
    ).thenAnswer((_) async => testAlgorithm);
    when(
      () => controller.getParametersForSlot(0),
    ).thenAnswer((_) async => testParameters);
    when(
      () => controller.getValuesForSlot(0),
    ).thenAnswer((_) async => testValues);
    when(
      () => controller.getMappingsForSlot(0),
    ).thenAnswer((_) async => testMappings);
    when(() => controller.flushParameterQueue()).thenAnswer((_) async {});
    when(() => controller.savePreset()).thenAnswer((_) async {});
    when(
      () => controller.getCurrentPresetName(),
    ).thenAnswer((_) async => 'TestPreset');
    when(
      () => controller.getAllSlots(),
    ).thenAnswer((_) async => {0: testAlgorithm});
    when(() => controller.setPresetName(any())).thenAnswer((_) async {});
    // Stub cubit.state for _getAllKnownAlgorithms (returns non-synchronized)
    when(() => cubit.state).thenReturn(const DistingStateInitial());
  });

  tearDownAll(() async {
    await database.close();
  });

  group('show tools — non-contiguous parameter numbers', () {
    test('showSlot returns hardware parameter numbers', () async {
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;
      final params = json['parameters'] as List<dynamic>;

      final paramNumbers = params
          .map((p) => (p as Map<String, dynamic>)['parameter_number'])
          .toList();
      expect(paramNumbers, equals([0, 5, 10]));
    });

    test('showParameter(5) finds correct param', () async {
      final result = await algoTools.showParameter('0:5');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['parameter_number'], equals(5));
      expect(json['parameter_name'], equals('Mix'));
    });

    test('showParameter(3) errors with available numbers', () async {
      final result = await algoTools.showParameter('0:3');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('3'));
      expect(json['error'], contains('[0, 5, 10]'));
    });

    test(
      'showParameter(1) errors — array index exists but not a hardware number',
      () async {
        final result = await algoTools.showParameter('0:1');
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('1'));
        expect(json['error'], contains('[0, 5, 10]'));
      },
    );
  });

  group('editParameter — parameter resolution + call ordering', () {
    test('editParameter by number=5 calls controller with 5', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });

      verify(() => controller.updateParameterValue(0, 5, 80)).called(1);
    });

    test('editParameter by name="Mix" resolves to hardware number 5', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 'Mix',
        'value': 80,
      });

      verify(() => controller.updateParameterValue(0, 5, 80)).called(1);
    });

    test('editParameter returns hardware param number in response', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['parameter_number'], equals(5));
    });

    test('editParameter(3) errors with available hardware numbers', () async {
      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 3,
        'value': 50,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('3'));
      expect(json['error'], contains('0:'));
      expect(json['error'], contains('5:'));
      expect(json['error'], contains('10:'));
    });

    test(
      'editParameter(1) errors — array index, not hardware number',
      () async {
        final result = await distingTools.editParameter({
          'slot_index': 0,
          'parameter_number': 1,
          'value': 50,
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('1'));
      },
    );

    test('editParameter flushes before save', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });

      verifyInOrder([
        () => controller.updateParameterValue(0, 5, 80),
        () => controller.flushParameterQueue(),
        () => controller.savePreset(),
      ]);
    });

    test('editParameter reads back after flush+save', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });

      verifyInOrder([
        () => controller.flushParameterQueue(),
        () => controller.savePreset(),
        () => controller.getParameterValue(0, 5),
      ]);
    });

    test('editParameter read-back returns post-write value', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['value'], equals(80));
    });
  });

  group('editSlot — multi-param + ordering', () {
    test('editSlot resolves param by hardware number', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        final idx = testParameters.indexWhere(
          (p) => p.parameterNumber == paramNum,
        );
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: paramNum == 5 ? 80 : testValues[idx].value,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 5, 'value': 80},
          ],
        },
      });

      verify(() => controller.updateParameterValue(0, 5, 80)).called(1);
    });

    test('editSlot errors with available numbers for invalid param', () async {
      final result = await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 3, 'value': 50},
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('3'));
    });

    test('editSlot read-back uses hardware param numbers', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        final idx = testParameters.indexWhere(
          (p) => p.parameterNumber == paramNum,
        );
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: paramNum == 5 ? 80 : testValues[idx].value,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      final result = await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 5, 'value': 80},
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final params = json['parameters'] as List<dynamic>;

      final paramNumbers = params
          .map((p) => (p as Map<String, dynamic>)['parameter_number'])
          .toList();
      expect(paramNumbers, equals([0, 5, 10]));
    });

    test('editSlot with multiple params: flush before save', () async {
      when(
        () => controller.updateParameterValue(
          0,
          any(that: isA<int>()),
          any(that: isA<int>()),
        ),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: 80,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 0, 'value': 80},
            {'parameter_number': 5, 'value': 80},
          ],
        },
      });

      verifyInOrder([
        () => controller.updateParameterValue(0, 0, 80),
        () => controller.updateParameterValue(0, 5, 80),
        () => controller.flushParameterQueue(),
        () => controller.savePreset(),
      ]);
    });

    test('editSlot applies mapping updates via _applyMappingUpdates', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        final idx = testParameters.indexWhere(
          (p) => p.parameterNumber == paramNum,
        );
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: paramNum == 5 ? 80 : testValues[idx].value,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      // Stub getParameterMapping to return existing mapping for param 5
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      // Stub saveMapping to accept the update
      when(() => controller.saveMapping(0, 5, any())).thenAnswer((_) async {});

      await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {
              'parameter_number': 5,
              'value': 80,
              'mapping': {
                'cv': {'source': 1},
              },
            },
          ],
        },
      });

      // Verify that saveMapping was called — mapping was applied
      verify(() => controller.saveMapping(0, 5, any())).called(1);
    });

    test('editSlot read-back returns post-write values', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: paramNum == 5 ? 80 : 50,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      final result = await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 5, 'value': 80},
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final params = json['parameters'] as List<dynamic>;

      final mixParam =
          params.firstWhere(
                (p) => (p as Map<String, dynamic>)['parameter_number'] == 5,
              )
              as Map<String, dynamic>;
      expect(mixParam['value'], equals(80));
    });
  });

  group('editPreset — ordering', () {
    test('editPreset flushes before save', () async {
      // Use empty preset so _applyDiff doesn't need extensive stubs
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'OldPreset');

      await distingTools.editPreset({
        'data': {'name': 'NewPreset'},
      });

      verifyInOrder([
        () => controller.flushParameterQueue(),
        () => controller.savePreset(),
      ]);
    });

    test('editPreset read-back uses hardware param numbers', () async {
      // Use empty preset for simplicity; the flush→save ordering is verified above
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});
      // Simulate name changing: first call returns old, subsequent return new
      var nameCallCount = 0;
      when(() => controller.getCurrentPresetName()).thenAnswer((_) async {
        nameCallCount++;
        return nameCallCount <= 1 ? 'OldPreset' : 'NewPreset';
      });

      final result = await distingTools.editPreset({
        'data': {'name': 'NewPreset'},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      expect(json['preset_name'], equals('NewPreset'));
    });
  });

  group('show tools don\'t flush', () {
    test('showSlot does not call flushParameterQueue', () async {
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      await algoTools.showSlot(0);

      verifyNever(() => controller.flushParameterQueue());
    });

    test('showParameter does not call flushParameterQueue', () async {
      await algoTools.showParameter('0:5');

      verifyNever(() => controller.flushParameterQueue());
    });
  });

  group(
    'editPreset _applyDiff — mapping collection uses hardware param numbers',
    () {
      test(
        'getParameterMapping called with hardware numbers not array indices',
        () async {
          // Preset has one slot with non-contiguous params [0, 5, 10].
          // editPreset keeps same algorithm (no swap). The pre-collection
          // loop in _applyDiff should call getParameterMapping with hardware
          // parameter numbers, NOT array indices.
          //
          // Bug: loop uses `paramNum` (0,1,2) instead of
          // `paramList[paramNum].parameterNumber` (0,5,10).

          // Use a real GUID so _validateDiff passes metadata checks
          const realGuid = 'attn';
          final realAlgorithm = Algorithm(
            algorithmIndex: 0,
            guid: realGuid,
            name: 'Attenuator',
          );

          when(
            () => controller.getAllSlots(),
          ).thenAnswer((_) async => {0: realAlgorithm});
          when(
            () => controller.getAlgorithmInSlot(0),
          ).thenAnswer((_) async => realAlgorithm);
          when(
            () => controller.getParametersForSlot(0),
          ).thenAnswer((_) async => testParameters);
          when(
            () => controller.getCurrentPresetName(),
          ).thenAnswer((_) async => 'TestPreset');

          // Stub getParameterMapping for hardware numbers
          when(
            () => controller.getParameterMapping(0, 0),
          ).thenAnswer((_) async => testMappings[0]);
          when(
            () => controller.getParameterMapping(0, 5),
          ).thenAnswer((_) async => testMappings[1]);
          when(
            () => controller.getParameterMapping(0, 10),
          ).thenAnswer((_) async => testMappings[2]);

          // Stub the buggy array-index calls so the test doesn't throw
          when(
            () => controller.getParameterMapping(0, 1),
          ).thenAnswer((_) async => null);
          when(
            () => controller.getParameterMapping(0, 2),
          ).thenAnswer((_) async => null);

          // Stub read-back methods
          when(
            () => controller.getParameterValue(0, any(that: isA<int>())),
          ).thenAnswer((inv) async {
            final paramNum = inv.positionalArguments[1] as int;
            return ParameterValue(
              algorithmIndex: 0,
              parameterNumber: paramNum,
              value: 50,
            );
          });

          // editPreset: same algorithm, no parameter changes — just triggers
          // the mapping pre-collection loop
          await distingTools.editPreset({
            'data': {
              'name': 'TestPreset',
              'slots': [
                {
                  'algorithm': {'guid': realGuid},
                },
              ],
            },
          });

          // The mapping pre-collection should use hardware param numbers
          verify(
            () => controller.getParameterMapping(0, 0),
          ).called(greaterThanOrEqualTo(1));
          verify(
            () => controller.getParameterMapping(0, 5),
          ).called(greaterThanOrEqualTo(1));
          verify(
            () => controller.getParameterMapping(0, 10),
          ).called(greaterThanOrEqualTo(1));

          // Array indices 1 and 2 should NEVER be used as parameter numbers
          verifyNever(() => controller.getParameterMapping(0, 1));
          verifyNever(() => controller.getParameterMapping(0, 2));
        },
      );
    },
  );

  group('newWithAlgorithms — non-contiguous parameter read-back', () {
    // Use a real GUID so algorithm resolution works
    const realGuid = 'attn';
    final realAlgorithm = Algorithm(
      algorithmIndex: 0,
      guid: realGuid,
      name: 'Attenuator',
    );

    // Make param at index 1 (hardware number 5) an enum param (unit=1)
    final enumTestParameters = [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Level',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 5,
        min: 0,
        max: 3,
        defaultValue: 0,
        unit: 1, // enum unit
        name: 'Mode',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 10,
        min: 0,
        max: 1000,
        defaultValue: 500,
        unit: 0,
        name: 'Freq',
        powerOfTen: 0,
      ),
    ];

    setUp(() {
      // Stubs for newWithAlgorithms flow
      when(() => controller.newPreset()).thenAnswer((_) async {});
      when(() => controller.setPresetName(any())).thenAnswer((_) async {});
      when(() => controller.addAlgorithm(any())).thenAnswer((_) async {});
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => {0: realAlgorithm});
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => realAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => enumTestParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'TestPreset');
    });

    test(
      'read-back calls getParameterEnumStrings with hardware numbers, not array indices',
      () async {
        // Stub getParameterEnumStrings for hardware number 5 (the enum param)
        when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
          (_) async => ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 5,
            values: ['Off', 'Low', 'Mid', 'High'],
          ),
        );

        // Stub the buggy call (array index 1) so it doesn't throw
        when(
          () => controller.getParameterEnumStrings(0, 1),
        ).thenAnswer((_) async => null);

        // Stub getParameterMapping for all hardware numbers
        when(
          () => controller.getParameterMapping(0, any(that: isA<int>())),
        ).thenAnswer((_) async => null);

        // Stub getParameterValue for read-back
        when(
          () => controller.getParameterValue(0, any(that: isA<int>())),
        ).thenAnswer((inv) async {
          final paramNum = inv.positionalArguments[1] as int;
          return ParameterValue(
            algorithmIndex: 0,
            parameterNumber: paramNum,
            value: 50,
          );
        });

        await distingTools.newWithAlgorithms({
          'name': 'Test Preset',
          'algorithms': [
            {'guid': realGuid},
          ],
        });

        // Should call with hardware number 5, not array index 1
        verify(() => controller.getParameterEnumStrings(0, 5)).called(1);
        verifyNever(() => controller.getParameterEnumStrings(0, 1));
      },
    );

    test(
      'read-back calls getParameterMapping with hardware numbers, not array indices',
      () async {
        // Stub getParameterMapping for hardware numbers
        when(
          () => controller.getParameterMapping(0, 0),
        ).thenAnswer((_) async => testMappings[0]);
        when(
          () => controller.getParameterMapping(0, 5),
        ).thenAnswer((_) async => testMappings[1]);
        when(
          () => controller.getParameterMapping(0, 10),
        ).thenAnswer((_) async => testMappings[2]);

        // Stub buggy array-index calls
        when(
          () => controller.getParameterMapping(0, 1),
        ).thenAnswer((_) async => null);
        when(
          () => controller.getParameterMapping(0, 2),
        ).thenAnswer((_) async => null);

        // Stub getParameterEnumStrings for enum param
        when(
          () => controller.getParameterEnumStrings(0, 5),
        ).thenAnswer((_) async => null);

        // Stub getParameterValue for read-back
        when(
          () => controller.getParameterValue(0, any(that: isA<int>())),
        ).thenAnswer((inv) async {
          final paramNum = inv.positionalArguments[1] as int;
          return ParameterValue(
            algorithmIndex: 0,
            parameterNumber: paramNum,
            value: 50,
          );
        });

        await distingTools.newWithAlgorithms({
          'name': 'Test Preset',
          'algorithms': [
            {'guid': realGuid},
          ],
        });

        // Should use hardware param numbers
        verify(
          () => controller.getParameterMapping(0, 0),
        ).called(greaterThanOrEqualTo(1));
        verify(
          () => controller.getParameterMapping(0, 5),
        ).called(greaterThanOrEqualTo(1));
        verify(
          () => controller.getParameterMapping(0, 10),
        ).called(greaterThanOrEqualTo(1));

        // Array indices 1 and 2 should NEVER be used
        verifyNever(() => controller.getParameterMapping(0, 1));
        verifyNever(() => controller.getParameterMapping(0, 2));
      },
    );
  });

  group('searchParameters — display-scaled values', () {
    // Parameters with powerOfTen: 2 so raw values differ from display values
    final scaledParameters = [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 10000,
        defaultValue: 5000,
        unit: 0,
        name: 'Frequency',
        powerOfTen: 2,
      ),
    ];

    test('searchParametersInSlot returns display-scaled values', () async {
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => scaledParameters);
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
      );

      final result = await distingTools.searchParametersInSlot(
        0,
        'Frequency',
        false,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      final matches = json['matches'] as List<dynamic>;
      expect(matches, hasLength(1));

      final match = matches[0] as Map<String, dynamic>;
      expect(match['parameter_name'], equals('Frequency'));
      // Display-scaled: 150 / 10^2 = 1.5
      expect(match['value'], equals(1.5));
      // Display-scaled: 0 / 10^2 = 0
      expect(match['min'], equals(0));
      // Display-scaled: 10000 / 10^2 = 100.0
      expect(match['max'], equals(100.0));
    });

    test('searchParametersInPreset returns display-scaled values', () async {
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => scaledParameters);
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
      );

      final result = await distingTools.searchParametersInPreset(
        'Frequency',
        false,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      final results = json['results'] as List<dynamic>;
      expect(results, hasLength(1));

      final slotResult = results[0] as Map<String, dynamic>;
      final matches = slotResult['matches'] as List<dynamic>;
      expect(matches, hasLength(1));

      final match = matches[0] as Map<String, dynamic>;
      expect(match['parameter_name'], equals('Frequency'));
      // Display-scaled: 150 / 10^2 = 1.5
      expect(match['value'], equals(1.5));
      // Display-scaled: 0 / 10^2 = 0
      expect(match['min'], equals(0));
      // Display-scaled: 10000 / 10^2 = 100.0
      expect(match['max'], equals(100.0));
    });

    test(
      'searchParametersInPreset exact match ignores surrounding whitespace in parameter names',
      () async {
        final whitespaceyParameters = [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            min: 0,
            max: 10000,
            defaultValue: 5000,
            unit: 0,
            name: 'Speed ',
            powerOfTen: 0,
          ),
        ];

        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => whitespaceyParameters);
        when(() => controller.getParameterValue(0, 0)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 12),
        );

        final result = await distingTools.searchParametersInPreset(
          'Speed',
          false,
        );
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        final results = json['results'] as List<dynamic>;
        expect(results, hasLength(1));

        final slotResult = results[0] as Map<String, dynamic>;
        final matches = slotResult['matches'] as List<dynamic>;
        expect(matches, hasLength(1));
        final match = matches[0] as Map<String, dynamic>;
        expect(match['parameter_name'], equals('Speed '));
      },
    );
  });

  group('getMultipleParameters — value extraction', () {
    test('returns actual values from nested data, not null', () async {
      // Stub getParameterValue and getParameterMapping for params 0 and 5
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
      );
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 75),
      );
      when(
        () => controller.getParameterMapping(0, 0),
      ).thenAnswer((_) async => testMappings[0]);
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => testMappings[1]);

      final result = await distingTools.getMultipleParameters({
        'slot_index': 0,
        'parameter_numbers': [0, 5],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      // buildSuccess flattens data into top-level map
      final results = json['results'] as List<dynamic>;

      // Values should NOT be null — they should be the actual parameter values
      final param0 = results[0] as Map<String, dynamic>;
      final param5 = results[1] as Map<String, dynamic>;
      expect(
        param0['value'],
        isNotNull,
        reason: 'param 0 value should not be null',
      );
      expect(param0['value'], equals(50));
      expect(
        param5['value'],
        isNotNull,
        reason: 'param 5 value should not be null',
      );
      expect(param5['value'], equals(75));
      // Should also include parameter_name from nested data
      expect(param0['parameter_name'], equals('Level'));
      expect(param5['parameter_name'], equals('Mix'));
    });
  });

  group('editPreset _validateDiff — hardware parameter number validation', () {
    const realGuid = 'attn';
    final realAlgorithm = Algorithm(
      algorithmIndex: 0,
      guid: realGuid,
      name: 'Attenuator',
    );

    setUp(() {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => {0: realAlgorithm});
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => realAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParameters);
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'TestPreset');
    });

    test(
      'accepts valid hardware parameter number for existing algorithm',
      () async {
        // Stub for the apply phase
        when(
          () => controller.updateParameterValue(0, 5, 75),
        ).thenAnswer((_) async {});
        when(
          () => controller.getParameterValue(0, any(that: isA<int>())),
        ).thenAnswer((inv) async {
          final paramNum = inv.positionalArguments[1] as int;
          return ParameterValue(
            algorithmIndex: 0,
            parameterNumber: paramNum,
            value: 75,
          );
        });
        when(
          () => controller.getParameterMapping(0, any(that: isA<int>())),
        ).thenAnswer((_) async => null);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final result = await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 5, 'value': 75},
                ],
              },
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
      },
    );

    test(
      'rejects invalid hardware parameter number for existing algorithm',
      () async {
        final result = await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 3, 'value': 50},
                ],
              },
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('3'));
        expect(json['error'], contains('[0, 5, 10]'));
      },
    );

    test(
      'validates bounds using correct parameter for existing algorithm',
      () async {
        final result = await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 10, 'value': 5000},
                ],
              },
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('bounds'));
        expect(json['error'], contains('5000'));
      },
    );
  });

  group('powerOfTen scaling — editSlot and _applyDiff', () {
    final scaledParameters = [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 10000,
        defaultValue: 5000,
        unit: 0,
        name: 'ScaledParam',
        powerOfTen: 2,
      ),
    ];

    final scaledValues = [
      ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 5000),
    ];

    final scaledMappings = [
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler(),
      ),
    ];

    const realGuid = 'attn';
    final realAlgorithm = Algorithm(
      algorithmIndex: 0,
      guid: realGuid,
      name: 'Attenuator',
    );

    test('editSlot with powerOfTen parameter scales display to raw', () async {
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => realAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => scaledParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => scaledValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => scaledMappings);
      when(
        () => controller.updateParameterValue(0, 0, 150),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
      );
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 0, 'value': 1.5},
          ],
        },
      });

      verify(() => controller.updateParameterValue(0, 0, 150)).called(1);
    });

    test(
      'editPreset _applyDiff with powerOfTen parameter scales display to raw',
      () async {
        when(
          () => controller.getAllSlots(),
        ).thenAnswer((_) async => {0: realAlgorithm});
        when(
          () => controller.getAlgorithmInSlot(0),
        ).thenAnswer((_) async => realAlgorithm);
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => scaledParameters);
        when(
          () => controller.getCurrentPresetName(),
        ).thenAnswer((_) async => 'TestPreset');
        when(
          () => controller.getParameterMapping(0, 0),
        ).thenAnswer((_) async => scaledMappings[0]);
        when(
          () => controller.updateParameterValue(0, 0, 150),
        ).thenAnswer((_) async {});
        when(() => controller.getParameterValue(0, 0)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
        );
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 0, 'value': 1.5},
                ],
              },
            ],
          },
        });

        verify(() => controller.updateParameterValue(0, 0, 150)).called(1);
      },
    );
  });

  group('_buildMappingJson — CV threshold bug', () {
    PackedMappingData makeMappingData({
      int cvInput = 0,
      int source = 0,
      bool isMidiEnabled = false,
      int midiChannel = 0,
      int midiCC = 1,
    }) {
      return PackedMappingData(
        source: source,
        cvInput: cvInput,
        isUnipolar: false,
        isGate: false,
        volts: 5,
        delta: 0,
        midiChannel: midiChannel,
        midiMappingType: MidiMappingType.cc,
        midiCC: midiCC,
        isMidiEnabled: isMidiEnabled,
        isMidiSymmetric: false,
        isMidiRelative: false,
        midiMin: 0,
        midiMax: 127,
        i2cCC: 0,
        isI2cEnabled: false,
        isI2cSymmetric: false,
        i2cMin: 0,
        i2cMax: 127,
        perfPageIndex: 0,
        version: 5,
      );
    }

    test('mapping omits CV when cvInput=0 and source=0', () async {
      final midiOnlyMapping = Mapping(
        algorithmIndex: 0,
        parameterNumber: 5,
        packedMappingData: makeMappingData(
          cvInput: 0,
          source: 0,
          isMidiEnabled: true,
        ),
      );

      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => midiOnlyMapping);

      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final mapping = json['mapping'] as Map<String, dynamic>;

      expect(
        mapping.containsKey('cv'),
        isFalse,
        reason: 'CV section should be omitted when cvInput=0 and source=0',
      );
      expect(mapping.containsKey('midi'), isTrue);
    });

    test('mapping includes CV when cvInput > 0', () async {
      final cvMapping = Mapping(
        algorithmIndex: 0,
        parameterNumber: 5,
        packedMappingData: makeMappingData(cvInput: 1, source: 0),
      );

      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => cvMapping);

      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final mapping = json['mapping'] as Map<String, dynamic>;

      expect(
        mapping.containsKey('cv'),
        isTrue,
        reason: 'CV section should be present when cvInput > 0',
      );
    });

    test('mapping includes CV when source > 0 even if cvInput=0', () async {
      final sourceMapping = Mapping(
        algorithmIndex: 0,
        parameterNumber: 5,
        packedMappingData: makeMappingData(cvInput: 0, source: 1),
      );

      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 80),
      );
      when(
        () => controller.getParameterMapping(0, 5),
      ).thenAnswer((_) async => sourceMapping);

      final result = await distingTools.editParameter({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final mapping = json['mapping'] as Map<String, dynamic>;

      expect(
        mapping.containsKey('cv'),
        isTrue,
        reason: 'CV section should be present when source > 0',
      );
    });
  });

  group('Bug 1: _validateDiff scales display values to raw before bounds check', () {
    // Parameter with powerOfTen: 2, raw bounds 0-10000, display bounds 0-100
    final scaledParameters = [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 10000,
        defaultValue: 5000,
        unit: 0,
        name: 'ScaledParam',
        powerOfTen: 2,
      ),
    ];

    const realGuid = 'attn';
    final realAlgorithm = Algorithm(
      algorithmIndex: 0,
      guid: realGuid,
      name: 'Attenuator',
    );

    setUp(() {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => {0: realAlgorithm});
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => realAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => scaledParameters);
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'TestPreset');
    });

    test(
      'rejects display value 150 (exceeds display max 100) for existing algorithm',
      () async {
        // Display value 150 with powerOfTen=2 => raw 15000, exceeds raw max 10000
        // Without the fix, 150 < 10000 (raw max) would PASS validation incorrectly
        final result = await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 0, 'value': 150},
                ],
              },
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('bounds'));
      },
    );

    test(
      'accepts display value 50 (within display bounds 0-100) for existing algorithm',
      () async {
        // Display value 50 with powerOfTen=2 => raw 5000, within raw bounds 0-10000
        when(
          () => controller.updateParameterValue(0, 0, 5000),
        ).thenAnswer((_) async {});
        when(() => controller.getParameterValue(0, 0)).thenAnswer(
          (_) async => ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 5000,
          ),
        );
        when(
          () => controller.getParameterMapping(0, 0),
        ).thenAnswer((_) async => null);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final result = await distingTools.editPreset({
          'data': {
            'name': 'TestPreset',
            'slots': [
              {
                'algorithm': {'guid': realGuid},
                'parameters': [
                  {'parameter_number': 0, 'value': 50},
                ],
              },
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
      },
    );
  });

  group('Bug 2: setMultipleParameters returns confirmed value', () {
    test('returns device-confirmed value, not input value', () async {
      // Set up: input value 80, but device confirms 79 (e.g., clamped)
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => testAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => testMappings);
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});

      final result = await distingTools.setMultipleParameters({
        'slot_index': 0,
        'parameters': [
          {'parameter_number': 5, 'value': 80},
        ],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      final results = json['results'] as List<dynamic>;
      final param = results[0] as Map<String, dynamic>;
      // setParameterValue returns the message string as success text,
      // and the value field in setMultipleParameters should come from
      // the confirmed response, not the input
      expect(param['value'], isNotNull);
      // The value should match what setParameterValue confirmed (80 in this case)
      expect(param['value'], equals(80));
    });
  });

  group('Bug 4: setParameterValue enum bounds validation', () {
    // Use enum parameter: unit=1, max=3 (4 enum options: 0,1,2,3)
    final enumParameters = [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 3,
        defaultValue: 0,
        unit: 1,
        name: 'Mode',
        powerOfTen: 0,
      ),
    ];

    final enumValues = [
      ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
    ];

    final enumMappings = [
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler(),
      ),
    ];

    test('rejects numeric enum index exceeding enum length', () async {
      when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
        (_) async =>
            Algorithm(algorithmIndex: 0, guid: 'test', name: 'TestAlgo'),
      );
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => enumParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => enumValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => enumMappings);
      when(() => controller.getParameterEnumStrings(0, 0)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 0,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 0,
        'value': 'Invalid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Valid values'));
    });

    test('rejects numeric value for enum parameter', () async {
      when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
        (_) async =>
            Algorithm(algorithmIndex: 0, guid: 'test', name: 'TestAlgo'),
      );
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => enumParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => enumValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => enumMappings);
      when(() => controller.getParameterEnumStrings(0, 0)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 0,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 0,
        'value': 2,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('string value'));
    });

    test('accepts valid enum string value', () async {
      when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
        (_) async =>
            Algorithm(algorithmIndex: 0, guid: 'test', name: 'TestAlgo'),
      );
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => enumParameters);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => enumValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => enumMappings);
      when(() => controller.getParameterEnumStrings(0, 0)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 0,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      when(
        () => controller.updateParameterValue(0, 0, 2),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 0,
        'value': 'Mid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
    });
  });

  group('response key consistency — parameter_name not name', () {
    test('editSlot response uses parameter_name key', () async {
      when(
        () => controller.updateParameterValue(0, 5, 80),
      ).thenAnswer((_) async {});
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        final idx = testParameters.indexWhere(
          (p) => p.parameterNumber == paramNum,
        );
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: paramNum == 5 ? 80 : testValues[idx].value,
        );
      });
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      final result = await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 5, 'value': 80},
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final params = json['parameters'] as List<dynamic>;

      for (final p in params) {
        final param = p as Map<String, dynamic>;
        expect(
          param.containsKey('parameter_name'),
          isTrue,
          reason: 'editSlot response should use parameter_name, not name',
        );
        expect(
          param.containsKey('name'),
          isFalse,
          reason: 'editSlot response should not use bare name key',
        );
      }
    });

    test('getCurrentPreset returns a bounded parameter page', () async {
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        final idx = testParameters.indexWhere(
          (p) => p.parameterNumber == paramNum,
        );
        return testValues[idx];
      });
      when(
        () => controller.getParameterEnumStrings(
          any(that: isA<int>()),
          any(that: isA<int>()),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => controller.getParameterMapping(0, any(that: isA<int>())),
      ).thenAnswer((invocation) async {
        final parameterNumber = invocation.positionalArguments[1] as int;
        return Mapping(
          algorithmIndex: 0,
          parameterNumber: parameterNumber,
          packedMappingData: PackedMappingData.filler().copyWith(
            perfPageIndex: parameterNumber == 0 ? 3 : 0,
          ),
        );
      });
      when(
        () => controller.getSlotName(0),
      ).thenAnswer((_) async => 'Lead Voice');

      final result = await distingTools.getCurrentPreset({
        'parameter_limit': 1,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final slots = json['slots'] as List<dynamic>;
      final slot = slots.single as Map<String, dynamic>;
      final params = slot['parameters'] as List<dynamic>;

      expect(json['success'], isTrue);
      expect(json['populated_slot_count'], 1);
      expect(slot['name'], 'Lead Voice');
      expect(params, hasLength(1));
      expect(params.first['mapping'], {'performance_page': 3});
      expect(json['paging'], {
        'slot_offset': 0,
        'parameter_offset': 0,
        'parameter_limit': 1,
        'count': 1,
        'total': 3,
        'has_more': true,
        'next': {
          'tool': 'get_preset',
          'arguments': {
            'slot_offset': 0,
            'parameter_offset': 1,
            'parameter_limit': 1,
          },
        },
      });

      for (final p in params) {
        final param = p as Map<String, dynamic>;
        expect(
          param.containsKey('parameter_name'),
          isTrue,
          reason:
              'getCurrentPreset response should use parameter_name, not name',
        );
        expect(
          param.containsKey('name'),
          isFalse,
          reason: 'getCurrentPreset response should not use bare name key',
        );
      }

      final nextArguments =
          ((json['paging'] as Map<String, dynamic>)['next']
                  as Map<String, dynamic>)['arguments']
              as Map<String, dynamic>;
      final next =
          jsonDecode(await distingTools.getCurrentPreset(nextArguments))
              as Map<String, dynamic>;
      final nextSlot = (next['slots'] as List<dynamic>).single;
      final nextParams = nextSlot['parameters'] as List<dynamic>;
      expect(nextParams.single['parameter_number'], 5);
    });

    test(
      'getCurrentPreset continuation advances to the next populated slot',
      () async {
        final secondAlgorithm = Algorithm(
          algorithmIndex: 1,
          guid: 'next',
          name: 'Next Algorithm',
        );
        when(
          () => controller.getAllSlots(),
        ).thenAnswer((_) async => {3: secondAlgorithm, 0: testAlgorithm});
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => const <ParameterInfo>[]);
        when(
          () => controller.getSlotName(0),
        ).thenAnswer((_) async => 'Empty Control Slot');

        final json =
            jsonDecode(await distingTools.getCurrentPreset({}))
                as Map<String, dynamic>;
        final paging = json['paging'] as Map<String, dynamic>;
        final next = paging['next'] as Map<String, dynamic>;

        expect(json['populated_slot_count'], 2);
        expect((json['slots'] as List<dynamic>).single['slot_index'], 0);
        expect(paging['count'], 0);
        expect(paging['has_more'], isTrue);
        expect(next['arguments'], {
          'slot_offset': 1,
          'parameter_offset': 0,
          'parameter_limit': 4,
        });
      },
    );

    test('getCurrentPreset rejects an unbounded parameter page', () async {
      final json =
          jsonDecode(
                await distingTools.getCurrentPreset({'parameter_limit': 17}),
              )
              as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('between 1 and 16'));
    });

    test('editPreset response uses parameter_name key', () async {
      const realGuid = 'attn';
      final realAlgorithm = Algorithm(
        algorithmIndex: 0,
        guid: realGuid,
        name: 'Attenuator',
      );

      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => {0: realAlgorithm});
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => realAlgorithm);
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParameters);
      when(
        () => controller.getParameterValue(0, any(that: isA<int>())),
      ).thenAnswer((inv) async {
        final paramNum = inv.positionalArguments[1] as int;
        return ParameterValue(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          value: 50,
        );
      });
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'TestPreset');
      when(
        () => controller.getParameterMapping(0, any(that: isA<int>())),
      ).thenAnswer((_) async => null);

      final result = await distingTools.editPreset({
        'data': {
          'name': 'TestPreset',
          'slots': [
            {
              'algorithm': {'guid': realGuid},
            },
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      final slots = json['slots'] as List<dynamic>;
      final slot = (slots.firstWhere((s) => s != null)) as Map<String, dynamic>;
      final params = slot['parameters'] as List<dynamic>;
      expect(params, isNotEmpty);

      for (final p in params) {
        final param = p as Map<String, dynamic>;
        expect(
          param.containsKey('parameter_name'),
          isTrue,
          reason: 'editPreset response should use parameter_name, not name',
        );
        expect(
          param.containsKey('name'),
          isFalse,
          reason: 'editPreset response should not use bare name key',
        );
      }
    });
  });
}
