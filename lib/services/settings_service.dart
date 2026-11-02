import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/additional_provider_config.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/ipad_mcp_settings.dart';
import 'package:nt_helper/ui/widgets/rtt_stats_dialog.dart';
import 'package:nt_helper/ui/widgets/theme_seed_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service to manage application settings
class SettingsService {
  // Singleton instance
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // SharedPreferences instance
  SharedPreferences? _prefs;

  /// Notifier for CPU monitor enabled state changes
  final cpuMonitorEnabledNotifier = ValueNotifier<bool>(
    defaultCpuMonitorEnabled,
  );

  /// Notifier for UI scale changes; listeners rebuild when scale updates.
  final uiScaleNotifier = ValueNotifier<double>(defaultUiScale);

  /// Notifier for Material theme seed changes; listeners rebuild app themes.
  final themeSeedColorNotifier = ValueNotifier<Color>(defaultThemeSeedColor);

  /// Notifier for video toolbar visibility changes.
  final videoToolbarAlwaysVisibleNotifier = ValueNotifier<bool>(
    defaultVideoToolbarAlwaysVisible,
  );

  /// Notifier for contextual help hint visibility changes.
  final contextualHelpEnabledNotifier = ValueNotifier<bool>(
    defaultShowContextualHelp,
  );

  // Keys for storing settings
  static const String _requestTimeoutKey = 'request_timeout_ms';
  static const String _interMessageDelayKey = 'inter_message_delay_ms';
  static const String _hapticsEnabledKey = 'haptics_enabled';
  static const String _mcpEnabledKey = 'mcp_enabled';
  static const String _ipadMcpEnabledKey = 'ipad_mcp_enabled';
  static const String _startPagesCollapsedKey = 'start_pages_collapsed';
  static const String _galleryUrlKey = 'gallery_url';
  static const String _graphqlEndpointKey = 'graphql_endpoint';
  static const String _includeCommunityPluginsKey =
      'include_community_plugins_in_presets';
  static const String _overlayPositionXKey = 'overlay_position_x';
  static const String _overlayPositionYKey = 'overlay_position_y';
  static const String _overlaySizeScaleKey = 'overlay_size_scale';
  static const String _videoPopupNativeWindowEnabledKey =
      'video_popup_native_window_enabled';
  static const String _videoToolbarAlwaysVisibleKey =
      'video_toolbar_always_visible';
  static const String _videoPopupAlwaysOnTopKey = 'video_popup_always_on_top';
  static const String _videoPopupBoundsXKey = 'video_popup_bounds_x';
  static const String _videoPopupBoundsYKey = 'video_popup_bounds_y';
  static const String _videoPopupBoundsWidthKey = 'video_popup_bounds_width';
  static const String _videoPopupBoundsHeightKey = 'video_popup_bounds_height';
  static const String _showDebugPanelKey = 'show_debug_panel';
  static const String _showContextualHelpKey = 'show_contextual_help';
  static const String _algorithmCacheDaysKey = 'algorithm_cache_days';
  static const String _cpuMonitorEnabledKey = 'cpu_monitor_enabled';
  static const String _dismissedUpdateVersionKey = 'dismissed_update_version';
  static const String _lastUpdateCheckTimestampKey =
      'last_update_check_timestamp';
  static const String _splitDividerPositionKey = 'split_divider_position';
  static const String _mcpRemoteConnectionsKey = 'mcp_remote_connections';
  static const String _chatEnabledKey = 'chat_enabled';
  static const String _chatPanelWidthKey = 'chat_panel_width';
  static const String _companionColumnWidthsKey = 'companion_column_widths';
  static const String _chatLlmProviderKey = 'chat_llm_provider';
  static const String _anthropicApiKeyKey = 'anthropic_api_key';
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _anthropicModelKey = 'anthropic_model';
  static const String _openaiModelKey = 'openai_model';
  static const String _openaiSubscriptionModelKey = 'openai_subscription_model';
  static const String _openaiBaseUrlKey = 'openai_base_url';
  static const String _additionalChatProvidersKey = 'chat_additional_providers';
  static const String _allowCodexAuthRefreshKey = 'allow_codex_auth_refresh';
  static const String _chatLocalDirectoryKey = 'chat_local_directory';
  static const String _allowedFileRootsKey = 'allowed_file_roots';
  static const String _uiScaleKey = 'ui_scale';
  static const String _themeSeedColorKey = 'theme_seed_argb';
  static const String _autoCenterOnSelectionKey = 'auto_center_on_selection';
  static const String _showBackwardConnectionsKey = 'show_backward_connections';

  /// Single source of truth for every persisted setting key owned by this
  /// service. `resetToDefaults()` clears every entry here so getters fall back
  /// to their declared defaults. Adding a new persisted setting REQUIRES adding
  /// its storage key here; the test in
  /// `test/services/settings_service_test.dart` enforces this by source-scanning
  /// `_xxxKey` constants and comparing against this list.
  static const List<String> _persistedKeys = [
    _requestTimeoutKey,
    _interMessageDelayKey,
    _hapticsEnabledKey,
    _mcpEnabledKey,
    _ipadMcpEnabledKey,
    _startPagesCollapsedKey,
    _galleryUrlKey,
    _graphqlEndpointKey,
    _includeCommunityPluginsKey,
    _overlayPositionXKey,
    _overlayPositionYKey,
    _overlaySizeScaleKey,
    _videoPopupNativeWindowEnabledKey,
    _videoToolbarAlwaysVisibleKey,
    _videoPopupAlwaysOnTopKey,
    _videoPopupBoundsXKey,
    _videoPopupBoundsYKey,
    _videoPopupBoundsWidthKey,
    _videoPopupBoundsHeightKey,
    _showDebugPanelKey,
    _showContextualHelpKey,
    _algorithmCacheDaysKey,
    _cpuMonitorEnabledKey,
    _dismissedUpdateVersionKey,
    _lastUpdateCheckTimestampKey,
    _splitDividerPositionKey,
    _mcpRemoteConnectionsKey,
    _chatEnabledKey,
    _chatPanelWidthKey,
    _companionColumnWidthsKey,
    _chatLlmProviderKey,
    _anthropicApiKeyKey,
    _openaiApiKeyKey,
    _anthropicModelKey,
    _openaiModelKey,
    _openaiSubscriptionModelKey,
    _openaiBaseUrlKey,
    _additionalChatProvidersKey,
    _allowCodexAuthRefreshKey,
    _chatLocalDirectoryKey,
    _allowedFileRootsKey,
    _uiScaleKey,
    _themeSeedColorKey,
    _autoCenterOnSelectionKey,
    _showBackwardConnectionsKey,
  ];

