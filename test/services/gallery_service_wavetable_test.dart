import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';

class MockSettingsService extends Mock implements SettingsService {}

GalleryPlugin _plugin({String? downloadUrl}) => GalleryPlugin(
  id: 'wavetable-test',
  name: 'Wavetable test',
  description: 'Bundled dependency fixture',
  type: GalleryPluginType.cpp,
  author: 'author',
  repository: const PluginRepository(
    owner: 'owner',
    name: 'repo',
    url: 'https://example.invalid/owner/repo',
  ),
  releases: const PluginReleases(latest: 'v1.0.0'),
  installation: PluginInstallation(
    targetPath: 'programs/plug-ins',
    sourceDirectoryPath: 'release',
    extractPattern: r'\.o$',
    downloadUrl: downloadUrl,
  ),
);

List<int> _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late GalleryService service;

  setUp(() {
    final settings = MockSettingsService();
    service = GalleryService(settingsService: settings);
  });

  tearDown(() => service.dispose());

  test(
    'extracts root wavetables before source and plugin-only filters',
    () async {
      final result = await service.extractArchiveForTesting(
        _zip({
          'release/plugin.o': [1],
          'wavetables/Bank.WAV': [2, 3],
          'Wavetables/Folder/Slice.wav': [4],
          'samples/Drum.wav': [5],
          'programs/helper/companion.lua': [6],
          'release/README.md': [7],
          'other/wavetables/ignored.wav': [8],
          'my_wavetables/ignored.wav': [9],
          'wavetables.txt': [10],
        }),
        _plugin(),
      );

      expect(result.pluginFiles.map((entry) => entry.key), [
        'programs/helper/companion.lua',
        'plugin.o',
      ]);
      expect(result.sampleFiles.map((entry) => entry.key), [
        'wavetables/Bank.WAV',
        'Wavetables/Folder/Slice.wav',
        'samples/Drum.wav',
      ]);
      expect(result.sampleFiles.first.value, [2, 3]);
      expect(result.totalFileCount, 5);
      expect(result.hasSamples, isTrue);
    },
  );

  test(
    'installs canonical SD roots, preserving names, bytes and skips',
    () async {
      final plugins = <String>[];
      final dependencies = <String, List<int>>{};
      final events = <String>[];
      final progress = <double>[];
      final result = await service.installPlugin(
        _plugin(),
        cachedArchiveBytes: _zip({
          'release/plugin.o': [1],
          '/WAVETABLES/Bank.WAV': [2, 3],
          r'wavetables\Folder\Slice.wav': [4],
          'Samples/Existing.wav': [5],
          'wavetables/Existing.wav': [6],
        }),
        distingInstallPlugin:
            (
              fileName,
              fileData, {
              onProgress,
              galleryPluginId,
              galleryPluginVersion,
            }) async {
              plugins.add(fileName);
              events.add('plugin');
            },
        distingInstallSample: (target, data, {onProgress}) async {
          dependencies[target] = data;
          events.add('dependency');
          onProgress?.call(1.0);
          return !target.endsWith('/Existing.wav');
        },
        onProgress: (phase, value) => progress.add(value),
      );

      expect(plugins, ['plugin.o']);
      expect(events.first, 'plugin');
      expect(dependencies, {
        '/wavetables/Bank.WAV': [2, 3],
        '/wavetables/Folder/Slice.wav': [4],
        '/samples/Existing.wav': [5],
        '/wavetables/Existing.wav': [6],
      });
      expect(result, isNotNull);
      expect(result!.installedSamples, [
        '/wavetables/Bank.WAV',
        '/wavetables/Folder/Slice.wav',
      ]);
      expect(result.skippedSamples, [
        '/samples/Existing.wav',
        '/wavetables/Existing.wav',
      ]);
      expect(result.failedSamples, isEmpty);
      expect(progress.last, 1.0);
      expect(progress, orderedEquals([...progress]..sort()));
    },
  );

  test(
    'reports failed wavetables after retries and continues other data',
    () async {
      var attempts = 0;
      final result = await service.installPlugin(
        _plugin(),
        cachedArchiveBytes: _zip({
          'release/plugin.o': [1],
          'wavetables/Failed.wav': [2],
          'samples/Ok.wav': [3],
        }),
        distingInstallPlugin:
            (
              fileName,
              fileData, {
              onProgress,
              galleryPluginId,
              galleryPluginVersion,
            }) async {},
        distingInstallSample: (target, data, {onProgress}) async {
          if (target == '/wavetables/Failed.wav') {
            attempts++;
            throw StateError('upload failed');
          }
          return true;
        },
      );

      expect(attempts, 3);
      expect(result!.installedSamples, ['/samples/Ok.wav']);
      expect(result.failedSamples.keys, ['/wavetables/Failed.wav']);
      expect(result.skippedSamples, isEmpty);
    },
  );

  test('does not route bundled data through the plugin callback', () async {
    final plugins = <String>[];
    final result = await service.installPlugin(
      _plugin(),
      cachedArchiveBytes: _zip({
        'release/plugin.o': [1],
        'wavetables/Bank.wav': [2],
        'wavetables/not-a-plugin.o': [3],
      }),
      distingInstallPlugin:
          (
            fileName,
            fileData, {
            onProgress,
            galleryPluginId,
            galleryPluginVersion,
          }) async => plugins.add(fileName),
    );

    expect(plugins, ['plugin.o']);
    expect(result, isNull); // Optional dependency callback remains optional.
  });

  for (final invalidPath in [
    'wavetables/../outside.wav',
    r'wavetables\..\outside.wav',
    'wavetables/C:/outside.wav',
    'wavetables/bad\u0000.wav',
  ]) {
    test(
      'rejects unsafe archive path before any upload: $invalidPath',
      () async {
        var uploads = 0;
        await expectLater(
          service.installPlugin(
            _plugin(),
            cachedArchiveBytes: _zip({
              'release/plugin.o': [1],
              invalidPath: [2],
            }),
            distingInstallPlugin:
                (
                  fileName,
                  fileData, {
                  onProgress,
                  galleryPluginId,
                  galleryPluginVersion,
                }) async => uploads++,
            distingInstallSample: (target, data, {onProgress}) async {
              uploads++;
              return true;
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(uploads, 0);
      },
    );
  }

  test(
    'ignores symbolic links rather than installing link target text',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('release/plugin.o', [1]))
        ..addFile(ArchiveFile.bytes('wavetables/Bank.wav', [2]))
        ..addFile(
          ArchiveFile.string('wavetables/link.wav', '../../outside.wav')
            ..mode = 0xa1ff,
        );
      final bytes = ZipEncoder().encode(archive);
      // ZipEncoder writes DOS creator metadata even with Unix mode bits. Mark
      // these known central-directory headers as Unix, as a real symlink ZIP is.
      for (var i = 0; i + 5 < bytes.length; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4b &&
            bytes[i + 2] == 0x01 &&
            bytes[i + 3] == 0x02) {
          bytes[i + 5] = 3;
        }
      }
      // Verify the encoded fixture really is a Unix symlink after decoding.
      expect(ZipDecoder().decodeBytes(bytes).last.isSymbolicLink, isTrue);

      final result = await service.extractArchiveForTesting(bytes, _plugin());

      expect(result.sampleFiles.map((entry) => entry.key), [
        'wavetables/Bank.wav',
      ]);
      expect(result.pluginFiles.map((entry) => entry.key), ['plugin.o']);
    },
  , tags: ['regression']);

  test('wavetable-only archive still requires an installable plugin', () async {
    await expectLater(
      service.extractArchiveForTesting(
        _zip({
          'wavetables/Bank.wav': [1],
        }),
        _plugin(),
      ),
      throwsA(isA<GalleryException>()),
    );
  });

  test(
    'queued install uses the same wavetable path and result handling',
    () async {
      final bytes = _zip({
        'release/plugin.o': [1],
        'Wavetables/Bank.wav': [2, 3],
        'wavetables/Existing.wav': [4],
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final plugin = _plugin(
        downloadUrl: 'http://${server.address.host}:${server.port}/plugin.zip',
      );
      await service.addToQueue(plugin);
      final uploaded = <String, Uint8List>{};
      final errors = <String>[];
      final results = <SampleInstallationResult>[];
      var completed = false;

      await service.installQueuedPlugins(
        distingInstallPlugin:
            (
              fileName,
              fileData, {
              onProgress,
              galleryPluginId,
              galleryPluginVersion,
            }) async => expect(fileName, 'plugin.o'),
        distingInstallSample: (target, data, {onProgress}) async {
          uploaded[target] = data;
          return !target.endsWith('/Existing.wav');
        },
        onPluginError: (_, error) => errors.add(error),
        onPluginComplete: (_) => completed = true,
        onSampleInstallComplete: (_, result) => results.add(result),
      );

      expect(errors, isEmpty);
      expect(completed, isTrue);
      expect(service.installQueue, isEmpty);
      expect(uploaded.keys, [
        '/wavetables/Bank.wav',
        '/wavetables/Existing.wav',
      ]);
      expect(uploaded['/wavetables/Bank.wav'], [2, 3]);
      expect(results.single.installedSamples, ['/wavetables/Bank.wav']);
      expect(results.single.skippedSamples, ['/wavetables/Existing.wav']);
    },
  );
}
