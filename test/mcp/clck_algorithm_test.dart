import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../test_helpers/mock_midi_command.dart';

void main() {
  group('CLCK Algorithm Specific Tests', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
    });
    test('clck.json should be valid and loadable', () async {
      final file = File('docs/algorithms/clck.json');
      expect(file.existsSync(), isTrue, reason: 'clck.json file should exist');

      final jsonString = await file.readAsString();
      expect(
        () => json.decode(jsonString),
        returnsNormally,
        reason: 'clck.json should be valid JSON',
      );

      final jsonData = json.decode(jsonString);
      expect(jsonData['guid'], equals('clck'));
      expect(jsonData['name'], equals('Clock'));
      expect(jsonData['parameters'], isList);
    });

    test('AlgorithmMetadataService should load clck', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final database = AppDatabase.forTesting(NativeDatabase.memory());

      try {
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

        await AlgorithmMetadataService().initialize(database);

        final service = AlgorithmMetadataService();
        final clckAlgo = service.getAlgorithmByGuid('clck');

        expect(clckAlgo, isNotNull, reason: 'clck algorithm should be loaded');
        expect(clckAlgo!.guid, equals('clck'));
        expect(clckAlgo.name, equals('Clock'));
      } finally {
        await database.close();
      }
    });

    test('MCPAlgorithmTools.getAlgorithmDetails should handle clck', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final database = AppDatabase.forTesting(NativeDatabase.memory());

      try {
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

        await AlgorithmMetadataService().initialize(database);

        final cubit = DistingCubit(database, midiCommand: MockMidiCommand());
        final tools = MCPAlgorithmTools(DistingControllerImpl(cubit), cubit);

        // Test with timeout to catch any hanging
        final resultFuture = tools
            .getAlgorithmDetails({'algorithm_guid': 'clck'})
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException(
                'getAlgorithmDetails timed out for clck',
              ),
            );

        final result = await resultFuture;
        final decoded = json.decode(result);

        if (decoded['success'] == false) {
          // Error response: ${decoded['error']}
        }

        expect(decoded['guid'], equals('clck'));
        expect(decoded['name'], equals('Clock'));

        cubit.close();
      } finally {
        await database.close();
      }
    });

    
  });
}
