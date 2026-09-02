import 'dart:convert';

import 'package:flutter/foundation.dart' show DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        AlgorithmVisualBracket,
        AlgorithmVisualStyle,
        Mapping,
        ParameterEnumStrings,
        ParameterInfo,
        ParameterValue;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart'
    show DistingCubit, DistingStateInitial, DistingStateSynchronized;
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
  late MCPAlgorithmTools algoTools;
  late AppDatabase database;

  // Non-contiguous hardware parameter numbers [0, 5, 10]
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

  PackedMappingData makeMappingData({
    int cvInput = 0,
    int source = 0,
    bool isMidiEnabled = false,
    int midiChannel = 0,
    int midiCC = 1,
    bool isI2cEnabled = false,
    int i2cCC = 0,
    int perfPageIndex = 0,
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
      i2cCC: i2cCC,
      isI2cEnabled: isI2cEnabled,
      isI2cSymmetric: false,
      i2cMin: 0,
      i2cMax: 127,
      perfPageIndex: perfPageIndex,
      version: 5,
    );
  }

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
    algoTools = MCPAlgorithmTools(controller, cubit);

    // Default stubs
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
    when(
      () => controller.getCurrentPresetName(),
    ).thenAnswer((_) async => 'TestPreset');
    when(
      () => controller.getAllSlots(),
    ).thenAnswer((_) async => {0: testAlgorithm});
    when(() => cubit.state).thenReturn(const DistingStateInitial());
  });

  tearDownAll(() async {
    await database.close();
  });

  group('searchAlgorithms — input validation', () {
    test('returns error when query is missing', () async {
      final result = await algoTools.searchAlgorithms({});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('"query"'));
    });

    test('returns error when query is empty string', () async {
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': '',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('"query"'));
    });
  });

  group('searchAlgorithms — matching', () {
    test('exact name match returns result in top position', () async {
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': 'Attenuverter',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['results'], isNotEmpty);
      final results = json['results'] as List<dynamic>;
      expect(
        results.any(
          (r) => (r as Map<String, dynamic>)['name'] == 'Attenuverter',
        ),
        isTrue,
      );
    });

    test('partial name match returns results', () async {
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': 'attenuv',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['results'], isNotEmpty);
      final results = json['results'] as List<dynamic>;
      expect(
        results.any(
          (r) => (r as Map<String, dynamic>)['name']
              .toString()
              .toLowerCase()
              .contains('attenuverter'),
        ),
        isTrue,
      );
    });

    test('no match returns empty results with message', () async {
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': 'zzzznonexistent',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['results'], isEmpty);
      expect(json['message'], contains('No algorithms found'));
    });

    test('limits results to 10 maximum', () async {
      // Use a very broad query that matches many algorithms
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': 'a',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      if (json.containsKey('results')) {
        final results = json['results'] as List<dynamic>;
        expect(results.length, lessThanOrEqualTo(10));
      }
    });

    test('result contains expected fields', () async {
      final result = await algoTools.searchAlgorithms({
        'type': 'algorithm',
        'query': 'Attenuverter',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['results'], isNotEmpty);
      final first =
          (json['results'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(first.containsKey('guid'), isTrue);
      expect(first.containsKey('name'), isTrue);
      expect(first.containsKey('category'), isTrue);
      expect(first.containsKey('description'), isTrue);
      expect(first.containsKey('general_parameters'), isTrue);
    });
  });

  group('listAlgorithms — filtering', () {
    test('returns all algorithms when no filters', () async {
      final result = await algoTools.listAlgorithms({});
      final json = jsonDecode(result) as List<dynamic>;

      expect(json, isNotEmpty);
    });

    test('filters by category', () async {
      final result = await algoTools.listAlgorithms({'category': 'Utility'});
      final json = jsonDecode(result) as List<dynamic>;

      expect(json, isNotEmpty);
      // All results should have some relation to the category
    });

    test('filters by query', () async {
      final result = await algoTools.listAlgorithms({'query': 'delay'});
      final json = jsonDecode(result) as List<dynamic>;

      expect(json, isNotEmpty);
      // At least one result should contain 'delay' in name or description
      final hasDelay = json.any((a) {
        final m = a as Map<String, dynamic>;
        final name = (m['name'] as String).toLowerCase();
        final desc = (m['description'] as String).toLowerCase();
        return name.contains('delay') || desc.contains('delay');
      });
      expect(hasDelay, isTrue);
    });

    test('each result has guid, name, description', () async {
      final result = await algoTools.listAlgorithms({});
      final json = jsonDecode(result) as List<dynamic>;

      expect(json, isNotEmpty);
      final first = json[0] as Map<String, dynamic>;
      expect(first.containsKey('guid'), isTrue);
      expect(first.containsKey('name'), isTrue);
      expect(first.containsKey('description'), isTrue);
    });

    test('description is truncated to first sentence', () async {
      final result = await algoTools.listAlgorithms({'query': 'delay'});
      final json = jsonDecode(result) as List<dynamic>;

      expect(json, isNotEmpty);
      for (final item in json) {
        final desc = (item as Map<String, dynamic>)['description'] as String;
        if (desc.contains('.')) {
          // Should end at first period — only one period allowed
          final periodCount = '.'.allMatches(desc).length;
          expect(
            periodCount,
            equals(1),
            reason: 'Description "$desc" should be truncated to first sentence',
          );
        }
      }
    });
  });

  group('show dispatcher — routing', () {
    test('routes "preset" to showPreset', () async {
      final result = await algoTools.show({'target': 'preset'});
      final json = jsonDecode(result) as Map<String, dynamic>;

      // showPreset with synchronized controller returns preset data
      expect(json.containsKey('name') || json.containsKey('error'), isTrue);
    });

    test('routes "cpu" to showCpu', () async {
      final result = await algoTools.show({'target': 'cpu'});
      final json = jsonDecode(result) as Map<String, dynamic>;

      // showCpu checks DistingStateSynchronized
      expect(json['success'], isFalse);
      expect(json['error'], contains('not synchronized'));
    });

    test('routes "routing" to showRouting', () async {
      final result = await algoTools.show({'target': 'routing'});

      // showRouting returns [] when not synchronized
      final decoded = jsonDecode(result);
      expect(decoded, isA<List>());
    });
  });

  group('showPreset — synchronized state', () {
    test('returns preset name and slots', () async {
      final result = await algoTools.showPreset();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['name'], equals('TestPreset'));
      expect(json['slots'], isA<List>());
      final slots = json['slots'] as List<dynamic>;
      expect(slots, hasLength(1));
    });

    test('returns error when not synchronized', () async {
      when(() => controller.isSynchronized).thenReturn(false);

      final result = await algoTools.showPreset();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not synchronized'));
    });

    test(
      'slot JSON contains algorithm and parameter_count (not parameters)',
      () async {
        final result = await algoTools.showPreset();
        final json = jsonDecode(result) as Map<String, dynamic>;

        final slot =
            (json['slots'] as List<dynamic>)[0] as Map<String, dynamic>;
        expect(slot['slot_index'], equals(0));
        expect(slot['algorithm'], isA<Map>());
        expect(
          (slot['algorithm'] as Map<String, dynamic>)['name'],
          equals('TestAlgo'),
        );
        expect(slot['parameter_count'], equals(3));
        expect(slot.containsKey('parameters'), isFalse);
      },
    );
  });

  group('showSlot — empty slot handling', () {
    test('returns empty slot JSON when algorithm is null', () async {
      when(
        () => controller.getAlgorithmInSlot(0),
      ).thenAnswer((_) async => null);

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['slot_index'], equals(0));
      expect(json['algorithm'], isA<Map>());
      expect((json['algorithm'] as Map<String, dynamic>)['guid'], equals(''));
      expect(json['parameter_count'], equals(0));
      expect(json['count'], equals(0));
      expect(json['has_more'], isFalse);
      expect(json['next'], isNull);
    });

    test('triggers _ensureSlotReady when parameters empty', () async {
      var callCount = 0;
      when(() => controller.getParametersForSlot(0)).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? [] : testParameters;
      });
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;

      verify(() => controller.refreshSlot(0)).called(1);
      expect(json['parameters'], isA<List>());
    });
  });

  group('showSlot — result sizing', () {
    test(
      'returns a bounded page by default with an exact continuation',
      () async {
        final parameters = List.generate(
          10,
          (index) => ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: index,
            min: 0,
            max: 100,
            defaultValue: 0,
            unit: 0,
            name: 'Parameter $index',
            powerOfTen: 0,
          ),
        );
        final values = List.generate(
          10,
          (index) => ParameterValue(
            algorithmIndex: 0,
            parameterNumber: index,
            value: index,
          ),
        );
        final mappings = List.generate(
          10,
          (index) => Mapping(
            algorithmIndex: 0,
            parameterNumber: index,
            packedMappingData: PackedMappingData.filler(),
          ),
        );
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => parameters);
        when(
          () => controller.getValuesForSlot(0),
        ).thenAnswer((_) async => values);
        when(
          () => controller.getMappingsForSlot(0),
        ).thenAnswer((_) async => mappings);

        final result = await algoTools.showSlot(0);
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['parameter_count'], equals(10));
        expect(json['offset'], equals(0));
        expect(json['limit'], equals(8));
        expect(json['count'], equals(8));
        expect(json['has_more'], isTrue);
        expect((json['parameters'] as List).length, equals(8));
        expect(json['next'], {
          'tool': 'show_slot',
          'arguments': {
            'slot_index': 0,
            'parameter_offset': 8,
            'parameter_limit': 8,
          },
        });
      },
    );

    test('respects custom limit', () async {
      final result = await algoTools.showSlot(0, limit: 2);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect((json['parameters'] as List).length, equals(2));
      expect(json['has_more'], isTrue);
      expect(json['next'], {
        'tool': 'show_slot',
        'arguments': {
          'slot_index': 0,
          'parameter_offset': 2,
          'parameter_limit': 2,
        },
      });
    });

    test('respects offset', () async {
      final result = await algoTools.showSlot(0, offset: 2);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect((json['parameters'] as List).length, equals(1));
      expect(json['offset'], equals(2));
      expect(json['has_more'], isFalse);
    });

    test('offset beyond parameter count returns empty list', () async {
      final result = await algoTools.showSlot(0, offset: 100);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect((json['parameters'] as List), isEmpty);
      expect(json['has_more'], isFalse);
    });

    test(
      'rejects a parameter page larger than the context-safe maximum',
      () async {
        final result = await algoTools.showSlot(0, limit: 17);
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        expect(json['error'], contains('between 1 and 16 per page'));
      },
    );
  });

  group('showSlot — parameter summary format', () {
    test(
      'includes the current algorithm visual style for restoration',
      () async {
        when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
          (_) async => Algorithm(
            algorithmIndex: 0,
            guid: 'test',
            name: 'TestAlgo',
            visualStyle: const AlgorithmVisualStyle(
              leftIndent: 3,
              rightIndent: 5,
              lineAbove: true,
              lineBelow: false,
              bracket: AlgorithmVisualBracket.openAndClose,
            ),
          ),
        );

        final result = await algoTools.showSlot(0);
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['visual_style'], {
          'left_indent': 3,
          'right_indent': 5,
          'line_above': true,
          'line_below': false,
          'bracket': 'open_and_close',
        });
      },
    );

    test('includes algorithm specification values', () async {
      when(() => controller.getAlgorithmInSlot(0)).thenAnswer(
        (_) async => Algorithm(
          algorithmIndex: 0,
          guid: 'test',
          name: 'TestAlgo',
          specifications: const [2, 4],
        ),
      );

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;
      final algorithm = json['algorithm'] as Map<String, dynamic>;

      expect(algorithm['specifications'], equals([2, 4]));
    });

    test(
      'numeric summary has current state but omits inspection metadata',
      () async {
        final result = await algoTools.showSlot(0);
        final json = jsonDecode(result) as Map<String, dynamic>;

        final param = (json['parameters'] as List)[0] as Map<String, dynamic>;
        expect(param['parameter_name'], equals('Level'));
        expect(param['value'], isNotNull);
        expect(param.containsKey('min'), isFalse);
        expect(param.containsKey('max'), isFalse);
        expect(param.containsKey('is_disabled'), isFalse);
        expect(param.containsKey('valid_enum_values'), isFalse);
      },
    );

    test('parameter with no mapping has no has_mapping key', () async {
      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;

      final param = (json['parameters'] as List)[0] as Map<String, dynamic>;
      expect(param.containsKey('has_mapping'), isFalse);
    });

    test('parameter with MIDI mapping has has_mapping: true', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(isMidiEnabled: true, midiCC: 74),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;

      final param = (json['parameters'] as List)[0] as Map<String, dynamic>;
      expect(param['has_mapping'], isTrue);
      expect(param.containsKey('performance_page'), isFalse);
    });

    test('parameter with performance page includes performance_page', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(perfPageIndex: 3),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showSlot(0);
      final json = jsonDecode(result) as Map<String, dynamic>;

      final param = (json['parameters'] as List)[0] as Map<String, dynamic>;
      expect(param['has_mapping'], isTrue);
      expect(param['performance_page'], equals(3));
    });
  });

  group('showParameter — edge cases', () {
    test('returns error for "0:" (empty param number)', () async {
      final result = await algoTools.showParameter('0:');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid identifier format'));
    });

    test('returns error for ":5" (empty slot index)', () async {
      final result = await algoTools.showParameter(':5');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid identifier format'));
    });

    test('returns error for "0:5:10" (too many parts)', () async {
      final result = await algoTools.showParameter('0:5:10');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid identifier format'));
    });
  });

  group('showScreen — display_mode validation', () {
    test('returns error for invalid display_mode', () async {
      final result = await algoTools.showScreen(displayMode: 'invalid_mode');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid display_mode'));
      expect(json['valid_modes'], isNotNull);
    });

    test('returns error when not synchronized (no display_mode)', () async {
      final result = await algoTools.showScreen();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not synchronized'));
    });

    test('validates display_mode before checking synchronized state', () async {
      // Even when not synchronized, invalid display_mode should error first
      final result = await algoTools.showScreen(displayMode: 'bogus');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid display_mode'));
    });
  });

  group('showCpu — error handling', () {
    test('returns error when not synchronized', () async {
      // cubit.state returns DistingStateInitial by default
      final result = await algoTools.showCpu();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not synchronized'));
    });

    test('returns error when getCpuUsage returns null', () async {
      when(() => cubit.state).thenReturn(_FakeSynchronizedState());
      when(() => cubit.getCpuUsage()).thenAnswer((_) async => null);

      final result = await algoTools.showCpu();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Could not retrieve CPU usage'));
    });

    test('returns formatted CPU data on success', () async {
      when(() => cubit.state).thenReturn(_FakeSynchronizedState());
      when(() => cubit.getCpuUsage()).thenAnswer(
        (_) async => CpuUsage(cpu1: 40, cpu2: 60, slotUsages: [30, 50]),
      );

      final result = await algoTools.showCpu();
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      final cpuData = json['cpu_usage'] as Map<String, dynamic>;
      expect(cpuData['cpu1_percent'], equals(40));
      expect(cpuData['cpu2_percent'], equals(60));
      expect(cpuData['total_usage_percent'], equals(50.0));
      expect(cpuData['slot_usages'], isA<List>());
      expect((cpuData['slot_usages'] as List).length, equals(2));
    });
  });

  group('showRouting — non-synchronized', () {
    test('returns empty array when not synchronized', () async {
      final result = await algoTools.showRouting();
      final decoded = jsonDecode(result);

      expect(decoded, isA<List>());
      expect(decoded, isEmpty);
    });
  });

  group('_buildMappingJson — mapping type filtering (via showParameter)', () {
    // showSlot now returns lightweight summaries (has_mapping: true flag only).
    // Full mapping detail is in showParameter. Tests below use showParameter.

    test('no mapping key when all mappings disabled (showParameter)', () async {
      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(
        json.containsKey('mapping'),
        isFalse,
        reason: 'Filler mapping should produce no mapping key',
      );
    });

    test('includes only CV when cv_input > 0', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(cvInput: 1),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json.containsKey('mapping'), isTrue);
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping.containsKey('cv'), isTrue);
      expect(mapping.containsKey('midi'), isFalse);
      expect(mapping.containsKey('i2c'), isFalse);
    });

    test('includes only MIDI when midi enabled', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(isMidiEnabled: true, midiCC: 10),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json.containsKey('mapping'), isTrue);
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping.containsKey('midi'), isTrue);
      expect(mapping.containsKey('cv'), isFalse);
      expect(mapping.containsKey('i2c'), isFalse);
    });

    test('serializes expressive MIDI mapping type as snake case', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(isMidiEnabled: true, midiCC: 0)
                .copyWith(
                  midiMappingType: MidiMappingType.channelPressure,
                  version: 7,
                ),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;
      final mapping = json['mapping'] as Map<String, dynamic>;
      final midi = mapping['midi'] as Map<String, dynamic>;

      expect(midi['midi_type'], equals('channel_pressure'));
    });

    test('includes only i2c when i2c enabled', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(isI2cEnabled: true, i2cCC: 5),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json.containsKey('mapping'), isTrue);
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping.containsKey('i2c'), isTrue);
      expect(mapping.containsKey('cv'), isFalse);
      expect(mapping.containsKey('midi'), isFalse);
    });

    test('includes performance_page when perfPageIndex > 0', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(perfPageIndex: 3),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json.containsKey('mapping'), isTrue);
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping['performance_page'], equals(3));
    });

    test('includes all mapping types when all enabled', () async {
      when(() => controller.getMappingsForSlot(0)).thenAnswer(
        (_) async => [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: makeMappingData(
              cvInput: 1,
              source: 2,
              isMidiEnabled: true,
              midiCC: 10,
              isI2cEnabled: true,
              i2cCC: 5,
              perfPageIndex: 1,
            ),
          ),
          testMappings[1],
          testMappings[2],
        ],
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json.containsKey('mapping'), isTrue);
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping.containsKey('cv'), isTrue);
      expect(mapping.containsKey('midi'), isTrue);
      expect(mapping.containsKey('i2c'), isTrue);
      expect(mapping['performance_page'], equals(1));
    });
  });

  group('_buildParameterJson — scaling and disabled', () {
    test(
      'applies powerOfTen scaling to value, min, max, and default',
      () async {
        final scaledParams = [
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
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
        ];
        final scaledMappings = [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: PackedMappingData.filler(),
          ),
        ];

        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => scaledParams);
        when(
          () => controller.getValuesForSlot(0),
        ).thenAnswer((_) async => scaledValues);
        when(
          () => controller.getMappingsForSlot(0),
        ).thenAnswer((_) async => scaledMappings);

        final result = await algoTools.showParameter('0:0');
        final json = jsonDecode(result) as Map<String, dynamic>;

        // Display-scaled: 150 / 10^2 = 1.5
        expect(json['value'], equals(1.5));
        // Display-scaled: 0 / 10^2 = 0
        expect(json['min'], equals(0));
        // Display-scaled: 10000 / 10^2 = 100.0
        expect(json['max'], equals(100.0));
        // Display-scaled: 5000 / 10^2 = 50.0
        expect(json['default'], equals(50.0));
      },
    );

    test('reports readable enum current and default values', () async {
      final enumParameters = [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: 0,
          max: 2,
          defaultValue: 1,
          unit: 1,
          name: 'Mode',
          powerOfTen: 0,
        ),
      ];
      final enumValues = [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 2),
      ];
      final enumMappings = [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler(),
        ),
      ];
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
          values: ['Off', 'Low', 'High'],
        ),
      );

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['value'], equals('High'));
      expect(json['default'], equals('Low'));
      expect(json['valid_enum_values'], equals(['Off', 'Low', 'High']));
    });

    test('includes is_disabled flag', () async {
      final disabledValues = [
        ParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 50,
          isDisabled: true,
        ),
        testValues[1],
        testValues[2],
      ];
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => disabledValues);

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['is_disabled'], isTrue);
    });

    test('includes parameter_name', () async {
      final result = await algoTools.showParameter('0:5');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['parameter_name'], equals('Mix'));
    });
  });

  group('getCurrentRoutingState — basic behavior', () {
    test('returns empty list when not synchronized', () async {
      // cubit.state is DistingStateInitial by default
      final result = await algoTools.getCurrentRoutingState({});
      final decoded = jsonDecode(result);

      expect(decoded, isA<List>());
      expect(decoded, isEmpty);
    });
  });
}

/// Mock DistingStateSynchronized for testing showCpu
class _FakeSynchronizedState extends Mock implements DistingStateSynchronized {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      'FakeSynchronizedState';
}
