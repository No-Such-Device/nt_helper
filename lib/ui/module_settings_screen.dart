import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/ui/module_settings_navigation.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

class ModuleSettingsScreen extends StatefulWidget {
  const ModuleSettingsScreen({super.key, required this.cubit});
  final DistingCubit cubit;
  @override
  State<ModuleSettingsScreen> createState() => _ModuleSettingsScreenState();
}

class _ModuleSettingsScreenState extends State<ModuleSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.cubit.loadModuleSettings());
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _apply(int group, String name, int connectionId) async {
    final snapshot = widget.cubit.moduleSettingsState;
    if (snapshot.connectionId != connectionId ||
        !snapshot.canApplyGroup(group)) {
      return;
    }
    final changes = snapshot.tree!.groups[group]!.children
        .where((c) => !c.isGroup)
        .map((c) => snapshot.settings[c.id]!)
        .where((edit) => edit.changed && !edit.needsRefresh)
        .toList();
    final warning = [
      if (changes.any((e) => e.info.restartsEngine)) 'Restarts audio.',
      if (changes.any((e) => e.info.needsReboot)) 'Reboot required.',
      if (changes.any((e) => e.info.name == 'SysEx Device ID'))
        'Changes the MIDI connection address; the connection may be lost.',
    ].join(' ');
    if (warning.isNotEmpty) {
      if (!await _confirm(
        'Apply changes to $name?',
        warning,
        'Apply changes',
      )) {
        return;
      }
      final latest = widget.cubit.moduleSettingsState;
      if (!mounted ||
          latest.connectionId != connectionId ||
          !latest.canApplyGroup(group)) {
        return;
      }
      // A modal approval covers only the batch that was actually reviewed.
      final ids = latest.tree!.groups[group]!.children
          .where((c) => !c.isGroup)
          .map((c) => latest.settings[c.id]!)
          .where((e) => e.changed && !e.needsRefresh)
          .toList();
      if (ids.length != changes.length ||
          ids.any(
            (e) => !changes.any(
              (before) =>
                  before.info == e.info &&
                  before.displayed.sameValue(e.displayed),
            ),
          )) {
        return;
      }
    }
    await widget.cubit.applyModuleSettingsGroup(group);
  }

  Future<void> _action(bool revert, int connectionId) async {
    final approved = await _confirm(
      revert ? 'Revert to saved settings?' : 'Commit settings to flash?',
      revert
          ? 'Restore settings from flash? Audio or MIDI may restart. Refresh afterward; this action has no acknowledgement.'
          : 'Keep current settings after power-off? The module does not acknowledge flash writes.',
      revert ? 'Revert to saved' : 'Commit to flash',
    );
    final latest = widget.cubit.moduleSettingsState;
    if (!approved ||
        !mounted ||
        latest.connectionId != connectionId ||
        !latest.canCommit) {
      return;
    }
    if (revert) {
      await widget.cubit.revertModuleSettings();
    } else {
      await widget.cubit.commitModuleSettings();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ModuleSettingsState>(
    stream: widget.cubit.moduleSettingsStream,
    initialData: widget.cubit.moduleSettingsState,
    builder: (context, snapshot) => _SettingsWorkspace(
      key: ValueKey(snapshot.data!.connectionId),
      state: snapshot.data!,
      cubit: widget.cubit,
      apply: _apply,
      action: _action,
    ),
  );
}

class _SettingsWorkspace extends StatefulWidget {
  const _SettingsWorkspace({
    super.key,
    required this.state,
    required this.cubit,
    required this.apply,
    required this.action,
  });
  final ModuleSettingsState state;
  final DistingCubit cubit;
  final Future<void> Function(int, String, int) apply;
  final Future<void> Function(bool, int) action;
  @override
  State<_SettingsWorkspace> createState() => _SettingsWorkspaceState();
}

class _SettingsWorkspaceState extends State<_SettingsWorkspace> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _picker = FocusNode(debugLabel: 'Settings group picker');
  final _detailOffsets = <int, double>{};
  double _navOffset = 0;
  int? _selected;
  Set<int> _expanded = {};
  ModuleSettingsNavigation? get nav => widget.state.tree == null
      ? null
      : ModuleSettingsNavigation(widget.state.tree!);
  void _initialize() {
    final n = nav;
    _selected = n?.initial;
    _expanded = n?.ancestors(_selected) ?? {};
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(_SettingsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.tree != null &&
        (oldWidget.state.tree == null ||
            !widget.state.tree!.groups.containsKey(_selected))) {
      _initialize();
    }
  }

  @override
  void dispose() {
    _picker.dispose();
    super.dispose();
  }

  void _select(int id, {bool activate = false, bool drawer = false}) {
    final n = nav!;
    setState(() {
      _selected = id;
      if (activate && n.direct(id).isEmpty) _expanded.add(id);
    });
    if (activate && drawer && n.direct(id).isNotEmpty) {
      _scaffold.currentState?.closeDrawer();
    }
  }

  void _toggle(int id) => setState(() {
    if (!_expanded.remove(id)) {
      _expanded.add(id);
    } else if (nav!.ancestors(_selected).contains(id)) {
      _selected = id;
    }
  });

  Widget _tree(
    ModuleSettingsNavigation? n,
    int? selected, {
    bool drawer = false,
  }) => _GroupTree(
    key: ValueKey(drawer),
    nav: n,
    state: widget.state,
    selected: selected,
    expanded: _expanded,
    offset: _navOffset,
    onScroll: (v) => _navOffset = v,
    select: (id, activate) => _select(id, activate: activate, drawer: drawer),
    toggle: _toggle,
    autofocus: drawer,
  );

  Widget _global() => Padding(
    key: const Key('module-settings-global'),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(16) > 24;
            final buttons = [
              FilledButton(
                onPressed: widget.state.canCommit
                    ? () => widget.action(false, widget.state.connectionId)
                    : null,
                child: const Text('Commit to flash'),
              ),
              OutlinedButton(
                onPressed: widget.state.canCommit
                    ? () => widget.action(true, widget.state.connectionId)
                    : null,
                child: const Text('Revert to saved'),
              ),
            ];
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: buttons[i],
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: buttons[i],
                          ),
                        ),
                      ],
                    ],
                  );
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final n = nav;
      final selected = n?.effective(_selected, _expanded);
      final compact =
          constraints.maxWidth <
          281 + MediaQuery.textScalerOf(context).scale(360);
      if (!compact && (_scaffold.currentState?.isDrawerOpen ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scaffold.currentState?.closeDrawer();
        });
      }
      final name = selected == null ? 'NT Settings' : n!.name(selected);
      final headerHeight =
          (MediaQuery.textScalerOf(context).scale(16) * 1.5 + 24).clamp(
            56.0,
            double.infinity,
          );
      final detail = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: compact
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: OutlinedButton(
                      key: const Key('module-settings-picker'),
                      focusNode: _picker,
                      onPressed: n == null
                          ? null
                          : () => _scaffold.currentState?.openDrawer(),
                      child: Semantics(
                        label: 'Settings group, $name',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: _SettingsDetail(
              key: ValueKey(selected),
              state: widget.state,
              cubit: widget.cubit,
              selected: selected,
              name: name,
              leadingInset: compact ? 16 : 24,
              offset: _detailOffsets[selected] ?? 0,
              onScroll: (v) {
                if (selected != null) _detailOffsets[selected] = v;
              },
              apply: selected == null
                  ? null
                  : () =>
                        widget.apply(selected, name, widget.state.connectionId),
            ),
          ),
        ],
      );
      return Scaffold(
        key: _scaffold,
        drawerEnableOpenDragGesture: false,
        onDrawerChanged: (open) {
          if (!open && compact) _picker.requestFocus();
        },
        drawer: compact
            ? Drawer(child: SafeArea(child: _tree(n, selected, drawer: true)))
            : null,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: ModalRoute.of(context)?.impliesAppBarDismissal == true
              ? const BackButton()
              : null,
          title: const Text('NT Settings'),
          actions: [
            IconButton(
              tooltip: 'Discard drafts',
              onPressed: widget.state.ready && widget.state.hasDrafts
                  ? widget.cubit.discardModuleSettingsDrafts
                  : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              key: const Key('refresh-module-settings'),
              tooltip: 'Refresh module settings',
              onPressed:
                  widget.state.unavailableReason != null || widget.state.busy
                  ? null
                  : () => widget.cubit.loadModuleSettings(force: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SettingsFeedback(
                  key: const Key('module-settings-status'),
                  message:
                      widget.state.unavailableReason ?? widget.state.message,
                  busy: widget.state.busy,
                ),
              ),
              Expanded(
                child: compact
                    ? detail
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            key: const Key('module-settings-sidebar'),
                            width: 280,
                            child: _tree(n, selected),
                          ),
                          const VerticalDivider(
                            key: Key('module-settings-separator'),
                            width: 1,
                          ),
                          Expanded(child: detail),
                        ],
                      ),
              ),
              _global(),
            ],
          ),
        ),
      );
    },
  );
}

