import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late DistingCubit cubit;
  late MockAppDatabase mockDatabase;
  late MockMetadataDao mockMetadataDao;
  late MockDistingMidiManager mockDisting;
  late MockMidiCommand mockMidiCommand;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
  });

  setUp(() {
    mockDatabase = MockAppDatabase();
    mockMetadataDao = MockMetadataDao();
    mockDisting = MockDistingMidiManager();
    mockMidiCommand = MockMidiCommand();

    when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
    when(
      () => mockMetadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);

    when(
      () => mockDisting.requestSetPresetName(any()),
    ).thenAnswer((_) async {});
    when(() => mockDisting.requestSavePreset()).thenAnswer((_) async {});
    when(() => mockDisting.requestPresetName()).thenAnswer((_) async => null);

    cubit = DistingCubit(mockDatabase, midiCommand: mockMidiCommand);
  });

  tearDown(() async {
    await cubit.close();
  });

  DistingStateSynchronized makeSyncState({String presetName = 'Old Name'}) {
    return DistingStateSynchronized(
      disting: mockDisting,
      distingVersion: '1.10.0',
      firmwareVersion: FirmwareVersion('1.14.0'),
      presetName: presetName,
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
      offline: false,
    );
  }

  Future<void> pumpEventQueue() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('renamePreset auto-save', () {
    test('awaitable rename completes only after the save completes', () async {
      final saveCompleter = Completer<void>();
      when(
        () => mockDisting.requestSavePreset(),
      ).thenAnswer((_) => saveCompleter.future);
      cubit.emit(makeSyncState(presetName: 'Old Name'));

      var completed = false;
      final rename = cubit.renamePresetAndSave('New Name').then((_) {
        completed = true;
      });
      await pumpEventQueue();

      expect(completed, isFalse);
      saveCompleter.complete();
      await rename;
      expect(completed, isTrue);
    });

    test('awaitable rename reports a failed write', () async {
      when(
        () => mockDisting.requestSetPresetName(any()),
      ).thenThrow(StateError('rename failed'));
      cubit.emit(makeSyncState(presetName: 'Old Name'));

      await expectLater(
        cubit.renamePresetAndSave('New Name'),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test('rename to non-empty name calls set then save in order', () async {
      cubit.emit(makeSyncState(presetName: 'Old Name'));

      cubit.renamePreset('New Name');
      await pumpEventQueue();

      verifyInOrder([
        () => mockDisting.requestSetPresetName('New Name'),
        () => mockDisting.requestSavePreset(),
      ]);
    });

    test('rename to empty string does not set or save', () async {
      cubit.emit(makeSyncState(presetName: 'Old Name'));

      cubit.renamePreset('');
      await pumpEventQueue();

      verifyNever(() => mockDisting.requestSetPresetName(any()));
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test('rename to whitespace-only name does not set or save', () async {
      cubit.emit(makeSyncState(presetName: 'Old Name'));

      cubit.renamePreset('   \t\n  ');
      await pumpEventQueue();

      verifyNever(() => mockDisting.requestSetPresetName(any()));
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test('rename to the same trimmed name does not set or save', () async {
      cubit.emit(makeSyncState(presetName: 'Same Name'));

      cubit.renamePreset('  Same Name  ');
      await pumpEventQueue();

      verifyNever(() => mockDisting.requestSetPresetName(any()));
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test('rename when not synchronized does not set or save', () async {
      cubit.renamePreset('Anything');
      await pumpEventQueue();

      verifyNever(() => mockDisting.requestSetPresetName(any()));
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test('save is skipped when requestSetPresetName fails', () async {
      when(
        () => mockDisting.requestSetPresetName(any()),
      ).thenAnswer((_) async => throw Exception('rename failed'));

      cubit.emit(makeSyncState(presetName: 'Old Name'));

      cubit.renamePreset('New Name');
      await pumpEventQueue();

      verify(() => mockDisting.requestSetPresetName('New Name')).called(1);
      verifyNever(() => mockDisting.requestSavePreset());
    });

    test(
      'two rapid renames produce two saves with last name being final',
      () async {
        cubit.emit(makeSyncState(presetName: 'Old Name'));

        cubit.renamePreset('First');
        cubit.renamePreset('Second');
        await pumpEventQueue();

        final captured = verify(
          () => mockDisting.requestSetPresetName(captureAny()),
        ).captured;
        expect(captured, ['First', 'Second']);
        verify(() => mockDisting.requestSavePreset()).called(2);
      },
    );
  });
}
