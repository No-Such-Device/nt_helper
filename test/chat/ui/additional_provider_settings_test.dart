import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/chat/ui/chat_settings_dialog.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Catalog implements ChatModelCatalog {
  final Future<List<LlmModelOption>> result;
  bool disposed = false;
  _Catalog(this.result);
  @override
  Future<List<LlmModelOption>> fetchModels() => result;
  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  late SettingsService settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'chat_llm_provider': 'gemini',
      'anthropic_api_key': 'claude-secret',
      'openai_api_key': 'openai-secret',
      'openai_base_url': 'http://legacy:1234/v1/chat/completions',
      'chat_additional_providers': jsonEncode({
        'gemini': {'api_key': 'google-key', 'model': 'gemini-fixture'},
        'openrouter': {'api_key': 'router-key', 'model': 'vendor/fixture'},
        'local': {
          'model': 'local-fixture',
          'base_url': 'http://localhost:1234/v1',
        },
      }),
    });
    settings = SettingsService();
    await settings.init();
  });
  Future<void> open(
    WidgetTester tester, {
    AdditionalCatalogFactory? factory,
    double scale = 1,
    bool pendingModels = false,
    Brightness brightness = Brightness.dark,
    GlobalKey? boundary,
    bool evidenceFonts = false,
  }) async {
    var theme = AppTheme.build(
      seedColor: AppTheme.defaultSeedColor,
      brightness: brightness,
    );
    if (evidenceFonts) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Evidence'),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ChatSettingsDialog(
                  additionalCatalogFactory:
                      factory ??
                      (type, config) => _Catalog(
                        Future.value([
                          LlmModelOption(
                            id: config.model.isEmpty ? 'fixture' : config.model,
                            displayName: 'Fixture model',
                            contextWindowTokens: 64000,
                          ),
                        ]),
                      ),
                ),
              ),
              child: const Text('Settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    if (pendingModels) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> choose(
    WidgetTester tester,
    LlmProviderType type, {
    bool pendingModels = false,
  }) async {
    await tester.tap(find.byKey(const ValueKey('chat_provider')));
    if (pendingModels) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(type.label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'provider choices are visible and Gemini saves only its own profile',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('chat_provider')));
      await tester.pumpAndSettle();
      for (final type in [
        LlmProviderType.anthropic,
        LlmProviderType.openai,
        LlmProviderType.gemini,
        LlmProviderType.openrouter,
        LlmProviderType.local,
      ]) {
        expect(find.text(type.label), findsWidgets);
      }
      await tester.tap(find.text('Google Gemini').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('apikey_gemini')),
        'new-google-key',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSettingsDialog), findsNothing);
      expect(settings.chatLlmProvider, LlmProviderType.gemini);
      expect(
        settings.additionalChatProviders[LlmProviderType.gemini]!.apiKey,
        'new-google-key',
      );
      expect(
        settings.additionalChatProviders[LlmProviderType.openrouter]!.apiKey,
        'router-key',
      );
      expect(settings.anthropicApiKey, 'claude-secret');
      expect(settings.openaiApiKey, 'openai-secret');
      expect(settings.openaiBaseUrl, 'http://legacy:1234/v1/chat/completions');
    },
  );
  testWidgets(
    'settings omit explanatory copy and keep a labelled refresh action',
    (tester) async {
      await open(tester);
      for (final copy in [
        'stored locally',
        'Google AI Studio',
        'models available',
        'NT tools need',
        'No folders are available',
      ]) {
        expect(find.textContaining(copy), findsNothing);
      }
      expect(find.byTooltip('Refresh model list'), findsOneWidget);
      expect(find.text('Refresh model list'), findsNothing);
      await choose(tester, LlmProviderType.local);
      for (final copy in [
        'Connect to Ollama',
        'Use HTTPS',
        'advertised maximum',
      ]) {
        expect(find.textContaining(copy), findsNothing);
      }
    },
  );

  testWidgets(
    'local configuration saves without a fake key and retains the configured context window',
    (tester) async {
      await open(tester);
      await choose(tester, LlmProviderType.local);
      expect(find.byKey(const ValueKey('apikey_local')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('local_base_url')),
        'http://127.0.0.1:11434/v1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('local_context_window')),
        '16384',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(settings.chatLlmProvider, LlmProviderType.local);
      final config = settings.additionalChatProviders[LlmProviderType.local]!;
      expect(config.apiKey, isEmpty);
      expect(config.model, 'local-fixture');
      expect(config.contextWindowTokens, 16384);
    },
  );
  testWidgets(
    'invalid endpoint stays in the dialog and cannot change the selected provider',
    (tester) async {
      await open(tester);
      await choose(tester, LlmProviderType.local);
      await tester.enterText(
        find.byKey(const ValueKey('local_base_url')),
        'https://user:private@server/v1',
      );
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSettingsDialog), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              (widget.message?.contains('without credentials') ?? false),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(find.widgetWithText(FilledButton, 'Save')), save);
      expect(settings.chatLlmProvider, LlmProviderType.gemini);
    },
  , tags: ['regression']);
  testWidgets(
    'late model discovery cannot contaminate another provider or move Save',
    (tester) async {
      final pending = Completer<List<LlmModelOption>>();
      final old = _Catalog(pending.future);
      await open(
        tester,
        pendingModels: true,
        factory: (type, config) => type == LlmProviderType.gemini
            ? old
            : _Catalog(
                Future.value([
                  const LlmModelOption(
                    id: 'local-only',
                    displayName: 'Local only',
                  ),
                ]),
              ),
      );
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      await choose(tester, LlmProviderType.local, pendingModels: true);
      expect(old.disposed, isTrue);
      pending.complete([
        const LlmModelOption(id: 'google-only', displayName: 'Google only'),
      ]);
      await tester.pumpAndSettle();
      final menu = tester.widget<DropdownMenu<String>>(
        find.byKey(const ValueKey('model_local')),
      );
      expect(
        menu.dropdownMenuEntries.map((e) => e.value),
        contains('local-only'),
      );
      expect(
        menu.dropdownMenuEntries.map((e) => e.value),
        isNot(contains('google-only')),
      );
      expect(tester.getRect(find.widgetWithText(FilledButton, 'Save')), save);
    },
  , tags: ['regression']);
  testWidgets(
    'Claude subscription toggle does not turn Gemini into a Claude provider',
    (tester) async {
      await settings.setChatLlmProvider(LlmProviderType.anthropicSubscription);
      await settings.setAnthropicApiKey('');
      await open(tester);
      await choose(tester, LlmProviderType.gemini);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(settings.chatLlmProvider, LlmProviderType.gemini);
    },
  , tags: ['regression']);
  testWidgets(
    'Cancel never persists edited credentials or provider selection',
    (tester) async {
      await open(tester);
      await choose(tester, LlmProviderType.openrouter);
      await tester.enterText(
        find.byKey(const ValueKey('apikey_openrouter')),
        'unsaved-key',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(settings.chatLlmProvider, LlmProviderType.gemini);
      expect(
        settings.additionalChatProviders[LlmProviderType.openrouter]!.apiKey,
        'router-key',
      );
    },
  , tags: ['regression']);
  

  testWidgets(
    'compact enlarged settings have named controls and remain scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(380, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await settings.setChatLlmProvider(LlmProviderType.local);
      await open(tester, scale: 1.5);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chat_provider')), findsOneWidget);
      expect(find.byKey(const ValueKey('local_base_url')), findsOneWidget);
      expect(
        tester.getSize(find.byType(SingleChildScrollView).first).height,
        greaterThan(48),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );
}
