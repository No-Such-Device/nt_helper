import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isNew;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      ChatMessageRole.user => _UserBubble(message: message),
      ChatMessageRole.assistant => _AssistantBubble(
        message: message,
        isNew: isNew,
      ),
      ChatMessageRole.system => _SystemBubble(message: message),
      ChatMessageRole.compaction => const _CompactionChip(),
      ChatMessageRole.toolCall ||
      ChatMessageRole.toolResult => const SizedBox.shrink(),
      ChatMessageRole.thinking => _ThinkingIndicator(label: message.content),
    };
  }
}

class _UserBubble extends StatefulWidget {
  final ChatMessage message;

  const _UserBubble({required this.message});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Semantics(
                label: _userMessageSemanticsLabel(widget.message),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.message.hasImageAttachments) ...[
                      _MessageImageGrid(
                        attachments: widget.message.imageAttachments,
                      ),
                      if (widget.message.content.isNotEmpty ||
                          widget.message.hasFileAttachments)
                        const SizedBox(height: 8),
                    ],
                    if (widget.message.hasFileAttachments) ...[
                      _MessageFileChips(
                        attachments: widget.message.fileAttachments,
                      ),
                      if (widget.message.content.isNotEmpty)
                        const SizedBox(height: 8),
                    ],
                    if (widget.message.content.isNotEmpty)
                      Text(
                        widget.message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_hovered)
              Positioned(
                top: 0,
                right: 12,
                child: _CopyButton(text: widget.message.content),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageFileChips extends StatelessWidget {
  final List<ChatFileAttachment> attachments;

  const _MessageFileChips({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final attachment in attachments)
          Semantics(
            label: 'Attached file ${attachment.name}',
            child: Chip(
              avatar: Icon(
                attachment.mimeType == 'application/pdf'
                    ? Icons.picture_as_pdf
                    : Icons.description_outlined,
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              label: Text(
                attachment.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              backgroundColor: theme.colorScheme.primaryContainer,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}

class _MessageImageGrid extends StatelessWidget {
  final List<ChatImageAttachment> attachments;

  const _MessageImageGrid({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final attachment in attachments)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(attachment.data),
              width: 140,
              height: 100,
              fit: BoxFit.cover,
              semanticLabel: attachment.name == null
                  ? 'Attached image'
                  : 'Attached image ${attachment.name}',
            ),
          ),
      ],
    );
  }
}

String _userMessageSemanticsLabel(ChatMessage message) {
  final parts = <String>['You said: ${message.content}'];
  if (message.hasImageAttachments) {
    parts.add(
      message.imageAttachments.length == 1
          ? '1 image attached'
          : '${message.imageAttachments.length} images attached',
    );
  }
  if (message.hasFileAttachments) {
    parts.add(
      message.fileAttachments.length == 1
          ? '1 file attached'
          : '${message.fileAttachments.length} files attached',
    );
  }
  return parts.join('. ');
}

class _AssistantBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isNew;

  const _AssistantBubble({required this.message, required this.isNew});

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Semantics(
                liveRegion: widget.isNew,
                label: widget.isNew
                    ? 'Assistant: ${widget.message.content}'
                    : null,
                child: MarkdownBody(
                  data: widget.message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium,
                    code: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      backgroundColor: theme.colorScheme.surfaceContainerLow,
                    ),
                    blockquote: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 3,
                        ),
                      ),
                    ),
                    blockquotePadding: const EdgeInsets.only(left: 12),
                  ),
                ),
              ),
            ),
            if (_hovered)
              Positioned(
                top: 0,
                right: 12,
                child: _CopyButton(text: widget.message.content),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders a group of consecutive tool call/result messages as compact icons
/// in a Wrap layout. Each icon can be tapped to expand details.
class ToolGroupBubble extends StatelessWidget {
  final List<ChatMessage> messages;

  const ToolGroupBubble({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    final pairs = _pairToolMessages(messages);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: pairs.map((pair) => _ToolChip(pair: pair)).toList(),
      ),
    );
  }

  static List<_ToolPair> _pairToolMessages(List<ChatMessage> messages) {
    final calls = <String, ChatMessage>{};
    final results = <String, ChatMessage>{};

    for (final msg in messages) {
      final id = msg.toolCallId;
      if (id == null) continue;
      if (msg.role == ChatMessageRole.toolCall) {
        calls[id] = msg;
      } else if (msg.role == ChatMessageRole.toolResult) {
        results[id] = msg;
      }
    }

    final pairs = <_ToolPair>[];
    final seen = <String>{};

    // Preserve original order based on first appearance
    for (final msg in messages) {
      final id = msg.toolCallId;
      if (id == null || seen.contains(id)) continue;
      seen.add(id);
      pairs.add(_ToolPair(call: calls[id], result: results[id]));
    }

    return pairs;
  }
}

class _ToolPair {
  final ChatMessage? call;
  final ChatMessage? result;

  const _ToolPair({this.call, this.result});

  String get toolName => call?.toolName ?? result?.toolName ?? 'Tool';

  bool get isPending => result == null;

  bool get isSuccess {
    if (result == null) return false;
    try {
      final json = jsonDecode(result!.content);
      if (json is Map) return json['success'] != false;
    } catch (_) {}
    return true;
  }
}

class _ToolChip extends StatefulWidget {
  final _ToolPair pair;

  const _ToolChip({required this.pair});

  @override
  State<_ToolChip> createState() => _ToolChipState();
}

class _ToolChipState extends State<_ToolChip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pair = widget.pair;

    if (!_expanded) {
      return Semantics(
        label:
            '${pair.toolName}: ${pair.isPending
                ? 'running'
                : pair.isSuccess
                ? 'success'
                : 'error'}',
        button: true,
        child: Tooltip(
          message: pair.toolName,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _buildIcon(theme, pair),
            ),
          ),
        ),
      );
    }

    return _ToolExpandedCard(
      pair: pair,
      onCollapse: () => setState(() => _expanded = false),
    );
  }

  Widget _buildIcon(ThemeData theme, _ToolPair pair) {
    if (pair.isPending) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (pair.isSuccess) {
      return Icon(
        Icons.check_circle,
        size: 16,
        color: theme.appColors.success.color,
      );
    }
    return Icon(Icons.cancel, size: 16, color: theme.colorScheme.error);
  }
}

class _ToolExpandedCard extends StatelessWidget {
  final _ToolPair pair;
  final VoidCallback onCollapse;

  const _ToolExpandedCard({required this.pair, required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onCollapse,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.build_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        pair.toolName,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.expand_less,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                if (pair.call?.toolArguments != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Arguments',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _formatJson(pair.call!.toolArguments!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
                if (pair.result != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Result',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (pair.result!.hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        base64Decode(pair.result!.imageBase64!),
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _formatJsonString(pair.result!.content),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  final ChatMessage message;

  const _SystemBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.data_object,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LLM Context',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _CopyButton(text: message.content),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 400),
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactionChip extends StatelessWidget {
  const _CompactionChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Semantics(
        label: 'Context compacted',
        child: Tooltip(
          message: 'Earlier context was compacted to stay within limits',
          child: Icon(
            Icons.compress,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  final String label;

  const _ThinkingIndicator({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;

  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _copied ? 'Copied' : 'Copy message',
      button: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatJson(Map<String, dynamic> json) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}

String _formatJsonString(String content) {
  try {
    final parsed = jsonDecode(content);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(parsed);
  } catch (_) {
    return content;
  }
}
