import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/ui/chat_input_bar.dart';
import 'package:nt_helper/chat/ui/chat_message_bubble.dart';
import 'package:nt_helper/chat/ui/chat_settings_dialog.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

class ChatPanel extends StatefulWidget {
  final bool requestInputFocus;

  const ChatPanel({super.key, this.requestInputFocus = false});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  int _previousMessageCount = 0;
  bool _previousIsProcessing = false;
  bool _wasProcessing = false;

  @override
  void initState() {
    super.initState();
    if (widget.requestInputFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestInputFocus && !oldWidget.requestInputFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  ChatSettings _loadSettings() {
    final settings = SettingsService();
    return ChatSettings(
      provider: settings.chatLlmProvider,
      anthropicApiKey: settings.anthropicApiKey,
      openaiApiKey: settings.openaiApiKey,
      anthropicModel: settings.anthropicModel,
      openaiModel: settings.openaiModel,
      openaiSubscriptionModel: settings.openaiSubscriptionModel,
      openaiBaseUrl: settings.openaiBaseUrl,
      allowCodexAuthRefresh: settings.allowCodexAuthRefresh,
      chatEnabled: settings.chatEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Chat panel',
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: BlocBuilder<ChatCubit, ChatState>(
          builder: (context, state) {
            return switch (state) {
              ChatInitial() => _buildEmpty(context),
              ChatError(message: final msg) => _buildError(context, msg),
              ChatReady() => _buildChat(context, state),
            };
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        const Expanded(child: _EmptyState()),
        ChatInputBar(
          isProcessing: false,
          onSend: (text, images, files) => _send(context, text, images, files),
          onCancel: () {},
          onSettings: () => _openSettings(context),
          focusNode: _inputFocusNode,
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      context.read<ChatCubit>().dismissError();
                      _openSettings(context);
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChat(BuildContext context, ChatReady state) {
    final messages = state.messages;
    final messageCount = messages.length;
    final isProcessing = state.isProcessing;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (messageCount > _previousMessageCount ||
          (isProcessing && !_previousIsProcessing)) {
        _scrollToBottom();
      }
      if (_wasProcessing && !state.isProcessing) {
        _inputFocusNode.requestFocus();
      }
      _previousMessageCount = messageCount;
      _previousIsProcessing = isProcessing;
      _wasProcessing = state.isProcessing;
    });

    final displayItems = _groupMessages(messages, state.isProcessing);

    return Column(
      children: [
        _buildHeader(context, state),
        Expanded(
          child: ExcludeFocus(
            child: messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: displayItems.length,
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      return switch (item) {
                        _SingleMessage(:final message, :final isNew) =>
                          ChatMessageBubble(message: message, isNew: isNew),
                        _ToolGroup(:final messages) => ToolGroupBubble(
                          messages: messages,
                        ),
                        _Thinking() => ChatMessageBubble(
                          message: ChatMessage.thinking(),
                        ),
                      };
                    },
                  ),
          ),
        ),
        if (state.totalInputTokens > 0 || state.totalOutputTokens > 0)
          _TokenUsageBar(
            inputTokens: state.totalInputTokens,
            outputTokens: state.totalOutputTokens,
          ),
        ChatInputBar(
          isProcessing: state.isProcessing,
          onSend: (text, images, files) => _send(context, text, images, files),
          onCancel: () => context.read<ChatCubit>().cancelProcessing(),
          onSettings: () => _openSettings(context),
          focusNode: _inputFocusNode,
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, [ChatReady? state]) {
    final theme = Theme.of(context);
    final readyState = state ?? const ChatReady();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('Chat', style: theme.textTheme.titleSmall),
          const Spacer(),
          _ContextStatusButton(
            state: readyState,
            summary: context.read<ChatCubit>().contextSummary,
            settings: _loadSettings(),
            onCompact: (settings) {
              context.read<ChatCubit>().compactContext(settings);
            },
            onClearChat: () => _confirmClearChat(context),
          ),
        ],
      ),
    );
  }

  void _send(
    BuildContext context,
    String text,
    List<ChatImageAttachment> imageAttachments,
    List<ChatFileAttachment> fileAttachments,
  ) {
    final settings = _loadSettings();
    context.read<ChatCubit>().sendMessage(
      text,
      settings,
      imageAttachments: imageAttachments,
      fileAttachments: fileAttachments,
    );
  }

  void _openSettings(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => const ChatSettingsDialog(),
    );
  }

  Future<void> _confirmClearChat(BuildContext context) async {
    final cubit = context.read<ChatCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This removes the visible conversation and current model context.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Clear chat'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      cubit.clearChat();
    }
  }
}

enum _ContextMenuAction { compact, clear }

class _ContextStatusButton extends StatelessWidget {
  final ChatReady state;
  final ChatContextSummary summary;
  final ChatSettings settings;
  final ValueChanged<ChatSettings> onCompact;
  final VoidCallback onClearChat;