class _SettingsDetail extends StatefulWidget {
  const _SettingsDetail({
    super.key,
    required this.state,
    required this.cubit,
    required this.selected,
    required this.name,
    required this.leadingInset,
    required this.offset,
    required this.onScroll,
    required this.apply,
  });
  final ModuleSettingsState state;
  final DistingCubit cubit;
  final int? selected;
  final String name;
  final double leadingInset;
  final double offset;
  final ValueChanged<double> onScroll;
  final VoidCallback? apply;
  @override
  State<_SettingsDetail> createState() => _SettingsDetailState();
}

class _SettingsDetailState extends State<_SettingsDetail> {
  late final _scroll = ScrollController(initialScrollOffset: widget.offset);
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final children =
        state.tree?.groups[widget.selected]?.children
            .where((c) => !c.isGroup)
            .toList() ??
        [];
    final editable = children.any(
      (c) => state.settings[c.id]?.info.writable ?? false,
    );
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              label: widget.name,
              child: const SizedBox.shrink(),
            ),
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null) widget.onScroll(n.metrics.pixels);
                  return false;
                },
                child: SingleChildScrollView(
                  key: const Key('module-settings-detail'),
                  controller: _scroll,
                  padding: EdgeInsetsDirectional.only(
                    start: widget.leadingInset,
                    end: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in children)
                        if (state.settings[c.id] != null)
                          _ModuleSettingField(
                            key: ValueKey(
                              'module-setting-${state.connectionId}-${c.id}',
                            ),
                            edit: state.settings[c.id]!,
                            enabled: state.ready,
                            units:
                                widget.cubit.state is DistingStateSynchronized
                                ? (widget.cubit.state
                                          as DistingStateSynchronized)
                                      .unitStrings
                                : const [],
                            onChanged: (value) =>
                                widget.cubit.editModuleSetting(c.id, value),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              key: const Key('module-settings-footer'),
              padding: EdgeInsetsDirectional.fromSTEB(
                widget.leadingInset,
                8,
                16,
                8,
              ),
              child: Visibility(
                visible: editable,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: OutlinedButton(
                      key: ValueKey('module-settings-apply-${widget.selected}'),
                      onPressed:
                          widget.selected != null &&
                              state.canApplyGroup(widget.selected!)
                          ? widget.apply
                          : null,
                      child: const Text('Apply changes'),
                    ),
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

class _GroupTree extends StatefulWidget {
  const _GroupTree({
    super.key,
    required this.nav,
    required this.state,
    required this.selected,
    required this.expanded,
    required this.offset,
    required this.onScroll,
    required this.select,
    required this.toggle,
    required this.autofocus,
  });
  final ModuleSettingsNavigation? nav;
  final ModuleSettingsState state;
  final int? selected;
  final Set<int> expanded;
  final double offset;
  final ValueChanged<double> onScroll;
  final void Function(int, bool) select;
  final ValueChanged<int> toggle;
  final bool autofocus;
  @override
  State<_GroupTree> createState() => _GroupTreeState();
}

class _GroupTreeState extends State<_GroupTree> {
  final _focus = FocusNode(debugLabel: 'Settings group tree');
  late final _scroll = ScrollController(initialScrollOffset: widget.offset);
  double _extent(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(14) * 1.43 + 16).clamp(
        48.0,
        double.infinity,
      );
  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal([int? selected]) {
    final rows = widget.nav?.rows(widget.expanded) ?? [];
    final i = rows.indexWhere((r) => r.$1 == (selected ?? widget.selected));
    if (!mounted || !_scroll.hasClients || i < 0) return;
    final top = i * _extent(context);
    final position = _scroll.position;
    if (top < position.pixels ||
        top + _extent(context) > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        top.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final n = widget.nav;
    if (n == null || widget.selected == null) return KeyEventResult.ignored;
    final rows = n.rows(widget.expanded).map((r) => r.$1).toList();
    final id = widget.selected!;
    final i = rows.indexOf(id);
    final key = event.logicalKey;
    int? next;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = rows[(i + 1).clamp(0, rows.length - 1)];
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = rows[(i - 1).clamp(0, rows.length - 1)];
    } else if (key == LogicalKeyboardKey.home) {
      next = rows.first;
    } else if (key == LogicalKeyboardKey.end) {
      next = rows.last;
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      if (n.children(id).isNotEmpty && id != 0) {
        if (!widget.expanded.contains(id)) {
          widget.toggle(id);
        } else {
          next = n.children(id).first;
        }
      }
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      if (id != 0 && widget.expanded.contains(id)) {
        widget.toggle(id);
      } else if (n.parents[id] != 0) {
        next = n.parents[id];
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      widget.select(id, true);
    } else {
      return KeyEventResult.ignored;
    }
    if (next != null) {
      widget.select(next, false);
      _reveal(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.nav;
    final rows = n?.rows(widget.expanded) ?? [];
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      onFocusChange: (_) => setState(() {}),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (event) {
          if (event.dragDetails != null) widget.onScroll(event.metrics.pixels);
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          itemExtent: _extent(context),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final (id, depth) = rows[index];
            final branch = id != 0 && n!.children(id).isNotEmpty;
            final expanded = widget.expanded.contains(id);
            final ids = branch && !expanded ? n.descendants(id) : n!.direct(id);
            final edits = ids
                .map((id) => widget.state.settings[id])
                .whereType<ModuleSettingEdit>();
            final error = edits.any((e) => e.error != null || e.needsRefresh);
            final changed = edits.any((e) => e.changed);
            final selected = widget.selected == id;
            final name = n.name(id);
            return Semantics(
              selected: selected,
              expanded: branch ? expanded : null,
              value: error
                  ? 'invalid value'
                  : changed
                  ? 'unapplied changes'
                  : null,
              child: Material(
                color: selected
                    ? colors.secondaryContainer
                    : Colors.transparent,
                shape: Border.all(
                  color: selected && _focus.hasFocus
                      ? colors.primary
                      : Colors.transparent,
                  width: 2,
                ),
                child: InkWell(
                  key: ValueKey('module-settings-nav-$id'),
                  canRequestFocus: false,
                  onTap: () {
                    _focus.requestFocus();
                    widget.select(id, true);
                  },
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: (depth * 16.0).clamp(0, 160),
                      end: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: branch
                              ? ExcludeFocus(
                                  child: IconButton(
                                    tooltip:
                                        '${expanded ? 'Collapse' : 'Expand'} $name',
                                    onPressed: () => widget.toggle(id),
                                    icon: Icon(
                                      expanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Expanded(
                          child: Tooltip(
                            message: name,
                            excludeFromSemantics: true,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 24,
                          child: ExcludeSemantics(
                            child: error
                                ? Icon(
                                    Icons.error_outline,
                                    size: 18,
                                    color: colors.error,
                                  )
                                : changed
                                ? const Icon(Icons.circle, size: 8)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsFeedback extends StatelessWidget {
  const _SettingsFeedback({
    super.key,
    required this.message,
    this.busy = false,
    this.isError = false,
    this.detail = '',
    this.subject = 'NT Settings',
    this.semanticMessage,
    this.compact = false,
  });
  final String message;
  final String detail;
  final String subject;
  final String? semanticMessage;
  final bool busy;
  final bool isError;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final line = scaler.scale(14) * 1.5;
    final fullMessage = detail.isEmpty ? message : '$message\n$detail';
    final displayMessage = compact && detail.isNotEmpty
        ? '$message · $detail'
        : fullMessage;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: isError ? Theme.of(context).colorScheme.error : null);
    final maxLines = compact ? 1 : 2;
    return SizedBox(
      height: compact ? (line + 8).clamp(48.0, double.infinity) : line * 2 + 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter =
              TextPainter(
                text: TextSpan(text: displayMessage, style: style),
                textDirection: Directionality.of(context),
                textScaler: scaler,
                maxLines: maxLines,
                ellipsis: '…',
              )..layout(
                maxWidth: (constraints.maxWidth - (compact ? 48 : 80)).clamp(
                  0.0,
                  double.infinity,
                ),
              );
          final truncated = painter.didExceedMaxLines;
          painter.dispose();
          return Row(
            children: [
              if (!compact) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: busy
                      ? const ExcludeSemantics(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Tooltip(
                  message: fullMessage,
                  child: Semantics(
                    liveRegion: true,
                    label: fullMessage.isEmpty
                        ? ''
                        : '$subject: ${semanticMessage ?? fullMessage}',
                    excludeSemantics: true,
                    child: Text(
                      displayMessage,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: fullMessage.isEmpty || !truncated
                    ? null
                    : IconButton(
                        tooltip: 'Read full status for $subject',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('$subject status'),
                            content: SingleChildScrollView(
                              child: SelectableText(fullMessage),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModuleSettingField extends StatefulWidget {
  const _ModuleSettingField({
    super.key,
    required this.edit,
    required this.enabled,
    required this.onChanged,
    required this.units,
  });
  final ModuleSettingEdit edit;
  final bool enabled;
  final ValueChanged<ModuleSettingValue> onChanged;
  final List<String> units;
  @override
  State<_ModuleSettingField> createState() => _ModuleSettingFieldState();
}

class _ModuleSettingFieldState extends State<_ModuleSettingField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.edit.displayed.value.toString(),
  );
  @override
  void didUpdateWidget(covariant _ModuleSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final displayed = widget.edit.displayed.value;
    final current = displayed is int && widget.edit.info.isNumeric
        ? int.tryParse(_text.text)
        : _text.text;
    final value = displayed.toString();
    if (current != displayed) {
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    final info = edit.info;
    final value = edit.displayed.value;
    final observed = edit.observed.value;
    final observedLabel = info.unit == 1 && observed is int
        ? info.enums[observed]
        : observed is BigInt
        ? '0x${observed.toRadixString(16).padLeft(16, '0')}'
        : edit.observed.presentation.isNotEmpty
        ? edit.observed.presentation
        : observed.toString();
    final enabled = widget.enabled && info.writable && !edit.needsRefresh;
    final unit =
        info.unit > 1 &&
            info.unit != 16 &&
            info.unit != 18 &&
            info.unit <= widget.units.length
        ? widget.units[info.unit - 1]
        : null;
    late final Widget control;
    if (info.type == 6) {
      final bits = value as BigInt;
      control = LayoutBuilder(
        builder: (context, constraints) {
          final target = MediaQuery.textScalerOf(context)
              .scale(48)
              .clamp(48.0, 96.0);
          final columns = (constraints.maxWidth / target).floor().clamp(1, 16);
          final cellWidth = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (var b = 0; b < 64; b++)
                SizedBox(
                  width: cellWidth,
                  height: 64 + MediaQuery.textScalerOf(context).scale(14),
                  child: Column(
                    children: [
                      ExcludeSemantics(child: Text('${b + 1}')),
                      Semantics(
                        label: '${info.name}, bit ${b + 1}',
                        child: Checkbox(
                          value: bits & (BigInt.one << b) != BigInt.zero,
                          onChanged: enabled
                              ? (on) => widget.onChanged(
                                  ModuleSettingValue(
                                    on!
                                        ? bits | (BigInt.one << b)
                                        : bits & ~(BigInt.one << b),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    } else if (info.type == 5 || !info.writable) {
      control = Semantics(
        label: '${info.name}, read only',
        child: SelectableText(
          info.unit == 1 && value is int ? info.enums[value] : value.toString(),
        ),
      );
    } else if (info.type != 4 && info.isToggle) {
      control = SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(info.name),
        value: value == 1,
        onChanged: enabled
            ? (on) => widget.onChanged(ModuleSettingValue(on ? 1 : 0))
            : null,
      );
    } else if (info.type != 4 && info.unit == 1) {
      control = DropdownButtonFormField<int>(
        initialValue: value as int,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: info.name,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (var i = 0; i < info.enums.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(info.enums[i], overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled
            ? (v) {
                if (v != null) widget.onChanged(ModuleSettingValue(v));
              }
            : null,
      );
    } else {
      control = DigitShortcutBlocker(
        child: TextField(
          controller: _text,
          enabled: enabled,
          keyboardType: info.type == 4
              ? TextInputType.text
              : const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(
            labelText: info.name,
            suffixText: unit,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => widget.onChanged(
            ModuleSettingValue(info.type == 4 ? v : int.tryParse(v) ?? v),
          ),
        ),
      );
    }
    final details = [
      if (!info.writable) 'Read only',
      if (info.flags & 4 != 0)
        'The module marks this setting read only.'
      else if (info.type == 5)
        'Path editing is not supported by the settings protocol reference.',
      if (info.unit == 1)
        'Default: ${info.enums[info.defaultValue]}'
      else if (info.isNumeric)
        '${info.min}–${info.max} · Default ${info.defaultValue}'
      else if (info.type == 4)
        'Printable ASCII, up to ${info.maxLength} characters',
      if (info.needsReboot) 'Takes effect after reboot',
      if (info.restartsEngine) 'Restarts the audio engine when applied',
      if (info.type > 6) 'Unsupported type ${info.type}',
    ].join('. ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.type == 6 || info.type == 5 || !info.writable) ...[
            Text(info.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          Tooltip(
            message: details,
            child: Semantics(hint: details, child: control),
          ),
          _SettingsFeedback(
            key: ValueKey('module-setting-feedback-${info.id}'),
            compact: true,
            subject: info.name,
            message:
                edit.error ??
                (edit.changed
                    ? 'was $observedLabel'
                    : info.needsReboot
                    ? 'Reboot required'
                    : info.unit == 16
                    ? edit.observed.presentation
                    : ''),
            detail: edit.error != null || edit.needsRefresh && !edit.changed
                ? (edit.changed
                      ? 'was $observedLabel'
                      : 'confirmed $observedLabel')
                : '',
            semanticMessage: edit.changed
                ? 'Previous confirmed value: $observedLabel. ${edit.error ?? 'Unapplied changes.'}'
                : null,
            isError: edit.error != null,
          ),
        ],
      ),
    );
  }
}
