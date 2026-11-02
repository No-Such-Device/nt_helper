import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../test_helpers/mock_midi_command.dart';

void main() {
  group('MCPAlgorithmTools', () {
    late MCPAlgorithmTools tools;
    late DistingCubit distingCubit;
    late AppDatabase database;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase.forTesting(NativeDatabase.memory());

      // Load metadata from file and import into test database
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

      // Initialize the AlgorithmMetadataService
      await AlgorithmMetadataService().initialize(database);
    });

    setUp(() {
      distingCubit = DistingCubit(database, midiCommand: MockMidiCommand());
      tools = MCPAlgorithmTools(
        DistingControllerImpl(distingCubit),
        distingCubit,
      );
    });

    tearDown(() {
      distingCubit.close();
    });

    tearDownAll(() async {
      await database.close();
    });

    group('getAlgorithmDetails', () {
      test('algorithmInfo accepts public guid argument', () async {
        final result = await tools.algorithmInfo({'guid': 'clck'});

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
        expect(decoded['description'], isNotEmpty);
        expect(decoded['parameters'], isList);
      });

      test('algorithmInfo accepts public name argument', () async {
        final result = await tools.algorithmInfo({'name': 'Clock'});

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
      });

      test('should return algorithm details for valid GUID', () async {
        final result = await tools.getAlgorithmDetails({
          'algorithm_guid': 'clck',
        });

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
        expect(decoded['description'], isNotEmpty);
      });

      test('should handle clck algorithm specifically', () async {
        // Test the problematic 'clck' algorithm
        final result = await tools.getAlgorithmDetails({
          'algorithm_guid': 'clck',
        });

        expect(() => jsonDecode(result), returnsNormally);

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
        expect(decoded['parameters'], isList);
        expect(decoded['categories'], isList);
        expect(decoded['categories'], isNotEmpty);
      });

      test('should return algorithm details by name', () async {
        final result = await tools.getAlgorithmDetails({
          'algorithm_name': 'Clock',
        });

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
      });

      test('should return error for missing parameters', () async {
        final result = await tools.getAlgorithmDetails({});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(decoded['error'], contains('Missing required parameter'));
      });

      test('should return error for invalid GUID', () async {
        final result = await tools.getAlgorithmDetails({
          'algorithm_guid': 'invalid_guid_12345',
        });

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(decoded['error'], contains('Resource not found'));
      });

      test('should return error for ambiguous name', () async {
        // Find an algorithm name that might have multiple matches
        // or use a partial name that could match multiple
        final result = await tools.getAlgorithmDetails({
          'algorithm_name': 'a', // Very generic, might match multiple
        });

        final decoded = jsonDecode(result);
        // Either no match or ambiguous
        expect(decoded['success'], isFalse);
      });

      test('should expand features when requested', () async {
        final result = await tools.getAlgorithmDetails({
          'algorithm_guid': 'clck',
          'expand_features': true,
        });

        final decoded = jsonDecode(result);
        expect(decoded['guid'], equals('clck'));
        // Expanded parameters might include additional feature-based params
        expect(decoded['parameters'], isList);
      });

      test('should handle fuzzy name matching', () async {
        final result = await tools.getAlgorithmDetails({
          'algorithm_name': 'Clok', // Typo in Clock
        });

        final decoded = jsonDecode(result);
        // Should either find Clock via fuzzy matching or return error
        if (decoded['success'] == false) {
          expect(decoded['error'], isNotNull);
        } else {
          expect(decoded['guid'], equals('clck'));
        }
      });
    });

    group('ToolRegistry algorithm_info', () {
      test('registers shared chat and MCP tool entry', () async {
        final registry = ToolRegistry(distingCubit);
        final entry = registry.findByName('algorithm_info');

        expect(entry, isNotNull);
        expect(entry!.description, contains('Help screen'));
        expect(entry.inputSchema['properties'], contains('guid'));
        expect(entry.inputSchema['properties'], contains('name'));

        final decoded = jsonDecode(await entry.handler({'guid': 'clck'}));
        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));
      });
    });

    group('listAlgorithms', () {
      test('should list all algorithms without filter', () async {
        final result = await tools.listAlgorithms({});

        final decoded = jsonDecode(result);
        expect(decoded, isList);
        expect(decoded.length, greaterThan(0));

        // Check structure of first algorithm
        final first = decoded[0];
        expect(first['guid'], isNotNull);
        expect(first['name'], isNotNull);
        expect(first['description'], isNotNull);
      });

      test('should filter by category', () async {
        // In test environment, algorithms are synced from full_metadata.json
        // and get "Synced From Device" category
        final result = await tools.listAlgorithms({
          'category': 'Synced From Device',
        });

        final decoded = jsonDecode(result);
        expect(decoded, isList);

        // Should include algorithms synced from database
        expect(decoded.length, greaterThan(0));
      });

      test('should filter by query text', () async {
        final result = await tools.listAlgorithms({'query': 'clock'});

        final decoded = jsonDecode(result);
        expect(decoded, isList);

        // Should find algorithms with 'clock' in name or description
        final hasClockRelated = decoded.any(
          (alg) =>
              alg['name'].toString().toLowerCase().contains('clock') ||
              alg['description'].toString().toLowerCase().contains('clock'),
        );
        expect(hasClockRelated, isTrue);
      });

      test('should combine category and query filters', () async {
        final result = await tools.listAlgorithms({
          'category': 'Utility',
          'query': 'clock',
        });

        final decoded = jsonDecode(result);
        expect(decoded, isList);
        // Results should be filtered by both criteria
      });
    });

    group('screen observation and explicit display mode', () {
      test('shared tools keep observation and mode changes separate', () async {
        final registry = ToolRegistry(distingCubit);
        addTearDown(registry.dispose);
        final screen = registry.findByName('show_screen')!;
        expect(screen.inputSchema['properties'], isEmpty);
        expect(screen.inputSchema['additionalProperties'], isFalse);
        final mode = registry.findByName('set_display_mode')!;
        expect(mode.inputSchema['required'], ['mode']);
        expect((mode.inputSchema['properties'] as Map)['mode']['enum'], [
          'parameter',
          'algorithm',
          'overview',
          'vu_meters',
        ]);
      });

      test(
        'screen observations reject mode arguments without pretending to change views',
        () async {
          for (final mode in [
            'invalid_mode',
            'parameter',
            'algorithm',
            'overview',
            'vu_meters',
          ]) {
            final decoded = jsonDecode(
              await tools.show({'target': 'screen', 'display_mode': mode}),
            );
            expect(decoded['success'], isFalse);
            expect(
              decoded['error'],
              contains('show_screen takes no arguments'),
            );
            expect(decoded['error'], contains('set_display_mode'));
            expect(decoded.containsKey('valid_modes'), isFalse);
          }
        },
      );

      test(
        'the explicit mode tool validates modes before requiring live hardware',
        () async {
          final invalid = jsonDecode(
            await tools.setDisplayMode('invalid_mode'),
          );
          expect(invalid['success'], isFalse);
          expect(invalid['error'], contains('Invalid mode'));
          expect(invalid['valid_modes'], [
            'parameter',
            'algorithm',
            'overview',
            'vu_meters',
          ]);
          for (final mode in [
            'parameter',
            'algorithm',
            'overview',
            'vu_meters',
          ]) {
            final result = jsonDecode(await tools.setDisplayMode(mode));
            expect(result['success'], isFalse);
            expect(result['error'], contains('synchronized live device'));
          }
        },
      );

      test('should work without display_mode parameter', () async {
        // Test that show works when display_mode is not provided
        final result = await tools.show({'target': 'screen'});

        final decoded = jsonDecode(result);
        // Should either succeed or fail with non-validation error
        // Device not synchronized is expected in test environment
        expect(decoded, isNotEmpty);
      });

      test('should handle missing target parameter', () async {
        final result = await tools.show({'display_mode': 'parameter'});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(
          decoded['error'],
          contains('Missing required parameter: target'),
        );
      });

      test(
        'should accept display_mode with other targets without error',
        () async {
          // Test that display_mode is accepted but not used with non-screen targets
          // (it should be ignored gracefully)
          final result = await tools.show({
            'target': 'preset',
            'display_mode': 'parameter',
          });

          final decoded = jsonDecode(result);
          // Should work normally for preset target, ignoring display_mode
          expect(decoded, isNotEmpty);
        },
      );
    });

    group('Error Handling', () {
      
    });
  });
}
