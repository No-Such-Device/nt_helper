import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('PluginInstallationsDao - recordPluginByPath', () {
    test('inserts new record for new path', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/test.lua',
        pluginName: 'test.lua',
        pluginType: 'lua',
        totalBytes: 1024,
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].installationPath, equals('/programs/lua/test.lua'));
      expect(records[0].pluginName, equals('test.lua'));
      expect(records[0].pluginType, equals('lua'));
      expect(records[0].totalBytes, equals(1024));
      expect(records[0].installationStatus, equals('completed'));
    });

    test('updates existing record for same path', () async {
      // First install
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/test.lua',
        pluginName: 'test.lua',
        pluginType: 'lua',
        totalBytes: 1024,
      );

      // Reinstall with different size
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/test.lua',
        pluginName: 'test.lua',
        pluginType: 'lua',
        totalBytes: 2048,
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      // Should still be just one record (upsert)
      expect(records.length, equals(1));
      expect(records[0].totalBytes, equals(2048));
    });

    test('records 3pot plugin with correct type', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/three_pot/effect.3pot',
        pluginName: 'effect.3pot',
        pluginType: 'threepot',
        totalBytes: 512,
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].pluginType, equals('threepot'));
    });

    test('records cpp plugin with correct type', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        totalBytes: 65536,
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].pluginType, equals('cpp'));
    });

    test('uses provided pluginId when given', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/gallery-plugin.lua',
        pluginName: 'gallery-plugin.lua',
        pluginType: 'lua',
        pluginId: 'gallery-plugin-id',
        pluginVersion: 'v1.2.0',
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('gallery-plugin-id'));
      expect(records[0].pluginVersion, equals('v1.2.0'));
    });

    test('generates local pluginId when not provided', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/local-plugin.lua',
        pluginName: 'local-plugin.lua',
        pluginType: 'lua',
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].pluginId, startsWith('local:'));
      expect(records[0].pluginVersion, equals('unknown'));
      expect(records[0].pluginAuthor, equals('Local Install'));
    });

    test('gallery install replaces local install at same path', () async {
      // First: local install (no pluginId provided)
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/test.lua',
        pluginName: 'test.lua',
        pluginType: 'lua',
      );

      var records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, startsWith('local:'));

      // Second: gallery install at same path (with pluginId)
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/test.lua',
        pluginName: 'test.lua',
        pluginType: 'lua',
        pluginId: 'gallery-plugin',
        pluginVersion: 'v1.0.0',
      );

      // Should have only ONE record (gallery install replaced local)
      records = await database.pluginInstallationsDao.getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('gallery-plugin'));
      expect(records[0].pluginVersion, equals('v1.0.0'));
    });
  });

  group('PluginInstallationsDao - gallery association preservation', () {
    test('preserves gallery pluginId on local re-upload', () async {
      // First: gallery install with proper pluginId
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        pluginId: 'gallery-synth',
        pluginVersion: 'v1.0.0',
      );

      var records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('gallery-synth'));
      expect(records[0].pluginVersion, equals('v1.0.0'));

      // Second: local re-upload at same path (no pluginId)
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        totalBytes: 70000,
      );

      // Should preserve gallery pluginId but mark as user-installed
      records = await database.pluginInstallationsDao.getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('gallery-synth'));
      expect(records[0].pluginVersion, equals('user-installed'));
    }, tags: ['regression']);

    test('does not preserve local pluginId on local re-upload', () async {
      // First: local install (no pluginId)
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/custom.o',
        pluginName: 'custom.o',
        pluginType: 'cpp',
      );

      var records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records[0].pluginId, startsWith('local:'));

      // Second: another local re-upload
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/custom.o',
        pluginName: 'custom.o',
        pluginType: 'cpp',
        totalBytes: 50000,
      );

      // Should still be a local: ID (no gallery association to preserve)
      records = await database.pluginInstallationsDao.getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, startsWith('local:'));
      expect(records[0].pluginVersion, equals('unknown'));
    });

    test('explicit pluginId overrides gallery preservation', () async {
      // First: gallery install
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        pluginId: 'gallery-synth',
        pluginVersion: 'v1.0.0',
      );

      // Second: new gallery install with different pluginId
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        pluginId: 'gallery-synth-v2',
        pluginVersion: 'v2.0.0',
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();
      expect(records.length, equals(1));
      expect(records[0].pluginId, equals('gallery-synth-v2'));
      expect(records[0].pluginVersion, equals('v2.0.0'));
    });
  });

  group('PluginInstallationsDao - getByInstallationPath', () {
    test('returns record for existing path', () async {
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/plug-ins/synth.o',
        pluginName: 'synth.o',
        pluginType: 'cpp',
        pluginId: 'gallery-synth',
        pluginVersion: 'v1.0.0',
      );

      final record = await database.pluginInstallationsDao
          .getByInstallationPath('/programs/plug-ins/synth.o');

      expect(record, isNotNull);
      expect(record!.pluginId, equals('gallery-synth'));
    });

    test('returns null for non-existent path', () async {
      final record = await database.pluginInstallationsDao
          .getByInstallationPath('/nonexistent/path.o');

      expect(record, isNull);
    });
  });

  group('PluginInstallationsDao - removeByInstallationPath', () {
    test('removes correct record by path', () async {
      // Add two plugins
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/keep.lua',
        pluginName: 'keep.lua',
        pluginType: 'lua',
      );
      await database.pluginInstallationsDao.recordPluginByPath(
        installationPath: '/programs/lua/delete.lua',
        pluginName: 'delete.lua',
        pluginType: 'lua',
      );

      // Delete one
      await database.pluginInstallationsDao.removeByInstallationPath(
        '/programs/lua/delete.lua',
      );

      final records = await database.pluginInstallationsDao
          .getAllInstalledPlugins();

      expect(records.length, equals(1));
      expect(records[0].installationPath, equals('/programs/lua/keep.lua'));
    });

    test('does not error when path not found', () async {
      // Should not throw
      final deleted = await database.pluginInstallationsDao
          .removeByInstallationPath('/nonexistent/path.lua');

      expect(deleted, equals(0));
    });
  });
}
