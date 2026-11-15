import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

/// Returns an ID to open, an empty string for New chat, or null to cancel.
/// Browsing and filtering are local; opening never resumes an agent run.
class ConversationPicker extends StatefulWidget {
  final ChatCubit cubit;
  const ConversationPicker({super.key, required this.cubit});
  @override
  State<ConversationPicker> createState() => _ConversationPickerState();
}

class _ConversationPickerState extends State<ConversationPicker> {
  late Future<List<ConversationSummary>> _conversations;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String? _deletingId;
  bool _deleteFailed = false;

  Future<List<ConversationSummary>> _load() async {
    final items = List<ConversationSummary>.of(
      await widget.cubit.listConversations(),
    );
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  @override
  void initState() {
    super.initState();
    _conversations = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _retry() => setState(() {
    _conversations = _load();
  });

  void _searchChanged(String _) {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<ConversationSummary> _filter(List<ConversationSummary> items) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty
        ? items
        : items.where((s) => s.title.toLowerCase().contains(query)).toList();
  }

  void _newChat() {
    if (_deletingId == null) Navigator.pop(context, '');
  }

  Future<void> _delete(ConversationSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: SingleChildScrollView(
          child: Text(
            '“${summary.title}” will be removed from saved chats.\n\n'
            'Memory notes and separate text snapshots are kept.',
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingId = summary.id;
      _deleteFailed = false;
    });
    final deleted = await widget.cubit.deleteConversation(summary.id);
    if (!mounted) return;
    setState(() {
      _deletingId = null;
      _deleteFailed = !deleted;
      if (deleted) _conversations = _load();
    });
  }

  String _group(DateTime date, DateTime now) {
    if (DateUtils.isSameDay(date, now)) return 'Today';
    if (DateUtils.isSameDay(date, DateTime(now.year, now.month, now.day - 1))) {
      return 'Yesterday';
    }
    return 'Earlier';
  }

  Widget _conversation(
    ConversationSummary summary,
    String? activeId,
    bool enabled,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = summary.id == activeId;
    final local = summary.updatedAt.toLocal();
    final l10n = MaterialLocalizations.of(context);
    final date = _group(local, now) == 'Earlier'
        ? l10n.formatCompactDate(local)
        : l10n.formatTimeOfDay(
            TimeOfDay.fromDateTime(local),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final subtitle = _deletingId == summary.id
        ? 'Deleting…'
        : current
        ? '$date · Current chat'
        : date;
    return ListTile(
      key: ValueKey(summary.id),
      contentPadding: const EdgeInsetsDirectional.only(start: 24, end: 8),
      minVerticalPadding: 12,
      selected: current,
      selectedTileColor: colors.secondaryContainer,
      title: Tooltip(
        excludeFromSemantics: true,
        message: summary.title,
        child: Text(
          summary.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            color: current ? colors.onSecondaryContainer : colors.onSurface,
          ),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: current
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(
                  Icons.check,
                  size: 18,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          SizedBox(
            width: 48,
            height: 48,
            child: PopupMenuButton<String>(
              enabled: enabled,
              tooltip: 'Options for ${summary.title}',
              icon: const Icon(Icons.more_horiz),
              onSelected: (_) => _delete(summary),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: colors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Delete conversation',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      onTap: enabled ? () => Navigator.pop(context, summary.id) : null,
    );
  }

  Widget _message(String title, String detail, {Widget? action}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: action),
          ],
        ),
      );

  Widget _loading() => Semantics(
    label: 'Loading conversations',
    liveRegion: true,
    child: ExcludeSemantics(
      child: ListView.builder(
        itemCount: 3,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: index == 1 ? .8 : .6,
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 64,
                height: 12,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.cubit.state;
    final activeId = current is ChatReady ? current.conversationId : null;
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    return DigitShortcutBlocker(
      includePeriod: true,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 520,
          height: 560,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labelledAction = constraints.maxWidth >= 440;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              labelledAction ? 'Conversations' : 'Chats',
                              style: labelledAction
                                  ? theme.textTheme.titleLarge
                                  : theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (labelledAction)
                          Tooltip(
                            message: 'New chat',
                            child: FilledButton.icon(
                              onPressed: _deletingId == null ? _newChat : null,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New chat'),
                            ),
                          )
                        else
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton.filledTonal(
                              tooltip: 'New chat',
                              onPressed: _deletingId == null ? _newChat : null,
                              icon: const Icon(Icons.add),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Close conversations',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Saved on this device',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  FutureBuilder<List<ConversationSummary>>(
                    future: _conversations,
                    builder: (context, snapshot) {
                      final items = snapshot.hasData
                          ? _filter(snapshot.data!)
                          : <ConversationSummary>[];
                      final enabled =
                          _deletingId == null &&
                          snapshot.connectionState == ConnectionState.done &&
                          !snapshot.hasError;
                      return Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: TextField(
                                controller: _search,
                                autofocus: desktop,
                                textInputAction: TextInputAction.search,
                                onChanged: _searchChanged,
                                onSubmitted: (_) {
                                  if (enabled && items.isNotEmpty) {
                                    Navigator.pop(context, items.first.id);
                                  }
                                },
                                decoration: InputDecoration(
                                  labelText: labelledAction
                                      ? 'Search conversations'
                                      : 'Search chats',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                  prefixIcon: const Icon(Icons.search),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _search.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Clear search',
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            _search.clear();
                                            _searchChanged('');
                                          },
                                        ),
                                ),
                              ),
                            ),
                            if (_deleteFailed)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  12,
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    'Could not delete the conversation. Try again from its options menu.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            const Divider(height: 1),
                            Expanded(
                              child: snapshot.hasError
                                  ? _message(
                                      'Couldn’t load conversations',
                                      'Your saved files haven’t been changed.',
                                      action: TextButton.icon(
                                        onPressed: _retry,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Try again'),
                                      ),
                                    )
                                  : !snapshot.hasData
                                  ? _loading()
                                  : snapshot.data!.isEmpty
                                  ? _message(
                                      'No saved conversations yet',
                                      'Start a new chat and it will appear here.',
                                    )
                                  : items.isEmpty
                                  ? _message(
                                      'No matching conversations',
                                      'Try another title or clear your search.',
                                      action: TextButton(
                                        onPressed: () {
                                          _search.clear();
                                          _searchChanged('');
                                        },
                                        child: const Text('Clear search'),
                                      ),
                                    )
                                  : Scrollbar(
                                      controller: _scroll,
                                      thumbVisibility: desktop,
                                      child: ListView.builder(
                                        controller: _scroll,
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        itemCount: items.length,
                                        itemBuilder: (context, index) {
                                          final now = DateTime.now();
                                          final summary = items[index];
                                          final group = _group(
                                            summary.updatedAt.toLocal(),
                                            now,
                                          );
                                          final startsGroup =
                                              index == 0 ||
                                              _group(
                                                    items[index - 1].updatedAt
                                                        .toLocal(),
                                                    now,
                                                  ) !=
                                                  group;
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (startsGroup)
                                                Padding(
                                                  padding:
                                                      const EdgeInsetsDirectional.fromSTEB(
                                                        24,
                                                        20,
                                                        24,
                                                        8,
                                                      ),
                                                  child: Semantics(
                                                    header: true,
                                                    child: Text(
                                                      group,
                                                      style: theme
                                                          .textTheme
                                                          .labelMedium
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              _conversation(
                                                summary,
                                                activeId,
                                                enabled,
                                                now,
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
