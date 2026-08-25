import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late DistingCubit cubit;
  late AppDatabase database;
  late MockDistingMidiManager mockDisting;
  late MockMidiCommand mockMidiCommand;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    // Use real in-memory database so we can verify recording
    database = AppDatabase.forTesting(NativeDatabase.memory());
    mockDisting = MockDistingMidiManager();
    mockMidiCommand = MockMidiCommand();

    cubit = DistingCubit(database, midiCommand: mockMidiCommand);

    // Setup common mocks for file upload
    when(() => mockDisting.requestWake()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestDirectoryListing(any()),
    ).thenAnswer((_) async => DirectoryListing(entries: []));
    when(
      () => mockDisting.requestDirectoryCreate(any()),
    ).thenAnswer((_) async => SdCardStatus(success: true, message: 'ok'));
    when(
      () => mockDisting.requestFileUploadChunk(
        any(),
        any(),
        any(),
        createAlways: any(named: 'createAlways'),
      ),
    ).thenAnswer((_) async => SdCardStatus(success: true, message: 'ok'));
    when(() => mockDisting.requestRescanPlugins()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestNumberOfAlgorithms(),
    ).thenAnswer((_) async => 0);
    when(() => mockDisting.requestNewPreset()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestLoadPreset(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockDisting.requestNumAlgorithmsInPreset(),
    ).thenAnswer((_) async => 0);
    when(() => mockDisting.requestPresetName()).thenAnswer((_) async => 'Test');
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  DistingStateSynchronized createSynchronizedState({
    List<AlgorithmInfo>? algorithms,
    List<Slot>? slots,
  }) {
    return DistingStateSynchronized(
      disting: mockDisting,
      distingVersion: '1.12.0',
      firmwareVersion: FirmwareVersion('1.12.0'),
      presetName: 'Test',
      algorithms: algorithms ?? [],
      slots: slots ?? [],
      unitStrings: [],
      inputDevice: null,
      outputDevice: null,
      loading: false,
      offline: false,
      screenshot: null,
      demo: false,
      videoStream: null,
    );
  }

  group('DistingCubit plugin recording', () {
    test('installs into an existing empty plugin directory', () async {
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      when(
        () => mockDisting.requestDirectoryListing('/programs/plug-ins'),
      ).thenAnswer((_) async => DirectoryListing(entries: []));
      when(
        () => mockDisting.requestDirectoryCreate('/programs/plug-ins'),
      ).thenThrow(
        const SdCardOperationException(
          operation: SdCardOperation.directoryCreate,
          message: 'Unable to create folder',
        ),
      );

      await cubit.installPlugin('shoal.o', testData);

      verifyNever(
        () => mockDisting.requestDirectoryCreate('/programs/plug-ins'),
      );
      verify(
        () => mockDisting.requestFileUploadChunk(
          '/programs/plug-ins/shoal.o',
          testData,
          0,
          createAlways: true,
        ),
      ).called(1);
    });

    test('creates a missing plugin directory before installation', () async {
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      when(
        () => mockDisting.requestDirectoryListing('/programs/plug-ins'),
      ).thenThrow(
        const SdCardOperationException(
          operation: SdCardOperation.directoryListing,
          message: 'Unable to open folder',
        ),
      );

      await cubit.installPlugin('shoal.o', testData);

      verify(
        () => mockDisting.requestDirectoryCreate('/programs/plug-ins'),
      ).called(1);
      verify(
        () => mockDisting.requestFileUploadChunk(
          '/programs/plug-ins/shoal.o',
          testData,
          0,
          createAlways: true,
        ),
      ).called(1);
    });

    test('fails when a missing plugin directory cannot be created', () async {
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      when(
        () => mockDisting.requestDirectoryListing('/programs/plug-ins'),
      ).thenThrow(
        const SdCardOperationException(
          operation: SdCardOperation.directoryListing,
          message: 'Unable to open folder',
        ),
      );
      when(
        () => mockDisting.requestDirectoryCreate('/programs/plug-ins'),
      ).thenThrow(
        const SdCardOperationException(
          operation: SdCardOperation.directoryCreate,
          message: 'SD card is read-only',
        ),
      );

      await expectLater(
        cubit.installPlugin('shoal.o', testData),
        throwsA(
          isA<SdCardOperationException>()
              .having(
                (error) => error.operation,
                'operation',
                SdCardOperation.directoryCreate,
              )
              .having(
                (error) => error.message,
                'message',
                'SD card is read-only',
              ),
        ),
      );

      verifyNever(
        () => mockDisting.requestFileUploadChunk(
          any(),
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      );
    });

    test('records lua plugin installation to database', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('test_script.lua', testData);

      // Assert - verify database record was created
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(
        records[0].installationPath,
        equals('/programs/lua/test_script.lua'),
      );
      expect(records[0].pluginType, equals('lua'));
      expect(records[0].pluginName, equals('test_script.lua'));
      expect(records[0].totalBytes, equals(3));
    });

    test('records 3pot plugin installation to database', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      // Act
      await cubit.installPlugin('effect.3pot', testData);

      // Assert
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(
        records[0].installationPath,
        equals('/programs/three_pot/effect.3pot'),
      );
      expect(records[0].pluginType, equals('threepot'));
    });

    test('records cpp plugin installation to database', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList(List.filled(100, 0x55));

      // Act
      await cubit.installPlugin('synth.o', testData);

      // Assert
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].installationPath, equals('/programs/plug-ins/synth.o'));
      expect(records[0].pluginType, equals('cpp'));
      expect(records[0].totalBytes, equals(100));
    });

    test('updates existing record on reinstall (same path)', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final smallData = Uint8List.fromList([0x01, 0x02, 0x03]);
      final largerData = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);

      // Act - install twice
      await cubit.installPlugin('test.lua', smallData);
      await cubit.installPlugin('test.lua', largerData);

      // Assert - should have only one record (upsert)
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].totalBytes, equals(5)); // Updated to larger size
    });

    test('does not record on upload failure', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Make upload fail
      when(
        () => mockDisting.requestFileUploadChunk(
          any(),
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      ).thenAnswer(
        (_) async => SdCardStatus(success: false, message: 'Upload failed'),
      );

      // Act & Assert
      await expectLater(
        cubit.installPlugin('test.lua', testData),
        throwsException,
      );

      // Verify no database record was created
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records, isEmpty);
    });

    test('records correct path for plugin with subdirectory', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02]);

      // Act
      await cubit.installPlugin('subfolder/nested.lua', testData);

      // Assert
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(
        records[0].installationPath,
        equals('/programs/lua/subfolder/nested.lua'),
      );
      expect(records[0].pluginName, equals('nested.lua'));
    });

    test('records gallery plugin with proper pluginId and version', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act - install with gallery metadata
      await cubit.installPlugin(
        'my-synth.o',
        testData,
        galleryPluginId: 'expert-sleepers/my-synth',
        galleryPluginVersion: '1.2.0',
      );

      // Assert - verify gallery metadata was recorded
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('expert-sleepers/my-synth'));
      expect(records[0].pluginVersion, equals('1.2.0'));
      // Gallery installs should NOT have 'Local Install' as author
      expect(records[0].pluginAuthor, isNot(equals('Local Install')));
    });

    test('local install without gallery metadata uses local prefix', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act - install without gallery metadata (local install)
      await cubit.installPlugin('my-script.lua', testData);

      // Assert - verify local prefix was used
      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, startsWith('local:'));
      expect(records[0].pluginVersion, equals('unknown'));
      expect(records[0].pluginAuthor, equals('Local Install'));
    });
  });
}
