import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/chat/models/additional_provider_config.dart';
import 'package:nt_helper/chat/providers/openai_endpoint.dart';
import 'package:nt_helper/chat/services/gemini_model_catalog.dart';
import 'package:nt_helper/chat/ui/additional_provider_fields.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/chat/ui/editable_model_selector.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

typedef AdditionalCatalogFactory = ChatModelCatalog Function(
  LlmProviderType provider,
  AdditionalProviderConfig config,
);

class ChatSettingsDialog extends StatefulWidget {
  final AdditionalCatalogFactory? additionalCatalogFactory;
  const ChatSettingsDialog({super.key, this.additionalCatalogFactory});

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  final _settings = SettingsService();
  final _codexAuthService = CodexAuthService();
  final _uuid = const Uuid();
  late final OpenAISubscriptionModelCatalog _openaiSubscriptionModelCatalog;
  late LlmProviderType _provider;
  late bool _useAnthropicSubscription;
  late bool _useOpenaiSubscription;
  late bool _allowCodexAuthRefresh;
  late List<AllowedFileRoot> _allowedRoots;
  late final TextEditingController _anthropicKeyController;
  late final TextEditingController _openaiKeyController;
  late final TextEditingController _anthropicModelController;
  late final TextEditingController _openaiModelController;
  late final TextEditingController _openaiSubscriptionModelController;
  late final TextEditingController _openaiBaseUrlController;
  bool _showAdvanced = false;
  bool? _codexAuthFound;
  String? _codexAuthError;
  bool _modelListLoading = false;
  String? _modelListError;
  int _modelLoadGeneration = 0;
  List<LlmModelOption> _anthropicModels = const [];
  List<LlmModelOption> _openAIModels = const [];
  List<LlmModelOption> _openaiSubscriptionModels = const [];
  final _extraKeys = <LlmProviderType, TextEditingController>{};
  final _extraModels = <LlmProviderType, TextEditingController>{};
  final _extraOptions = <LlmProviderType, List<LlmModelOption>>{};
  late final TextEditingController _localUrl;
  late final TextEditingController _localContext;
  ChatModelCatalog? _activeAdditionalCatalog;
  bool _saving = false;
  String? _saveError;

  bool get _isOpenAI => _provider == LlmProviderType.openai;
  bool get _isOpenaiSubscription => _isOpenAI && _useOpenaiSubscription;

  /// The effective provider type, factoring in subscription toggles.
  LlmProviderType get _effectiveProvider {
    if (_isOpenaiSubscription) return LlmProviderType.openaiSubscription;
    if (_provider == LlmProviderType.anthropic && _useAnthropicSubscription) {
      return LlmProviderType.anthropicSubscription;
    }
    return _provider;
  }

  @override
  void initState() {
    super.initState();
    _openaiSubscriptionModelCatalog = OpenAISubscriptionModelCatalog(
      authService: _codexAuthService,
    );
    final savedProvider = _settings.chatLlmProvider;
    _useAnthropicSubscription =
        savedProvider == LlmProviderType.anthropicSubscription;
    _useOpenaiSubscription =
        savedProvider == LlmProviderType.openaiSubscription;
    _allowCodexAuthRefresh = _settings.allowCodexAuthRefresh;
    // Collapse subscription providers back to their provider tabs.
    _provider = savedProvider == LlmProviderType.anthropicSubscription
        ? LlmProviderType.anthropic
        : savedProvider == LlmProviderType.openaiSubscription
        ? LlmProviderType.openai
        : savedProvider;
    _anthropicKeyController = TextEditingController(
      text: _settings.anthropicApiKey,
    );
    _openaiKeyController = TextEditingController(text: _settings.openaiApiKey);
    _anthropicModelController = TextEditingController(
      text: _settings.anthropicModel,
    );
    _openaiModelController = TextEditingController(text: _settings.openaiModel);
    _openaiSubscriptionModelController = TextEditingController(
      text: _settings.openaiSubscriptionModel,
    );
    _openaiBaseUrlController = TextEditingController(
      text: _settings.openaiBaseUrl,
    );
    final extras = _settings.additionalChatProviders;
    for (final type in LlmProviderType.values.where((p) => p.isAdditional)) {
      final config = extras[type] ?? const AdditionalProviderConfig();
      _extraKeys[type] = TextEditingController(text: config.apiKey);
      _extraModels[type] = TextEditingController(text: config.model);
    }
    final local =
        extras[LlmProviderType.local] ?? const AdditionalProviderConfig();
    _localUrl = TextEditingController(
      text: local.baseUrl.isEmpty ? defaultLocalBaseUrl : local.baseUrl,
    );
    _localContext = TextEditingController(
      text: local.contextWindowTokens?.toString() ?? '',
    );
    _allowedRoots = _settings.allowedFileRoots.toList();
    _showAdvanced =
        _settings.openaiBaseUrl != null && _settings.openaiBaseUrl!.isNotEmpty;
    _loadSelectedModels();
  }

