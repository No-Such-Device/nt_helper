import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show Mapping, ParameterInfo, ParameterValue;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
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

void main() {
  late MockDistingController controller;
  late MockDistingCubit cubit;
  late MCPAlgorithmTools algoTools;
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

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

    when(() => controller.isSynchronized).thenReturn(true);
    when(() => cubit.state).thenReturn(const DistingStateInitial());
  });

  tearDownAll(() async {
    await database.close();
  });

  group(
    '_generateGeneralParameterDescription — false positive from contains(q)',
    () {
      // Bug: contains('q') in the resonance check matches any parameter name
      // containing the letter 'q', e.g. "Freq" → "freq" contains 'q',
      // "Sequence" → "sequence" contains 'q'.
      // This causes algorithms with frequency/sequencer parameters to be
      // falsely described as having "resonance/filter emphasis controls".
      // Fix: use `name == 'q'` to match only the standalone "Q" parameter.

      test(
        'Clock algorithm should not show resonance/filter emphasis',
        () async {
          final result = await algoTools.searchAlgorithms({
            'type': 'algorithm',
            'query': 'Clock',
          });
          final json = jsonDecode(result) as Map<String, dynamic>;

          expect(json['results'], isNotEmpty);
          final clockResult =
              (json['results'] as List<dynamic>).firstWhere(
                    (r) => (r as Map<String, dynamic>)['name'] == 'Clock',
                  )
                  as Map<String, dynamic>;

          final generalParams = clockResult['general_parameters'] as String;
          expect(
            generalParams,
            isNot(contains('resonance')),
            reason: 'Clock has no resonance/Q/filter params',
          );
        },
      );

      test(
        'sequencer algorithms should not show resonance from "sequence" containing q',
        () async {
          // "Sequence" contains 'q' — the old contains('q') check would
          // falsely flag this as resonance/filter emphasis
          final result = await algoTools.searchAlgorithms({
            'type': 'algorithm',
            'query': 'Step Sequencer',
          });
          final json = jsonDecode(result) as Map<String, dynamic>;

          expect(json['results'], isNotEmpty);
          // Find a result with "Sequencer" in the name
          final seqResults = (json['results'] as List<dynamic>).where(
            (r) => (r as Map<String, dynamic>)['name']
                .toString()
                .toLowerCase()
                .contains('sequenc'),
          );

          if (seqResults.isNotEmpty) {
            final seqResult = seqResults.first as Map<String, dynamic>;
            final generalParams = seqResult['general_parameters'] as String;
            expect(
              generalParams,
              isNot(contains('resonance')),
              reason:
                  '"Sequence" params contain "q" but are not resonance-related',
            );
          }
        },
      tags: ['regression']);

      test(
        'algorithms with only Freq params should not show resonance category',
        () async {
          final result = await algoTools.searchAlgorithms({
            'type': 'algorithm',
            'query': 'Attenuverter',
          });
          final json = jsonDecode(result) as Map<String, dynamic>;

          expect(json['results'], isNotEmpty);
          final attenuverter =
              (json['results'] as List<dynamic>).firstWhere(
                    (r) =>
                        (r as Map<String, dynamic>)['name'] == 'Attenuverter',
                  )
                  as Map<String, dynamic>;

          final generalParams = attenuverter['general_parameters'] as String;
          expect(
            generalParams,
            isNot(contains('resonance')),
            reason: 'Attenuverter has no resonance params',
          );
        },
      );
    },
  );

  group('setDisplayMode — non-string mode handling', () {
    // Bug: non-string displayMode values (int, bool) are silently ignored
    // instead of returning an error. This is confusing for callers.

    test('should return error when displayMode is an integer', () async {
      final result = await algoTools.setDisplayMode(42);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('mode'));
      expect(json['valid_modes'], isNotNull);
    });

    test('should return error when displayMode is a boolean', () async {
      final result = await algoTools.setDisplayMode(true);
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('mode'));
      expect(json['valid_modes'], isNotNull);
    });
  });

  group('showParameter — boundary edge cases', () {
    test('returns error for negative parameter_number', () async {
      final testParams = [
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
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);

      final result = await algoTools.showParameter('0:-1');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not found'));
    });

    test('returns error for very large parameter_number', () async {
      final testParams = [
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
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);

      final result = await algoTools.showParameter('0:999');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not found'));
    });
  });

  group('_buildParameterJson — powerOfTen edge cases', () {
    test('powerOfTen of 0 returns raw integer value', () async {
      final testParams = [
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
      ];
      final testValues = [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 75),
      ];
      final testMappings = [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler(),
        ),
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => testMappings);

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['value'], equals(75));
      expect(json['value'], isA<int>());
    });

    test('powerOfTen of 1 divides by 10', () async {
      final testParams = [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: 0,
          max: 1000,
          defaultValue: 500,
          unit: 0,
          name: 'Level',
          powerOfTen: 1,
        ),
      ];
      final testValues = [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 150),
      ];
      final testMappings = [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler(),
        ),
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => testMappings);

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['value'], equals(15.0));
      expect(json['min'], equals(0));
      expect(json['max'], equals(100.0));
    });

    test('powerOfTen of 3 divides by 1000', () async {
      final testParams = [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: 0,
          max: 100000,
          defaultValue: 50000,
          unit: 0,
          name: 'Level',
          powerOfTen: 3,
        ),
      ];
      final testValues = [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 12345),
      ];
      final testMappings = [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler(),
        ),
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => testMappings);

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['value'], equals(12.345));
    });
  });

  group('_buildMappingJson — CV enabled with source > 0 only', () {
    test('includes CV mapping when source > 0 but cvInput == 0', () async {
      final sourceOnlyMappings = [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData(
            source: 3,
            cvInput: 0,
            isUnipolar: false,
            isGate: false,
            volts: 5,
            delta: 0,
            midiChannel: 0,
            midiMappingType: MidiMappingType.cc,
            midiCC: 1,
            isMidiEnabled: false,
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
          ),
        ),
      ];

      final testParams = [
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
      ];
      final testValues = [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
      ];

      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => testParams);
      when(
        () => controller.getValuesForSlot(0),
      ).thenAnswer((_) async => testValues);
      when(
        () => controller.getMappingsForSlot(0),
      ).thenAnswer((_) async => sourceOnlyMappings);

      final result = await algoTools.showParameter('0:0');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(
        json.containsKey('mapping'),
        isTrue,
        reason: 'CV mapping should be included when source > 0',
      );
      final mapping = json['mapping'] as Map<String, dynamic>;
      expect(mapping.containsKey('cv'), isTrue);
      expect((mapping['cv'] as Map<String, dynamic>)['source'], equals(3));
    }, tags: ['regression']);
  });
}
