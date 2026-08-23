import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show Algorithm;
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
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
import 'package:nt_helper/models/cpu_usage.dart';

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

  final notesAlgorithm = Algorithm(
    algorithmIndex: 1,
    guid: 'note',
    name: 'Notes',
  );

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
    when(() => cubit.state).thenReturn(const DistingStateInitial());
    when(
      () => controller.getCurrentPresetName(),
    ).thenAnswer((_) async => 'TestPreset');
    when(
      () => controller.getAllSlots(),
    ).thenAnswer((_) async => <int, Algorithm?>{});
    when(() => controller.flushParameterQueue()).thenAnswer((_) async {});
    when(() => controller.savePreset()).thenAnswer((_) async {});
  });

  tearDownAll(() async {
    await database.close();
  });

  group('getNotes — empty intermediate lines', () {
    test('BUG: empty intermediate lines are dropped from output', () async {
      // Notes has 3 lines: "Line 1", "", "Line 3"
      // getNotes currently skips empty lines, losing the structure.
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: notesAlgorithm});

      when(
        () => controller.getParameterStringValue(0, 1),
      ).thenAnswer((_) async => 'Line 1');
      when(
        () => controller.getParameterStringValue(0, 2),
      ).thenAnswer((_) async => '');
      when(
        () => controller.getParameterStringValue(0, 3),
      ).thenAnswer((_) async => 'Line 3');
      when(
        () => controller.getParameterStringValue(0, 4),
      ).thenAnswer((_) async => null);
      when(
        () => controller.getParameterStringValue(0, 5),
      ).thenAnswer((_) async => null);
      when(
        () => controller.getParameterStringValue(0, 6),
      ).thenAnswer((_) async => null);
      when(
        () => controller.getParameterStringValue(0, 7),
      ).thenAnswer((_) async => null);

      final result = await distingTools.getNotes({});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      // The text should preserve the empty line
      expect(json['text'], equals('Line 1\n\nLine 3'));
      // Line count should include the empty line
      expect(json['line_count'], equals(3));
    });

    test('all empty lines returns no notes', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: notesAlgorithm});

      for (int i = 1; i <= 7; i++) {
        when(
          () => controller.getParameterStringValue(0, i),
        ).thenAnswer((_) async => '');
      }

      final result = await distingTools.getNotes({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      // All empty — should have 0 lines
      expect(json['line_count'], equals(0));
    });
  });

  group('getNotes — no Notes algorithm', () {
    test('returns error when no Notes algorithm in preset', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: testAlgorithm});

      final result = await distingTools.getNotes({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('Notes'));
    });
  });

  group('setNotes — text validation', () {
    test('missing text returns error', () async {
      final result = await distingTools.setNotes({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('text'));
    });

    test('empty text passes validation', () async {
      // Empty text should produce empty lines array, which passes validation
      // but the method should still work
      when(() => cubit.state).thenReturn(const DistingStateInitial());

      // Notes doesn't exist, so _findOrAddNotesAlgorithm tries to add one
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: notesAlgorithm});

      for (int i = 1; i <= 7; i++) {
        when(
          () => controller.updateParameterString(0, i, any()),
        ).thenAnswer((_) async {});
      }
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      final result = await distingTools.setNotes({'text': '   '});
      final json = jsonDecode(result) as Map<String, dynamic>;
      // Whitespace-only text trims to empty, _splitTextIntoLines returns []
      // validateNotesText([]) returns true, so it should proceed
      expect(json['success'], isTrue);
    });

    test('text with exactly 7 lines passes', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: notesAlgorithm});

      for (int i = 1; i <= 7; i++) {
        when(
          () => controller.updateParameterString(0, i, any()),
        ).thenAnswer((_) async {});
      }
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      final text = List.generate(7, (i) => 'Line ${i + 1}').join('\n');
      final result = await distingTools.setNotes({'text': text});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['lines_set'], equals(7));
    });

    test('text wrapping splits long lines', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: notesAlgorithm});

      for (int i = 1; i <= 7; i++) {
        when(
          () => controller.updateParameterString(0, i, any()),
        ).thenAnswer((_) async {});
      }
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      // A long line that should be wrapped: 45 chars with spaces
      final text = 'This is a line that is too long to fit';
      // "This is a line that is too long" = 30 chars, fits
      // "to fit" goes on line 2
      final result = await distingTools.setNotes({'text': text});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      // Should have wrapped into 2 lines
      expect(json['lines_set'], equals(2));
    });
  });

  group('setNotes — Notes creation and positioning', () {
    test('moves Notes algorithm to slot 0 when found at higher slot', () async {
      // Notes at slot 3, should be moved to slot 0
      when(() => controller.getAllSlots()).thenAnswer(
        (_) async => <int, Algorithm?>{
          0: testAlgorithm,
          1: testAlgorithm,
          2: testAlgorithm,
          3: notesAlgorithm,
        },
      );

      for (int i = 1; i <= 7; i++) {
        when(
          () => controller.updateParameterString(3, i, any()),
        ).thenAnswer((_) async {});
      }
      when(() => controller.moveAlgorithmUp(3)).thenAnswer((_) async {});
      when(() => controller.moveAlgorithmUp(2)).thenAnswer((_) async {});
      when(() => controller.moveAlgorithmUp(1)).thenAnswer((_) async {});
      when(() => controller.refreshSlot(0)).thenAnswer((_) async {});

      final result = await distingTools.setNotes({'text': 'Hello'});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);

      verify(() => controller.moveAlgorithmUp(3)).called(1);
      verify(() => controller.moveAlgorithmUp(2)).called(1);
      verify(() => controller.moveAlgorithmUp(1)).called(1);
    });
  });

  group('getPresetName', () {
    test('returns current preset name', () async {
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'My Cool Preset');

      final result = await distingTools.getPresetName({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['preset_name'], equals('My Cool Preset'));
    });

    test('handles controller error', () async {
      when(
        () => controller.getCurrentPresetName(),
      ).thenThrow(StateError('Not synchronized'));

      final result = await distingTools.getPresetName({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });
  });

  group('setPresetName', () {
    test('missing name returns error', () async {
      final result = await distingTools.setPresetName({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('name'));
    });

    test('sets name successfully', () async {
      when(() => controller.setPresetName('NewName')).thenAnswer((_) async {});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'NewName');

      final result = await distingTools.setPresetName({'name': 'NewName'});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('NewName'));
      expect(json['preset_name'], 'NewName');
      expect(json['persisted'], isTrue);
      verify(() => controller.setPresetName('NewName')).called(1);
    });

    test('trims the name before applying it', () async {
      when(() => controller.setPresetName('NewName')).thenAnswer((_) async {});
      when(
        () => controller.getCurrentPresetName(),
      ).thenAnswer((_) async => 'NewName');

      final result = await distingTools.setPresetName({'name': '  NewName  '});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue);
      verify(() => controller.setPresetName('NewName')).called(1);
    });

    test(
      'rejects blank and overlong names without changing hardware',
      () async {
        final blank =
            jsonDecode(await distingTools.setPresetName({'name': '   '}))
                as Map<String, dynamic>;
        final overlong =
            jsonDecode(
                  await distingTools.setPresetName({
                    'name': List.filled(32, 'x').join(),
                  }),
                )
                as Map<String, dynamic>;

        expect(blank['success'], isFalse);
        expect(overlong['success'], isFalse);
        verifyNever(() => controller.setPresetName(any()));
      },
    );
  });

  group('getSlotName', () {
    test('missing slot_index returns error', () async {
      final result = await distingTools.getSlotName({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('returns slot name when set', () async {
      when(() => controller.getSlotName(0)).thenAnswer((_) async => 'MyVCO');

      final result = await distingTools.getSlotName({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['slot_name'], equals('MyVCO'));
    });

    test('returns empty string when no custom name', () async {
      when(() => controller.getSlotName(0)).thenAnswer((_) async => null);

      final result = await distingTools.getSlotName({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['slot_name'], equals(''));
    });
  });

  group('setSlotName', () {
    test('missing slot_index returns error', () async {
      final result = await distingTools.setSlotName({'name': 'Test'});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('missing name returns error', () async {
      final result = await distingTools.setSlotName({'slot_index': 0});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('sets slot name successfully', () async {
      when(() => controller.setSlotName(0, 'MyVCO')).thenAnswer((_) async {});

      final result = await distingTools.setSlotName({
        'slot_index': 0,
        'name': 'MyVCO',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      verify(() => controller.setSlotName(0, 'MyVCO')).called(1);
    });
  });

  group('newPreset', () {
    test('calls controller.newPreset and succeeds', () async {
      when(() => controller.newPreset()).thenAnswer((_) async {});

      final result = await distingTools.newPreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      verify(() => controller.newPreset()).called(1);
    });

    test('handles controller error', () async {
      when(() => controller.newPreset()).thenThrow(StateError('Not connected'));

      final result = await distingTools.newPreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });
  });

  group('findAlgorithmInPreset', () {
    test('missing both guid and name returns error', () async {
      final result = await distingTools.findAlgorithmInPreset({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('finds algorithm by GUID', () async {
      when(() => controller.getAllSlots()).thenAnswer(
        (_) async => <int, Algorithm?>{
          0: testAlgorithm,
          1: Algorithm(algorithmIndex: 1, guid: 'vco1', name: 'VCO'),
        },
      );

      final result = await distingTools.findAlgorithmInPreset({
        'algorithm_guid': 'vco1',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['slot_count'], equals(1));
      expect((json['found_in_slots'] as List).first['slot_index'], equals(1));
    });

    test('finds multiple instances of same algorithm', () async {
      when(() => controller.getAllSlots()).thenAnswer(
        (_) async => <int, Algorithm?>{
          0: Algorithm(algorithmIndex: 0, guid: 'attn', name: 'Attenuator'),
          2: Algorithm(algorithmIndex: 2, guid: 'attn', name: 'Attenuator'),
          5: Algorithm(algorithmIndex: 5, guid: 'attn', name: 'Attenuator'),
        },
      );

      final result = await distingTools.findAlgorithmInPreset({
        'algorithm_guid': 'attn',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['slot_count'], equals(3));
    });

    test('returns error when algorithm not found in preset', () async {
      when(
        () => controller.getAllSlots(),
      ).thenAnswer((_) async => <int, Algorithm?>{0: testAlgorithm});

      final result = await distingTools.findAlgorithmInPreset({
        'algorithm_guid': 'nonexistent',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('not found'));
    });

    test('providing both guid and name returns error', () async {
      final result = await distingTools.findAlgorithmInPreset({
        'algorithm_guid': 'test',
        'algorithm_name': 'Test',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });
  });

  group('buildPresetFromJson — validation', () {
    test('missing preset_data returns error', () async {
      final result = await distingTools.buildPresetFromJson({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('missing preset_name in data returns error', () async {
      final result = await distingTools.buildPresetFromJson({
        'preset_data': {'slots': []},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('preset_name'));
    });

    test('missing slots in data returns error', () async {
      final result = await distingTools.buildPresetFromJson({
        'preset_data': {'preset_name': 'Test'},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
      expect(json['error'], contains('slots'));
    });

    test('non-list slots returns error', () async {
      final result = await distingTools.buildPresetFromJson({
        'preset_data': {'preset_name': 'Test', 'slots': 'not a list'},
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });

    test('malformed slot data returns slot-level error', () async {
      when(() => controller.newPreset()).thenAnswer((_) async {});
      when(() => controller.setPresetName('Test')).thenAnswer((_) async {});

      final result = await distingTools.buildPresetFromJson({
        'preset_data': {
          'preset_name': 'Test',
          'slots': ['not an object'],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue); // overall success
      expect(json['failed_slots'], equals(1));
    });
  });

  group('buildPresetFromJson — null slot handling', () {
    test('null entries in slots array are skipped', () async {
      when(() => controller.newPreset()).thenAnswer((_) async {});
      when(() => controller.setPresetName('Test')).thenAnswer((_) async {});

      final result = await distingTools.buildPresetFromJson({
        'preset_data': {
          'preset_name': 'Test',
          'slots': [null, null],
        },
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      // Null slots are skipped, so 0 processed
      expect(json['total_slots_processed'], equals(0));
    });
  });

  group('moveAlgorithm — multi-step boundary clamping', () {
    test('move down multi-step from near bottom returns error', () async {
      when(
        () => controller.moveAlgorithmDown(any(that: isA<int>())),
      ).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 38,
        'direction': 'down',
        'steps': 3,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      // After 1 step (38 -> 39), second step would exceed the final slot.
      expect(json['success'], isFalse);
    });

    test('move down multi-step calls correct slot indices', () async {
      when(
        () => controller.moveAlgorithmDown(any(that: isA<int>())),
      ).thenAnswer((_) async {});

      final result = await distingTools.moveAlgorithm({
        'slot_index': 5,
        'direction': 'down',
        'steps': 3,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['message'], contains('slot 8'));

      // Should call moveAlgorithmDown(5), moveAlgorithmDown(6), moveAlgorithmDown(7)
      verify(() => controller.moveAlgorithmDown(5)).called(1);
      verify(() => controller.moveAlgorithmDown(6)).called(1);
      verify(() => controller.moveAlgorithmDown(7)).called(1);
    });
  });

  group('getCpuUsage', () {
    test('returns CPU data when available', () async {
      when(() => controller.getCpuUsage()).thenAnswer(
        (_) async => CpuUsage(cpu1: 45, cpu2: 30, slotUsages: [20, 25]),
      );

      final result = await distingTools.getCpuUsage({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['cpu1_percentage'], equals(45));
      expect(json['cpu2_percentage'], equals(30));
      expect(json['total_slots'], equals(2));
    });

    test('returns error when CPU data unavailable', () async {
      when(() => controller.getCpuUsage()).thenAnswer((_) async => null);

      final result = await distingTools.getCpuUsage({});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isFalse);
    });
  });
}
