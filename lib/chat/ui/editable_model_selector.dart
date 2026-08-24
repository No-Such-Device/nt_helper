import 'dart:math' as math;

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
    final statusMessage = loading
        ? 'Loading available models…'
        : error ??
              (suggestions.isEmpty
                  ? 'Enter a model ID or refresh the available models.'
                  : '${suggestions.length} models available. You can also enter a model ID.');

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
                    label: model.displayName,
                  ),
                )
                .toList(),
            onSelected: (model) {
              if (model == null) return;
              controller.text = model;
            },
          ),
        ),
        SettingsStatusRegion(
          message: statusMessage,
          loading: loading,
          isError: error != null,
          isSuccess: !loading && error == null && suggestions.isNotEmpty,
        ),
        TextButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: const ExcludeSemantics(child: Icon(Icons.refresh)),
          label: const Text('Refresh model list'),
        ),
      ],
    );
  }
}

/// A fixed-height status lane for settings controls with asynchronous state.
///
/// Loading, success, empty, and error content all occupy the same space so
/// controls below it never move while a request is in flight.
class SettingsStatusRegion extends StatelessWidget {
  final String message;
  final bool loading;
  final bool isError;
  final bool isSuccess;

  const SettingsStatusRegion({
    super.key,
    required this.message,
    this.loading = false,
    this.isError = false,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: color);
    final textHeight = TextPainter(
      text: TextSpan(text: 'Status\nStatus', style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout();
    final laneHeight = math.max(48.0, 8 + textHeight.height.ceilToDouble());

    return SizedBox(
      height: laneHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          container: true,
          liveRegion: true,
          label: message,
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: loading
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        )
                      : Icon(
                          isError
                              ? Icons.error_outline
                              : isSuccess
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 18,
                          color: color,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
