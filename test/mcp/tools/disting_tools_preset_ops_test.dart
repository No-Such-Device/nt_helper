import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        AlgorithmInfo,
        Mapping,
        ParameterInfo,
        ParameterValue,
        Specification;
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart'
    show DistingCubit, DistingState, DistingStateInitial;
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/db/database.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class MockDistingController extends Mock implements DistingController {}

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class FakePackedMappingData extends Fake implements PackedMappingData {}

void main() {
  late MockDistingController controller;
  late MockDistingCubit cubit;
  late DistingTools distingTools;
  late AppDatabase database;

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
    when(() => cubit.state).thenReturn(const DistingStateInitial());
  });

  tearDownAll(() async {
    await database.close();
  });

  group('addAlgorithm — verification ownership', () {
    test(
      'trusts controller completion without polling slot count or GUID again',
      () async {
        final manager = MockDistingMidiManager();
        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Test',
            firmwareVersion: FirmwareVersion('1.17'),
            presetName: 'Test Preset',
            algorithms: const [],
            slots: const [],
            unitStrings: const [],
          ),
        );
        when(() => cubit.requireDisting()).thenReturn(manager);
        when(() => controller.addAlgorithm(any())).thenAnswer((_) async {});
        when(
          () => manager.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(() => manager.requestAlgorithmGuid(0)).thenAnswer(
          (_) async =>
              Algorithm(algorithmIndex: 0, guid: 'attn', name: 'Attenuator'),
        );
        final result = await distingTools.addAlgorithm({
          'algorithm_guid': 'attn',
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        verify(() => controller.addAlgorithm(any())).called(1);
        verifyNever(() => cubit.refreshSlot(any()));
        verifyNever(() => manager.requestNumAlgorithmsInPreset());
        verifyNever(() => manager.requestAlgorithmGuid(any()));
      },
    );
  });

  group('addSimple — validation', () {
    test('missing name and guid returns error', () async {
      final result = await distingTools.addSimple({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('identifier'));
    });

    test('invalid slot_index returns error', () async {
      final result = await distingTools.addSimple({
        'name': 'VCO',
        'slot_index': -1,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('-1'));
    });

    test('slot_index 40 (out of range) returns error', () async {
      final result = await distingTools.addSimple({
        'name': 'VCO',
        'slot_index': 40,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('40'));
    });

    test(
      'offline mode with required specs omitted succeeds with limitation notice',
      () async {
        const guid = 'offline-spec-required';
        final manager = MockDistingMidiManager();

        final requiredSpecAlgorithm = AlgorithmInfo(
          algorithmIndex: 0,
          guid: guid,
          name: 'Offline Spec Required',
          specifications: [
            Specification(
              name: 'Mode',
              min: 0,
              max: 4,
              defaultValue: 2,
              type: 0,
            ),
          ],
        );

        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Offline',
            firmwareVersion: FirmwareVersion('1.0.0'),
            presetName: 'Offline Preset',
            algorithms: [requiredSpecAlgorithm],
            slots: const [],
            unitStrings: const [],
            offline: true,
          ),
        );

        when(() => cubit.requireDisting()).thenReturn(manager);
        when(() => controller.addAlgorithm(any())).thenAnswer((_) async {});
        when(
          () => manager.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(() => manager.requestAlgorithmGuid(0)).thenAnswer(
          (_) async => Algorithm(
            algorithmIndex: 0,
            guid: guid,
            name: 'Offline Spec Required',
          ),
        );
        when(() => cubit.refreshSlot(0)).thenAnswer((_) async {});

        final result = await distingTools.addSimple({'guid': guid});
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        expect(json['limitation'], isNotNull);
        expect(
          (json['limitation'] as String).toLowerCase(),
          contains('offline mode'),
        );
        expect(
          (json['limitation'] as String).toLowerCase(),
          contains('specification'),
        );
      },
    );
  });

  group('removeSlot — validation', () {
    test('missing target returns error', () async {
      final result = await distingTools.removeSlot({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('slot'));
    });

    test('missing slot_index returns error', () async {
      final result = await distingTools.removeSlot({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('slot_index'));
    });

    test('out of range slot_index returns error', () async {
      final result = await distingTools.removeSlot({'slot_index': 40});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('40'));
    });

    test('already-empty slot returns success', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});

      final result = await distingTools.removeSlot({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('already empty'));
    });

    test('occupied slot calls clearSlot and returns success', () async {
      when(() => controller.clearSlot(0)).thenAnswer((_) async {});

      final result = await distingTools.removeSlot({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('Removed'));
      verify(() => controller.clearSlot(0)).called(1);
    });

    test(
      'BUG: sparse map with algorithm in high slot index incorrectly reports empty',
      () async {
        // allSlots = {5: algo} — length is 1. removeSlot(5) does 5 < 1 → false → "already empty"
        // This is a bug: the length guard is wrong for a Map.
        final algoInSlot5 = Algorithm(
          algorithmIndex: 5,
          guid: 'test',
          name: 'TestAlgo',
        );
        when(
          () => controller.getAllSlots(),
        ).thenAnswer((_) async => <int, Algorithm?>{5: algoInSlot5});
        when(() => controller.clearSlot(5)).thenAnswer((_) async {});

        final result = await distingTools.removeSlot({'slot_index': 5});
        final json = jsonDecode(result) as Map<String, dynamic>;

        // Should say "Removed" not "already empty", because the slot IS occupied.
        // With the bug, this will say "already empty".
        expect(json['success'], isTrue);
        expect(
          json['message'],
          contains('Removed'),
          reason:
              'Slot 5 has an algorithm but sparse map length guard says it is empty',
        );
      },
    );
  });

  group('editSlot — offline specification limitation', () {
    test(
      'offline same-algorithm patch does not invent specification defaults',
      () async {
        const guid = 'offline-edit-spec-required';
        final manager = MockDistingMidiManager();
        final requiredSpecAlgorithm = AlgorithmInfo(
          algorithmIndex: 0,
          guid: guid,
          name: 'Offline Edit Spec Required',
          specifications: [
            Specification(
              name: 'Mode',
              min: 0,
              max: 4,
              defaultValue: 2,
              type: 0,
            ),
          ],
        );

        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Offline',
            firmwareVersion: FirmwareVersion('1.0.0'),
            presetName: 'Offline Preset',
            algorithms: [requiredSpecAlgorithm],
            slots: const [],
            unitStrings: const [],
            offline: true,
          ),
        );
        when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
          (_) async => Algorithm(
            algorithmIndex: 0,
            guid: guid,
            name: 'Offline Edit Spec Required',
          ),
        );
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => []);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final result = await distingTools.editSlot({
          'slot_index': 0,
          'data': {
            'algorithm': {'guid': guid},
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        expect(json['limitation'], isNull);
        verifyNever(() => controller.clearSlot(any()));
        verifyNever(() => controller.addAlgorithm(any()));
      },
    );
  });

  group('getCurrentPreset — required specifications', () {
    test(
      'exports known specification values with algorithm identity',
      () async {
        const guid = 'known-required-spec';
        final manager = MockDistingMidiManager();
        final algorithm = Algorithm(
          algorithmIndex: 0,
          guid: guid,
          name: 'Known Required Spec',
          specifications: const [4],
        );
        final algorithmInfo = AlgorithmInfo(
          algorithmIndex: 0,
          guid: guid,
          name: 'Known Required Spec',
          specifications: [
            Specification(
              name: 'Channels',
              min: 1,
              max: 8,
              defaultValue: 2,
              type: 0,
            ),
          ],
        );
        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Test',
            firmwareVersion: FirmwareVersion('1.17'),
            presetName: 'Test Preset',
            algorithms: [algorithmInfo],
            slots: const [],
            unitStrings: const [],
          ),
        );
        when(
          () => controller.getAllSlots(),
        ).thenAnswer((_) async => {0: algorithm});
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => const []);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final json =
            jsonDecode(await distingTools.getCurrentPreset({}))
                as Map<String, dynamic>;
        final editArguments =
            json['edit_slot_arguments'] as Map<String, dynamic>;
        final data = editArguments['data'] as Map<String, dynamic>;

        expect(json['restore_ready'], isTrue);
        expect(data['algorithm'], {
          'guid': guid,
          'name': 'Known Required Spec',
          'specifications': [4],
        });
      },
    );

    test(
      'omits unsafe algorithm replay when required values are unavailable',
      () async {
        const guid = 'unknown-required-spec';
        final manager = MockDistingMidiManager();
        final algorithm = Algorithm(
          algorithmIndex: 0,
          guid: guid,
          name: 'Unknown Required Spec',
        );
        final algorithmInfo = AlgorithmInfo(
          algorithmIndex: 0,
          guid: guid,
          name: 'Unknown Required Spec',
          specifications: [
            Specification(
              name: 'Channels',
              min: 1,
              max: 8,
              defaultValue: 2,
              type: 0,
            ),
          ],
        );
        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Test',
            firmwareVersion: FirmwareVersion('1.17'),
            presetName: 'Test Preset',
            algorithms: [algorithmInfo],
            slots: const [],
            unitStrings: const [],
          ),
        );
        when(
          () => controller.getAllSlots(),
        ).thenAnswer((_) async => {0: algorithm});
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => const []);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final json =
            jsonDecode(await distingTools.getCurrentPreset({}))
                as Map<String, dynamic>;
        final editArguments =
            json['edit_slot_arguments'] as Map<String, dynamic>;
        final data = editArguments['data'] as Map<String, dynamic>;

        expect(json['restore_ready'], isFalse);
        expect(json['restore_limitation'], contains('unavailable'));
        expect(json['algorithm_identity'], {
          'guid': guid,
          'name': 'Unknown Required Spec',
        });
        expect(data.containsKey('algorithm'), isFalse);
      },
    );
  });

  group('savePreset', () {
    test('not synchronized returns error', () async {
      when(() => controller.isSynchronized).thenReturn(false);

      final result = await distingTools.savePreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('synchronized'));
    });

    test('preset named "Init" returns error', () async {
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'Init');

      final result = await distingTools.savePreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('Init'));
    });

    test('empty preset name returns error', () async {
      when(() => controller.getCurrentPresetName()).thenAnswer((_) async => '');

      final result = await distingTools.savePreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('normal save succeeds', () async {
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'MyPreset');

      final result = await distingTools.savePreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('MyPreset'));
      verify(() => controller.savePreset()).called(1);
    });
  });

  group('moveAlgorithm', () {
    test('missing slot_index returns error', () async {
      final result = await distingTools.moveAlgorithm({'direction': 'up'});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('missing direction returns error', () async {
      final result = await distingTools.moveAlgorithm({'slot_index': 1});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('invalid direction returns error', () async {
      final result = await distingTools.moveAlgorithm({
        'slot_index': 1,
        'direction': 'left',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('up'));
    });

    test('steps < 1 returns error', () async {
      final result = await distingTools.moveAlgorithm({
        'slot_index': 1,
        'direction': 'up',
        'steps': 0,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('1'));
    });

    test('move up 1 step from slot 1 succeeds', () async {
      when(() => controller.moveAlgorithmUp(1)).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 1,
        'direction': 'up',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('slot 0'));
      verify(() => controller.moveAlgorithmUp(1)).called(1);
    });

    test('move down 1 step from slot 0 succeeds', () async {
      when(() => controller.moveAlgorithmDown(0)).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 0,
        'direction': 'down',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('slot 1'));
      verify(() => controller.moveAlgorithmDown(0)).called(1);
    });

    test('move up from slot 0 returns boundary error', () async {
      final result = await distingTools.moveAlgorithm({
        'slot_index': 0,
        'direction': 'up',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('up'));
    });

    test('move down from last slot returns boundary error', () async {
      final result = await distingTools.moveAlgorithm({
        'slot_index': 39,
        'direction': 'down',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('down'));
    });

    test('multi-step move up calls moveAlgorithmUp multiple times', () async {
      when(
        () => controller.moveAlgorithmUp(any(that: isA<int>())),
      ).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 3,
        'direction': 'up',
        'steps': 3,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('slot 0'));

      // Should call moveAlgorithmUp(3), moveAlgorithmUp(2), moveAlgorithmUp(1)
      verify(() => controller.moveAlgorithmUp(3)).called(1);
      verify(() => controller.moveAlgorithmUp(2)).called(1);
      verify(() => controller.moveAlgorithmUp(1)).called(1);
    });

    test('multi-step move exceeding boundary returns error mid-move', () async {
      when(
        () => controller.moveAlgorithmUp(any(that: isA<int>())),
      ).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 1,
        'direction': 'up',
        'steps': 3,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      // After first step (slot 1→0), second step would be 1-1=0 ≤ 0, error
      expect(json['success'], isFalse);
    });
  });

  group('editPreset — name-only change when not synchronized', () {
    test('name-only change succeeds even when not synchronized', () async {
      when(() => controller.isSynchronized).thenReturn(false);
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'OldPreset');

      final result = await distingTools.editPreset({
        'data': {'name': 'NewPreset'},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
    });

    test('slot changes when not synchronized returns error', () async {
      when(() => controller.isSynchronized).thenReturn(false);

      final result = await distingTools.editPreset({
        'data': {
          'name': 'NewPreset',
          'slots': [
            {
              'algorithm': {'guid': 'attn'},
            },
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('synchronized'));
    });
  });

  group('editPreset — validation', () {
    test('missing data returns error', () async {
      final result = await distingTools.editPreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('empty preset name returns error', () async {
      final result = await distingTools.editPreset({
        'data': {'name': ''},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('name'));
    });
  });

  group('editSlot — validation', () {
    test(
      'same required-spec algorithm can be replayed without specifications',
      () async {
        const guid = 'same-required-spec';
        final manager = MockDistingMidiManager();
        final currentAlgorithm = Algorithm(
          algorithmIndex: 0,
          guid: guid,
          name: 'Same Required Spec',
        );
        final requiredSpecAlgorithm = AlgorithmInfo(
          algorithmIndex: 0,
          guid: guid,
          name: 'Same Required Spec',
          specifications: [
            Specification(
              name: 'Channels',
              min: 1,
              max: 8,
              defaultValue: 2,
              type: 0,
            ),
          ],
        );
        final parameter = ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: -100,
          max: 100,
          defaultValue: 0,
          unit: 0,
          name: 'Pan',
          powerOfTen: 0,
        );

        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: manager,
            distingVersion: 'Test',
            firmwareVersion: FirmwareVersion('1.17'),
            presetName: 'Test Preset',
            algorithms: [requiredSpecAlgorithm],
            slots: const [],
            unitStrings: const [],
          ),
        );
        when(
          () => controller.getAlgorithmInSlot(0),
        ).thenAnswer((_) async => currentAlgorithm);
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => [parameter]);
        when(
          () => controller.updateParameterValue(0, 0, -35),
        ).thenAnswer((_) async {});
        when(() => controller.getParameterValue(0, 0)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: -35),
        );
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

        final result = await distingTools.editSlot({
          'slot_index': 0,
          'data': {
            'algorithm': {'guid': guid},
            'parameters': [
              {'parameter_number': 0, 'value': -35},
            ],
          },
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        expect(json['persisted'], isTrue);
        verify(() => controller.updateParameterValue(0, 0, -35)).called(1);
        verifyNever(() => controller.clearSlot(any()));
        verifyNever(() => controller.addAlgorithm(any()));
      },
    );

    test('missing slot_index returns error', () async {
      final result = await distingTools.editSlot({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('slot_index'));
    });

    test('out of range slot_index returns error', () async {
      final result = await distingTools.editSlot({'slot_index': 40});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('40'));
    });

    test('missing data returns error', () async {
      final result = await distingTools.editSlot({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('data'));
    });

    test('not synchronized returns error', () async {
      when(() => controller.isSynchronized).thenReturn(false);

      final result = await distingTools.editSlot({
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 0, 'value': 50},
          ],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('synchronized'));
    });
  });

  group('moveAlgorithmUp — boundary', () {
    test('moving slot 0 up returns error', () async {
      final result = await distingTools.moveAlgorithmUp({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('slot 0'));
    });

    test('moving slot 1 up succeeds', () async {
      when(() => controller.moveAlgorithmUp(1)).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithmUp({'slot_index': 1});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      verify(() => controller.moveAlgorithmUp(1)).called(1);
    });
  });

  group('moveAlgorithmDown — boundary', () {
    test('moving last slot down returns error', () async {
      final result = await distingTools.moveAlgorithmDown({'slot_index': 39});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('39'));
    });

    test('moving slot 0 down succeeds', () async {
      when(() => controller.moveAlgorithmDown(0)).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithmDown({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      verify(() => controller.moveAlgorithmDown(0)).called(1);
    });
  });

  group('newWithAlgorithms — validation', () {
    test('missing name returns error', () async {
      final result = await distingTools.newWithAlgorithms({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('name'));
    });

    test('empty name returns error', () async {
      final result = await distingTools.newWithAlgorithms({'name': ''});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('name'));
    });

    test('empty algorithms array creates preset with no algorithms', () async {
      when(() => controller.newPreset()).thenAnswer((_) async {});
      when(
        () => controller.setPresetName('Empty Preset'),
      ).thenAnswer((_) async {});
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'Empty Preset');

      final result = await distingTools.newWithAlgorithms({
        'name': 'Empty Preset',
        'algorithms': [],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['preset_name'], equals('Empty Preset'));
      expect(json['algorithms_added'], equals(0));
    });

    test('null algorithms array creates preset with no algorithms', () async {
      when(() => controller.newPreset()).thenAnswer((_) async {});
      when(
        () => controller.setPresetName('Empty Preset'),
      ).thenAnswer((_) async {});
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'Empty Preset');

      final result = await distingTools.newWithAlgorithms({
        'name': 'Empty Preset',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['algorithms_added'], equals(0));
    });
  });
}
