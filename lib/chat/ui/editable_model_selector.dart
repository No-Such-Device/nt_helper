import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

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
      if (current.isNotEmpty && !suggestions.any((m) => m.id == current))
        LlmModelOption(id: current, displayName: current),
      ...suggestions,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Model', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            SettingsStatusIndicator(
              loading: loading,
              error: error,
              readyLabel: suggestions.isEmpty ? null : 'Models loaded',
            ),
            IconButton(
              tooltip: 'Refresh model list',
              onPressed: loading ? null : onRefresh,
              icon: const Icon(
                Icons.refresh,
                semanticLabel: 'Refresh model list',
              ),
            ),
          ],
        ),
        DigitShortcutBlocker(
          includePeriod: true,
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
                  (m) => DropdownMenuEntry<String>(
                    value: m.id,
                    label: m.displayName,
                  ),
                )
                .toList(),
            onSelected: (model) {
              if (model != null) controller.text = model;
            },
          ),
        ),
      ],
    );
  }
}

/// Status always occupies the same small slot. Details stay available through
/// tooltips and live semantics without adding paragraphs to the settings form.
class SettingsStatusIndicator extends StatelessWidget {
  final bool loading;
  final String? error;
  final String? readyLabel;
  final String loadingLabel;
  const SettingsStatusIndicator({
    super.key,
    this.loading = false,
    this.error,
    this.readyLabel,
    this.loadingLabel = 'Loading models',
  });

  @override
  Widget build(BuildContext context) {
    final message = error ?? (loading ? loadingLabel : readyLabel);
    final Widget? indicator = loading
        ? const Padding(
            padding: EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : error == null
        ? null
        : Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          );
    return Semantics(
      container: true,
      liveRegion: message != null,
      label: message,
      child: SizedBox.square(
        dimension: 24,
        child: indicator == null
            ? null
            : Tooltip(
                message: message!,
                excludeFromSemantics: true,
                child: ExcludeSemantics(child: indicator),
              ),
      ),
    );
  }
}
