import 'dart:io';
import 'dart:convert';
import 'package:nt_helper/services/mcp_ipad_settings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-default seed values keyed by storage-key string. Each value is chosen
/// to differ from the corresponding declared default, so that asserting "the
/// getter returns the default after reset" actually proves a state change.
const Map<String, Object> _nonDefaultSeeds = {
  'request_timeout_ms': 12345,
  'inter_message_delay_ms': 999,
  'haptics_enabled': false,
  'mcp_enabled': true,
  'mcp_ipad_configuration':
      '{"version":1,"consentVersion":1,"interfaceIndex":7,"address":"192.168.2.1","peers":["192.168.2.2"]}',
  'start_pages_collapsed': true,
  'gallery_url': 'https://example.invalid/gallery.json',
  'graphql_endpoint': 'https://example.invalid/graphql',
  'include_community_plugins_in_presets': false,
  'overlay_position_x': 42.0,
  'overlay_position_y': 99.0,
  'overlay_size_scale': 2.5,
  'video_popup_native_window_enabled': true,
  'video_toolbar_always_visible': true,
  'video_popup_always_on_top': true,
  'video_popup_bounds_x': 10.0,
  'video_popup_bounds_y': 20.0,
  'video_popup_bounds_width': 640.0,
  'video_popup_bounds_height': 180.0,
  'show_debug_panel': false,
  'show_contextual_help': false,
  'algorithm_cache_days': 17,
  'cpu_monitor_enabled': false,
  'dismissed_update_version': '99.99.99',
  'last_update_check_timestamp': 1700000000000,
  'split_divider_position': 0.123,
  'mcp_remote_connections': true,
  'chat_enabled': true,
  'companion_column_widths': '{"seed":420}',
  'chat_panel_width': 777.0,
  'chat_llm_provider': 'openai',
  'chat_additional_providers':
      '{"local":{"api_key":"fixture","model":"fixture"}}',
  'anthropic_api_key': 'sk-fake-anthropic',
  'openai_api_key': 'sk-fake-openai',
  'anthropic_model': 'fake-anthropic-model',
  'openai_model': 'fake-openai-model',
  'openai_subscription_model': 'fake-openai-subscription-model',
  'openai_base_url': 'https://example.invalid/v1',
  'allow_codex_auth_refresh': true,
  'chat_local_directory': '/tmp/nt-helper-chat-workspace',
  'allowed_file_roots':
      '[{"id":"seed","label":"Seed","path":"/tmp/seed","acl":{"chat":["read"],"mcp":["search"]}}]',
  'ui_scale': 1.4,
  'theme_seed_argb': 0xFF6750A4,
  'auto_center_on_selection': false,
  'show_backward_connections': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'companion widths are isolated by GUID, table and stable column key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      await settings.setCompanionColumnWidth(
        'ThPh',
        'sockets',
        'destination',
        420,
      );
      await settings.setCompanionColumnWidth('ThPh', 'aux', 'description', 360);
      await settings.setCompanionColumnWidth(
        'Other',
        'sockets',
        'destination',
        240,
      );
      expect(settings.companionColumnWidths.length, 3);
      await settings.init();
      expect(
        settings.companionColumnWidths.values,
        containsAll([420.0, 360.0, 240.0]),
      );
      SharedPreferences.setMockInitialValues({
        'companion_column_widths': 'bad JSON',
      });
      await settings.init();
      expect(settings.companionColumnWidths, isEmpty);
    },
  );

  // AC-011: the exhaustive reset test does not prove generic desktop flags
  // survive reload without introducing the iPad consent requirement.
  test(
    'AC-011 desktop MCP remains default off with independently persisted enable and remote flags',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      expect(settings.mcpEnabled, isFalse);
      expect(settings.mcpRemoteConnections, isFalse);
      expect(await settings.setMcpEnabled(true), isTrue);
      expect(await settings.setMcpRemoteConnections(true), isTrue);
      await settings.init();
      expect(settings.mcpEnabled, isTrue);
      expect(settings.mcpRemoteConnections, isTrue);
      expect(settings.mcpIpadConfiguration, isNull);
      SharedPreferences.setMockInitialValues({
        'mcp_enabled': 'invalid',
        'mcp_remote_connections': 1,
      });
      await settings.init();
      expect(settings.mcpEnabled, isFalse);
      expect(settings.mcpRemoteConnections, isFalse);
    },
  );

  // AC-001/007: generic default/reset coverage cannot validate the versioned
  // nonsecret receipt, malformed restoration or the persistence whitelist.
  test(
    'AC-001 AC-007 iPad receipt rejects invalid restoration and stores only configuration',
    () async {
      final settings = SettingsService();
      for (final raw in [
        true,
        1,
        'bad JSON',
        '{}',
        '{"version":2,"consentVersion":1}',
        '{"version":true,"consentVersion":1}',
        '{"version":1,"consentVersion":"1"}',
        '{"version":1,"consentVersion":1,"interfaceIndex":7,"address":"192.168.2.1","peers":[false]}',
      ]) {
        SharedPreferences.setMockInitialValues({'mcp_ipad_configuration': raw});
        await settings.init();
        expect(settings.mcpIpadConfiguration, isNull);
      }
      SharedPreferences.setMockInitialValues({
        'mcp_enabled': true,
        'mcp_remote_connections': true,
      });
      await settings.init();
      expect(settings.mcpIpadConfiguration, isNull);
      const configuration = McpIpadSettings(
        interfaceIndex: 7,
        address: '192.168.2.1',
        peers: ['192.168.2.2'],
      );
      expect(await settings.setMcpIpadConfiguration(configuration), isTrue);
      await settings.init();
      expect(settings.mcpIpadConfiguration!.address, configuration.address);
      final prefs = await SharedPreferences.getInstance();
      final value =
          jsonDecode(prefs.getString('mcp_ipad_configuration')!) as Map;
      expect(value.keys.toSet(), {
        'version',
        'consentVersion',
        'interfaceIndex',
        'address',
        'peers',
      });
    },
  );

  group('SettingsService.resetToDefaults', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
    });

    test('every persisted key has a non-default seed in the test fixture', () {
      for (final key in SettingsService.debugPersistedKeys) {
        expect(
          _nonDefaultSeeds.containsKey(key),
          isTrue,
          reason:
              'Persisted key "$key" has no entry in _nonDefaultSeeds. Add a '
              'non-default value for it so the exhaustive-reset test '
              'actually exercises this key.',
        );
      }
    });

    test(
      'after reset, every persisted key returns its declared default',
      () async {
        SharedPreferences.setMockInitialValues(_nonDefaultSeeds);
        await settings.init();

        for (final key in SettingsService.debugPersistedKeys) {
          expect(
            _nonDefaultSeeds.containsKey(key),
            isTrue,
            reason: 'seed missing for $key',
          );
        }
        expect(
          settings.requestTimeout,
          isNot(SettingsService.defaultRequestTimeout),
        );
        expect(
          settings.cpuMonitorEnabled,
          isNot(SettingsService.defaultCpuMonitorEnabled),
        );
        expect(settings.chatEnabled, isNot(SettingsService.defaultChatEnabled));
        expect(settings.dismissedUpdateVersion, isNotNull);
        expect(settings.lastUpdateCheckTimestamp, isNotNull);
        expect(settings.anthropicApiKey, isNotNull);
        expect(settings.openaiApiKey, isNotNull);
        expect(settings.openaiBaseUrl, isNotNull);
        expect(
          settings.openaiSubscriptionModel,
          isNot(SettingsService.defaultOpenaiSubscriptionModel),
        );
        expect(
          settings.allowCodexAuthRefresh,
          isNot(SettingsService.defaultAllowCodexAuthRefresh),
        );
        expect(settings.chatLocalDirectory, isNotNull);
        expect(settings.allowedFileRoots, isNotEmpty);

        expect(settings.mcpIpadConfiguration, isNotNull);
        expect(settings.companionColumnWidths, isNotEmpty);
        await settings.resetToDefaults();
        expect(settings.companionColumnWidths, isEmpty);
        expect(settings.mcpIpadConfiguration, isNull);

        expect(settings.requestTimeout, SettingsService.defaultRequestTimeout);
        expect(
          settings.interMessageDelay,
          SettingsService.defaultInterMessageDelay,
        );
        expect(settings.hapticsEnabled, SettingsService.defaultHapticsEnabled);
        expect(settings.mcpEnabled, SettingsService.defaultMcpEnabled);
        expect(
          settings.mcpRemoteConnections,
          SettingsService.defaultMcpRemoteConnections,
        );
        expect(
          settings.startPagesCollapsed,
          SettingsService.defaultStartPagesCollapsed,
        );
        expect(settings.galleryUrl, SettingsService.defaultGalleryUrl);
        expect(
          settings.graphqlEndpoint,
          SettingsService.defaultGraphqlEndpoint,
        );
        expect(
          settings.includeCommunityPlugins,
          SettingsService.defaultIncludeCommunityPlugins,
        );
        expect(
          settings.overlayPositionX,
          SettingsService.defaultOverlayPositionX,
        );
        expect(
          settings.overlayPositionY,
          SettingsService.defaultOverlayPositionY,
        );
        expect(
          settings.overlaySizeScale,
          SettingsService.defaultOverlaySizeScale,
        );
        expect(
          settings.videoPopupNativeWindowEnabled,
          SettingsService.defaultVideoPopupNativeWindowEnabled,
        );
        expect(
          settings.videoToolbarAlwaysVisible,
          SettingsService.defaultVideoToolbarAlwaysVisible,
        );
        expect(
          settings.videoPopupAlwaysOnTop,
          SettingsService.defaultVideoPopupAlwaysOnTop,
        );
        expect(
          settings.videoPopupBoundsX,
          SettingsService.defaultVideoPopupBoundsX,
        );
        expect(
          settings.videoPopupBoundsY,
          SettingsService.defaultVideoPopupBoundsY,
        );
        expect(
          settings.videoPopupBoundsWidth,
          SettingsService.defaultVideoPopupBoundsWidth,
        );
        expect(
          settings.videoPopupBoundsHeight,
          SettingsService.defaultVideoPopupBoundsHeight,
        );
        expect(settings.showDebugPanel, SettingsService.defaultShowDebugPanel);
        expect(
          settings.showContextualHelp,
          SettingsService.defaultShowContextualHelp,
        );
        expect(
          settings.algorithmCacheDays,
          SettingsService.defaultAlgorithmCacheDays,
        );
        expect(
          settings.cpuMonitorEnabled,
          SettingsService.defaultCpuMonitorEnabled,
        );
        expect(
          settings.splitDividerPosition,
          SettingsService.defaultSplitDividerPosition,
        );
        expect(settings.chatEnabled, SettingsService.defaultChatEnabled);
        expect(settings.chatPanelWidth, SettingsService.defaultChatPanelWidth);
        expect(settings.chatLlmProvider, LlmProviderType.anthropic);
        expect(settings.anthropicApiKey, isNull);
        expect(settings.openaiApiKey, isNull);
        expect(settings.anthropicModel, SettingsService.defaultAnthropicModel);
        expect(settings.openaiModel, SettingsService.defaultOpenaiModel);
        expect(
          settings.openaiSubscriptionModel,
          SettingsService.defaultOpenaiSubscriptionModel,
        );
        expect(settings.openaiBaseUrl, isNull);
        expect(
          settings.allowCodexAuthRefresh,
          SettingsService.defaultAllowCodexAuthRefresh,
        );
        expect(settings.chatLocalDirectory, isNull);
        expect(settings.allowedFileRoots, isEmpty);
        expect(settings.dismissedUpdateVersion, isNull);
        expect(settings.lastUpdateCheckTimestamp, isNull);
        expect(settings.uiScale, SettingsService.defaultUiScale);
        expect(settings.themeSeedColor, SettingsService.defaultThemeSeedColor);
        expect(
          settings.autoCenterOnSelection,
          SettingsService.defaultAutoCenterOnSelection,
        );
        expect(
          settings.showBackwardConnections,
          SettingsService.defaultShowBackwardConnections,
        );

        final prefs = await SharedPreferences.getInstance();
        final leftoverOwnedKeys = prefs.getKeys().toSet().intersection(
          SettingsService.debugPersistedKeys.toSet(),
        );
        expect(
          leftoverOwnedKeys,
          isEmpty,
          reason:
              'resetToDefaults left behind owned keys in storage: $leftoverOwnedKeys',
        );
      },
    );

    test(
      'resetToDefaults resyncs ValueNotifiers backed by removed keys',
      () async {
        SharedPreferences.setMockInitialValues({
          'cpu_monitor_enabled': false,
          'ui_scale': 1.4,
          'theme_seed_argb': 0xFF6750A4,
          'video_toolbar_always_visible': true,
        });
        await settings.init();
        expect(settings.cpuMonitorEnabledNotifier.value, isFalse);
        expect(settings.uiScaleNotifier.value, closeTo(1.4, 1e-9));
        expect(settings.themeSeedColorNotifier.value, const Color(0xFF6750A4));
        expect(settings.videoToolbarAlwaysVisibleNotifier.value, isTrue);

        await settings.resetToDefaults();

        expect(
          settings.cpuMonitorEnabledNotifier.value,
          SettingsService.defaultCpuMonitorEnabled,
        );
        expect(settings.uiScaleNotifier.value, SettingsService.defaultUiScale);
        expect(
          settings.themeSeedColorNotifier.value,
          SettingsService.defaultThemeSeedColor,
        );
        expect(
          settings.videoToolbarAlwaysVisibleNotifier.value,
          SettingsService.defaultVideoToolbarAlwaysVisible,
        );
      },
    );
  });

  group('SettingsService theme seed', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
    });

    test('persists an opaque seed and updates its notifier', () async {
      const translucentPurple = Color(0x336750A4);

      expect(settings.themeSeedColor, SettingsService.defaultThemeSeedColor);
      expect(await settings.setThemeSeedColor(translucentPurple), isTrue);
      expect(settings.themeSeedColor, const Color(0xFF6750A4));
      expect(settings.themeSeedColorNotifier.value, const Color(0xFF6750A4));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('theme_seed_argb'), 0xFF6750A4);
    });

    testWidgets('Settings stages the seed until Save is pressed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Theme Colour'));
      await tester.tap(find.byTooltip('Choose theme colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Purple'));
      await tester.pump();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(settings.themeSeedColor, SettingsService.defaultThemeSeedColor);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(settings.themeSeedColor, Colors.purple.shade500);
      expect(settings.themeSeedColorNotifier.value, Colors.purple.shade500);
    });

    testWidgets('Settings reset restores the default seed when saved', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'theme_seed_argb': Colors.purple.shade500.toARGB32(),
      });
      await settings.init();
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Theme Colour'));
      await tester.tap(find.byKey(const ValueKey('reset-theme-seed')));
      await tester.pump();

      expect(settings.themeSeedColor, Colors.purple.shade500);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(settings.themeSeedColor, SettingsService.defaultThemeSeedColor);
      expect(
        settings.themeSeedColorNotifier.value,
        SettingsService.defaultThemeSeedColor,
      );
    });
  });

  group('SettingsService.allowedFileRoots', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
    });

    test('migrates legacy chat local directory as chat read/search', () async {
      SharedPreferences.setMockInitialValues({
        'chat_local_directory': '/Volumes/DistingSD',
      });
      await settings.init();

      final roots = settings.allowedFileRoots;

      expect(roots, hasLength(1));
      expect(roots.single.id, 'local_context');
      expect(roots.single.label, 'Local Context');
      expect(roots.single.path, '/Volumes/DistingSD');
      expect(
        roots.single.permissionsFor(FileRootActor.chat),
        containsAll({FileRootPermission.read, FileRootPermission.search}),
      );
      expect(roots.single.permissionsFor(FileRootActor.mcp), isEmpty);
    });

    test('saves and loads ACL permissions', () async {
      await settings.setAllowedFileRoots([
        const AllowedFileRoot(
          id: 'sd',
          label: 'SD Card',
          path: '/Volumes/DistingSD',
          acl: {
            FileRootActor.chat: {
              FileRootPermission.read,
              FileRootPermission.search,
            },
            FileRootActor.mcp: {FileRootPermission.read},
          },
        ),
      ]);

      final roots = settings.allowedFileRoots;

      expect(roots, hasLength(1));
      expect(roots.single.id, 'sd');
      expect(
        roots.single.permissionsFor(FileRootActor.chat),
        containsAll({FileRootPermission.read, FileRootPermission.search}),
      );
      expect(roots.single.permissionsFor(FileRootActor.mcp), {
        FileRootPermission.read,
      });
    });

    test('saving allowed roots clears the legacy directory key', () async {
      SharedPreferences.setMockInitialValues({
        'chat_local_directory': '/Volumes/DistingSD',
      });
      await settings.init();
      expect(settings.allowedFileRoots, isNotEmpty);

      await settings.setAllowedFileRoots(const []);

      expect(settings.chatLocalDirectory, isNull);
      expect(settings.allowedFileRoots, isEmpty);
    });

    test('malformed stored root entries are ignored safely', () async {
      SharedPreferences.setMockInitialValues({
        'allowed_file_roots':
            '[{"id":7,"label":"Bad","path":"/tmp/bad","acl":{"chat":["read"]}},'
            '{"id":"ok","label":"OK","path":"/tmp/ok","acl":{"chat":["read"]}}]',
      });
      await settings.init();

      final roots = settings.allowedFileRoots;

      expect(roots, hasLength(1));
      expect(roots.single.id, 'ok');
    });
  });

  group('SettingsDialog routing visibility settings', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'show_backward_connections': false,
        'video_popup_native_window_enabled': false,
        'video_toolbar_always_visible': false,
      });
      settings = SettingsService();
      await settings.init();
    });

    testWidgets('loads and saves Show Back Connections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pump();

      final settingTitle = find.text('Show Back Connections');
      await tester.ensureVisible(settingTitle);
      expect(settingTitle, findsOneWidget);
      expect(settings.showBackwardConnections, isFalse);

      await tester.tap(settingTitle);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.showBackwardConnections, isTrue);
      expect(settings.showBackwardConnectionsNotifier.value, isTrue);
    });

    testWidgets('loads and saves Open Video in Separate Window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pump();

      final settingTitle = find.text('Open Video in Separate Window');
      await tester.ensureVisible(settingTitle);
      expect(settingTitle, findsOneWidget);
      expect(settings.videoPopupNativeWindowEnabled, isFalse);

      await tester.tap(settingTitle);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.videoPopupNativeWindowEnabled, isTrue);
    });

    testWidgets('loads and saves Always Show Video Toolbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pump();

      final settingTitle = find.text('Always Show Video Toolbar');
      await tester.ensureVisible(settingTitle);
      expect(settingTitle, findsOneWidget);
      expect(settings.videoToolbarAlwaysVisible, isFalse);

      await tester.tap(settingTitle);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.videoToolbarAlwaysVisible, isTrue);
      expect(settings.videoToolbarAlwaysVisibleNotifier.value, isTrue);
    });
  });

  group('SettingsService key registry', () {
    test('every _xxxKey constant in settings_service.dart is in '
        '_persistedKeys (and vice-versa)', () {
      final source = File(
        'lib/services/settings_service.dart',
      ).readAsStringSync();

      final keyConstantPattern = RegExp(
        r"static\s+const\s+String\s+_\w+Key\s*=\s*'([^']+)'\s*;",
      );

      final declaredKeys = keyConstantPattern
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        declaredKeys,
        isNotEmpty,
        reason:
            'Source-scan regex found no `static const String _xxxKey` '
            'declarations — the regex is broken or the file path is wrong.',
      );

      final registered = SettingsService.debugPersistedKeys.toSet();

      final missingFromRegistry = declaredKeys.difference(registered);
      final extraInRegistry = registered.difference(declaredKeys);

      expect(
        missingFromRegistry,
        isEmpty,
        reason:
            'These persisted setting keys are declared in '
            'lib/services/settings_service.dart but are NOT in '
            '_persistedKeys: $missingFromRegistry. Add them to the '
            '_persistedKeys list so resetToDefaults() covers them. '
            '(If you added a new persisted setting and forgot to update '
            'the registry, this is the test that caught it.)',
      );

      expect(
        extraInRegistry,
        isEmpty,
        reason:
            '_persistedKeys contains keys that are NOT declared as '
            '`static const String _xxxKey` in settings_service.dart: '
            '$extraInRegistry. Either remove them from the registry or '
            'restore the missing constants.',
      );
    });
  });
}