  /// The set of persisted setting keys owned by this service. Test-only.
  @visibleForTesting
  static List<String> get debugPersistedKeys =>
      List.unmodifiable(_persistedKeys);

  // Default values
  static const int defaultRequestTimeout = 200;
  static const int defaultInterMessageDelay = 0;
  static const bool defaultHapticsEnabled = true;
  static const bool defaultMcpEnabled = false;
  static const bool defaultStartPagesCollapsed = false;
  static const String defaultGalleryUrl =
      'https://nt-gallery.nosuch.dev/api/gallery.json';
  static const String defaultGraphqlEndpoint =
      'https://nt-gallery-backend.fly.dev/api/graphql';
  static const bool defaultIncludeCommunityPlugins = true;
  static const double defaultOverlayPositionX =
      -1.0; // -1 means use default positioning
  static const double defaultOverlayPositionY =
      -1.0; // -1 means use default positioning
  static const double defaultOverlaySizeScale = 1.0;
  static const bool defaultVideoPopupNativeWindowEnabled = false;
  static const bool defaultVideoToolbarAlwaysVisible = false;
  static const bool defaultVideoPopupAlwaysOnTop = false;
  static const double defaultVideoPopupBoundsX = -1.0;
  static const double defaultVideoPopupBoundsY = -1.0;
  static const double defaultVideoPopupBoundsWidth = 384.0;
  static const double defaultVideoPopupBoundsHeight = 132.0;
  static const bool defaultShowDebugPanel = true;
  static const bool defaultShowContextualHelp = true;
  static const int defaultAlgorithmCacheDays = 2;
  static const bool defaultCpuMonitorEnabled = true;
  static const double defaultSplitDividerPosition = 0.5;
  static const bool defaultMcpRemoteConnections = false;
  static const bool defaultChatEnabled = false;
  static const double defaultChatPanelWidth = 360;
  static const String defaultAnthropicModel = 'claude-haiku-4-5-20251001';
  static const String defaultOpenaiModel = 'gpt-5-nano';
  static const String defaultOpenaiSubscriptionModel = 'gpt-5.4-mini';
  static const bool defaultAllowCodexAuthRefresh = false;
  static const double defaultUiScale = 1.0;
  static const double minUiScale = 0.7;
  static const double maxUiScale = 1.5;
  static const double uiScaleStep = 0.1;
  static const Color defaultThemeSeedColor = AppTheme.defaultSeedColor;
  static const bool defaultAutoCenterOnSelection = true;
  static const bool defaultShowBackwardConnections = true;

  /// Notifier for routing back-connection visibility changes.
  final showBackwardConnectionsNotifier = ValueNotifier<bool>(
    defaultShowBackwardConnections,
  );

