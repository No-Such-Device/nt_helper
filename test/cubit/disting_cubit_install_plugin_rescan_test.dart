import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/plugin_metadata_extractor.dart';
import 'package:nt_helper/services/settings_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockSettingsService extends Mock implements SettingsService {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockPluginInstallationsDao extends Mock
    implements PluginInstallationsDao {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late DistingCubit cubit;
  late MockAppDatabase mockDatabase;
  late MockMetadataDao mockMetadataDao;
  late MockPluginInstallationsDao mockPluginInstallationsDao;
  late MockDistingMidiManager mockDisting;
  late MockMidiCommand mockMidiCommand;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockDatabase = MockAppDatabase();
    mockMetadataDao = MockMetadataDao();
    mockPluginInstallationsDao = MockPluginInstallationsDao();
    mockDisting = MockDistingMidiManager();
    mockMidiCommand = MockMidiCommand();

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

    cubit = DistingCubit(mockDatabase, midiCommand: mockMidiCommand);

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

    // For C++ plugin workflow (reference implementation pattern)
    when(() => mockDisting.requestNewPreset()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestLoadPreset(any(), any()),
    ).thenAnswer((_) async {});

    // For _refreshStateFromManager() at end of installPlugin
    when(
      () => mockDisting.requestNumAlgorithmsInPreset(),
    ).thenAnswer((_) async => 0);
    when(() => mockDisting.requestPresetName()).thenAnswer((_) async => 'Test');
  });

  tearDown(() {
    cubit.close();
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

  /// Creates a state where a plugin is installed and being used by a slot
  DistingStateSynchronized createStateWithPluginInUse(String pluginPath) {
    const pluginGuid = 'test-plugin-guid';
    final algorithmInfo = AlgorithmInfo(
      algorithmIndex: 0,
      name: 'Test Plugin',
      guid: pluginGuid,
      specifications: [],
      isPlugin: true,
      filename: pluginPath,
    );
    final algorithm = Algorithm(
      algorithmIndex: 0,
      guid: pluginGuid,
      name: 'Test Plugin',
    );
    final slot = Slot(
      algorithm: algorithm,
      routing: RoutingInfo.filler(),
      pages: ParameterPages(algorithmIndex: 0, pages: []),
      parameters: [],
      values: [],
      enums: [],
      mappings: [],
      valueStrings: [],
    );
    return createSynchronizedState(algorithms: [algorithmInfo], slots: [slot]);
  }

  /// Creates a state where a plugin exists but is NOT being used by any slot
  DistingStateSynchronized createStateWithPluginNotInUse(String pluginPath) {
    final algorithmInfo = AlgorithmInfo(
      algorithmIndex: 0,
      name: 'Test Plugin',
      guid: 'test-plugin-guid',
      specifications: [],
      isPlugin: true,
      filename: pluginPath,
    );
    // Create a slot with a DIFFERENT algorithm (built-in, not the plugin)
    final differentAlgorithm = Algorithm(
      algorithmIndex: 0,
      guid: 'different-built-in-guid',
      name: 'Built-in Algorithm',
    );
    final slot = Slot(
      algorithm: differentAlgorithm,
      routing: RoutingInfo.filler(),
      pages: ParameterPages(algorithmIndex: 0, pages: []),
      parameters: [],
      values: [],
      enums: [],
      mappings: [],
      valueStrings: [],
    );
    return createSynchronizedState(algorithms: [algorithmInfo], slots: [slot]);
  }

  group('companion ZIP installation', () {
    const pluginPath = '/programs/plug-ins/patch_helper.o';
    const companionPath = '/programs/helper/ThPh.lua';
    final companion = Uint8List.fromList(List.generate(1100, (i) => i % 127));
    final object = Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46]);
    const plugin = GalleryPlugin(
      id: 'patch-helper',
      name: 'Patch Helper',
      description: '',
      type: GalleryPluginType.cpp,
      author: 'test',
      repository: PluginRepository(
        owner: 'test',
        name: 'test',
        url: 'https://example.com',
      ),
      releases: PluginReleases(latest: 'v1'),
      installation: PluginInstallation(
        targetPath: 'programs/plug-ins',
        extractPattern: r'\.o$',
        sourceDirectoryPath: 'programs/plug-ins',
      ),
    );

    Uint8List zip({String companionName = 'programs/helper/ThPh.lua'}) =>
        Uint8List.fromList(
          ZipEncoder().encode(
            Archive()
              ..addFile(
                ArchiveFile(
                  'programs/plug-ins/patch_helper.o',
                  object.length,
                  object,
                ),
              )
              ..addFile(ArchiveFile(companionName, companion.length, companion))
              ..addFile(ArchiveFile('README.md', 4, [1, 2, 3, 4])),
          ),
        );

    GalleryService gallery() {
      final settings = MockSettingsService();
      when(() => settings.galleryUrl).thenReturn('https://example.com/gallery');
      when(
        () => settings.graphqlEndpoint,
      ).thenReturn('https://example.com/graphql');
      return GalleryService(settingsService: settings);
    }

    for (final source in ['gallery']) {
      test(
        '$source ZIP uploads exact bytes into both SD directories',
        () async {
          cubit.emit(createSynchronizedState());
          final directories = <String>{'/programs'};
          final uploaded = <String, List<int>>{};
          final events = <String>[];
          when(() => mockDisting.requestDirectoryListing(any())).thenAnswer(
            (call) async => directories.contains(call.positionalArguments[0])
                ? DirectoryListing(entries: [])
                : null,
          );
          when(() => mockDisting.requestDirectoryCreate(any())).thenAnswer((
            call,
          ) async {
            directories.add(call.positionalArguments[0] as String);
            return SdCardStatus(success: true, message: 'ok');
          });
          when(
            () => mockDisting.requestFileUploadChunk(
              any(),
              any(),
              any(),
              createAlways: any(named: 'createAlways'),
            ),
          ).thenAnswer((call) async {
            final target = call.positionalArguments[0] as String;
            final bytes = call.positionalArguments[1] as Uint8List;
            final position = call.positionalArguments[2] as int;
            final data = uploaded.putIfAbsent(target, () => []);
            expect(position, data.length);
            expect(bytes.length, lessThanOrEqualTo(512));
            expect(call.namedArguments[#createAlways], position == 0);
            data.addAll(bytes);
            events.add(target);
            return SdCardStatus(success: true, message: 'ok');
          });
          when(() => mockDisting.requestRescanPlugins()).thenAnswer((_) async {
            events.add('rescan');
          });
          await gallery().installPlugin(
            plugin,
            cachedArchiveBytes: zip(),
            distingInstallPlugin: cubit.installPlugin,
          );
          expect(uploaded.keys, [companionPath, pluginPath]);
          expect(uploaded[companionPath], companion);
          expect(uploaded[pluginPath], object);
          expect(events.last, 'rescan');
          expect(
            directories,
            containsAll(['/programs/helper', '/programs/plug-ins']),
          );
          verifyNever(
            () => mockPluginInstallationsDao.recordPluginByPath(
              installationPath: companionPath,
              pluginName: any(named: 'pluginName'),
              pluginType: any(named: 'pluginType'),
              totalBytes: any(named: 'totalBytes'),
              pluginId: any(named: 'pluginId'),
              pluginVersion: any(named: 'pluginVersion'),
            ),
          );
        },
      );

      test(
        '$source fails companion upload without a Lua-folder fallback',
        () async {
          cubit.emit(createSynchronizedState());
          when(
            () => mockDisting.requestFileUploadChunk(
              companionPath,
              any(),
              any(),
              createAlways: any(named: 'createAlways'),
            ),
          ).thenAnswer(
            (_) async => SdCardStatus(success: false, message: 'disk full'),
          );
          await expectLater(
            gallery().installPlugin(
              plugin,
              cachedArchiveBytes: zip(),
              distingInstallPlugin: cubit.installPlugin,
            ),
            throwsException,
          );
          final paths = verify(
            () => mockDisting.requestFileUploadChunk(
              captureAny(),
              any(),
              any(),
              createAlways: any(named: 'createAlways'),
            ),
          ).captured;
          expect(paths, [companionPath]);
          verifyNever(() => mockDisting.requestRescanPlugins());
        },
      );
    }

    test('companion is not a selectable algorithm in a collection', () async {
      expect(
        await PluginMetadataExtractor.countInstallablePlugins(zip(), plugin),
        1,
      );
      final choices = await PluginMetadataExtractor.extractPluginsFromArchive(
        zip(),
        plugin,
      );
      expect(choices.map((p) => p.relativePath), ['patch_helper.o']);
      final uploaded = <String>[];
      await gallery().installPlugin(
        plugin,
        cachedArchiveBytes: zip(),
        selectedPlugins: [choices.single.copyWith(selected: true)],
        distingInstallPlugin:
            (
              String name,
              Uint8List data, {
              Function(double)? onProgress,
              String? galleryPluginId,
              String? galleryPluginVersion,
            }) async {
              uploaded.add(name);
            },
      );
      expect(uploaded, ['programs/helper/ThPh.lua', 'patch_helper.o']);
    });

    for (final badPath in [
      'programs/helper/../lua/ThPh.lua',
      'programs/plug-ins/ThPh.lua',
      'programs/helper-other/ThPh.lua',
    ]) {
      test('rejects invalid upload path $badPath', () async {
        cubit.emit(createSynchronizedState());
        await expectLater(
          cubit.installPlugin(badPath, companion),
          throwsFormatException,
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
    }

    test('plain Lua algorithm still uploads to programs/lua', () async {
      cubit.emit(createSynchronizedState());
      await cubit.installPlugin('normal.lua', Uint8List.fromList([1]));
      verify(
        () => mockDisting.requestFileUploadChunk(
          '/programs/lua/normal.lua',
          any(),
          0,
          createAlways: true,
        ),
      ).called(1);
    });
  });

  group('DistingCubit installPlugin rescan behavior', () {
    test('triggers requestRescanPlugins after .o file upload', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('test_plugin.o', testData);

      // Assert - rescan should be called for C++ plugins
      verify(() => mockDisting.requestRescanPlugins()).called(1);
    });

    test(
      'does NOT trigger requestRescanPlugins after .lua file upload',
      () async {
        // Arrange
        cubit.emit(createSynchronizedState());
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('test_script.lua', testData);

        // Assert - rescan should NOT be called for Lua scripts
        verifyNever(() => mockDisting.requestRescanPlugins());
      },
    );

    test(
      'does NOT trigger requestRescanPlugins after .3pot file upload',
      () async {
        // Arrange
        cubit.emit(createSynchronizedState());
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('test_script.3pot', testData);

        // Assert - rescan should NOT be called for Three Pot scripts
        verifyNever(() => mockDisting.requestRescanPlugins());
      },
    );

    test('continues successfully even if rescan fails', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Make rescan fail
      when(
        () => mockDisting.requestRescanPlugins(),
      ).thenThrow(Exception('Rescan failed'));

      // Act - should not throw
      await cubit.installPlugin('test_plugin.o', testData);

      // Assert - installation should complete without throwing
      verify(() => mockDisting.requestRescanPlugins()).called(1);
    });

    test('triggers rescan for .O extension (case insensitive)', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('test_plugin.O', testData);

      // Assert - rescan should be called (extension comparison is case-insensitive)
      verify(() => mockDisting.requestRescanPlugins()).called(1);
    });

    test('triggers rescan for plugins with subdirectories in path', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('subfolder/test_plugin.o', testData);

      // Assert - rescan should be called regardless of path structure
      verify(() => mockDisting.requestRescanPlugins()).called(1);
    });

    test(
      'creates blank preset before uploading C++ plugin when plugin IS in use',
      () async {
        // Arrange - plugin is currently used by a slot
        cubit.emit(
          createStateWithPluginInUse('/programs/plug-ins/test_plugin.o'),
        );
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('test_plugin.o', testData);

        // Assert - newPreset should be called to release plugin locks
        verify(() => mockDisting.requestNewPreset()).called(1);
      },
    );

    test(
      'reloads previous preset after C++ plugin installation when plugin was in use',
      () async {
        // Arrange - plugin is currently used by a slot
        cubit.emit(
          createStateWithPluginInUse('/programs/plug-ins/test_plugin.o'),
        );
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('test_plugin.o', testData);

        // Assert - loadPreset should be called with the original preset path
        verify(
          () => mockDisting.requestLoadPreset('/presets/Test.json', false),
        ).called(1);
      },
    );

    test(
      'skips preset dance when C++ plugin is NOT in use by any slot',
      () async {
        // Arrange - plugin exists but no slot uses it
        cubit.emit(
          createStateWithPluginNotInUse('/programs/plug-ins/test_plugin.o'),
        );
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('test_plugin.o', testData);

        // Assert - newPreset should NOT be called since plugin isn't in use
        verifyNever(() => mockDisting.requestNewPreset());
        verifyNever(() => mockDisting.requestLoadPreset(any(), any()));
        // But rescan should still be called
        verify(() => mockDisting.requestRescanPlugins()).called(1);
      },
    );

    test(
      'skips preset dance when installing a new C++ plugin (not yet in algorithms list)',
      () async {
        // Arrange - empty state, plugin doesn't exist yet
        cubit.emit(createSynchronizedState());
        final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

        // Act
        await cubit.installPlugin('brand_new_plugin.o', testData);

        // Assert - newPreset should NOT be called for new plugins
        verifyNever(() => mockDisting.requestNewPreset());
        verifyNever(() => mockDisting.requestLoadPreset(any(), any()));
        // But rescan should still be called
        verify(() => mockDisting.requestRescanPlugins()).called(1);
      },
    );

    test('does NOT create blank preset for .lua files', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('test_script.lua', testData);

      // Assert - newPreset should NOT be called for non-C++ plugins
      verifyNever(() => mockDisting.requestNewPreset());
      verifyNever(() => mockDisting.requestLoadPreset(any(), any()));
    });

    test('does NOT create blank preset for .3pot files', () async {
      // Arrange
      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act
      await cubit.installPlugin('test_script.3pot', testData);

      // Assert - newPreset should NOT be called for non-C++ plugins
      verifyNever(() => mockDisting.requestNewPreset());
      verifyNever(() => mockDisting.requestLoadPreset(any(), any()));
    });

    test('continues successfully even if database recording fails', () async {
      // Arrange - make DB recording throw
      when(
        () => mockPluginInstallationsDao.recordPluginByPath(
          installationPath: any(named: 'installationPath'),
          pluginName: any(named: 'pluginName'),
          pluginType: any(named: 'pluginType'),
          totalBytes: any(named: 'totalBytes'),
          pluginId: any(named: 'pluginId'),
          pluginVersion: any(named: 'pluginVersion'),
        ),
      ).thenThrow(Exception('Database error'));

      cubit.emit(createSynchronizedState());
      final testData = Uint8List.fromList([0x01, 0x02, 0x03]);

      // Act - should not throw despite DB error
      await cubit.installPlugin('test.lua', testData);

      // Assert - upload was still called (install proceeded despite DB error)
      verify(
        () => mockDisting.requestFileUploadChunk(
          any(),
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      ).called(greaterThan(0));
    });
  });
}
