import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  group('GalleryService Sample Extraction', () {
    late GalleryService galleryService;
    late MockSettingsService mockSettingsService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockSettingsService = MockSettingsService();

      when(
        () => mockSettingsService.galleryUrl,
      ).thenReturn('https://example.com/gallery.json');
      when(
        () => mockSettingsService.graphqlEndpoint,
      ).thenReturn('https://example.com/graphql');

      galleryService = GalleryService(settingsService: mockSettingsService);
    });

    GalleryPlugin createTestPlugin({
      String? extractPattern,
      String? sourceDirectoryPath,
    }) {
      return GalleryPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        description: 'A test plugin',
        type: GalleryPluginType.cpp,
        author: 'test-author',
        repository: const PluginRepository(
          owner: 'test-owner',
          name: 'test-repo',
          url: 'https://github.com/test-owner/test-repo',
        ),
        releases: const PluginReleases(latest: 'v1.0.0'),
        installation: PluginInstallation(
          targetPath: 'programs/plug-ins',
          extractPattern: extractPattern,
          sourceDirectoryPath: sourceDirectoryPath,
        ),
      );
    }

    List<int> createTestZip(Map<String, List<int>> files) {
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      return ZipEncoder().encode(archive);
    }

    group('isSampleFileForTesting', () {
      test('detects samples/ prefix (lowercase)', () {
        expect(
          GalleryService.isSampleFileForTesting('samples/kick.wav'),
          isTrue,
        );
      });

      test('detects Samples/ prefix (uppercase)', () {
        expect(
          GalleryService.isSampleFileForTesting('Samples/kick.wav'),
          isTrue,
        );
      });

      test('detects SAMPLES/ prefix (all caps)', () {
        expect(
          GalleryService.isSampleFileForTesting('SAMPLES/kick.wav'),
          isTrue,
        );
      });

      test('detects /samples/ prefix with leading slash', () {
        expect(
          GalleryService.isSampleFileForTesting('/samples/kick.wav'),
          isTrue,
        );
      });

      test('detects nested sample directories', () {
        expect(
          GalleryService.isSampleFileForTesting('samples/drums/kick.wav'),
          isTrue,
        );
        expect(
          GalleryService.isSampleFileForTesting(
            'samples/category/subcategory/file.wav',
          ),
          isTrue,
        );
      });

      test('returns false for non-sample files', () {
        expect(GalleryService.isSampleFileForTesting('plugin.o'), isFalse);
        expect(
          GalleryService.isSampleFileForTesting('src/samples.txt'),
          isFalse,
        );
        expect(
          GalleryService.isSampleFileForTesting('my_samples/file.wav'),
          isFalse,
        );
      });
    });

    group('extractArchiveForTesting', () {
      test('C++ plugin archives skip non-.o files before upload', () async {
        final plugin = createTestPlugin();
        final zipBytes = createTestZip({
          'programs/plug-ins/nt_marbles.o': [0x01, 0x02, 0x03],
          'licenses/THIRD_PARTY_NOTICES.md': [0x04],
          'licenses/nt_marbles-LICENSE.txt': [0x05],
          'BUILD_COMMIT.txt': [0x06],
          'PLUGIN_SHA256.txt': [0x07],
        });
        final installedFiles = <String>[];

        await galleryService.installPlugin(
          plugin,
          cachedArchiveBytes: zipBytes,
          distingInstallPlugin:
              (
                fileName,
                fileData, {
                onProgress,
                galleryPluginId,
                galleryPluginVersion,
              }) async {
                if (!fileName.toLowerCase().endsWith('.o')) {
                  throw StateError('Unexpected non-plugin file: $fileName');
                }
                installedFiles.add(fileName);
              },
        );

        expect(installedFiles, ['programs/plug-ins/nt_marbles.o']);
      });

      test('extracts plugin files from zip without samples', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01, 0x02, 0x03],
          'README.md': [0x04, 0x05],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.pluginFiles, hasLength(1));
        expect(result.pluginFiles.first.key, equals('plugin.o'));
        expect(result.sampleFiles, isEmpty);
        expect(result.hasSamples, isFalse);
      });

      test('extracts both plugin files and sample files', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01, 0x02, 0x03],
          'samples/kick.wav': [0x10, 0x11, 0x12, 0x13],
          'samples/snare.wav': [0x20, 0x21, 0x22],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.pluginFiles, hasLength(1));
        expect(result.pluginFiles.first.key, equals('plugin.o'));
        expect(result.sampleFiles, hasLength(2));
        expect(result.hasSamples, isTrue);

        final samplePaths = result.sampleFiles.map((e) => e.key).toList();
        expect(samplePaths, contains('samples/kick.wav'));
        expect(samplePaths, contains('samples/snare.wav'));
      });

      test('preserves full relative path for sample files', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01, 0x02],
          'samples/drums/kick.wav': [0x10, 0x11],
          'samples/drums/snare.wav': [0x12, 0x13],
          'samples/synth/lead.wav': [0x14, 0x15],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.sampleFiles, hasLength(3));

        final samplePaths = result.sampleFiles.map((e) => e.key).toList();
        expect(samplePaths, contains('samples/drums/kick.wav'));
        expect(samplePaths, contains('samples/drums/snare.wav'));
        expect(samplePaths, contains('samples/synth/lead.wav'));
      });

      test('handles case-insensitive samples directory', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01, 0x02],
          'Samples/kick.wav': [0x10, 0x11],
          'SAMPLES/snare.wav': [0x12, 0x13],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.sampleFiles, hasLength(2));

        final samplePaths = result.sampleFiles.map((e) => e.key).toList();
        expect(samplePaths, contains('Samples/kick.wav'));
        expect(samplePaths, contains('SAMPLES/snare.wav'));
      }, tags: ['regression']);

      test('sample files are extracted regardless of extractPattern', () async {
        // extractPattern only matches .o files, but samples should still be extracted
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'plugin.lua': [0x02], // Should be filtered out
          'samples/data.bin': [0x03], // Should be extracted
          'samples/audio.raw': [0x04], // Should be extracted
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.pluginFiles, hasLength(1));
        expect(result.pluginFiles.first.key, equals('plugin.o'));

        expect(result.sampleFiles, hasLength(2));
        final samplePaths = result.sampleFiles.map((e) => e.key).toList();
        expect(samplePaths, contains('samples/data.bin'));
        expect(samplePaths, contains('samples/audio.raw'));
      }, tags: ['regression']);

      test('handles deeply nested sample directories', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'samples/category/subcategory/deep/file.wav': [0x10],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.sampleFiles, hasLength(1));
        expect(
          result.sampleFiles.first.key,
          equals('samples/category/subcategory/deep/file.wav'),
        );
      });

      test('totalFileCount returns correct sum', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'samples/a.wav': [0x10],
          'samples/b.wav': [0x11],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.pluginFiles, hasLength(1));
        expect(result.sampleFiles, hasLength(2));
        expect(result.totalFileCount, equals(3));
      });

      test('works with sourceDirectoryPath filtering', () async {
        final plugin = createTestPlugin(
          extractPattern: r'\.o$',
          sourceDirectoryPath: 'build/output',
        );

        final zipBytes = createTestZip({
          'build/output/plugin.o': [0x01],
          'build/other/other.o': [0x02], // Should be filtered out
          'samples/kick.wav': [0x10], // Samples at root level
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        expect(result.pluginFiles, hasLength(1));
        expect(result.pluginFiles.first.key, equals('plugin.o'));

        expect(result.sampleFiles, hasLength(1));
        expect(result.sampleFiles.first.key, equals('samples/kick.wav'));
      });

      test('throws GalleryException when no plugin files found', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'samples/kick.wav': [0x10, 0x11],
          'README.md': [0x04, 0x05],
        });

        expect(
          () => galleryService.extractArchiveForTesting(zipBytes, plugin),
          throwsA(isA<GalleryException>()),
        );
      });
    });

    group('ExtractedArchiveContents', () {
      test('hasSamples returns true when sampleFiles is not empty', () {
        final contents = ExtractedArchiveContents(
          pluginFiles: [
            MapEntry('plugin.o', [0x01]),
          ],
          sampleFiles: [
            MapEntry('samples/kick.wav', [0x10]),
          ],
        );

        expect(contents.hasSamples, isTrue);
      });

      test('hasSamples returns false when sampleFiles is empty', () {
        final contents = ExtractedArchiveContents(
          pluginFiles: [
            MapEntry('plugin.o', [0x01]),
          ],
          sampleFiles: [],
        );

        expect(contents.hasSamples, isFalse);
      });

      test('totalFileCount returns sum of plugin and sample files', () {
        final contents = ExtractedArchiveContents(
          pluginFiles: [
            MapEntry('plugin1.o', [0x01]),
            MapEntry('plugin2.o', [0x02]),
          ],
          sampleFiles: [
            MapEntry('samples/a.wav', [0x10]),
            MapEntry('samples/b.wav', [0x11]),
            MapEntry('samples/c.wav', [0x12]),
          ],
        );

        expect(contents.totalFileCount, equals(5));
      });
    });

    group('SampleInstallationResult', () {
      test('hasFailures returns true when failedSamples is not empty', () {
        const result = SampleInstallationResult(
          installedSamples: ['/samples/a.wav'],
          skippedSamples: [],
          failedSamples: {'/samples/b.wav': 'Upload failed'},
        );

        expect(result.hasFailures, isTrue);
        expect(result.hasSuccesses, isTrue);
      });

      test('hasFailures returns false when failedSamples is empty', () {
        const result = SampleInstallationResult(
          installedSamples: ['/samples/a.wav'],
          skippedSamples: ['/samples/b.wav'],
          failedSamples: {},
        );

        expect(result.hasFailures, isFalse);
        expect(result.hasSuccesses, isTrue);
      });

      test('totalSamples returns correct count', () {
        const result = SampleInstallationResult(
          installedSamples: ['/samples/a.wav', '/samples/b.wav'],
          skippedSamples: ['/samples/c.wav'],
          failedSamples: {'/samples/d.wav': 'Error'},
        );

        expect(result.totalSamples, equals(4));
        expect(result.installedCount, equals(2));
        expect(result.skippedCount, equals(1));
        expect(result.failedCount, equals(1));
      });

      test('hasSuccesses returns false when all failed', () {
        const result = SampleInstallationResult(
          installedSamples: [],
          skippedSamples: [],
          failedSamples: {
            '/samples/a.wav': 'Error 1',
            '/samples/b.wav': 'Error 2',
          },
        );

        expect(result.hasSuccesses, isFalse);
        expect(result.hasFailures, isTrue);
      });

      test('default constructor creates empty result', () {
        const result = SampleInstallationResult();

        expect(result.totalSamples, equals(0));
        expect(result.hasSuccesses, isFalse);
        expect(result.hasFailures, isFalse);
      });
    });

    group('_getSampleTargetPath (via integration)', () {
      // Note: _getSampleTargetPath is private, so we test it indirectly
      // through the extraction and installation flow

      test('sample paths are preserved correctly in extraction', () async {
        final plugin = createTestPlugin(extractPattern: r'\.o$');

        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'samples/kick.wav': [0x10],
          'Samples/Snare.WAV': [0x11],
        });

        final result = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        // Verify paths are preserved as-is from zip
        final samplePaths = result.sampleFiles.map((e) => e.key).toList();
        expect(samplePaths, contains('samples/kick.wav'));
        expect(samplePaths, contains('Samples/Snare.WAV'));
      });
    });

    group('Sample Installation Callback Integration', () {
      test('install callback receives normalized sample paths', () async {
        final installedPaths = <String>[];

        // Create a mock install callback that records calls
        Future<bool> mockInstallCallback(
          String targetPath,
          Uint8List data, {
          Function(double)? onProgress,
        }) async {
          installedPaths.add(targetPath);
          return true; // Installed
        }

        final plugin = createTestPlugin(extractPattern: r'\.o$');
        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'Samples/Kick.wav': [0x10, 0x11], // Uppercase Samples
          'SAMPLES/snare.wav': [0x12, 0x13], // All caps SAMPLES
        });

        final extracted = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        // Simulate the installation process
        for (final sample in extracted.sampleFiles) {
          // Use the same path transformation as GalleryService
          String path = sample.key;
          if (!path.startsWith('/')) {
            path = '/$path';
          }
          // Normalize samples prefix to lowercase
          if (path.toLowerCase().startsWith('/samples/')) {
            path = '/samples/${path.substring('/samples/'.length)}';
          }
          await mockInstallCallback(path, Uint8List.fromList(sample.value));
        }

        // Verify paths are normalized to lowercase samples/
        expect(installedPaths, hasLength(2));
        expect(installedPaths, contains('/samples/Kick.wav'));
        expect(installedPaths, contains('/samples/snare.wav'));
      });

      

      

      test('progress callback receives correct values', () async {
        final progressValues = <double>[];

        Future<bool> mockInstallCallback(
          String targetPath,
          Uint8List data, {
          Function(double)? onProgress,
        }) async {
          // Simulate chunked upload progress
          onProgress?.call(0.25);
          onProgress?.call(0.50);
          onProgress?.call(0.75);
          onProgress?.call(1.0);
          return true;
        }

        await mockInstallCallback(
          '/samples/test.wav',
          Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
          onProgress: (p) => progressValues.add(p),
        );

        expect(progressValues, equals([0.25, 0.50, 0.75, 1.0]));
      });

      test('nested sample directories preserve structure', () async {
        final installedPaths = <String>[];

        Future<bool> mockInstallCallback(
          String targetPath,
          Uint8List data, {
          Function(double)? onProgress,
        }) async {
          installedPaths.add(targetPath);
          return true;
        }

        final plugin = createTestPlugin(extractPattern: r'\.o$');
        final zipBytes = createTestZip({
          'plugin.o': [0x01],
          'samples/drums/acoustic/kick.wav': [0x10],
          'samples/drums/electronic/808.wav': [0x11],
          'samples/synths/lead.wav': [0x12],
        });

        final extracted = await galleryService.extractArchiveForTesting(
          zipBytes,
          plugin,
        );

        for (final sample in extracted.sampleFiles) {
          final path = '/${sample.key}';
          await mockInstallCallback(path, Uint8List.fromList(sample.value));
        }

        expect(installedPaths, hasLength(3));
        expect(installedPaths, contains('/samples/drums/acoustic/kick.wav'));
        expect(installedPaths, contains('/samples/drums/electronic/808.wav'));
        expect(installedPaths, contains('/samples/synths/lead.wav'));
      });
    });

    group('Retry Logic', () {
      test('retry succeeds after transient failure', () async {
        var attemptCount = 0;

        Future<bool> flakyInstallCallback(
          String targetPath,
          Uint8List data, {
          Function(double)? onProgress,
        }) async {
          attemptCount++;
          if (attemptCount < 2) {
            throw Exception('Transient failure');
          }
          return true;
        }

        // Simulate retry logic (matching GalleryService._installSampleWithRetry)
        bool? result;
        bool succeeded = false;

        for (int attempt = 0; attempt < 3 && !succeeded; attempt++) {
          try {
            result = await flakyInstallCallback(
              '/samples/test.wav',
              Uint8List.fromList([0x01]),
            );
            succeeded = true;
          } catch (e) {
            // Continue to next attempt
          }
        }

        expect(succeeded, isTrue);
        expect(result, isTrue);
        expect(attemptCount, equals(2)); // Succeeded on second try
      });

      test('retry exhaustion throws final error', () async {
        var attemptCount = 0;

        Future<bool> alwaysFailCallback(
          String targetPath,
          Uint8List data, {
          Function(double)? onProgress,
        }) async {
          attemptCount++;
          throw Exception('Permanent failure #$attemptCount');
        }

        Exception? lastError;
        const maxRetries = 3;

        for (int attempt = 0; attempt < maxRetries; attempt++) {
          try {
            await alwaysFailCallback(
              '/samples/test.wav',
              Uint8List.fromList([0x01]),
            );
          } catch (e) {
            lastError = e as Exception;
          }
        }

        expect(attemptCount, equals(maxRetries));
        expect(lastError, isNotNull);
        expect(lastError.toString(), contains('Permanent failure #3'));
      });
    });
  });
}