  /// Initialize the settings service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Initialize notifier with stored value
    cpuMonitorEnabledNotifier.value = cpuMonitorEnabled;
    uiScaleNotifier.value = uiScale;
    themeSeedColorNotifier.value = themeSeedColor;
    videoToolbarAlwaysVisibleNotifier.value = videoToolbarAlwaysVisible;
    contextualHelpEnabledNotifier.value = showContextualHelp;
    showBackwardConnectionsNotifier.value = showBackwardConnections;
  }

  /// Get the global UI scale factor, clamped to the allowed range.
  double get uiScale {
    final stored = _prefs?.getDouble(_uiScaleKey) ?? defaultUiScale;
    return stored.clamp(minUiScale, maxUiScale);
  }

  /// Set the global UI scale factor. Value is clamped before storage and the
  /// [uiScaleNotifier] is updated so listeners rebuild.
  Future<bool> setUiScale(double value) async {
    final clamped = _clampUiScale(value);
    final result = await _prefs?.setDouble(_uiScaleKey, clamped) ?? false;
    if (result) {
      uiScaleNotifier.value = clamped;
    }
    return result;
  }

  /// Increase UI scale by [uiScaleStep] (clamped). Returns the new scale.
  Future<double> zoomInUi() async {
    final next = _clampUiScale(uiScale + uiScaleStep);
    await setUiScale(next);
    return next;
  }

  /// Decrease UI scale by [uiScaleStep] (clamped). Returns the new scale.
  Future<double> zoomOutUi() async {
    final next = _clampUiScale(uiScale - uiScaleStep);
    await setUiScale(next);
    return next;
  }

  /// Reset UI scale back to [defaultUiScale]. Returns the new scale.
  Future<double> resetUiScale() async {
    await setUiScale(defaultUiScale);
    return defaultUiScale;
  }

  /// The opaque Material 3 seed shared by every application theme variant.
  Color get themeSeedColor {
    final stored = _prefs?.getInt(_themeSeedColorKey);
    return _opaqueColor(stored ?? defaultThemeSeedColor.toARGB32());
  }

  /// Persist an opaque Material 3 seed and rebuild listening application roots.
  Future<bool> setThemeSeedColor(Color value) async {
    final opaque = _opaqueColor(value.toARGB32());
    final result =
        await _prefs?.setInt(_themeSeedColorKey, opaque.toARGB32()) ?? false;
    if (result) {
      themeSeedColorNotifier.value = opaque;
    }
    return result;
  }

  Color _opaqueColor(int argb) {
    final opaqueArgb = 0xFF000000 | (argb & 0x00FFFFFF);
    return Color(opaqueArgb);
  }

  /// Clamp and round a scale value to one decimal place.
  double _clampUiScale(double value) {
    final clamped = value.clamp(minUiScale, maxUiScale);
    return (clamped * 10).roundToDouble() / 10;
  }

  Map<String, dynamic> _deepStringMap(Map value) {
    return value.map((key, entryValue) {
      if (entryValue is Map) {
        return MapEntry(key.toString(), _deepStringMap(entryValue));
      }
      if (entryValue is List) {
        return MapEntry(
          key.toString(),
          entryValue
              .map((item) => item is Map ? _deepStringMap(item) : item)
              .toList(),
        );
      }
      return MapEntry(key.toString(), entryValue);
    });
  }

  /// Get the request timeout in milliseconds
  int get requestTimeout =>
      _prefs?.getInt(_requestTimeoutKey) ?? defaultRequestTimeout;

  /// Set the request timeout in milliseconds
  Future<bool> setRequestTimeout(int value) async {
    return await _prefs?.setInt(_requestTimeoutKey, value) ?? false;
  }

  /// Get the inter-message delay in milliseconds
  int get interMessageDelay =>
      _prefs?.getInt(_interMessageDelayKey) ?? defaultInterMessageDelay;

  /// Set the inter-message delay in milliseconds
  Future<bool> setInterMessageDelay(int value) async {
    return await _prefs?.setInt(_interMessageDelayKey, value) ?? false;
  }

  /// Check if haptics are enabled
  bool get hapticsEnabled =>
      _prefs?.getBool(_hapticsEnabledKey) ?? defaultHapticsEnabled;

  /// Set whether haptics are enabled
  Future<bool> setHapticsEnabled(bool value) async {
    return await _prefs?.setBool(_hapticsEnabledKey, value) ?? false;
  }

  /// Check if MCP service is enabled
  bool get mcpEnabled => Platform.isIOS
      ? ipadMcpEnabled
      : _prefs?.getBool(_mcpEnabledKey) ?? defaultMcpEnabled;

  /// Separate opt-in: restored desktop preferences must never enable iPad MCP.
  bool get ipadMcpEnabled => _prefs?.getBool(_ipadMcpEnabledKey) ?? false;

  Future<bool> setIpadMcpEnabled(bool value) async =>
      await _prefs?.setBool(_ipadMcpEnabledKey, value) ?? false;

  /// Set whether MCP service is enabled
  Future<bool> setMcpEnabled(bool value) async {
    if (Platform.isIOS) return setIpadMcpEnabled(value);
    return await _prefs?.setBool(_mcpEnabledKey, value) ?? false;
  }

  /// Check if MCP remote connections are allowed
  bool get mcpRemoteConnections =>
      _prefs?.getBool(_mcpRemoteConnectionsKey) ?? defaultMcpRemoteConnections;

  /// Set whether MCP remote connections are allowed
  Future<bool> setMcpRemoteConnections(bool value) async {
    return await _prefs?.setBool(_mcpRemoteConnectionsKey, value) ?? false;
  }

  /// Check if algorithm pages should start collapsed
  bool get startPagesCollapsed =>
      _prefs?.getBool(_startPagesCollapsedKey) ?? defaultStartPagesCollapsed;

  /// Set whether algorithm pages should start collapsed
  Future<bool> setStartPagesCollapsed(bool value) async {
    return await _prefs?.setBool(_startPagesCollapsedKey, value) ?? false;
  }

  /// Get the gallery URL
  String get galleryUrl =>
      _prefs?.getString(_galleryUrlKey) ?? defaultGalleryUrl;

  /// Set the gallery URL
  Future<bool> setGalleryUrl(String value) async {
    return await _prefs?.setString(_galleryUrlKey, value) ?? false;
  }

  /// Get the GraphQL endpoint URL
  String get graphqlEndpoint =>
      _prefs?.getString(_graphqlEndpointKey) ?? defaultGraphqlEndpoint;

  /// Set the GraphQL endpoint URL
  Future<bool> setGraphqlEndpoint(String value) async {
    return await _prefs?.setString(_graphqlEndpointKey, value) ?? false;
  }

  /// Check if community plugins should be included in preset packages by default
  bool get includeCommunityPlugins =>
      _prefs?.getBool(_includeCommunityPluginsKey) ??
      defaultIncludeCommunityPlugins;

  /// Set whether community plugins should be included in preset packages by default
  Future<bool> setIncludeCommunityPlugins(bool value) async {
    return await _prefs?.setBool(_includeCommunityPluginsKey, value) ?? false;
  }

  /// Get the overlay X position
  double get overlayPositionX =>
      _prefs?.getDouble(_overlayPositionXKey) ?? defaultOverlayPositionX;

  /// Set the overlay X position
  Future<bool> setOverlayPositionX(double value) async {
    return await _prefs?.setDouble(_overlayPositionXKey, value) ?? false;
  }

  /// Get the overlay Y position
  double get overlayPositionY =>
      _prefs?.getDouble(_overlayPositionYKey) ?? defaultOverlayPositionY;

  /// Set the overlay Y position
  Future<bool> setOverlayPositionY(double value) async {
    return await _prefs?.setDouble(_overlayPositionYKey, value) ?? false;
  }

  /// Get the overlay size scale
  double get overlaySizeScale =>
      _prefs?.getDouble(_overlaySizeScaleKey) ?? defaultOverlaySizeScale;

  /// Set the overlay size scale
  Future<bool> setOverlaySizeScale(double value) async {
    return await _prefs?.setDouble(_overlaySizeScaleKey, value) ?? false;
  }

  /// Check if desktop video should open in a separate native window.
  bool get videoPopupNativeWindowEnabled =>
      _prefs?.getBool(_videoPopupNativeWindowEnabledKey) ??
      defaultVideoPopupNativeWindowEnabled;

  /// Set whether desktop video should open in a separate native window.
  Future<bool> setVideoPopupNativeWindowEnabled(bool value) async {
    return await _prefs?.setBool(_videoPopupNativeWindowEnabledKey, value) ??
        false;
  }

  /// Check if video toolbar controls should remain visible.
  bool get videoToolbarAlwaysVisible =>
      _prefs?.getBool(_videoToolbarAlwaysVisibleKey) ??
      defaultVideoToolbarAlwaysVisible;

  /// Set whether video toolbar controls should remain visible.
  Future<bool> setVideoToolbarAlwaysVisible(bool value) async {
    final result =
        await _prefs?.setBool(_videoToolbarAlwaysVisibleKey, value) ?? false;
    if (result) {
      videoToolbarAlwaysVisibleNotifier.value = value;
    }
    return result;
  }

  /// Check if the native video popup should float above other windows.
  bool get videoPopupAlwaysOnTop =>
      _prefs?.getBool(_videoPopupAlwaysOnTopKey) ??
      defaultVideoPopupAlwaysOnTop;

  /// Set whether the native video popup should float above other windows.
  Future<bool> setVideoPopupAlwaysOnTop(bool value) async {
    return await _prefs?.setBool(_videoPopupAlwaysOnTopKey, value) ?? false;
  }

  double get videoPopupBoundsX =>
      _prefs?.getDouble(_videoPopupBoundsXKey) ?? defaultVideoPopupBoundsX;

  double get videoPopupBoundsY =>
      _prefs?.getDouble(_videoPopupBoundsYKey) ?? defaultVideoPopupBoundsY;

  double get videoPopupBoundsWidth =>
      _prefs?.getDouble(_videoPopupBoundsWidthKey) ??
      defaultVideoPopupBoundsWidth;

  double get videoPopupBoundsHeight =>
      _prefs?.getDouble(_videoPopupBoundsHeightKey) ??
      defaultVideoPopupBoundsHeight;

  Future<bool> setVideoPopupBounds(Rect bounds) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final results = await Future.wait([
      prefs.setDouble(_videoPopupBoundsXKey, bounds.left),
      prefs.setDouble(_videoPopupBoundsYKey, bounds.top),
      prefs.setDouble(_videoPopupBoundsWidthKey, bounds.width),
      prefs.setDouble(_videoPopupBoundsHeightKey, bounds.height),
    ]);
    return results.every((result) => result);
  }

  /// Check if debug panel should be shown
  bool get showDebugPanel =>
      _prefs?.getBool(_showDebugPanelKey) ?? defaultShowDebugPanel;

  /// Set whether debug panel should be shown
  Future<bool> setShowDebugPanel(bool value) async {
    return await _prefs?.setBool(_showDebugPanelKey, value) ?? false;
  }

  /// Check if contextual help hints should be shown
  bool get showContextualHelp =>
      _prefs?.getBool(_showContextualHelpKey) ?? defaultShowContextualHelp;

  /// Set whether contextual help hints should be shown
  Future<bool> setShowContextualHelp(bool value) async {
    final result =
        await _prefs?.setBool(_showContextualHelpKey, value) ?? false;
    if (result) {
      contextualHelpEnabledNotifier.value = value;
    }
    return result;
  }

  /// Get the algorithm cache freshness duration in days
  int get algorithmCacheDays =>
      _prefs?.getInt(_algorithmCacheDaysKey) ?? defaultAlgorithmCacheDays;

  /// Set the algorithm cache freshness duration in days
  Future<bool> setAlgorithmCacheDays(int value) async {
    return await _prefs?.setInt(_algorithmCacheDaysKey, value) ?? false;
  }

  /// Check if the routing canvas should auto-center on the selected algorithm
  bool get autoCenterOnSelection =>
      _prefs?.getBool(_autoCenterOnSelectionKey) ??
      defaultAutoCenterOnSelection;

  /// Set whether the routing canvas should auto-center on the selected algorithm
  Future<bool> setAutoCenterOnSelection(bool value) async {
    return await _prefs?.setBool(_autoCenterOnSelectionKey, value) ?? false;
  }

  /// Check if backward connections should be shown on the routing canvas.
  bool get showBackwardConnections =>
      _prefs?.getBool(_showBackwardConnectionsKey) ??
      defaultShowBackwardConnections;

  /// Set whether backward connections should be shown on the routing canvas.
  Future<bool> setShowBackwardConnections(bool value) async {
    final result =
        await _prefs?.setBool(_showBackwardConnectionsKey, value) ?? false;
    if (result) {
      showBackwardConnectionsNotifier.value = value;
    }
    return result;
  }

  /// Check if CPU monitor is enabled
  bool get cpuMonitorEnabled =>
      _prefs?.getBool(_cpuMonitorEnabledKey) ?? defaultCpuMonitorEnabled;

  /// Set whether CPU monitor is enabled
  Future<bool> setCpuMonitorEnabled(bool value) async {
    final result = await _prefs?.setBool(_cpuMonitorEnabledKey, value) ?? false;
    if (result) {
      cpuMonitorEnabledNotifier.value = value;
    }
    return result;
  }

  /// Get the split-screen divider position (0.0 to 1.0, fraction of width for left pane)
  double get splitDividerPosition =>
      _prefs?.getDouble(_splitDividerPositionKey) ??
      defaultSplitDividerPosition;

  /// Set the split-screen divider position
  Future<bool> setSplitDividerPosition(double value) async {
    return await _prefs?.setDouble(_splitDividerPositionKey, value) ?? false;
  }

  /// Column IDs survive Lua label and order changes. Preferences stay on the host.
  Map<String, double> get companionColumnWidths {
    final raw = _prefs?.get(_companionColumnWidthsKey);
    if (raw is! String) return {};
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return {};
      return {
        for (final entry in value.entries)
          if (entry.key is String &&
              entry.value is num &&
              (entry.value as num).isFinite &&
              entry.value > 0 &&
              entry.value <= 2000)
            entry.key as String: (entry.value as num).toDouble(),
      };
    } on FormatException {
      return {};
    }
  }

  Future<bool> setCompanionColumnWidth(
    String companion,
    String table,
    String column,
    double width,
  ) async {
    if (!width.isFinite || width < 32 || width > 2000) {
      throw ArgumentError.value(width, 'width');
    }
    final key = jsonEncode([companion, table, column]);
    return await _prefs?.setString(
          _companionColumnWidthsKey,
          jsonEncode({...companionColumnWidths, key: width}),
        ) ??
        false;
  }

  /// Check if chat is enabled
  bool get chatEnabled =>
      _prefs?.getBool(_chatEnabledKey) ?? defaultChatEnabled;

  /// Set whether chat is enabled
  Future<bool> setChatEnabled(bool value) async {
    return await _prefs?.setBool(_chatEnabledKey, value) ?? false;
  }

  /// Get the chat panel width
  double get chatPanelWidth =>
      _prefs?.getDouble(_chatPanelWidthKey) ?? defaultChatPanelWidth;

  /// Set the chat panel width
  Future<bool> setChatPanelWidth(double value) async {
    return await _prefs?.setDouble(_chatPanelWidthKey, value) ?? false;
  }

  /// Get the configured LLM provider
  LlmProviderType get chatLlmProvider {
    final value = _prefs?.getString(_chatLlmProviderKey);
    for (final provider in LlmProviderType.values.where(
      (p) => p.isAdditional,
    )) {
      if (value == provider.name) return provider;
    }
    if (value == 'openai') return LlmProviderType.openai;
    if (value == 'openai_subscription') {
      return LlmProviderType.openaiSubscription;
    }
    if (value == 'anthropic_subscription') {
      return LlmProviderType.anthropicSubscription;
    }
    return LlmProviderType.anthropic;
  }

  /// Set the LLM provider
  Future<bool> setChatLlmProvider(LlmProviderType provider) async {
    final String value;
    switch (provider) {
      case LlmProviderType.openai:
        value = 'openai';
      case LlmProviderType.openaiSubscription:
        value = 'openai_subscription';
      case LlmProviderType.anthropicSubscription:
        value = 'anthropic_subscription';
      case LlmProviderType.anthropic:
        value = 'anthropic';
      case LlmProviderType.gemini:
      case LlmProviderType.openrouter:
      case LlmProviderType.local:
        value = provider.name;
    }
    return await _prefs?.setString(_chatLlmProviderKey, value) ?? false;
  }

  Map<LlmProviderType, AdditionalProviderConfig> get additionalChatProviders {
    final raw = _prefs?.getString(_additionalChatProvidersKey);
    if (raw == null) return const {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return Map.unmodifiable({
        for (final type in LlmProviderType.values.where((p) => p.isAdditional))
          if (data[type.name] is Map)
            type: AdditionalProviderConfig.fromJson(
              Map<String, dynamic>.from(data[type.name] as Map),
            ),
      });
    } on Object {
      return const {};
    }
  }

  Future<bool> setAdditionalChatProviders(
    Map<LlmProviderType, AdditionalProviderConfig> configs,
  ) async {
    if (configs.keys.any((p) => !p.isAdditional)) {
      throw ArgumentError('Only additional provider settings belong here');
    }
    return await _prefs?.setString(
          _additionalChatProvidersKey,
          jsonEncode({
            for (final entry in configs.entries)
              entry.key.name: entry.value.toJson(),
          }),
        ) ??
        false;
  }

  /// Get the Anthropic API key
  String? get anthropicApiKey => _prefs?.getString(_anthropicApiKeyKey);

  /// Set the Anthropic API key
  Future<bool> setAnthropicApiKey(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_anthropicApiKeyKey) ?? false;
    }
    return await _prefs?.setString(_anthropicApiKeyKey, value) ?? false;
  }

  /// Get the OpenAI API key
  String? get openaiApiKey => _prefs?.getString(_openaiApiKeyKey);

  /// Set the OpenAI API key
  Future<bool> setOpenaiApiKey(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_openaiApiKeyKey) ?? false;
    }
    return await _prefs?.setString(_openaiApiKeyKey, value) ?? false;
  }

  /// Get the Anthropic model name
  String get anthropicModel =>
      _prefs?.getString(_anthropicModelKey) ?? defaultAnthropicModel;

  /// Set the Anthropic model name
  Future<bool> setAnthropicModel(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_anthropicModelKey) ?? false;
    }
    return await _prefs?.setString(_anthropicModelKey, value) ?? false;
  }

  /// Get the OpenAI model name
  String get openaiModel =>
      _prefs?.getString(_openaiModelKey) ?? defaultOpenaiModel;

  /// Set the OpenAI model name
  Future<bool> setOpenaiModel(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_openaiModelKey) ?? false;
    }
    return await _prefs?.setString(_openaiModelKey, value) ?? false;
  }

  /// Get the OpenAI subscription model name
  String get openaiSubscriptionModel =>
      _prefs?.getString(_openaiSubscriptionModelKey) ??
      defaultOpenaiSubscriptionModel;

  /// Set the OpenAI subscription model name
  Future<bool> setOpenaiSubscriptionModel(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_openaiSubscriptionModelKey) ?? false;
    }
    return await _prefs?.setString(_openaiSubscriptionModelKey, value) ?? false;
  }

  /// Whether nt_helper may refresh Codex ChatGPT auth when a request is unauthorized.
  bool get allowCodexAuthRefresh =>
      _prefs?.getBool(_allowCodexAuthRefreshKey) ??
      defaultAllowCodexAuthRefresh;

  /// Set whether nt_helper may refresh Codex ChatGPT auth.
  Future<bool> setAllowCodexAuthRefresh(bool value) async {
    return await _prefs?.setBool(_allowCodexAuthRefreshKey, value) ?? false;
  }

  /// Local directory the chat assistant may access through chat-only tools.
  String? get chatLocalDirectory => _prefs?.getString(_chatLocalDirectoryKey);

  /// Set the local directory the chat assistant may access.
  Future<bool> setChatLocalDirectory(String value) async {
    if (value.trim().isEmpty) {
      return await _prefs?.remove(_chatLocalDirectoryKey) ?? false;
    }
    return await _prefs?.setString(_chatLocalDirectoryKey, value.trim()) ??
        false;
  }

  /// Named filesystem roots available to chat and/or MCP tools.
  List<AllowedFileRoot> get allowedFileRoots {
    final raw = _prefs?.getString(_allowedFileRootsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final roots = decoded
              .whereType<Map>()
              .map((item) => AllowedFileRoot.fromJson(_deepStringMap(item)))
              .where((root) => root.isValid)
              .toList(growable: false);
          return List.unmodifiable(roots);
        }
      } on Object {
        return const [];
      }
    }

    final legacyDirectory = chatLocalDirectory?.trim();
    if (legacyDirectory == null || legacyDirectory.isEmpty) {
      return const [];
    }
    return [
      AllowedFileRoot.chatReadSearch(
        id: 'local_context',
        label: 'Local Context',
        path: legacyDirectory,
      ),
    ];
  }

  /// Persist named filesystem roots available to chat and/or MCP tools.
  Future<bool> setAllowedFileRoots(List<AllowedFileRoot> roots) async {
    final normalized = roots
        .where((root) => root.isValid)
        .map((root) => root.toJson())
        .toList(growable: false);
    await _prefs?.remove(_chatLocalDirectoryKey);
    if (normalized.isEmpty) {
      return await _prefs?.remove(_allowedFileRootsKey) ?? false;
    }
    return await _prefs?.setString(
          _allowedFileRootsKey,
          jsonEncode(normalized),
        ) ??
        false;
  }

  /// Get the OpenAI base URL (for LM Studio, OpenRouter, etc.)
  String? get openaiBaseUrl => _prefs?.getString(_openaiBaseUrlKey);

  /// Set the OpenAI base URL
  Future<bool> setOpenaiBaseUrl(String value) async {
    if (value.isEmpty) {
      return await _prefs?.remove(_openaiBaseUrlKey) ?? false;
    }
    return await _prefs?.setString(_openaiBaseUrlKey, value) ?? false;
  }

  /// Get the dismissed update version (user chose to skip this version)
  String? get dismissedUpdateVersion =>
      _prefs?.getString(_dismissedUpdateVersionKey);

  /// Set the dismissed update version
  Future<bool> setDismissedUpdateVersion(String? value) async {
    if (value == null) {
      return await _prefs?.remove(_dismissedUpdateVersionKey) ?? false;
    }
    return await _prefs?.setString(_dismissedUpdateVersionKey, value) ?? false;
  }

  /// Get the last update check timestamp (epoch milliseconds)
  int? get lastUpdateCheckTimestamp =>
      _prefs?.getInt(_lastUpdateCheckTimestampKey);

  /// Set the last update check timestamp
  Future<bool> setLastUpdateCheckTimestamp(int value) async {
    return await _prefs?.setInt(_lastUpdateCheckTimestampKey, value) ?? false;
  }

  /// Reset every persisted setting owned by [SettingsService] to its declared
  /// default. Implemented as a bulk-remove of every key in [_persistedKeys] —
  /// getters then fall back to their declared defaults via the `?? default`
  /// pattern, so there is no risk of the reset site duplicating (and
  /// drifting from) the canonical default. Keys outside the registry — for
  /// example window-bounds or routing-editor state stored elsewhere in
  /// [SharedPreferences] — are intentionally untouched.
  Future<void> resetToDefaults() async {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final key in _persistedKeys) {
      await prefs.remove(key);
    }
    cpuMonitorEnabledNotifier.value = defaultCpuMonitorEnabled;
    uiScaleNotifier.value = defaultUiScale;
    themeSeedColorNotifier.value = defaultThemeSeedColor;
    videoToolbarAlwaysVisibleNotifier.value = defaultVideoToolbarAlwaysVisible;
    contextualHelpEnabledNotifier.value = defaultShowContextualHelp;
    showBackwardConnectionsNotifier.value = defaultShowBackwardConnections;
  }
}