  const _ContextStatusButton({
    required this.state,
    required this.summary,
    required this.settings,
    required this.onCompact,
    required this.onClearChat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _contextProgress(state);
    final percent = (progress * 100).round();
    final canCompact =
        !state.isProcessing && !summary.isEmpty && settings.hasApiKey;
    final canClear = state.messages.isNotEmpty || !summary.isEmpty;
    return Semantics(
      label: 'Context status, $percent percent used',
      button: true,
      child: PopupMenuButton<_ContextMenuAction>(
        tooltip: 'Context status',
        position: PopupMenuPosition.under,
        onSelected: (action) {
          switch (action) {
            case _ContextMenuAction.compact:
              onCompact(settings);
            case _ContextMenuAction.clear:
              onClearChat();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_ContextMenuAction>(
            enabled: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: 320,
              child: Theme(
                data: theme,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Context', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _ContextDetails(state: state, summary: summary),
                  ],
                ),
              ),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<_ContextMenuAction>(
            enabled: canCompact,
            value: _ContextMenuAction.compact,
            child: const Row(
              children: [
                Icon(Icons.compress, size: 18),
                SizedBox(width: 12),
                Text('Compact context'),
              ],
            ),
          ),
          PopupMenuItem<_ContextMenuAction>(
            enabled: canClear,
            value: _ContextMenuAction.clear,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: canClear ? theme.colorScheme.error : null,
                ),
                const SizedBox(width: 12),
                Text(
                  'Clear chat...',
                  style: canClear
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
              ],
            ),
          ),
        ],
        icon: CustomPaint(
          size: const Size.square(22),
          painter: _ContextArcPainter(
            progress: progress,
            color: _contextColor(theme, progress),
            trackColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _ContextArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  const _ContextArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = 2.5;
    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final foreground = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, -1.5708, 6.2832, false, track);
    canvas.drawArc(
      arcRect,
      -1.5708,
      6.2832 * progress.clamp(0.0, 1.0),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _ContextArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

class _ContextDetails extends StatelessWidget {
  final ChatReady state;
  final ChatContextSummary summary;

  const _ContextDetails({required this.state, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _contextProgress(state);
    final used = _formatNumber(state.contextInputTokens);
    final window = _formatNumber(state.contextWindowTokens);
    final hasAttachments =
        summary.imageAttachments > 0 || summary.fileAttachments > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CustomPaint(
              size: const Size.square(32),
              painter: _ContextArcPainter(
                progress: progress,
                color: _contextColor(theme, progress),
                trackColor: theme.colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${(progress * 100).round()}% used\n$used / $window input tokens',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Breakdown', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _ContextDetailRow('Messages', summary.messageCount.toString()),
        _ContextDetailRow(
          'Turns',
          '${summary.userMessages} user / ${summary.assistantMessages} assistant',
        ),
        _ContextDetailRow(
          'Tools',
          '${summary.toolCalls} calls / ${summary.toolResults} results',
        ),
        if (hasAttachments)
          _ContextDetailRow(
            'Attachments',
            '${summary.imageAttachments} images / ${summary.fileAttachments} files',
          ),
        _ContextDetailRow(
          'Text',
          '~${_formatNumber(summary.approxCharacters)} chars',
        ),
      ],
    );
  }
}

class _ContextDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ContextDetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask me about your preset',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'I can search algorithms, show routing,\nedit parameters, and more.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenUsageBar extends StatelessWidget {
  final int inputTokens;
  final int outputTokens;

  const _TokenUsageBar({required this.inputTokens, required this.outputTokens});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        'Tokens: ${_formatNumber(inputTokens)} in / ${_formatNumber(outputTokens)} out',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

double _contextProgress(ChatReady state) {
  if (state.contextWindowTokens <= 0) return 0;
  return (state.contextInputTokens / state.contextWindowTokens).clamp(0.0, 1.0);
}

Color _contextColor(ThemeData theme, double progress) {
  const compactionThreshold = 0.85;
  final thresholdProgress = progress / compactionThreshold;
  if (thresholdProgress >= 0.9) return theme.colorScheme.error;
  if (thresholdProgress >= 0.7) return theme.appColors.warning.color;
  return theme.appColors.success.color;
}

String _formatNumber(int n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

// Display item types for grouping tool messages
sealed class _DisplayItem {}

class _SingleMessage extends _DisplayItem {
  final ChatMessage message;
  final bool isNew;
  _SingleMessage(this.message, {this.isNew = false});
}

class _ToolGroup extends _DisplayItem {
  final List<ChatMessage> messages;
  _ToolGroup(this.messages);
}

class _Thinking extends _DisplayItem {}

List<_DisplayItem> _groupMessages(
  List<ChatMessage> messages,
  bool isProcessing,
) {
  final items = <_DisplayItem>[];
  int i = 0;
  while (i < messages.length) {
    final msg = messages[i];
    if (msg.role == ChatMessageRole.toolCall ||
        msg.role == ChatMessageRole.toolResult) {
      final toolMessages = <ChatMessage>[];
      while (i < messages.length &&
          (messages[i].role == ChatMessageRole.toolCall ||
              messages[i].role == ChatMessageRole.toolResult)) {
        toolMessages.add(messages[i]);
        i++;
      }
      items.add(_ToolGroup(toolMessages));
    } else {
      final isLast = i == messages.length - 1;
      final hasThinking = isProcessing;
      items.add(_SingleMessage(msg, isNew: isLast && !hasThinking));
      i++;
    }
  }
  if (isProcessing) {
    items.add(_Thinking());
  }
  return items;
}
