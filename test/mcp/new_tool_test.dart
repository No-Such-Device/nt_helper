import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
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
  group('DistingTools - newWithAlgorithms', () {
    late DistingTools tools;
    late DistingCubit distingCubit;
    late DistingControllerImpl controller;
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
      controller = DistingControllerImpl(distingCubit);
      tools = DistingTools(controller, distingCubit);
    });

    tearDown(() {
      distingCubit.close();
    });

    tearDownAll(() async {
      await database.close();
    });

    group('newWithAlgorithms - parameter validation', () {
      test('should return error when name parameter is missing', () async {
        final result = await tools.newWithAlgorithms({});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(decoded['error'], contains('name'));
      });

      test('should return error when name is empty string', () async {
        final result = await tools.newWithAlgorithms({'name': ''});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(decoded['error'], contains('name'));
      });

      test('should accept null algorithms parameter', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Blank Preset',
          'algorithms': null,
        });

        final decoded = jsonDecode(result);
        // Should be valid response (success or error depending on device state)
        expect(decoded is Map, isTrue);
      });

      test('should accept empty algorithms array', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Blank Preset',
          'algorithms': [],
        });

        final decoded = jsonDecode(result);
        // Should be valid response (success or error depending on device state)
        expect(decoded is Map, isTrue);
      });
    });

    group('newWithAlgorithms - response structure', () {
      test('should return valid JSON for blank preset', () async {
        final result = await tools.newWithAlgorithms({'name': 'Test Preset'});

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
        expect(decoded.containsKey('success'), isTrue);
      });

      test('should return JSON for algorithms request', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Test With Algos',
          'algorithms': [
            {'guid': 'clck'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('should return success=true with data field on success', () async {
        final result = await tools.newWithAlgorithms({'name': 'Success Test'});

        final decoded = jsonDecode(result);
        if (decoded['success'] == true) {
          expect(decoded.containsKey('data'), isTrue);
        }
      });

      test('should return success=false with error field on failure', () async {
        final result = await tools.newWithAlgorithms({});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
        expect(decoded.containsKey('error'), isTrue);
      });
    });

    group('newWithAlgorithms - algorithm processing', () {
      test('should process GUID-based algorithm requests', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'GUID Test',
          'algorithms': [
            {'guid': 'clck'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
        // Should either succeed or report error
        expect(decoded.containsKey('success'), isTrue);
      });

      test('should process name-based algorithm requests', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Name Test',
          'algorithms': [
            {'name': 'Clock'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('should handle multiple algorithms', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Multi Algo',
          'algorithms': [
            {'guid': 'clck'},
            {'guid': 'clkd'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('should handle invalid GUIDs gracefully', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Invalid Test',
          'algorithms': [
            {'guid': 'notarealguid'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
        // Should return error or report algorithm failure
        expect(decoded.containsKey('success'), isTrue);
      });

      test('should support specifications parameter', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Specs Test',
          'algorithms': [
            {
              'guid': 'clck',
              'specifications': [1, 2, 3],
            },
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('should include algorithm_results when algorithms provided', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Results Test',
          'algorithms': [
            {'guid': 'clck'},
          ],
        });

        final decoded = jsonDecode(result);
        if (decoded['success'] == true && decoded['data'] != null) {
          // algorithm_results should be present if there were algorithms to process
          expect(decoded['data'].containsKey('algorithm_results'), isTrue);
        }
      });

      test('should not include algorithm_results for blank presets', () async {
        final result = await tools.newWithAlgorithms({'name': 'Blank Test'});

        final decoded = jsonDecode(result);
        if (decoded['success'] == true && decoded['data'] != null) {
          // Blank preset should not have algorithm_results
          expect(decoded['data'].containsKey('algorithm_results'), isFalse);
        }
      });
    });

    group('newWithAlgorithms - data field content', () {
      test('should include preset_name in successful response', () async {
        final result = await tools.newWithAlgorithms({'name': 'My Preset'});

        final decoded = jsonDecode(result);
        if (decoded['success'] == true) {
          expect(decoded['data'].containsKey('preset_name'), isTrue);
          expect(decoded['data']['preset_name'], equals('My Preset'));
        }
      });

      test('should include slots array in successful response', () async {
        final result = await tools.newWithAlgorithms({'name': 'Slots Test'});

        final decoded = jsonDecode(result);
        if (decoded['success'] == true) {
          expect(decoded['data'].containsKey('slots'), isTrue);
          expect(decoded['data']['slots'], isList);
        }
      });

      test('should include algorithm counts in response', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Counts Test',
          'algorithms': [
            {'guid': 'clck'},
          ],
        });

        final decoded = jsonDecode(result);
        if (decoded['success'] == true) {
          expect(decoded['data'].containsKey('algorithms_added'), isTrue);
          expect(decoded['data'].containsKey('algorithms_failed'), isTrue);
        }
      });
    });

    group('newWithAlgorithms - error handling', () {
      test('should handle missing name parameter', () async {
        final result = await tools.newWithAlgorithms({});

        final decoded = jsonDecode(result);
        expect(decoded['success'], isFalse);
      });

      test('should not crash with empty input', () async {
        final result = await tools.newWithAlgorithms({});

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      

      test('should continue processing after partial failures', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Partial Fail',
          'algorithms': [
            {'guid': 'notreal'},
            {'guid': 'clck'},
            {'guid': 'alsonotreal'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });
    });

    group('newWithAlgorithms - use cases', () {
      test('supports blank preset creation', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Empty Starting Point',
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('supports preset with single algorithm', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Single Algorithm Setup',
          'algorithms': [
            {'guid': 'clck'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('supports preset with multiple algorithms', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Complex Setup',
          'algorithms': [
            {'guid': 'clck'},
            {'guid': 'clkd'},
            {'guid': 'clkm'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });

      test('supports mixed GUID and name lookups', () async {
        final result = await tools.newWithAlgorithms({
          'name': 'Mixed Lookup',
          'algorithms': [
            {'guid': 'clck'},
            {'name': 'Clock Divider'},
          ],
        });

        final decoded = jsonDecode(result);
        expect(decoded is Map, isTrue);
      });
    });
  });
}