  @override
  void dispose() {
    _activeAdditionalCatalog?.dispose();
    for (final controller in [
      ..._extraKeys.values,
      ..._extraModels.values,
      _localUrl,
      _localContext,
    ]) {
      controller.dispose();
    }
    _anthropicKeyController.dispose();
    _openaiKeyController.dispose();
    _anthropicModelController.dispose();
    _openaiModelController.dispose();
    _openaiSubscriptionModelController.dispose();
    _openaiBaseUrlController.dispose();
    _openaiSubscriptionModelCatalog.dispose();
    _codexAuthService.dispose();
    super.dispose();
  }

  AdditionalProviderConfig _draft(LlmProviderType type) {
    final model = _extraModels[type]!.text.trim();
    final saved = _settings.additionalChatProviders[type];
    int? window = type == LlmProviderType.local
        ? int.tryParse(_localContext.text.trim())
        : null;
    if (type != LlmProviderType.local) {
      for (final option in _extraOptions[type] ?? const <LlmModelOption>[]) {
        if (option.id == model) {
          window = option.contextWindowTokens;
          break;
        }
      }
      if (window == null && saved?.model == model) {
        window = saved?.contextWindowTokens;
      }
    }
    return AdditionalProviderConfig(
      apiKey: _extraKeys[type]!.text.trim(),
      model: model,
      baseUrl: type == LlmProviderType.local ? _localUrl.text.trim() : '',
      contextWindowTokens: window,
    );
  }

