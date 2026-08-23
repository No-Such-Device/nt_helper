import 'package:flutter/material.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

/// A model picker that offers discovered models without rejecting future or
/// locally hosted model IDs that are not present in the catalog.
class EditableModelSelector extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final List<LlmModelOption> suggestions;
  final String hintText;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  const EditableModelSelector({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.suggestions,
    required this.hintText,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim();
    final options = <LlmModelOption>[
      if (current.isNotEmpty &&
          !suggestions.any((model) => model.id == current))
        LlmModelOption(id: current, displayName: current),
      ...suggestions,
    ];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DigitShortcutBlocker(
          child: DropdownMenu<String>(
            key: fieldKey,
            controller: controller,
            requestFocusOnTap: true,
            enableFilter: true,
            enableSearch: true,
            expandedInsets: EdgeInsets.zero,
            hintText: hintText,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            dropdownMenuEntries: options
                .map(
                  (model) => DropdownMenuEntry<String>(
                    value: model.id,
                    label: model.displayName == model.id
                        ? model.id
                        : '${model.id} — ${model.displayName}',
                  ),
                )
                .toList(),
            onSelected: (model) {
              if (model == null) return;
              controller.text = model;
            },
          ),
        ),
        if (loading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: const Text('Loading available models…'),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
        TextButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: const ExcludeSemantics(child: Icon(Icons.refresh)),
          label: const Text('Refresh model list'),
        ),
      ],
    );
  }
}
