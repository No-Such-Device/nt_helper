import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        ParameterEnumStrings,
        ParameterInfo,
        ParameterValue,
        Mapping;
import 'package:nt_helper/models/packed_mapping_data.dart';
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
  late AppDatabase database;

  // Non-contiguous hardware parameter numbers: [0, 5, 10]
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
      max: 3,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Mode',
      powerOfTen: 0,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 10,
      min: 0,
      max: 10000,
      defaultValue: 5000,
      unit: 0,
      name: 'Freq',
      powerOfTen: 2, // display values are raw / 100
    ),
  ];

  final testValues = [
    ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
    ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 1),
    ParameterValue(algorithmIndex: 0, parameterNumber: 10, value: 5000),
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

  group('setParameterValue — enum string value', () {
    test('converts enum string to correct index', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      when(
        () => controller.updateParameterValue(0, 5, 2),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 'Mid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 5, 2)).called(1);
    });

    test('rejects invalid enum string', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 'Invalid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Invalid'));
      expect(json['error'], contains('Off'));
    });
  });

  group('setParameterValue — enum string value', () {
    test('accepts valid enum string', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      when(
        () => controller.updateParameterValue(0, 5, 3),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 'High',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 5, 3)).called(1);
    });

    test('rejects invalid enum string', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 'Invalid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('Valid values'));
    });

    test('rejects numeric value for enum parameter', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': -1,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('string value'));
    });
  });

  group('setParameterValue — powerOfTen scaling', () {
    test('scales display value to raw using powerOfTen', () async {
      // Freq param: powerOfTen=2, so display 1.5 => raw 150
      when(
        () => controller.updateParameterValue(0, 10, 150),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 10,
        'value': 1.5,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 10, 150)).called(1);
    });

    test('rejects display value exceeding display max', () async {
      // Freq param: powerOfTen=2, raw max=10000, display max=100
      // Display value 150 => raw 15000 > 10000
      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 10,
        'value': 150,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('out of range'));
    });

    test('accepts display value at display max boundary', () async {
      // Freq param: powerOfTen=2, raw max=10000, display max=100
      // Display value 100 => raw 10000 == max
      when(
        () => controller.updateParameterValue(0, 10, 10000),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 10,
        'value': 100,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 10, 10000)).called(1);
    });
  });

  group('getParameterValue — name resolution with duplicates', () {
    // Two parameters share the name "Level" but have different hardware numbers
    final duplicateNameParams = [
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
        name: 'Level',
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

    test(
      'getParameterValue by duplicate name should error with ambiguity',
      () async {
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => duplicateNameParams);
        // Stub in case it picks the first match instead of erroring
        when(() => controller.getParameterValue(0, 0)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
        );

        final result = await distingTools.getParameterValue({
          'slot_index': 0,
          'parameter_name': 'Level',
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        // Should fail with ambiguity, matching setParameterValue behavior
        expect(
          json['success'],
          isFalse,
          reason:
              'getParameterValue should error on ambiguous name, like setParameterValue does',
        );
        expect(
          json['error'],
          contains('ambiguous'),
          reason: 'Error should mention ambiguity',
        );
      },
    );
  });

  group('setMultipleParameters — partial failures', () {
    test('reports mix of successes and failures', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      // Valid: set Level (param 0) to 80
      when(
        () => controller.updateParameterValue(0, 0, 80),
      ).thenAnswer((_) async {});
      // Invalid: param 99 doesn't exist

      final result = await distingTools.setMultipleParameters({
        'slot_index': 0,
        'parameters': [
          {'parameter_number': 0, 'value': 80},
          {'parameter_number': 99, 'value': 50},
        ],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue); // batch always "succeeds" overall
      expect(json['has_errors'], isTrue);
      expect(json['successful_updates'], equals(1));
      expect(json['failed_updates'], equals(1));

      final results = json['results'] as List<dynamic>;
      final success = results[0] as Map<String, dynamic>;
      final failure = results[1] as Map<String, dynamic>;

      expect(success['value'], equals(80));
      expect(failure.containsKey('error'), isTrue);
    });

    test('handles missing value field in parameter entry', () async {
      final result = await distingTools.setMultipleParameters({
        'slot_index': 0,
        'parameters': [
          {'parameter_number': 0},
        ],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['has_errors'], isTrue);
      final results = json['results'] as List<dynamic>;
      final failure = results[0] as Map<String, dynamic>;
      expect(failure['error'], contains('value'));
    });
  });

  group('getMultipleParameters — validation', () {
    test('rejects non-integer parameter numbers in array', () async {
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
      );
      when(
        () => controller.getParameterMapping(0, 0),
      ).thenAnswer((_) async => testMappings[0]);

      final result = await distingTools.getMultipleParameters({
        'slot_index': 0,
        'parameter_numbers': [0, 'abc', 5],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['has_errors'], isTrue);
      final results = json['results'] as List<dynamic>;

      // First param (0) should succeed
      final param0 = results[0] as Map<String, dynamic>;
      expect(param0['value'], isNotNull);

      // Second param ('abc') should fail
      final paramAbc = results[1] as Map<String, dynamic>;
      expect(paramAbc.containsKey('error'), isTrue);
      expect(paramAbc['error'], contains('integer'));
    });

    test('rejects empty parameter_numbers array', () async {
      final result = await distingTools.getMultipleParameters({
        'slot_index': 0,
        'parameter_numbers': [],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('empty'));
    });
  });

  group('getParameterEnumValues — non-enum parameter', () {
    test('errors for non-enum parameter', () async {
      // Level (param 0) is unit=0, not an enum
      final result = await distingTools.getParameterEnumValues({
        'slot_index': 0,
        'parameter_number': 0,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('not an enum'));
    });

    test('returns enum values for valid enum parameter', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      when(() => controller.getParameterValue(0, 5)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 2),
      );

      final result = await distingTools.getParameterEnumValues({
        'slot_index': 0,
        'parameter_number': 5,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      expect(json['enum_values'], equals(['Off', 'Low', 'Mid', 'High']));
      expect(json['parameter_name'], equals('Mode'));
    });
  });

  group('Bug: getParameterEnumValues current_value_index returns raw object', () {
    test(
      'current_value_index should be an integer, not a ParameterValue object',
      () async {
        when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
          (_) async => ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 5,
            values: ['Off', 'Low', 'Mid', 'High'],
          ),
        );
        when(() => controller.getParameterValue(0, 5)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 2),
        );

        final result = await distingTools.getParameterEnumValues({
          'slot_index': 0,
          'parameter_number': 5,
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        // current_value_index should be the integer value (2), not a serialized
        // ParameterValue object or null
        expect(
          json['current_value_index'],
          isA<int>(),
          reason:
              'current_value_index should be an int, not a ParameterValue object',
        );
        expect(json['current_value_index'], equals(2));
      },
    , tags: ['regression']);
  });

  group('setParameterValue — parameter name resolution', () {
    test('resolves parameter by name to correct hardware number', () async {
      when(
        () => controller.updateParameterValue(0, 0, 80),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_name': 'Level',
        'value': 80,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 0, 80)).called(1);
    });

    test('errors for non-existent parameter name', () async {
      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_name': 'NonExistent',
        'value': 50,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isFalse);
      expect(json['error'], contains('NonExistent'));
    });
  });

  group('getParameterValue — powerOfTen scaling', () {
    test('returns display-scaled value', () async {
      // Freq param: powerOfTen=2, raw value=5000 => display 50.0
      when(() => controller.getParameterValue(0, 10)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 10, value: 5000),
      );

      final result = await distingTools.getParameterValue({
        'slot_index': 0,
        'parameter_number': 10,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      expect(json['value'], equals(50.0));
      expect(json['parameter_name'], equals('Freq'));
    });
  });

  group('Bug: getParameterValue null paramValue error uses wrong variable', () {
    test(
      'error message should use resolvedParameterNumber, not input parameterNumber',
      () async {
        // Look up by name so input parameterNumber is null
        when(
          () => controller.getParameterValue(0, 0),
        ).thenAnswer((_) async => null);

        final result = await distingTools.getParameterValue({
          'slot_index': 0,
          'parameter_name': 'Level',
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isFalse);
        // The error message should mention the resolved parameter number (0),
        // not "null" which would happen if using the input parameterNumber variable
        expect(
          json['error'],
          isNot(contains('null')),
          reason:
              'Error message should use resolvedParameterNumber, not the input parameterNumber which is null',
        );
        expect(json['error'], contains('0'));
      },
    , tags: ['regression']);
  });

  group('getParameterValue — both parameter_number and parameter_name', () {
    test('when both provided, parameter_name takes priority', () async {
      // getParameterValue doesn't use validateExactlyOne like setParameterValue,
      // so it silently prefers parameter_name. This test documents that behavior.
      when(() => controller.getParameterValue(0, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 42),
      );

      final result = await distingTools.getParameterValue({
        'slot_index': 0,
        'parameter_number': 10, // Freq
        'parameter_name': 'Level', // resolves to param 0
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      // parameter_name wins — resolves to Level (param 0), not Freq (param 10)
      expect(json['success'], isTrue);
      expect(json['parameter_name'], equals('Level'));
      expect(json['parameter_number'], equals(0));
    });
  });

  group('Bug: getParameterEnumValues should handle ambiguous names', () {
    final duplicateNameParams = [
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
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 5,
        min: 0,
        max: 3,
        defaultValue: 0,
        unit: 1,
        name: 'Mode',
        powerOfTen: 0,
      ),
    ];

    test(
      'should error when parameter_name matches multiple parameters',
      () async {
        when(
          () => controller.getParametersForSlot(0),
        ).thenAnswer((_) async => duplicateNameParams);

        final result = await distingTools.getParameterEnumValues({
          'slot_index': 0,
          'parameter_name': 'Mode',
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(
          json['success'],
          isFalse,
          reason:
              'getParameterEnumValues should error on ambiguous name, like setParameterValue does',
        );
        expect(
          json['error'],
          contains('ambiguous'),
          reason: 'Error should mention ambiguity',
        );
      },
    );
  });

  group('setParameterValue — enum string case sensitivity', () {
    test('case-insensitive enum string match should work', () async {
      when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
        (_) async => ParameterEnumStrings(
          algorithmIndex: 0,
          parameterNumber: 5,
          values: ['Off', 'Low', 'Mid', 'High'],
        ),
      );
      when(
        () => controller.updateParameterValue(0, 5, 2),
      ).thenAnswer((_) async {});

      // User types "mid" but enum is "Mid"
      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 5,
        'value': 'mid',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(
        json['success'],
        isTrue,
        reason: 'Enum string matching should be case-insensitive for usability',
      );
    });
  });

  group('setParameterValue — zero powerOfTen', () {
    test(
      'integer value passes through without scaling when powerOfTen is 0',
      () async {
        // Level param: powerOfTen=0, so value 80 => raw 80
        when(
          () => controller.updateParameterValue(0, 0, 80),
        ).thenAnswer((_) async {});

        final result = await distingTools.setParameterValue({
          'slot_index': 0,
          'parameter_number': 0,
          'value': 80,
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        verify(() => controller.updateParameterValue(0, 0, 80)).called(1);
      },
    );
  });

  group('setParameterValue — negative scaled value', () {
    test('negative display value scales correctly', () async {
      // Create a parameter with negative min
      final negParams = [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: -10000,
          max: 10000,
          defaultValue: 0,
          unit: 0,
          name: 'Pan',
          powerOfTen: 2,
        ),
      ];
      when(
        () => controller.getParametersForSlot(0),
      ).thenAnswer((_) async => negParams);
      when(
        () => controller.updateParameterValue(0, 0, -5000),
      ).thenAnswer((_) async {});

      final result = await distingTools.setParameterValue({
        'slot_index': 0,
        'parameter_number': 0,
        'value': -50.0,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.updateParameterValue(0, 0, -5000)).called(1);
    });
  });

  group('getParameterValue — enum parameter returns enum metadata', () {
    test(
      'includes valid_enum_values and string value for enum parameter',
      () async {
        when(() => controller.getParameterValue(0, 5)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 2),
        );
        when(() => controller.getParameterEnumStrings(0, 5)).thenAnswer(
          (_) async => ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 5,
            values: ['Off', 'Low', 'Mid', 'High'],
          ),
        );

        final result = await distingTools.getParameterValue({
          'slot_index': 0,
          'parameter_number': 5,
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['success'], isTrue);
        expect(json['is_enum'], isTrue);
        expect(
          json['valid_enum_values'],
          equals(['Off', 'Low', 'Mid', 'High']),
        );
        expect(json['value'], equals('Mid'));
      },
    );
  });

  group('setMultipleParameters — both identifier fields provided', () {
    test(
      'rejects parameter entry with both parameter_number and parameter_name',
      () async {
        final result = await distingTools.setMultipleParameters({
          'slot_index': 0,
          'parameters': [
            {'parameter_number': 0, 'parameter_name': 'Level', 'value': 80},
          ],
        });
        final json = jsonDecode(result) as Map<String, dynamic>;

        expect(json['has_errors'], isTrue);
        final results = json['results'] as List<dynamic>;
        final failure = results[0] as Map<String, dynamic>;
        expect(failure.containsKey('error'), isTrue);
      },
    );
  });

  group('setMultipleParameters — non-object in parameters array', () {
    test('rejects non-map entries in parameters array', () async {
      final result = await distingTools.setMultipleParameters({
        'slot_index': 0,
        'parameters': [42, 'string_value'],
      });
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['has_errors'], isTrue);
      expect(json['failed_updates'], equals(2));
    });
  });
}
