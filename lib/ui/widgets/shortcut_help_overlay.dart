import 'dart:io';

import 'package:material_ui/material_ui.dart';

class ShortcutHelpOverlay extends StatelessWidget {
  const ShortcutHelpOverlay({super.key});

  static void show(BuildContext context) {
    showDialog(context: context, builder: (_) => const ShortcutHelpOverlay());
  }

  String get _mod => Platform.isMacOS ? 'Cmd' : 'Ctrl';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Semantics(
          label: 'Keyboard shortcuts',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                child: Row(
                  children: [
                    Text(
                      'Keyboard Shortcuts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      autofocus: true,
                      icon: const Icon(Icons.close, semanticLabel: 'Close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  children: [
                    _buildSection(context, 'Global', [
                      _ShortcutEntry('$_mod+S', 'Save Preset'),
                      _ShortcutEntry('$_mod+A', 'Add Algorithm'),
                      _ShortcutEntry('$_mod+O', 'File Browser'),
                      _ShortcutEntry('$_mod+N', 'New Preset'),
                      _ShortcutEntry('$_mod+R', 'Refresh'),
                      _ShortcutEntry('$_mod+1', 'Parameters Mode'),
                      _ShortcutEntry('$_mod+2', 'Routing Mode'),
                      _ShortcutEntry(
                        '$_mod+3',
                        'Split View (Parameters + Routing)',
                      ),
                      _ShortcutEntry('$_mod+[', 'Previous Slot'),
                      _ShortcutEntry('$_mod+]', 'Next Slot'),
                      _ShortcutEntry('$_mod+L', 'Toggle Chat Panel'),
                      _ShortcutEntry('$_mod+T', 'Template Manager'),
                      _ShortcutEntry(
                        '$_mod+C',
                        'Copy Selected Slots to Algorithm Clipboard',
                      ),
                      _ShortcutEntry(
                        '$_mod+V',
                        'Paste Algorithm Clipboard to End of Preset',
                      ),
                      _ShortcutEntry(
                        'Esc',
                        'Clear Algorithm Clipboard Selection',
                      ),
                      _ShortcutEntry('$_mod+/', 'Show This Help'),
                    ]),
                    _buildSection(context, 'Parameters', [
                      _ShortcutEntry('1-9', 'Jump to Parameter Page'),
                    ]),
                    _buildSection(context, 'Routing', [
                      _ShortcutEntry('$_mod+= / $_mod++', 'Zoom In'),
                      _ShortcutEntry('$_mod+-', 'Zoom Out'),
                      _ShortcutEntry('$_mod+0', 'Reset Zoom'),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_ShortcutEntry> entries,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: Semantics(
                      label: '${entry.shortcut}: ${entry.description}',
                      excludeSemantics: true,
                      child: Text(
                        entry.shortcut,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutEntry {
  final String shortcut;
  final String description;
  const _ShortcutEntry(this.shortcut, this.description);
}
