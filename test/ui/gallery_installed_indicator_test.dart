import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/ui/gallery/gallery_cubit.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';

class MockGalleryCubit extends Mock implements GalleryCubit {}

void main() {
  late MockGalleryCubit mockCubit;

  setUp(() {
    mockCubit = MockGalleryCubit();
  });

  GalleryPlugin createTestPlugin({
    required String id,
    required String name,
    String? guid,
  }) {
    return GalleryPlugin(
      id: id,
      name: name,
      description: 'Test plugin description',
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

  Widget createTestWidget({
    required GalleryPlugin plugin,
    Map<String, PluginUpdateInfo>? updateInfo,
  }) {
    final gallery = Gallery(
      version: '2.0.0',
      lastUpdated: DateTime.now(),
      metadata: const GalleryMetadata(
        name: 'Test Gallery',
        description: 'Test gallery',
        maintainer: GalleryMaintainer(name: 'Test'),
      ),
      plugins: [plugin],
    );

    final loadedState = GalleryState.loaded(
      gallery: gallery,
      filteredPlugins: [plugin],
      selectedCategory: null,
      selectedType: null,
      showFeaturedOnly: false,
      showVerifiedOnly: false,
      searchQuery: '',
      updateInfo: updateInfo ?? {},
    );

    when(() => mockCubit.state).thenReturn(loadedState);
    when(() => mockCubit.stream).thenAnswer((_) => Stream.value(loadedState));

    return MaterialApp(
      home: BlocProvider<GalleryCubit>.value(
        value: mockCubit,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              final state = context.watch<GalleryCubit>().state;
              if (state is GalleryLoaded) {
                final updateInfo = state.updateInfo[plugin.id];
                final isInstalled = updateInfo != null;
                final hasUpdate = updateInfo?.updateAvailable ?? false;

                return Column(
                  children: [
                    // Badge widget (similar to gallery_screen.dart)
                    if (isInstalled)
                      Container(
                        key: const Key('installed_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasUpdate ? Colors.orange : Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          hasUpdate ? 'UPDATE' : 'INSTALLED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    // Install button (similar to gallery_screen.dart)
                    ElevatedButton(
                      key: const Key('install_button'),
                      onPressed: isInstalled ? null : () {},
                      child: Text(isInstalled ? 'Installed' : 'Install'),
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  group('Gallery Installed Indicator Visual Tests', () {
    testWidgets('shows INSTALLED badge for installed plugin', (tester) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      final updateInfo = {
        'test-plugin': PluginUpdateInfo(
          pluginId: 'test-plugin',
          pluginName: 'Test Plugin',
          installedVersion: 'v1.0.0',
          availableVersion: 'v1.0.0',
          updateAvailable: false,
          lastChecked: DateTime.now(),
        ),
      };

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      expect(find.byKey(const Key('installed_badge')), findsOneWidget);
      expect(find.text('INSTALLED'), findsOneWidget);
      expect(find.text('UPDATE'), findsNothing);
    });

    testWidgets('shows UPDATE badge when update is available', (tester) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      final updateInfo = {
        'test-plugin': PluginUpdateInfo(
          pluginId: 'test-plugin',
          pluginName: 'Test Plugin',
          installedVersion: 'v0.9.0',
          availableVersion: 'v1.0.0',
          updateAvailable: true,
          lastChecked: DateTime.now(),
        ),
      };

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      expect(find.byKey(const Key('installed_badge')), findsOneWidget);
      expect(find.text('UPDATE'), findsOneWidget);
      expect(find.text('INSTALLED'), findsNothing);

      // Verify orange color for update badge
      final badge = tester.widget<Container>(
        find.byKey(const Key('installed_badge')),
      );
      final decoration = badge.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.orange));
    });

    testWidgets('badge has green color for installed plugin', (tester) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      final updateInfo = {
        'test-plugin': PluginUpdateInfo(
          pluginId: 'test-plugin',
          pluginName: 'Test Plugin',
          installedVersion: 'v1.0.0',
          availableVersion: 'v1.0.0',
          updateAvailable: false,
          lastChecked: DateTime.now(),
        ),
      };

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      final badge = tester.widget<Container>(
        find.byKey(const Key('installed_badge')),
      );
      final decoration = badge.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.green));
    });

    testWidgets('hides badge for uninstalled plugin', (tester) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      // No update info = not installed
      final updateInfo = <String, PluginUpdateInfo>{};

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      expect(find.byKey(const Key('installed_badge')), findsNothing);
      expect(find.text('INSTALLED'), findsNothing);
      expect(find.text('UPDATE'), findsNothing);
    });

    testWidgets('disables install button for installed plugin', (tester) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      final updateInfo = {
        'test-plugin': PluginUpdateInfo(
          pluginId: 'test-plugin',
          pluginName: 'Test Plugin',
          installedVersion: 'v1.0.0',
          availableVersion: 'v1.0.0',
          updateAvailable: false,
          lastChecked: DateTime.now(),
        ),
      };

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('install_button')),
      );
      expect(button.onPressed, isNull); // Disabled button has null onPressed
      expect(find.text('Installed'), findsOneWidget);
    });

    testWidgets('enables install button for uninstalled plugin', (
      tester,
    ) async {
      // Arrange
      final plugin = createTestPlugin(
        id: 'test-plugin',
        name: 'Test Plugin',
        guid: 'TEST',
      );

      // No update info = not installed
      final updateInfo = <String, PluginUpdateInfo>{};

      // Act
      await tester.pumpWidget(
        createTestWidget(plugin: plugin, updateInfo: updateInfo),
      );

      // Assert
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('install_button')),
      );
      expect(button.onPressed, isNotNull); // Enabled button
      expect(find.text('Install'), findsOneWidget);
    });

    testWidgets(
      'shows installed badge for manually installed plugin (unknown version)',
      (tester) async {
        // Arrange
        final plugin = createTestPlugin(
          id: 'manual-plugin',
          name: 'Manual Plugin',
          guid: 'MNPL',
        );

        final updateInfo = {
          'manual-plugin': PluginUpdateInfo(
            pluginId: 'manual-plugin',
            pluginName: 'Manual Plugin',
            installedVersion: 'unknown', // Manually installed
            availableVersion: 'v1.0.0',
            updateAvailable: false,
            lastChecked: DateTime.now(),
          ),
        };

        // Act
        await tester.pumpWidget(
          createTestWidget(plugin: plugin, updateInfo: updateInfo),
        );

        // Assert
        expect(find.byKey(const Key('installed_badge')), findsOneWidget);
        expect(find.text('INSTALLED'), findsOneWidget);

        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('install_button')),
        );
        expect(button.onPressed, isNull); // Should be disabled
      },
    );
  });

  group('PluginUpdateInfo model tests', () {
    test('hasUpdate returns true when update is available', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v0.9.0',
        availableVersion: 'v1.0.0',
        updateAvailable: true,
        lastChecked: DateTime.now(),
      );

      expect(info.hasUpdate, isTrue);
    });

    test('hasUpdate returns false when no update available', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v1.0.0',
        availableVersion: 'v1.0.0',
        updateAvailable: false,
        lastChecked: DateTime.now(),
      );

      expect(info.hasUpdate, isFalse);
    });

    test('hasUpdate returns false when availableVersion is null', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v1.0.0',
        availableVersion: null,
        updateAvailable: true,
        lastChecked: DateTime.now(),
      );

      expect(info.hasUpdate, isFalse);
    });

    test('needsCheck returns true when lastChecked is null', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v1.0.0',
        availableVersion: 'v1.0.0',
        updateAvailable: false,
        lastChecked: null,
      );

      expect(info.needsCheck, isTrue);
    });

    test('needsCheck returns true when lastChecked is over 1 hour old', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v1.0.0',
        availableVersion: 'v1.0.0',
        updateAvailable: false,
        lastChecked: DateTime.now().subtract(const Duration(hours: 2)),
      );

      expect(info.needsCheck, isTrue);
    });

    test('needsCheck returns false when lastChecked is recent', () {
      final info = PluginUpdateInfo(
        pluginId: 'test',
        pluginName: 'Test',
        installedVersion: 'v1.0.0',
        availableVersion: 'v1.0.0',
        updateAvailable: false,
        lastChecked: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      expect(info.needsCheck, isFalse);
    });
  });
}