  String? _validateAdditional(AdditionalProviderConfig config) {
    if (config.model.isEmpty) {
      return 'Choose or enter a model ID for ${_provider.label}.';
    }
    if (_provider != LlmProviderType.local && config.apiKey.isEmpty) {
      return 'Enter an API key for ${_provider.label}.';
    }
    if (_provider == LlmProviderType.local) {
      try {
        chatCompletionsUri(config.baseUrl);
      } on FormatException {
        return 'Enter an HTTP(S) server URL without credentials, a query or fragment.';
      }
      if (_localContext.text.trim().isNotEmpty &&
          (config.contextWindowTokens == null ||
              config.contextWindowTokens! <= 0)) {
        return 'The local context window must be a positive number of tokens.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final effective = _effectiveProvider;
    final config = _provider.isAdditional ? _draft(_provider) : null;
    final error = config == null ? null : _validateAdditional(config);
    if (error != null) {
      setState(() => _saveError = error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    Future<void> write(Future<bool> setting) async {
      if (!await setting) throw StateError('Settings storage unavailable');
    }

    try {
      if (effective == LlmProviderType.openaiSubscription) {
        final authFound = await _codexAuthService.authFound();
        if (!mounted) return;
        if (!authFound) {
          setState(() {
            _codexAuthFound = false;
            _codexAuthError =
                'Codex auth not found. Run `codex login` in a terminal.';
            _saveError = _codexAuthError;
          });
          return;
        }
      }
      await write(
        _settings.setAnthropicApiKey(_anthropicKeyController.text.trim()),
      );
      await write(_settings.setOpenaiApiKey(_openaiKeyController.text.trim()));
      await write(
        _settings.setAnthropicModel(_anthropicModelController.text.trim()),
      );
      await write(_settings.setOpenaiModel(_openaiModelController.text.trim()));
      await write(
        _settings.setOpenaiSubscriptionModel(
          _openaiSubscriptionModelController.text.trim(),
        ),
      );
      await write(_settings.setAllowCodexAuthRefresh(_allowCodexAuthRefresh));
      if (_isOpenAI && !_isOpenaiSubscription) {
        await write(
          _settings.setOpenaiBaseUrl(
            _showAdvanced ? _openaiBaseUrlController.text.trim() : '',
          ),
        );
      }
      if (config != null) {
        await write(
          _settings.setAdditionalChatProviders({
            ..._settings.additionalChatProviders,
            _provider: config,
          }),
        );
      }
      await write(_settings.setAllowedFileRoots(_allowedRoots));
      // Select only after its configuration has been stored successfully.
      await write(_settings.setChatLlmProvider(effective));
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(
          () => _saveError =
              'Could not save settings. Keep this dialog open and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadSelectedModels() {
    if (_isOpenaiSubscription) return _loadOpenAISubscriptionModels();
    if (_isOpenAI) return _loadOpenAIModels();
    if (_provider == LlmProviderType.anthropic) return _loadAnthropicModels();
    return _loadAdditionalModels();
  }

  void _invalidateAdditionalModels() {
    _modelLoadGeneration++;
    _activeAdditionalCatalog?.dispose();
    _activeAdditionalCatalog = null;
    setState(() {
      _extraOptions[_provider] = const [];
      _modelListLoading = false;
      _modelListError = null;
      _saveError = null;
    });
  }

  Future<void> _loadAdditionalModels() async {
    if (!_provider.isAdditional) return;
    final type = _provider;
    final config = _draft(type);
    final generation = ++_modelLoadGeneration;
    _activeAdditionalCatalog?.dispose();
    _activeAdditionalCatalog = null;
    if (type == LlmProviderType.gemini && config.apiKey.isEmpty) {
      setState(() {
        _modelListLoading = false;
        _modelListError = null;
      });
      return;
    }
    setState(() {
      _modelListLoading = true;
      _modelListError = null;
    });
    ChatModelCatalog? catalog;
    try {
      catalog =
          widget.additionalCatalogFactory?.call(type, config) ??
          (type == LlmProviderType.gemini
              ? GeminiModelCatalog(apiKey: config.apiKey)
              : OpenAIModelCatalog(
                  apiKey: config.apiKey,
                  providerLabel: type.label,
                  requireTools: type == LlmProviderType.openrouter,
                  baseUrl: type == LlmProviderType.openrouter
                      ? openRouterChatUrl
                      : chatCompletionsUri(
                          config.baseUrl.isEmpty
                              ? defaultLocalBaseUrl
                              : config.baseUrl,
                        ).toString(),
                ));
      _activeAdditionalCatalog = catalog;
      final models = await catalog.fetchModels();
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _extraOptions[type] = models;
        _modelListLoading = false;
        _modelListError = models.isEmpty
            ? 'No models returned. You can still enter a model ID.'
            : null;
      });
    } on ModelCatalogException catch (error) {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError = '${error.message} You can still enter a model ID.';
      });
    } on Object {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError = 'Could not load models. Check the connection and refresh, or enter a model ID.';
      });
    } finally {
      catalog?.dispose();
      if (identical(_activeAdditionalCatalog, catalog)) {
        _activeAdditionalCatalog = null;
      }
    }
  }

