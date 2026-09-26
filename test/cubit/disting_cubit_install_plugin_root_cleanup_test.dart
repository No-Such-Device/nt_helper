import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/elf_guid_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockPluginInstallationsDao extends Mock
    implements PluginInstallationsDao {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

const _root = '/programs/plug-ins';
const _rootFile = '$_root/seq.o';

/// Replaces every occurrence of the 2-byte prefix of the fixture's factory
/// GUIDs ("AT") so the patched ELF yields a different GUID set.
Uint8List _withGuidPrefix(Uint8List source, String prefix) {
  final bytes = Uint8List.fromList(source);
  for (final guid in ['ATds', 'ATdm']) {
    final pattern = guid.codeUnits;
    for (var i = 0; i + 4 <= bytes.length; i++) {
      if (bytes[i] == pattern[0] &&
          bytes[i + 1] == pattern[1] &&
          bytes[i + 2] == pattern[2] &&
          bytes[i + 3] == pattern[3]) {
        bytes[i] = prefix.codeUnitAt(0);
        bytes[i + 1] = prefix.codeUnitAt(1);
      }
    }
  }
  return bytes;
}

DirectoryEntry _file(String name) =>
    DirectoryEntry(name: name, attributes: 0x20, date: 0, time: 0, size: 1);

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: name, attributes: 0x10, date: 0, time: 0, size: 0);

