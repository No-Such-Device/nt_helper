import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/gallery/gallery_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockPluginInstallationsDao extends Mock
    implements PluginInstallationsDao {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockSettingsService extends Mock implements SettingsService {}

class MockGalleryService extends Mock implements GalleryService {}

const _root = '/programs/plug-ins';
const _rootFile = '$_root/seq.o';
const _subFile = '$_root/sub/seq.o';

const _plugin = GalleryPlugin(
  id: 'seq',
  name: 'Seq',
  description: 'Test plugin',
  type: GalleryPluginType.cpp,
  author: 'author',
  repository: PluginRepository(
    owner: 'owner',
    name: 'repo',
    url: 'https://github.com/owner/repo',
  ),
  releases: PluginReleases(latest: 'v1.0.0'),
  installation: PluginInstallation(targetPath: 'programs/plug-ins'),
);

dynamic _noopInstall(
  String fileName,
  Uint8List fileData, {
  Function(double)? onProgress,
  String? galleryPluginId,
  String? galleryPluginVersion,
}) => null;

void main() {
  late DistingCubit distingCubit;
  late MockDistingMidiManager mockDisting;
  late MockPluginInstallationsDao mockInstallationsDao;
  late GalleryService galleryService;
  late Uint8List pluginBytes;
  late List<int> archive;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_plugin);
    registerFallbackValue(_noopInstall);
    pluginBytes = File(
      'test/fixtures/plugins/directionalSequencer.o',
    ).readAsBytesSync();
    archive = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('sub/seq.o', pluginBytes.length, pluginBytes)),
    );
  });

  setUp(() {
    final mockDatabase = MockAppDatabase();
    final mockMetadataDao = MockMetadataDao();
    mockInstallationsDao = MockPluginInstallationsDao();
    mockDisting = MockDistingMidiManager();

    when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
    when(
      () => mockDatabase.pluginInstallationsDao,
    ).thenReturn(mockInstallationsDao);
    when(
      () => mockMetadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    when(
      () => mockMetadataDao.invalidateAlgorithmInfoCache(),
    ).thenAnswer((_) async {});
    when(
      () => mockInstallationsDao.recordPluginByPath(
        installationPath: any(named: 'installationPath'),
        pluginName: any(named: 'pluginName'),
        pluginType: any(named: 'pluginType'),
        totalBytes: any(named: 'totalBytes'),
        pluginId: any(named: 'pluginId'),
        pluginVersion: any(named: 'pluginVersion'),
      ),
    ).thenAnswer((_) async => 1);

    when(() => mockDisting.requestWake()).thenAnswer((_) async {});
    when(
      () => mockDisting.requestDirectoryListing(any()),
    ).thenAnswer((_) async => DirectoryListing(entries: []));
    // The root always holds a same-named, same-GUID duplicate.
    when(() => mockDisting.requestDirectoryListing(_root)).thenAnswer(
      (_) async => DirectoryListing(
        entries: [
          DirectoryEntry(
            name: 'seq.o',
            attributes: 0x20,
            date: 0,
            time: 0,
            size: 1,
          ),
        ],
      ),
    );
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
    when(
      () => mockDisting.requestNumAlgorithmsInPreset(),
    ).thenAnswer((_) async => 0);
    when(() => mockDisting.requestPresetName()).thenAnswer((_) async => 'Test');

    distingCubit = DistingCubit(mockDatabase, midiCommand: MockMidiCommand());
    distingCubit.emit(
      DistingStateSynchronized(
        disting: mockDisting,
        distingVersion: '1.12.0',
        firmwareVersion: FirmwareVersion('1.12.0'),
        presetName: 'Test',
        algorithms: const [],
        slots: const [],
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

    final settings = MockSettingsService();
    when(
      () => settings.galleryUrl,
    ).thenReturn('https://example.com/gallery.json');
    when(
      () => settings.graphqlEndpoint,
    ).thenReturn('https://example.com/graphql');
    galleryService = GalleryService(settingsService: settings);
  });

  tearDown(() => distingCubit.close());

  Future<List<PluginCleanupOutcome>> installFromGallery() async {
    final outcomes = <PluginCleanupOutcome>[];
    await galleryService.installPlugin(
      _plugin,
      cachedArchiveBytes: archive,
      distingInstallPlugin:
          (
            fileName,
            fileData, {
            onProgress,
            galleryPluginId,
            galleryPluginVersion,
          }) => distingCubit.installPlugin(
            fileName,
            fileData,
            onProgress: onProgress,
            galleryPluginId: galleryPluginId,
            galleryPluginVersion: galleryPluginVersion,
          ),
      onCleanupOutcome: outcomes.add,
    );
    return outcomes;
  }

  group('GalleryService.installPlugin cleanup outcome', () {
    test('subfolder install reports the removed root path', () async {
      final outcomes = await installFromGallery();

      expect(outcomes, hasLength(1));
      expect((outcomes.single as PluginCleanupRemoved).path, _rootFile);
      verify(() => mockDisting.requestFileDelete(_rootFile)).called(1);
    });

    test(
      'fallback to a root upload issues no cleanup and reports none',
      () async {
        when(
          () => mockDisting.requestFileUploadChunk(
            _subFile,
            any(),
            any(),
            createAlways: any(named: 'createAlways'),
          ),
        ).thenAnswer((_) async => SdCardStatus(success: false, message: 'no'));

        final outcomes = await installFromGallery();

        expect(outcomes, isEmpty);
        verify(
          () => mockDisting.requestFileUploadChunk(
            _rootFile,
            any(),
            any(),
            createAlways: any(named: 'createAlways'),
          ),
        ).called(greaterThan(0));
        // Only the existing target-directory check lists the root.
        verify(() => mockDisting.requestDirectoryListing(_root)).called(1);
        verifyNever(() => mockDisting.requestFileDownload(any()));
        verifyNever(() => mockDisting.requestFileDelete(any()));
        // Behaves as a normal root install: rescanned and recorded.
        verify(() => mockDisting.requestRescanPlugins()).called(1);
        verify(
          () => mockInstallationsDao.recordPluginByPath(
            installationPath: _rootFile,
            pluginName: any(named: 'pluginName'),
            pluginType: any(named: 'pluginType'),
            totalBytes: any(named: 'totalBytes'),
            pluginId: any(named: 'pluginId'),
            pluginVersion: any(named: 'pluginVersion'),
          ),
        ).called(1);
      },
    );
  });

  test('GalleryCubit queue passes the outcome to the UI callback', () async {
    final service = MockGalleryService();
    when(
      () => service.installPlugin(
        any(),
        distingInstallPlugin: any(named: 'distingInstallPlugin'),
        distingInstallSample: any(named: 'distingInstallSample'),
        onProgress: any(named: 'onProgress'),
        cachedArchiveBytes: any(named: 'cachedArchiveBytes'),
        selectedPlugins: any(named: 'selectedPlugins'),
        onCleanupOutcome: any(named: 'onCleanupOutcome'),
      ),
    ).thenAnswer((invocation) async {
      final report =
          invocation.namedArguments[#onCleanupOutcome]
              as void Function(PluginCleanupOutcome)?;
      report?.call(const PluginCleanupDeletionFailed(_rootFile));
      return null;
    });

    final galleryCubit = GalleryCubit(service);
    galleryCubit.emit(
      GalleryState.loaded(
        gallery: Gallery(
          version: '1',
          lastUpdated: DateTime(2026),
          metadata: const GalleryMetadata(
            name: 'g',
            description: 'g',
            maintainer: GalleryMaintainer(name: 'm'),
          ),
          plugins: const [_plugin],
        ),
        filteredPlugins: const [_plugin],
        searchQuery: '',
        showFeaturedOnly: false,
        showVerifiedOnly: false,
      ),
    );

    final received = <PluginCleanupOutcome>[];
    var completed = false;
    galleryCubit.installPlugin(
      _plugin,
      distingInstallPlugin:
          (
            fileName,
            fileData, {
            onProgress,
            galleryPluginId,
            galleryPluginVersion,
          }) async {},
      onCleanupOutcome: received.add,
      onComplete: () => completed = true,
    );
    await pumpEventQueue();

    expect(completed, isTrue);
    expect(received, hasLength(1));
    expect((received.single as PluginCleanupDeletionFailed).path, _rootFile);
    await galleryCubit.close();
  });
}