  Future<void> _addAllowedRoot() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose Allowed Root',
    );
    if (selected == null || !mounted) return;
    final baseName = path.basename(selected);
    setState(() {
      _allowedRoots = [
        ..._allowedRoots,
        AllowedFileRoot.chatReadSearch(
          id: _uuid.v4(),
          label: baseName.isEmpty ? 'Allowed Root' : baseName,
          path: selected,
        ),
      ];
    });
  }

  Future<void> _chooseAllowedRootDirectory(int index) async {
    final current = _allowedRoots[index];
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose Allowed Root',
      initialDirectory: current.path.trim().isEmpty ? null : current.path,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _allowedRoots[index] = current.copyWith(path: selected);
    });
  }

  void _updateRoot(int index, AllowedFileRoot root) {
    setState(() => _allowedRoots[index] = root);
  }

  void _removeRoot(int index) {
    setState(() {
      _allowedRoots = [
        ..._allowedRoots.take(index),
        ..._allowedRoots.skip(index + 1),
      ];
    });
  }

  void _setPermission(
    int index,
    FileRootActor actor,
    FileRootPermission permission,
    bool enabled,
  ) {
    final root = _allowedRoots[index];
    final permissions = {...root.permissionsFor(actor)};
    if (enabled) {
      permissions.add(permission);
    } else {
      permissions.remove(permission);
    }
    final acl = {
      for (final entry in root.acl.entries) entry.key: {...entry.value},
      actor: permissions,
    };
    _updateRoot(index, root.copyWith(acl: acl));
  }

  Future<void> _loadOpenAISubscriptionModels() async {
    final generation = ++_modelLoadGeneration;
    setState(() {
      _codexAuthFound = null;
      _codexAuthError = null;
      _modelListLoading = true;
      _modelListError = null;
    });
    try {
      final models = await _openaiSubscriptionModelCatalog.fetchModels(
        allowAuthRefresh: _allowCodexAuthRefresh,
      );
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _codexAuthFound = true;
        _modelListLoading = false;
        _openaiSubscriptionModels = models;
        _modelListError = models.isEmpty
            ? 'No selectable subscription models were returned.'
            : null;
      });
    } on CodexAuthException catch (error) {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _codexAuthFound = false;
        _codexAuthError = error.message;
        _modelListLoading = false;
      });
    } on ModelCatalogException catch (error) {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _codexAuthFound = true;
        _modelListLoading = false;
        _modelListError = '${error.message} Keeping the saved model.';
      });
    } on Object {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _codexAuthFound = true;
        _modelListLoading = false;
        _modelListError =
            'Could not load subscription models. Keeping the saved model.';
      });
    }
  }

  Future<void> _loadOpenAIModels() async {
    final apiKey = _openaiKeyController.text.trim();
    final generation = ++_modelLoadGeneration;
    if (apiKey.isEmpty) {
      setState(() {
        _modelListLoading = false;
        _modelListError = 'Enter an API key to load available models.';
      });
      return;
    }

    setState(() {
      _modelListLoading = true;
      _modelListError = null;
    });
    OpenAIModelCatalog? catalog;
    try {
      catalog = OpenAIModelCatalog(
        apiKey: apiKey,
        baseUrl: _showAdvanced ? _openaiBaseUrlController.text : null,
      );
      final models = await catalog.fetchModels();
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _openAIModels = models;
        _modelListLoading = false;
        _modelListError = models.isEmpty
            ? 'No models were returned. You can still enter a model ID.'
            : null;
      });
    } on ModelCatalogException catch (error) {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError = '${error.message} You can still enter a model ID.';
      });
    } on Object {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError =
            'Could not load OpenAI models. You can still enter a model ID.';
      });
    } finally {
      catalog?.dispose();
    }
  }

  Future<void> _loadAnthropicModels() async {
    final credential = _anthropicKeyController.text.trim();
    final generation = ++_modelLoadGeneration;
    if (credential.isEmpty) {
      setState(() {
        _modelListLoading = false;
        _modelListError = _useAnthropicSubscription
            ? 'Enter an OAuth token to load available models.'
            : 'Enter an API key to load available models.';
      });
      return;
    }

    setState(() {
      _modelListLoading = true;
      _modelListError = null;
    });
    final catalog = AnthropicModelCatalog(
      credential: credential,
      subscriptionAuth: _useAnthropicSubscription,
    );
    try {
      final models = await catalog.fetchModels();
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _anthropicModels = models;
        _modelListLoading = false;
        _modelListError = models.isEmpty
            ? 'No models were returned. You can still enter a model ID.'
            : null;
      });
    } on ModelCatalogException catch (error) {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError = '${error.message} You can still enter a model ID.';
      });
    } on Object {
      if (!mounted || generation != _modelLoadGeneration) return;
      setState(() {
        _modelListLoading = false;
        _modelListError =
            'Could not load Anthropic models. You can still enter a model ID.';
      });
    } finally {
      catalog.dispose();
    }
  }

  Future<void> _setOpenaiSubscription(bool value) async {
    setState(() {
      _useOpenaiSubscription = value;
      _modelListError = null;
    });
    if (value) {
      await _loadOpenAISubscriptionModels();
    } else {
      await _loadOpenAIModels();
    }
  }

  Future<void> _setAnthropicSubscription(bool value) async {
    setState(() {
      _useAnthropicSubscription = value;
      _anthropicModels = const [];
      _modelListError = null;
    });
    await _loadAnthropicModels();
  }

  Future<void> _setProvider(LlmProviderType provider) async {
    _modelLoadGeneration++;
    _activeAdditionalCatalog?.dispose();
    _activeAdditionalCatalog = null;
    setState(() {
      _provider = provider;
      _modelListError = null;
      _saveError = null;
    });
    await _loadSelectedModels();
  }

  Future<void> _setAllowCodexAuthRefresh(bool value) async {
    if (!value) {
      setState(() => _allowCodexAuthRefresh = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Semantics(
          header: true,
          child: const Text('Allow Codex Auth Refresh?'),
        ),
        content: const Text(
          'nt_helper will refresh your Codex ChatGPT credentials when a '
          'request is rejected as unauthorized. Refresh can rotate tokens, so '
          'nt_helper may update ~/.codex/auth.json.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() => _allowCodexAuthRefresh = confirmed ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Semantics(header: true, child: const Text('Chat Settings')),
      content: SizedBox(
        width: 400,
        height: 520,
        child: FocusScope(
          canRequestFocus: !_saving,
          child: AbsorbPointer(
            absorbing: _saving,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LlmProviderType>(
                    key: const ValueKey('chat_provider'),
                    initialValue: _provider,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final type in [
                        LlmProviderType.anthropic,
                        LlmProviderType.openai,
                        LlmProviderType.gemini,
                        LlmProviderType.openrouter,
                        LlmProviderType.local,
                      ])
                        DropdownMenuItem(
                          value: type,
                          child: Text(
                            type.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _setProvider(value);
                    },
                  ),
                  if (_isOpenAI) ..._buildOpenAISettings(theme),
                  if (_provider == LlmProviderType.anthropic)
                    ..._buildAnthropicSettings(theme),
                  if (_provider.isAdditional)
                    AdditionalProviderFields(
                      provider: _provider,
                      apiKeyController: _extraKeys[_provider]!,
                      modelController: _extraModels[_provider]!,
                      localUrlController: _localUrl,
                      localContextController: _localContext,
                      models: _extraOptions[_provider] ?? const [],
                      loading: _modelListLoading,
                      error: _modelListError,
                      onRefresh: _loadAdditionalModels,
                      onConnectionChanged: _invalidateAdditionalModels,
                    ),
                  ..._buildLocalContextSettings(theme),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        SettingsStatusIndicator(
          loading: _saving,
          error: _saveError,
          loadingLabel: 'Saving settings',
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<Widget> _buildAnthropicSettings(ThemeData theme) => [
    const SizedBox(height: 12),
    SwitchListTile(
      title: Text('Use Subscription', style: theme.textTheme.titleSmall),

      value: _useAnthropicSubscription,
      onChanged: _setAnthropicSubscription,
      contentPadding: EdgeInsets.zero,
      dense: true,
    ),
    const SizedBox(height: 16),
    Text(
      _useAnthropicSubscription ? 'OAuth Token' : 'API Key',
      style: theme.textTheme.titleSmall,
    ),
    const SizedBox(height: 8),
    DigitShortcutBlocker(
      child: TextField(
        key: ValueKey('apikey_${_effectiveProvider.name}'),
        controller: _anthropicKeyController,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: _useAnthropicSubscription ? 'sk-ant-oat...' : 'sk-ant...',
          isDense: true,
        ),
        obscureText: true,
      ),
    ),
    const SizedBox(height: 16),
    EditableModelSelector(
      fieldKey: const ValueKey('model_anthropic'),
      controller: _anthropicModelController,
      suggestions: _anthropicModels,
      hintText: 'claude-haiku-4-5-20251001',
      loading: _modelListLoading,
      error: _modelListError,
      onRefresh: _loadAnthropicModels,
    ),
  ];

  List<Widget> _buildOpenAISettings(ThemeData theme) => [
    const SizedBox(height: 12),
    SwitchListTile(
      title: Text(
        'Use Subscription (Codex)',
        style: theme.textTheme.titleSmall,
      ),
      secondary: _isOpenaiSubscription
          ? SettingsStatusIndicator(
              loading: _codexAuthFound == null,
              error:
                  _codexAuthError ??
                  (_codexAuthFound == false
                      ? 'Codex authentication not found.'
                      : null),
              readyLabel: _codexAuthFound == true
                  ? 'Codex authentication found.'
                  : null,
              loadingLabel: 'Checking Codex authentication',
            )
          : null,
      value: _useOpenaiSubscription,
      onChanged: (v) => _setOpenaiSubscription(v),
      contentPadding: EdgeInsets.zero,
      dense: true,
    ),
    if (_isOpenaiSubscription) ..._buildOpenAISubscriptionSettings(theme),
    if (!_isOpenaiSubscription) ..._buildOpenAIApiKeySettings(theme),
  ];

  List<Widget> _buildOpenAISubscriptionSettings(ThemeData theme) => [
    const SizedBox(height: 8),
    EditableModelSelector(
      fieldKey: const ValueKey('model_openai_subscription'),
      controller: _openaiSubscriptionModelController,
      suggestions: _openaiSubscriptionModels,
      hintText: 'gpt-5.4-mini',
      loading: _modelListLoading,
      error: _modelListError,
      onRefresh: _loadOpenAISubscriptionModels,
    ),
    const SizedBox(height: 12),
    SwitchListTile(
      title: Text(
        'Allow nt_helper to refresh Codex auth',
        style: theme.textTheme.titleSmall,
      ),
      value: _allowCodexAuthRefresh,
      onChanged: (v) => _setAllowCodexAuthRefresh(v),
      contentPadding: EdgeInsets.zero,
      dense: true,
    ),
  ];

  List<Widget> _buildOpenAIApiKeySettings(ThemeData theme) => [
    const SizedBox(height: 16),
    Text('API Key', style: theme.textTheme.titleSmall),
    const SizedBox(height: 8),
    DigitShortcutBlocker(
      child: TextField(
        key: const ValueKey('apikey_openai'),
        controller: _openaiKeyController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'sk-...',
          isDense: true,
        ),
        obscureText: true,
      ),
    ),
    const SizedBox(height: 16),
    EditableModelSelector(
      fieldKey: const ValueKey('model_openai'),
      controller: _openaiModelController,
      suggestions: _openAIModels,
      hintText: 'gpt-5-nano',
      loading: _modelListLoading,
      error: _modelListError,
      onRefresh: _loadOpenAIModels,
    ),
    const SizedBox(height: 12),
    GestureDetector(
      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      child: Row(
        children: [
          Icon(
            _showAdvanced ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'Advanced',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    if (_showAdvanced) ...[
      const SizedBox(height: 12),
      Text('Base URL', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      DigitShortcutBlocker(
        child: TextField(
          controller: _openaiBaseUrlController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'https://api.openai.com/v1/chat/completions',
            isDense: true,
          ),
          keyboardType: TextInputType.url,
        ),
      ),
    ],
  ];

  List<Widget> _buildLocalContextSettings(ThemeData theme) => [
    const SizedBox(height: 24),
    Semantics(
      header: true,
      child: Text('Allowed File Roots', style: theme.textTheme.titleSmall),
    ),
    const SizedBox(height: 8),
    for (var i = 0; i < _allowedRoots.length; i++) ...[
      _buildAllowedRootEditor(theme, i),
      const SizedBox(height: 16),
    ],
    OutlinedButton.icon(
      onPressed: _addAllowedRoot,
      icon: const Icon(Icons.create_new_folder_outlined),
      label: const Text('Add Folder'),
    ),
  ];

  Widget _buildAllowedRootEditor(ThemeData theme, int index) {
    final root = _allowedRoots[index];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DigitShortcutBlocker(
                  child: TextFormField(
                    key: ValueKey('file_root_label_${root.id}'),
                    initialValue: root.label,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Label',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        _updateRoot(index, root.copyWith(label: value.trim())),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove allowed root',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeRoot(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DigitShortcutBlocker(
                  child: TextFormField(
                    key: ValueKey('file_root_path_${root.id}'),
                    initialValue: root.path,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Path',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        _updateRoot(index, root.copyWith(path: value.trim())),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Choose folder',
                icon: const Icon(Icons.folder_open),
                onPressed: () => _chooseAllowedRootDirectory(index),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPermissionTable(theme, index),
        ],
      ),
    );
  }

  Widget _buildPermissionTable(ThemeData theme, int index) {
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(64),
        1: FixedColumnWidth(72),
        2: FixedColumnWidth(72),
        3: FixedColumnWidth(80),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            _permissionHeader('Read', headerStyle),
            _permissionHeader('Write', headerStyle),
            _permissionHeader('Search', headerStyle),
          ],
        ),
        _permissionTableRow(theme, index, FileRootActor.chat, 'Chat'),
        _permissionTableRow(theme, index, FileRootActor.mcp, 'MCP'),
      ],
    );
  }

  TableRow _permissionTableRow(
    ThemeData theme,
    int index,
    FileRootActor actor,
    String label,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        _buildPermissionCheckbox(index, actor, FileRootPermission.read, 'Read'),
        _buildPermissionCheckbox(
          index,
          actor,
          FileRootPermission.write,
          'Write',
        ),
        _buildPermissionCheckbox(
          index,
          actor,
          FileRootPermission.search,
          'Search',
        ),
      ],
    );
  }

  Widget _permissionHeader(String label, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(child: Text(label, style: style)),
    );
  }

  Widget _buildPermissionCheckbox(
    int index,
    FileRootActor actor,
    FileRootPermission permission,
    String label,
  ) {
    final checked = _allowedRoots[index].allows(actor, permission);
    return Semantics(
      label: '${actor.storageKey} ${permission.storageKey} permission',
      checked: checked,
      button: true,
      child: Center(
        child: Checkbox(
          value: checked,
          onChanged: (value) =>
              _setPermission(index, actor, permission, value ?? false),
          semanticLabel: '$label permission for ${actor.storageKey}',
        ),
      ),
    );
  }
}
