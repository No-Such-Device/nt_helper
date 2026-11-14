import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/services/debug_service.dart';

class DebugPanel extends StatefulWidget {
  final VoidCallback? onDismiss;

  const DebugPanel({super.key, this.onDismiss});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  final ScrollController _scrollController = ScrollController();
  final DebugService _debugService = DebugService();

  @override
  void initState() {
    super.initState();
    // Auto-scroll to bottom when new messages arrive
    _debugService.debugStream.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const ExcludeSemantics(child: Icon(Icons.bug_report, size: 16)),
                const SizedBox(width: 8),
                const Text(
                  'Debug Log',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  onPressed: () {
                    final text = _debugService.debugMessages.join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear'),
                  onPressed: () {
                    _debugService.clearMessages();
                    setState(() {});
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, semanticLabel: 'Dismiss panel'),
                  iconSize: 16,
                  onPressed: widget.onDismiss,
                  tooltip: 'Dismiss panel',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 200,
            child: StreamBuilder<String>(
              stream: _debugService.debugStream,
              builder: (context, snapshot) {
                final messages = _debugService.debugMessages;

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No debug messages yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.0),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