/// A dialog to edit application settings
class SettingsDialog extends StatefulWidget {
  final IDistingMidiManager? midiManager;
  final List<AlgorithmInfo>? algorithms;
  final Map<String, dynamic>? ccNotificationDiagnostics;

  const SettingsDialog({
    super.key,
    this.midiManager,
    this.algorithms,
    this.ccNotificationDiagnostics,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _requestTimeoutController = TextEditingController();
  final _interMessageDelayController = TextEditingController();
  final _galleryUrlController = TextEditingController();
  final _algorithmCacheDaysController = TextEditingController();
  late bool _hapticsEnabled;
  late bool _mcpEnabled;
  late bool _mcpRemoteConnections;
  late bool _startPagesCollapsed;
  late bool _showDebugPanel;
  late bool _showContextualHelp;
  late bool _cpuMonitorEnabled;
  late bool _autoCenterOnSelection;
  late bool _showBackwardConnections;
  late bool _videoPopupNativeWindowEnabled;
  late bool _videoToolbarAlwaysVisible;
  late double _uiScale;
  late Color _themeSeedColor;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = SettingsService();
    _requestTimeoutController.text = settings.requestTimeout.toString();
    _interMessageDelayController.text = settings.interMessageDelay.toString();
    _galleryUrlController.text = settings.galleryUrl;
    _algorithmCacheDaysController.text = settings.algorithmCacheDays.toString();
    setState(() {
      _hapticsEnabled = settings.hapticsEnabled;
      _mcpEnabled = settings.mcpEnabled;
      _mcpRemoteConnections = settings.mcpRemoteConnections;
      _startPagesCollapsed = settings.startPagesCollapsed;
      _showDebugPanel = settings.showDebugPanel;
      _showContextualHelp = settings.showContextualHelp;
      _cpuMonitorEnabled = settings.cpuMonitorEnabled;
      _autoCenterOnSelection = settings.autoCenterOnSelection;
      _showBackwardConnections = settings.showBackwardConnections;
      _videoPopupNativeWindowEnabled = settings.videoPopupNativeWindowEnabled;
      _videoToolbarAlwaysVisible = settings.videoToolbarAlwaysVisible;
      _uiScale = settings.uiScale;
      _themeSeedColor = settings.themeSeedColor;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final settings = SettingsService();
      await settings.setRequestTimeout(
        int.parse(_requestTimeoutController.text),
      );
      await settings.setInterMessageDelay(
        int.parse(_interMessageDelayController.text),
      );
      await settings.setGalleryUrl(_galleryUrlController.text.trim());
      await settings.setAlgorithmCacheDays(
        int.parse(_algorithmCacheDaysController.text),
      );
      await settings.setHapticsEnabled(_hapticsEnabled);
      await settings.setMcpEnabled(_mcpEnabled);
      await settings.setMcpRemoteConnections(_mcpRemoteConnections);
      await settings.setStartPagesCollapsed(_startPagesCollapsed);
      await settings.setShowDebugPanel(_showDebugPanel);
      await settings.setShowContextualHelp(_showContextualHelp);
      await settings.setCpuMonitorEnabled(_cpuMonitorEnabled);
      await settings.setAutoCenterOnSelection(_autoCenterOnSelection);
      await settings.setShowBackwardConnections(_showBackwardConnections);
      await settings.setVideoPopupNativeWindowEnabled(
        _videoPopupNativeWindowEnabled,
      );
      await settings.setVideoToolbarAlwaysVisible(_videoToolbarAlwaysVisible);
      await settings.setUiScale(_uiScale);
      await settings.setThemeSeedColor(_themeSeedColor);

      if (mounted) {
        Navigator.of(
          context,
        ).pop(true); // Return true to indicate settings were saved
      }
    }
  }

  @override
  void dispose() {
    _requestTimeoutController.dispose();
    _interMessageDelayController.dispose();
    _galleryUrlController.dispose();
    _algorithmCacheDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Settings'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Settings content
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Request timeout setting
                    _SettingSection(
                      title: 'Request Timeout',
                      subtitle: 'Default timeout for requests',
                      child: DigitShortcutBlocker(
                        child: TextFormField(
                          controller: _requestTimeoutController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixText: 'ms',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a value';
                            }
                            final number = int.tryParse(value);
                            if (number == null) {
                              return 'Please enter a valid number';
                            }
                            if (number <= 0) {
                              return 'Value must be greater than 0';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Inter-message delay setting
                    _SettingSection(
                      title: 'Inter-Message Delay',
                      subtitle: 'Minimum time between messages',
                      child: DigitShortcutBlocker(
                        child: TextFormField(
                          controller: _interMessageDelayController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixText: 'ms',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a value';
                            }
                            final number = int.tryParse(value);
                            if (number == null) {
                              return 'Please enter a valid number';
                            }
                            if (number < 0) {
                              return 'Value must be 0 or greater';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Algorithm cache duration setting
                    _SettingSection(
                      title: 'Algorithm Cache Duration',
                      subtitle:
                          'How long to cache algorithm info before refreshing',
                      child: DigitShortcutBlocker(
                        child: TextFormField(
                          controller: _algorithmCacheDaysController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixText: 'days',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a value';
                            }
                            final number = int.tryParse(value);
                            if (number == null) {
                              return 'Please enter a valid number';
                            }
                            if (number < 0) {
                              return 'Value must be 0 or greater';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),

                    // RTT Statistics button
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: widget.midiManager != null
                          ? () {
                              context.showRttStatsDialog(
                                widget.midiManager,
                                algorithms: widget.algorithms,
                                ccNotificationDiagnostics:
                                    widget.ccNotificationDiagnostics,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.speed),
                      label: const Text('View RTT Statistics'),
                    ),
                    if (widget.midiManager == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Connect to device to view RTT stats',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // UI scale setting
                    _SettingSection(
                      title: 'UI Scale',
                      subtitle:
                          'Adjust interface size (shortcuts: ${Platform.isMacOS ? 'Cmd' : 'Ctrl'}+= to zoom in, ${Platform.isMacOS ? 'Cmd' : 'Ctrl'}+- to zoom out)',
                      child: Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _uiScale,
                              min: SettingsService.minUiScale,
                              max: SettingsService.maxUiScale,
                              divisions:
                                  ((SettingsService.maxUiScale -
                                              SettingsService.minUiScale) /
                                          SettingsService.uiScaleStep)
                                      .round(),
                              label: '${(_uiScale * 100).round()}%',
                              onChanged: (value) {
                                setState(() {
                                  _uiScale = (value * 10).roundToDouble() / 10;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${(_uiScale * 100).round()}%',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Reset to 100%',
                            onPressed:
                                _uiScale == SettingsService.defaultUiScale
                                ? null
                                : () {
                                    setState(() {
                                      _uiScale = SettingsService.defaultUiScale;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    ThemeSeedPicker(
                      value: _themeSeedColor,
                      defaultValue: SettingsService.defaultThemeSeedColor,
                      onChanged: (value) {
                        setState(() => _themeSeedColor = value);
                      },
                    ),

                    const SizedBox(height: 24),

                    // Haptics enabled setting
                    SwitchListTile(
                      title: Text(
                        'Enable Haptics',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Provide tactile feedback when interacting with the app',
                      ),
                      value: _hapticsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _hapticsEnabled = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // CPU monitor enabled setting
                    SwitchListTile(
                      title: Text(
                        'Enable CPU Monitor',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Show CPU usage in toolbar (disabling reduces MIDI traffic)',
                      ),
                      value: _cpuMonitorEnabled,
                      onChanged: (value) {
                        setState(() {
                          _cpuMonitorEnabled = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Start pages collapsed setting
                    SwitchListTile(
                      title: Text(
                        'Collapse Algorithm Pages by Default',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'When viewing an algorithm, all parameter pages will start collapsed',
                      ),
                      value: _startPagesCollapsed,
                      onChanged: (value) {
                        setState(() {
                          _startPagesCollapsed = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Contextual help setting
                    SwitchListTile(
                      title: Text(
                        'Show Contextual Help Hints',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Display helpful hints when hovering over interactive elements',
                      ),
                      value: _showContextualHelp,
                      onChanged: (value) {
                        setState(() {
                          _showContextualHelp = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Auto-center on algorithm selection setting
                    SwitchListTile(
                      title: Text(
                        'Auto-Center on Algorithm Selection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Automatically scroll the routing canvas to the selected algorithm',
                      ),
                      value: _autoCenterOnSelection,
                      onChanged: (value) {
                        setState(() {
                          _autoCenterOnSelection = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Backward connection visibility setting
                    SwitchListTile(
                      title: Text(
                        'Show Back Connections',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Show connections that route from a later slot back to an earlier slot on the routing canvas',
                      ),
                      value: _showBackwardConnections,
                      onChanged: (value) {
                        setState(() {
                          _showBackwardConnections = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux)
                      SwitchListTile(
                        title: Text(
                          'Open Video in Separate Window',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: const Text(
                          'Use a native floating video window instead of the in-app overlay',
                        ),
                        value: _videoPopupNativeWindowEnabled,
                        onChanged: (value) {
                          setState(() {
                            _videoPopupNativeWindowEnabled = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),

                    SwitchListTile(
                      title: Text(
                        'Always Show Video Toolbar',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Keep video controls visible instead of hiding them when not hovering',
                      ),
                      value: _videoToolbarAlwaysVisible,
                      onChanged: (value) {
                        setState(() {
                          _videoToolbarAlwaysVisible = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 24),

                    // Gallery URL setting
                    _SettingSection(
                      title: 'Gallery URL',
                      subtitle: 'URL for the plugin gallery JSON feed',
                      child: DigitShortcutBlocker(
                        child: TextFormField(
                          controller: _galleryUrlController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            hintText: 'https://...',
                          ),
                          keyboardType: TextInputType.url,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a URL';
                            }
                            final uri = Uri.tryParse(value.trim());
                            if (uri == null || !uri.hasScheme) {
                              return 'Please enter a valid URL';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),

                    if (Platform.isIOS)
                      IpadMcpSettings(
                        value: _mcpEnabled,
                        onChanged: (value) =>
                            setState(() => _mcpEnabled = value),
                      ),

                    // Desktop settings retain their existing behavior.
                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux) ...[
                      SwitchListTile(
                        title: Text(
                          'Enable MCP Service',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: const Text(
                          'Enable the MCP server for desktop integrations',
                        ),
                        value: _mcpEnabled,
                        onChanged: (value) {
                          setState(() {
                            _mcpEnabled = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: Text(
                          'Allow Remote MCP Connections',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: const Text(
                          'Allow connections from other devices on the network',
                        ),
                        value: _mcpRemoteConnections,
                        onChanged: _mcpEnabled
                            ? (value) {
                                setState(() {
                                  _mcpRemoteConnections = value;
                                });
                              }
                            : null,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Reset App Data section
                    _SettingSection(
                      title: 'Reset App Data',
                      subtitle:
                          'Delete all local data including cached algorithm metadata, '
                          'presets, plugin records, and settings. '
                          'Use this if you experience connection issues or data corruption. '
                          'The app will close after reset.',
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text('Reset App Data?'),
                              content: const Text(
                                'This will delete all local data:\n\n'
                                '• Cached algorithm metadata\n'
                                '• Saved presets\n'
                                '• Plugin installation records\n'
                                '• App settings and preferences\n\n'
                                'Your Disting NT hardware is not affected.\n'
                                'The app will close and you will need to reopen it.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(true),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await DatabaseIntegrityService.resetAll();
                            exit(0);
                          }
                        },
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Reset App Data'),
                      ),
                    ),

                    // Debug panel visibility setting (debug mode only)
                    if (kDebugMode)
                      SwitchListTile(
                        title: Text(
                          'Show Debug Log',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: const Text(
                          'Display debug log panel (debug mode only)',
                        ),
                        value: _showDebugPanel,
                        onChanged: (value) {
                          setState(() {
                            _showDebugPanel = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(false); // Return false to indicate cancel
                  },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saveSettings,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper widget for consistent setting sections
class _SettingSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingSection({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Extension method to easily show the settings dialog
extension SettingsDialogExtension on BuildContext {
  Future<bool?> showSettingsDialog({
    IDistingMidiManager? midiManager,
    List<AlgorithmInfo>? algorithms,
    Map<String, dynamic>? ccNotificationDiagnostics,
  }) {
    return showDialog<bool>(
      context: this,
      builder: (context) => SettingsDialog(
        midiManager: midiManager,
        algorithms: algorithms,
        ccNotificationDiagnostics: ccNotificationDiagnostics,
      ),
    );
  }
}

class _SettingsStatusCard extends StatefulWidget {
  const _SettingsStatusCard();

  @override
  State<_SettingsStatusCard> createState() => _SettingsStatusCardState();
}

class _SettingsStatusCardState extends State<_SettingsStatusCard> {
  late SettingsService _settings;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _SettingListTile(
              icon: Icons.timer,
              title: 'Request Timeout',
              value: '${_settings.requestTimeout} ms',
            ),
            const Divider(),
            _SettingListTile(
              icon: Icons.message,
              title: 'Inter-Message Delay',
              value: '${_settings.interMessageDelay} ms',
            ),
            const Divider(),
            _SettingListTile(
              icon: Icons.vibration,
              title: 'Haptics',
              value: _settings.hapticsEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    // This will refresh the widget to show updated settings
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _SettingListTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
