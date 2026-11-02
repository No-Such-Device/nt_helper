import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  group('GalleryService Installed Plugin Detection', () {
    late GalleryService galleryService;
    late MockSettingsService mockSettingsService;
    late AppDatabase database;

    setUp(() async {
      // Initialize shared preferences for testing
      SharedPreferences.setMockInitialValues({});

      // Create in-memory database for testing
      database = AppDatabase.forTesting(NativeDatabase.memory());

      mockSettingsService = MockSettingsService();

      // Mock the settings service methods
      when(
        () => mockSettingsService.galleryUrl,
      ).thenReturn('https://example.com/gallery.json');
      when(
        () => mockSettingsService.graphqlEndpoint,
      ).thenReturn('https://example.com/graphql');

      galleryService = GalleryService(
        settingsService: mockSettingsService,
        database: database,
      );
    });

    tearDown(() async {
      await database.close();
    });

    GalleryPlugin createTestPlugin({
      required String id,
      required String name,
      String? guid,
    }) {
      return GalleryPlugin(
        id: id,
        name: name,
        description: 'Test plugin',
        type: GalleryPluginType.lua,
        author: 'test-author',
        repository: const PluginRepository(
          owner: 'test-owner',
          name: 'test-repo',
          url: 'https://github.com/test-owner/test-repo',
        ),
        releases: const PluginReleases(latest: 'v1.0.0'),
        installation: const PluginInstallation(targetPath: '/programs/lua'),
        guid: guid,
      );
    }

    Gallery createTestGallery(List<GalleryPlugin> plugins) {
      return Gallery(
        version: '2.0.0',
        lastUpdated: DateTime.now(),
        metadata: const GalleryMetadata(
          name: 'Test Gallery',
          description: 'Test gallery for unit tests',
          maintainer: GalleryMaintainer(name: 'Test'),
        ),
        plugins: plugins,
      );
    }

    group('Database-based detection', () {
      test('detects plugin installed via gallery (in database)', () async {
        // Create a plugin and add it to database
        final plugin = createTestPlugin(
          id: 'test-plugin',
          name: 'Test Plugin',
          guid: 'TEST',
        );

        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'v1.0.0',
          installationPath: '/programs/lua',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, contains('test-plugin'));
        expect(updateInfo['test-plugin']!.installedVersion, equals('v1.0.0'));
        expect(updateInfo['test-plugin']!.updateAvailable, isFalse);
      });

      test('shows update available when newer version exists', () async {
        final plugin = createTestPlugin(
          id: 'test-plugin',
          name: 'Test Plugin',
          guid: 'TEST',
        );

        // Install version 1.0.0
        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'v0.9.0', // Older version
          installationPath: '/programs/lua',
        );

        // Gallery has version 1.0.0
        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, contains('test-plugin'));
        expect(updateInfo['test-plugin']!.installedVersion, equals('v0.9.0'));
        expect(updateInfo['test-plugin']!.availableVersion, equals('v1.0.0'));
        expect(updateInfo['test-plugin']!.updateAvailable, isTrue);
      });

      test('does not detect uninstalled plugins', () async {
        final plugin = createTestPlugin(
          id: 'test-plugin',
          name: 'Test Plugin',
          guid: 'TEST',
        );

        // Plugin not in database
        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, isEmpty);
      });
    });

    group('Device GUID-based detection', () {
      test(
        'detects manually installed plugin via device GUID with update available',
        () async {
          final plugin = createTestPlugin(
            id: 'manual-plugin',
            name: 'Manual Plugin',
            guid: 'MNPL',
          );

          // Plugin not in database, but on device
          final gallery = createTestGallery([plugin]);
          final devicePluginGuids = {'MNPL'}; // Plugin is on device

          final updateInfo = await galleryService.compareWithInstalledVersions(
            gallery,
            devicePluginGuids: devicePluginGuids,
          );

          expect(updateInfo, contains('manual-plugin'));
          expect(
            updateInfo['manual-plugin']!.installedVersion,
            equals('unknown'),
          );
          // Unknown version should suggest update available
          expect(updateInfo['manual-plugin']!.updateAvailable, isTrue);
        },
      );

      test('does not auto-cache manually installed plugin in database', () async {
        // Note: Database recording is now handled by DistingCubit.installPlugin(),
        // not by the gallery service's GUID detection. This test verifies the
        // gallery service no longer auto-caches.
        final plugin = createTestPlugin(
          id: 'manual-plugin',
          name: 'Manual Plugin',
          guid: 'MNPL',
        );

        final gallery = createTestGallery([plugin]);
        final devicePluginGuids = {'MNPL'};

        // Detection - should NOT cache in database
        await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: devicePluginGuids,
        );

        // Verify nothing was cached (recording is now done by cubit)
        final cached = await database.pluginInstallationsDao
            .getAllInstalledPlugins();
        expect(cached, isEmpty);
      }, tags: ['regression']);

      test('GUID detection works without database caching', () async {
        // Note: Database recording is now handled by DistingCubit.installPlugin(),
        // not by GUID detection. This test verifies GUID detection still works
        // but doesn't create database records.
        final plugin = createTestPlugin(
          id: 'detected-plugin',
          name: 'Detected Plugin',
          guid: 'DTCT',
        );

        final gallery = createTestGallery([plugin]);
        final devicePluginGuids = {'DTCT'};

        // First check - detects via GUID
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: devicePluginGuids,
        );

        expect(updateInfo, contains('detected-plugin'));
        expect(
          updateInfo['detected-plugin']!.installedVersion,
          equals('unknown'),
        );
        expect(updateInfo['detected-plugin']!.updateAvailable, isTrue);

        // Verify no database record was created
        final cached = await database.pluginInstallationsDao
            .getAllInstalledPlugins();
        expect(cached, isEmpty);
      });

      test('does not detect plugin without matching GUID', () async {
        final plugin = createTestPlugin(
          id: 'other-plugin',
          name: 'Other Plugin',
          guid: 'OTHR',
        );

        final gallery = createTestGallery([plugin]);
        final devicePluginGuids = {'DIFF'}; // Different GUID

        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: devicePluginGuids,
        );

        expect(updateInfo, isEmpty);
      });

      test('handles plugins without GUIDs gracefully', () async {
        final plugin = createTestPlugin(
          id: 'no-guid-plugin',
          name: 'No GUID Plugin',
          guid: null, // No GUID
        );

        final gallery = createTestGallery([plugin]);
        final devicePluginGuids = {'SOME'};

        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: devicePluginGuids,
        );

        expect(updateInfo, isEmpty);
      });
    });

    group('Mixed detection scenarios', () {
      test('prioritizes database version over device GUID detection', () async {
        final plugin = createTestPlugin(
          id: 'mixed-plugin',
          name: 'Mixed Plugin',
          guid: 'MIXD',
        );

        // Plugin in database with specific version
        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'v2.0.0',
          installationPath: '/programs/lua',
        );

        final gallery = createTestGallery([plugin]);
        final devicePluginGuids = {'MIXD'}; // Also on device

        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: devicePluginGuids,
        );

        // Should use database version, not 'unknown'
        expect(updateInfo['mixed-plugin']!.installedVersion, equals('v2.0.0'));
      });

      test(
        'detects multiple plugins with different installation methods',
        () async {
          final galleryPlugin = createTestPlugin(
            id: 'gallery-plugin',
            name: 'Gallery Plugin',
            guid: 'GALL',
          );
          final manualPlugin = createTestPlugin(
            id: 'manual-plugin',
            name: 'Manual Plugin',
            guid: 'MNPL',
          );
          final unknownPlugin = createTestPlugin(
            id: 'unknown-plugin',
            name: 'Unknown Plugin',
            guid: 'UNKN',
          );

          // Gallery plugin in database
          await database.pluginInstallationsDao.recordPluginInstallation(
            plugin: galleryPlugin,
            installedVersion: 'v1.0.0',
            installationPath: '/programs/lua',
          );

          final gallery = createTestGallery([
            galleryPlugin,
            manualPlugin,
            unknownPlugin,
          ]);
          final devicePluginGuids = {'GALL', 'MNPL'}; // Manual plugin on device

          final updateInfo = await galleryService.compareWithInstalledVersions(
            gallery,
            devicePluginGuids: devicePluginGuids,
          );

          // Gallery plugin detected via database
          expect(updateInfo, contains('gallery-plugin'));
          expect(
            updateInfo['gallery-plugin']!.installedVersion,
            equals('v1.0.0'),
          );

          // Manual plugin detected via device GUID (update available for unknown version)
          expect(updateInfo, contains('manual-plugin'));
          expect(
            updateInfo['manual-plugin']!.installedVersion,
            equals('unknown'),
          );
          expect(updateInfo['manual-plugin']!.updateAvailable, isTrue);

          // Unknown plugin not detected
          expect(updateInfo, isNot(contains('unknown-plugin')));
        },
      );
    });

    group('Edge cases', () {
      test('handles empty gallery', () async {
        final gallery = createTestGallery([]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, isEmpty);
      });

      test('handles empty device GUID set', () async {
        final plugin = createTestPlugin(
          id: 'test-plugin',
          name: 'Test Plugin',
          guid: 'TEST',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: {},
        );

        expect(updateInfo, isEmpty);
      });

      test('handles null device GUID set', () async {
        final plugin = createTestPlugin(
          id: 'test-plugin',
          name: 'Test Plugin',
          guid: 'TEST',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
          devicePluginGuids: null,
        );

        expect(updateInfo, isEmpty);
      });
    });

    group('Date-based comparison fallback', () {
      test('uses date comparison when versions are invalid', () async {
        // Create plugin with invalid version but recent updatedAt
        final plugin = GalleryPlugin(
          id: 'date-plugin',
          name: 'Date Plugin',
          description: 'Plugin with invalid version',
          type: GalleryPluginType.lua,
          author: 'test-author',
          repository: const PluginRepository(
            owner: 'test-owner',
            name: 'test-repo',
            url: 'https://github.com/test-owner/test-repo',
          ),
          releases: const PluginReleases(latest: 'invalid-version'),
          installation: const PluginInstallation(targetPath: '/programs/lua'),
          guid: 'DATE',
          updatedAt: DateTime.now(), // Recently updated
        );

        // Install with invalid version 2 days ago
        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'old-invalid-version',
          installationPath: '/programs/lua',
        );

        // Manually update installedAt to 2 days ago
        final installed = await database.pluginInstallationsDao
            .getAllInstalledPlugins();
        final id = installed.first.id;
        await (database.update(
          database.pluginInstallations,
        )..where((tbl) => tbl.id.equals(id))).write(
          PluginInstallationsCompanion(
            installedAt: Value(
              DateTime.now().subtract(const Duration(days: 2)),
            ),
          ),
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        // Should detect update via date comparison
        expect(updateInfo, contains('date-plugin'));
        expect(updateInfo['date-plugin']!.updateAvailable, isTrue);
      }, tags: ['regression']);

      test(
        'no update when gallery updatedAt is older than installation',
        () async {
          final plugin = GalleryPlugin(
            id: 'old-plugin',
            name: 'Old Plugin',
            description: 'Plugin with old updatedAt',
            type: GalleryPluginType.lua,
            author: 'test-author',
            repository: const PluginRepository(
              owner: 'test-owner',
              name: 'test-repo',
              url: 'https://github.com/test-owner/test-repo',
            ),
            releases: const PluginReleases(latest: 'invalid-version'),
            installation: const PluginInstallation(targetPath: '/programs/lua'),
            guid: 'OLDP',
            updatedAt: DateTime.now().subtract(
              const Duration(days: 5),
            ), // Old update
          );

          // Install recently
          await database.pluginInstallationsDao.recordPluginInstallation(
            plugin: plugin,
            installedVersion: 'current-version',
            installationPath: '/programs/lua',
          );

          final gallery = createTestGallery([plugin]);
          final updateInfo = await galleryService.compareWithInstalledVersions(
            gallery,
          );

          // Should not detect update - installed version is newer
          expect(updateInfo, contains('old-plugin'));
          expect(updateInfo['old-plugin']!.updateAvailable, isFalse);
        },
      );

      test('handles plugins with no updatedAt date gracefully', () async {
        final plugin = GalleryPlugin(
          id: 'no-date-plugin',
          name: 'No Date Plugin',
          description: 'Plugin without dates',
          type: GalleryPluginType.lua,
          author: 'test-author',
          repository: const PluginRepository(
            owner: 'test-owner',
            name: 'test-repo',
            url: 'https://github.com/test-owner/test-repo',
          ),
          releases: const PluginReleases(latest: 'invalid'),
          installation: const PluginInstallation(targetPath: '/programs/lua'),
          guid: 'NODT',
          updatedAt: null, // No date
        );

        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'unknown',
          installationPath: '/programs/lua',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        // Unknown version should always suggest update available
        expect(updateInfo, contains('no-date-plugin'));
        expect(updateInfo['no-date-plugin']!.updateAvailable, isTrue);
      });

      test('user-installed version always shows update available', () async {
        final plugin = createTestPlugin(
          id: 'user-installed-plugin',
          name: 'User Installed Plugin',
          guid: 'USRI',
        );

        // Simulate a user-installed record (gallery association preserved)
        await database.pluginInstallationsDao.recordPluginByPath(
          installationPath: '/programs/plug-ins/synth.o',
          pluginName: 'synth.o',
          pluginType: 'cpp',
          pluginId: 'user-installed-plugin',
          pluginVersion: 'user-installed',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, contains('user-installed-plugin'));
        expect(updateInfo['user-installed-plugin']!.updateAvailable, isTrue);
      });

      test('device-detected version always shows update available', () async {
        final plugin = createTestPlugin(
          id: 'device-detected-plugin',
          name: 'Device Detected Plugin',
          guid: 'DVCD',
        );

        // Simulate a device-detected record (reconciliation result)
        await database.pluginInstallationsDao.recordPluginByPath(
          installationPath: '/programs/plug-ins/detected.o',
          pluginName: 'detected.o',
          pluginType: 'cpp',
          pluginId: 'device-detected-plugin',
          pluginVersion: 'device-detected',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        expect(updateInfo, contains('device-detected-plugin'));
        expect(updateInfo['device-detected-plugin']!.updateAvailable, isTrue);
      });

      test('prefers version comparison over date comparison', () async {
        // Plugin with both valid version AND updatedAt
        final plugin = GalleryPlugin(
          id: 'version-priority',
          name: 'Version Priority Plugin',
          description: 'Plugin with both version and date',
          type: GalleryPluginType.lua,
          author: 'test-author',
          repository: const PluginRepository(
            owner: 'test-owner',
            name: 'test-repo',
            url: 'https://github.com/test-owner/test-repo',
          ),
          releases: const PluginReleases(latest: 'v2.0.0'),
          installation: const PluginInstallation(targetPath: '/programs/lua'),
          guid: 'VPRI',
          updatedAt: DateTime.now().subtract(
            const Duration(days: 10),
          ), // Old date
        );

        // Install v1.0.0 recently
        await database.pluginInstallationsDao.recordPluginInstallation(
          plugin: plugin,
          installedVersion: 'v1.0.0',
          installationPath: '/programs/lua',
        );

        final gallery = createTestGallery([plugin]);
        final updateInfo = await galleryService.compareWithInstalledVersions(
          gallery,
        );

        // Should detect update via version comparison (v1 < v2)
        // even though date suggests no update
        expect(updateInfo, contains('version-priority'));
        expect(updateInfo['version-priority']!.updateAvailable, isTrue);
      }, tags: ['regression']);
    });
  });
}
