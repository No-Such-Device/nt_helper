import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/chat/ui/editable_model_selector.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

class AdditionalProviderFields extends StatelessWidget {
  final LlmProviderType provider;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final TextEditingController localUrlController;
  final TextEditingController localContextController;
  final List<LlmModelOption> models;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onConnectionChanged;

  const AdditionalProviderFields({
    super.key,
    required this.provider,
    required this.apiKeyController,
    required this.modelController,
    required this.localUrlController,
    required this.localContextController,
    required this.models,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onConnectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final local = provider == LlmProviderType.local;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (local) ...[
          DigitShortcutBlocker(
            includePeriod: true,
            child: TextField(
              key: const ValueKey('local_base_url'),
              controller: localUrlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://127.0.0.1:11434/v1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
              onChanged: (_) => onConnectionChanged(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        DigitShortcutBlocker(
          includePeriod: true,
          child: TextField(
            key: ValueKey('apikey_${provider.name}'),
            controller: apiKeyController,
            decoration: InputDecoration(
              labelText: local ? 'API key (optional)' : 'API key',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            onChanged: (_) => onConnectionChanged(),
          ),
        ),
        const SizedBox(height: 8),
        EditableModelSelector(
          fieldKey: ValueKey('model_${provider.name}'),
          controller: modelController,
          suggestions: models,
          hintText: 'Model ID',
          loading: loading,
          error: error,
          onRefresh: onRefresh,
        ),
        if (local) ...[
          const SizedBox(height: 16),
          DigitShortcutBlocker(
            includePeriod: true,
            child: TextField(
              key: const ValueKey('local_context_window'),
              controller: localContextController,
              decoration: const InputDecoration(
                labelText: 'Context tokens (optional)',
                hintText: '8192',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ],
    );
  }
}