void main() {
  late DistingCubit cubit;
  late MockAppDatabase mockDatabase;
  late MockMetadataDao mockMetadataDao;
  late MockPluginInstallationsDao mockPluginInstallationsDao;
  late MockDistingMidiManager mockDisting;
  late Uint8List pluginBytes;
  late Uint8List otherGuidBytes;
  late List<DirectoryEntry> rootEntries;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(Uint8List(0));
    pluginBytes = File(
      'test/fixtures/plugins/directionalSequencer.o',
    ).readAsBytesSync();
    otherGuidBytes = _withGuidPrefix(pluginBytes, 'XY');
  });

  setUp(() {
    mockDatabase = MockAppDatabase();
    mockMetadataDao = MockMetadataDao();
    mockPluginInstallationsDao = MockPluginInstallationsDao();
    mockDisting = MockDistingMidiManager();
    rootEntries = [];

    when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
    when(
      () => mockDatabase.pluginInstallationsDao,
    ).thenReturn(mockPluginInstallationsDao);
    when(
      () => mockMetadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    when(
      () => mockMetadataDao.invalidateAlgorithmInfoCache(),
    ).thenAnswer((_) async {});
    when(
      () => mockPluginInstallationsDao.recordPluginByPath(
        installationPath: any(named: 'installationPath'),
        pluginName: any(named: 'pluginName'),
        pluginType: any(named: 'pluginType'),
        totalBytes: any(named: 'totalBytes'),
        pluginId: any(named: 'pluginId'),
        pluginVersion: any(named: 'pluginVersion'),
      ),
    ).thenAnswer((_) async => 1);

    cubit = DistingCubit(mockDatabase, midiCommand: MockMidiCommand());

    when(() => mockDisting.requestWake()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestDirectoryListing(any()),
    ).thenAnswer((_) async => DirectoryListing(entries: []));
    when(
      () => mockDisting.requestDirectoryListing(_root),
    ).thenAnswer((_) async => DirectoryListing(entries: rootEntries));
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
    when(
      () => mockDisting.requestFileDownload(any()),
    ).thenAnswer((_) async => pluginBytes);
    when(
      () => mockDisting.requestFileDelete(any()),
    ).thenAnswer((_) async => SdCardStatus(success: true, message: 'ok'));
    when(() => mockDisting.requestRescanPlugins()).thenAnswer((_) async {});
    when(() => mockDisting.requestNewPreset()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestLoadPreset(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockDisting.requestNumAlgorithmsInPreset(),
    ).thenAnswer((_) async => 0);
    when(() => mockDisting.requestPresetName()).thenAnswer((_) async => 'Test');
  });

  tearDown(() => cubit.close());

  void emitSynchronized({List<Slot> slots = const []}) {
    cubit.emit(
      DistingStateSynchronized(
        disting: mockDisting,
        distingVersion: '1.12.0',
        firmwareVersion: FirmwareVersion('1.12.0'),
        presetName: 'Test',
        algorithms: const [],
        slots: slots,
        unitStrings: const [],
        inputDevice: null,
        outputDevice: null,
        loading: false,
        offline: false,
        screenshot: null,
        demo: false,
        videoStream: null,
      ),
    );
  }

  void verifyNoCleanupCalls() {
    verifyNever(() => mockDisting.requestDirectoryListing(_root));
    verifyNever(() => mockDisting.requestFileDownload(any()));
    verifyNever(() => mockDisting.requestFileDelete(any()));
  }

  void verifyInstallCompleted(String path) {
    verify(() => mockDisting.requestRescanPlugins()).called(1);
    verify(
      () => mockPluginInstallationsDao.recordPluginByPath(
        installationPath: path,
        pluginName: any(named: 'pluginName'),
        pluginType: any(named: 'pluginType'),
        totalBytes: any(named: 'totalBytes'),
        pluginId: any(named: 'pluginId'),
        pluginVersion: any(named: 'pluginVersion'),
      ),
    ).called(1);
  }

  group('installPlugin root duplicate cleanup', () {
    test('patched fixture yields a different GUID set', () async {
      final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
        otherGuidBytes,
        'seq.o',
      );
      expect(guids.map((g) => g.guid).toSet(), {'XYds', 'XYdm'});
    });

    test(
      'deletes same-name same-GUID root file before rescan and keeps install',
      () async {
        rootEntries.add(_file('seq.o'));
        emitSynchronized();

        final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

        expect(outcome, isA<PluginCleanupRemoved>());
        expect((outcome as PluginCleanupRemoved).path, _rootFile);
        verifyInOrder([
          () => mockDisting.requestFileUploadChunk(
            '$_root/vendor/seq.o',
            any(),
            any(),
            createAlways: any(named: 'createAlways'),
          ),
          () => mockDisting.requestDirectoryListing(_root),
          () => mockDisting.requestFileDownload(_rootFile),
          () => mockDisting.requestFileDelete(_rootFile),
          () => mockDisting.requestRescanPlugins(),
        ]);
        // Install is still recorded (rescan order is asserted above).
        verify(
          () => mockPluginInstallationsDao.recordPluginByPath(
            installationPath: '$_root/vendor/seq.o',
            pluginName: any(named: 'pluginName'),
            pluginType: any(named: 'pluginType'),
            totalBytes: any(named: 'totalBytes'),
            pluginId: any(named: 'pluginId'),
            pluginVersion: any(named: 'pluginVersion'),
          ),
        ).called(1);
      },
    );

    test('keeps same-name root file with a different GUID', () async {
      rootEntries.add(_file('seq.o'));
      when(
        () => mockDisting.requestFileDownload(_rootFile),
      ).thenAnswer((_) async => otherGuidBytes);
      emitSynchronized();

      final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

      expect(outcome, isA<PluginCleanupSkipped>());
      verify(() => mockDisting.requestFileDownload(_rootFile)).called(1);
      verifyNever(() => mockDisting.requestFileDelete(any()));
    });

    test(
      'never downloads or deletes a root file with a different name',
      () async {
        rootEntries.addAll([_file('other.o'), _file('Seq.o'), _dir('seq.o')]);
        emitSynchronized();

        final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

        expect(outcome, isA<PluginCleanupSkipped>());
        verifyNever(() => mockDisting.requestFileDownload(any()));
        verifyNever(() => mockDisting.requestFileDelete(any()));
      },
    );

    test('never lists for candidates in, downloads from or deletes from '
        'any subfolder', () async {
      rootEntries.addAll([_file('seq.o'), _dir('vendor'), _dir('other')]);
      emitSynchronized();

      await cubit.installPlugin('vendor/seq.o', pluginBytes);

      final listed = verify(
        () => mockDisting.requestDirectoryListing(captureAny()),
      ).captured.cast<String>();
      // Only the upload parent check and the single root candidate listing.
      expect(listed.where((p) => p == _root), hasLength(1));
      expect(listed.where((p) => p.startsWith('$_root/')), ['$_root/vendor']);
      final downloaded = verify(
        () => mockDisting.requestFileDownload(captureAny()),
      ).captured;
      final deleted = verify(
        () => mockDisting.requestFileDelete(captureAny()),
      ).captured;
      expect(downloaded, [_rootFile]);
      expect(deleted, [_rootFile]);
    });

    test('root install performs no cleanup', () async {
      rootEntries.add(_file('seq.o'));
      emitSynchronized();

      final outcome = await cubit.installPlugin('seq.o', pluginBytes);

      expect(outcome, isA<PluginCleanupSkipped>());
      verifyNever(() => mockDisting.requestFileDownload(any()));
      verifyNever(() => mockDisting.requestFileDelete(any()));
      verifyInstallCompleted(_rootFile);
    });

    test('Lua and 3pot installs perform no cleanup', () async {
      emitSynchronized();

      expect(
        await cubit.installPlugin('vendor/seq.lua', pluginBytes),
        isA<PluginCleanupSkipped>(),
      );
      expect(
        await cubit.installPlugin('vendor/seq.3pot', pluginBytes),
        isA<PluginCleanupSkipped>(),
      );
      verifyNoCleanupCalls();
    });

    test('failed upload performs no cleanup', () async {
      rootEntries.add(_file('seq.o'));
      when(
        () => mockDisting.requestFileUploadChunk(
          any(),
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      ).thenAnswer((_) async => SdCardStatus(success: false, message: 'no'));
      emitSynchronized();

      await expectLater(
        cubit.installPlugin('vendor/seq.o', pluginBytes),
        throwsException,
      );
      verifyNoCleanupCalls();
      verifyNever(() => mockDisting.requestRescanPlugins());
    });

    test('throwing upload performs no cleanup', () async {
      rootEntries.add(_file('seq.o'));
      when(
        () => mockDisting.requestFileUploadChunk(
          any(),
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      ).thenThrow(Exception('link lost'));
      emitSynchronized();

      await expectLater(
        cubit.installPlugin('vendor/seq.o', pluginBytes),
        throwsException,
      );
      verifyNoCleanupCalls();
    });

    for (final status in <SdCardStatus?>[
      SdCardStatus(success: false, message: 'locked'),
      null,
    ]) {
      test('delete status ${status?.message ?? 'null'} reports deletion '
          'failed and keeps install', () async {
        rootEntries.add(_file('seq.o'));
        when(
          () => mockDisting.requestFileDelete(_rootFile),
        ).thenAnswer((_) async => status);
        emitSynchronized();

        final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

        expect(outcome, isA<PluginCleanupDeletionFailed>());
        expect((outcome as PluginCleanupDeletionFailed).path, _rootFile);
        verifyInstallCompleted('$_root/vendor/seq.o');
      });
    }

    final unverifiable = <String, Future<Uint8List?> Function()>{
      'download returns null': () async => null,
      'download throws': () async => throw Exception('timeout'),
      'downloaded bytes are not ELF': () async => Uint8List.fromList([1, 2]),
    };
    unverifiable.forEach((name, download) {
      test('$name keeps the root file as could not be verified', () async {
        rootEntries.add(_file('seq.o'));
        when(
          () => mockDisting.requestFileDownload(_rootFile),
        ).thenAnswer((_) => download());
        emitSynchronized();

        final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

        expect(outcome, isA<PluginCleanupCouldNotBeVerified>());
        expect((outcome as PluginCleanupCouldNotBeVerified).path, _rootFile);
        verifyNever(() => mockDisting.requestFileDelete(any()));
        verifyInstallCompleted('$_root/vendor/seq.o');
      });
    });

    test('listing failure keeps root file as could not be verified', () async {
      when(
        () => mockDisting.requestDirectoryListing(_root),
      ).thenThrow(Exception('sd busy'));
      emitSynchronized();

      final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

      expect(outcome, isA<PluginCleanupCouldNotBeVerified>());
      verifyNever(() => mockDisting.requestFileDownload(any()));
      verifyNever(() => mockDisting.requestFileDelete(any()));
    });

    test('installed file without a GUID skips cleanup', () async {
      rootEntries.add(_file('seq.o'));
      emitSynchronized();

      final outcome = await cubit.installPlugin(
        'vendor/seq.o',
        Uint8List.fromList([1, 2, 3]),
      );

      expect(outcome, isA<PluginCleanupSkipped>());
      verifyNoCleanupCalls();
    });

    test('loaded preset using the GUID: delete attempted, no preset calls '
        'from cleanup', () async {
      rootEntries.add(_file('seq.o'));
      emitSynchronized(
        slots: [
          Slot(
            algorithm: Algorithm(algorithmIndex: 0, guid: 'ATds', name: 'Seq'),
            routing: RoutingInfo.filler(),
            pages: ParameterPages(algorithmIndex: 0, pages: []),
            parameters: [],
            values: [],
            enums: [],
            mappings: [],
            valueStrings: [],
          ),
        ],
      );

      final outcome = await cubit.installPlugin('vendor/seq.o', pluginBytes);

      expect(outcome, isA<PluginCleanupRemoved>());
      verify(() => mockDisting.requestFileDelete(_rootFile)).called(1);
      verifyNever(() => mockDisting.requestNewPreset());
      verifyNever(() => mockDisting.requestLoadPreset(any(), any()));
      verifyNever(
        () => mockDisting.requestSavePreset(option: any(named: 'option')),
      );
    });
  });
}
