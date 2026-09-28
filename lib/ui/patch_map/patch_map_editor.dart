import 'dart:convert';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/algorithm_controller/companion_table.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'patch_map_editor_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Resolves the live endpoint again when the connection changes. Demo/offline
/// managers deliberately cannot present an editable device map.
class PatchMapAlgorithmView extends StatelessWidget {
  const PatchMapAlgorithmView({super.key, required this.slotIndex});
  final int slotIndex;
  @override
  Widget build(BuildContext context) => BlocBuilder<DistingCubit, DistingState>(
    builder: (context, state) {
      final manager = context.read<DistingCubit>().disting();
      if (manager == null || manager is! PatchMapTransport) {
        return const Center(child: Text('Connect to NT'));
      }
      final cacheKey =
          state is DistingStateSynchronized &&
              manager is DistingMidiManager &&
              state.inputDevice != null &&
              state.outputDevice != null
          ? jsonEncode([
              state.inputDevice!.id,
              state.outputDevice!.id,
              manager.sysExId,
            ])
          : null;
      return PatchMapEditor(
        key: ValueKey((
          manager,
          slotIndex,
          cacheKey,
          state is DistingStateSynchronized ? state.presetName : null,
        )),
        transport: manager as PatchMapTransport,
        slotIndex: slotIndex,
        download: manager.requestFileDownload,
        companionCacheKey: cacheKey,
      );
    },
  );
}

class PatchMapEditor extends StatefulWidget {
  const PatchMapEditor({
    super.key,
    required this.transport,
    required this.slotIndex,
    required this.download,
    this.watchInterval = const Duration(seconds: 1),
    this.companionCacheKey,
  });
  final Future<Uint8List?> Function(String) download;
  final Duration? watchInterval;
  final String? companionCacheKey;
  final PatchMapTransport transport;
  final int slotIndex;
  @override
  State<PatchMapEditor> createState() => _PatchMapEditorState();
}

class _PatchMapEditorState extends State<PatchMapEditor>
    with WidgetsBindingObserver {
  late final PatchMapEditorCubit _cubit;
  final _scroll = ScrollController();
  final _horizontal = ScrollController();
  final _rows = <int, GlobalKey>{};
  int? _selected;
  bool _expanderDraftOpen = false;
  bool _compactMapOpen = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _cubit = PatchMapEditorCubit(
      PatchMapClient(widget.transport, widget.slotIndex),
      widget.download,
      watchInterval: widget.watchInterval,
      companionCacheKey: widget.companionCacheKey,
    );
    _cubit.load();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWatching();
  }

  void _updateWatching() => _cubit.setWatching(
    (_expanderDraftOpen || TickerMode.valuesOf(context).enabled) &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _updateWatching();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    _scroll.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _jump(int socket) {
    setState(() => _selected = socket);
    // All rows are mounted; ensureVisible accounts for text scaling and headers.
    final row = _rows[socket]?.currentContext;
    if (row != null) {
      Scrollable.ensureVisible(
        row,
        alignment: .45,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<PatchMapEditorCubit, PatchMapEditorState>(
    bloc: _cubit,
    listener: (context, state) {
      if (state.error != null && state.error != _lastError) {
        _lastError = state.error;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error!)));
      } else if (!state.busy && state.error == null) {
        _lastError = null;
      }
      if (!state.busy && state.error == null && state.map != null) {
        final focus = state.document?.focusSocket;
        if (state.fromDevice &&
            focus != null &&
            !state.pending &&
            !_expanderDraftOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _jump(focus);
          });
        }
      }
    },
    builder: (context, state) {
      final map = state.map;
      if (map == null) {
        return Center(
          child: state.busy || state.pending
              ? const CircularProgressIndicator(
                  semanticsLabel: 'Loading patch map',
                )
              : Text(state.error ?? ''),
        );
      }
      return Shortcuts(
        shortcuts: {
          for (final key in KeyBindingService().globalShortcuts.keys)
            key: const DoNothingAndStopPropagationTextIntent(),
        },
        child: DefaultTextEditingShortcuts(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: const ValueKey('companion-action-bar'),
                      height: 48,
                      child: Row(
                        children: [
                          _syncIndicator(state),
                          const Spacer(),
                          for (final action in state.document!.actions)
                            IconButton(
                              tooltip: action.label,
                              onPressed:
                                  state.editable &&
                                      !state.pending &&
                                      map.expanders.length <
                                          PatchMap.maxNewExpanders
                                  ? () => _chooseAction(action)
                                  : null,
                              icon: Icon(
                                Icons.add,
                                semanticLabel: action.label,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _table(map, state, state.document!),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 300,
                                  child: SingleChildScrollView(
                                    key: const ValueKey(
                                      'desktop-minimap-scroll',
                                    ),
                                    child: _minimap(map, state.document!),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => setState(
                                      () => _compactMapOpen = !_compactMapOpen,
                                    ),
                                    icon: Icon(
                                      _compactMapOpen
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                    label: const Text('Sockets'),
                                  ),
                                ),
                                if (_compactMapOpen)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: constraints.maxHeight * .38,
                                    ),
                                    child: SingleChildScrollView(
                                      key: const ValueKey(
                                        'compact-minimap-scroll',
                                      ),
                                      child: _minimap(
                                        map,
                                        state.document!,
                                        compact: true,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: _table(map, state, state.document!),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _syncIndicator(PatchMapEditorState state) {
    final (label, colour) = state.error != null
        ? ('Sync error: ${state.error}', Theme.of(context).colorScheme.error)
        : state.busy || state.pending
        ? ('Syncing', context.appColors.info.color)
        : ('Up to date', context.appColors.warning.color);
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Container(
          key: const ValueKey('patch-map-sync-indicator'),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Future<void> _chooseAction(CompanionChoiceAction action) async {
    _expanderDraftOpen = true;
    var chosen = false;
    try {
      final model = await showDialog<int>(
        context: context,
        builder: (dialogContext) =>
            BlocBuilder<PatchMapEditorCubit, PatchMapEditorState>(
              bloc: _cubit,
              builder: (context, state) => AlertDialog(
                title: Semantics(header: true, child: Text(action.title)),
                content: SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final choice in action.choices.entries)
                          TextButton(
                            autofocus: choice.key == action.choices.keys.first,
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed:
                                state.editable &&
                                    !state.pending &&
                                    state.map!.expanders.length <
                                        PatchMap.maxNewExpanders
                                ? () {
                                    if (chosen) return;
                                    chosen = true;
                                    Navigator.pop(dialogContext, choice.key);
                                  }
                                : null,
                            child: Text(choice.value),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(action.cancel),
                  ),
                ],
              ),
            ),
      );
      if (mounted && model != null) {
        await _cubit.chooseAction(action.id, model);
      }
    } finally {
      _expanderDraftOpen = false;
      if (mounted) _updateWatching();
    }
  }

  Future<void> _renameExpander(int index) async {
    final controller = TextEditingController(
      text: _cubit.state.map!.expanders[index].name,
    );
    String? validationError;
    _expanderDraftOpen = true;
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) =>
              BlocBuilder<PatchMapEditorCubit, PatchMapEditorState>(
                bloc: _cubit,
                builder: (context, state) => AlertDialog(
                  title: const Text('Expander name'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (name) {
                          try {
                            _cubit.queueExpanderName(index, name);
                            setDialogState(() => validationError = null);
                          } on FormatException catch (error) {
                            setDialogState(
                              () => validationError = error.message,
                            );
                          }
                        },
                      ),
                      SizedBox(
                        height: 60,
                        child: Text(
                          validationError ?? state.error ?? '',
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
        ),
      );
      await navigator.push(route);
      await route.completed;
    } finally {
      _expanderDraftOpen = false;
      if (mounted) _updateWatching();
      controller.dispose();
    }
  }

  Widget _table(
    PatchMap map,
    PatchMapEditorState state,
    CompanionTable document,
  ) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      controller: _horizontal,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 810 ? 810 : constraints.maxWidth,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(document.labels['socket']!),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(document.labels['destination']!),
                    ),
                    SizedBox(
                      width: 126,
                      child: Text(document.labels['colour']!),
                    ),
                    SizedBox(width: 64, child: Text(document.labels['tag']!)),
                    Expanded(flex: 2, child: Text(document.labels['group']!)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      for (final section in document.groups) ...[
                        Container(
                          width: double.infinity,
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(section.title),
                                ),
                              ),
                              if (section.start >= 20) ...[
                                IconButton(
                                  tooltip: 'Rename ${section.title}',
                                  onPressed: state.editable
                                      ? () => _renameExpander(
                                          (section.start - 20) ~/ 8,
                                        )
                                      : null,
                                  icon: const Icon(Icons.edit, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Move ${section.title} earlier',
                                  onPressed:
                                      state.editable &&
                                          !state.pending &&
                                          section.start > 20
                                      ? () => _cubit.moveExpander(
                                          (section.start - 20) ~/ 8,
                                          (section.start - 20) ~/ 8 - 1,
                                        )
                                      : null,
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move ${section.title} later',
                                  onPressed:
                                      state.editable &&
                                          !state.pending &&
                                          section.start <
                                              map.connections.length - 8
                                      ? () => _cubit.moveExpander(
                                          (section.start - 20) ~/ 8,
                                          (section.start - 20) ~/ 8 + 1,
                                        )
                                      : null,
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        for (final row
                            in map.connections
                                .skip(section.start)
                                .take(section.count))
                          PatchMapRow(
                            key: _rows.putIfAbsent(row.socket, GlobalKey.new),
                            row: row,
                            enabled: true,
                            selected: _selected == row.socket,
                            onSelected: () =>
                                setState(() => _selected = row.socket),
                            onEdit: (field, value) => _cubit.queueConnection(
                              row.socket,
                              field,
                              value,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _minimap(
    PatchMap map,
    CompanionTable document, {
    bool compact = false,
  }) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(header: true, child: const Text('Sockets')),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in document.groups) ...[
                _dotGroup(
                  map,
                  section.short,
                  section.start,
                  section.count,
                  section.columns,
                  compact,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 32,
          child: _selected != null && _selected! < map.connections.length
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${map.connections[_selected!].socketLabel}: ${map.connections[_selected!].destination.isEmpty ? 'Unused' : map.connections[_selected!].destination}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              : null,
        ),
      ],
    ),
  );

  Widget _dotGroup(
    PatchMap map,
    String name,
    int start,
    int count,
    int columns,
    bool compact,
  ) => Column(
    children: [
      Text(name, style: Theme.of(context).textTheme.labelSmall),
      for (var offset = 0; offset < count; offset += columns)
        Row(
          children: [
            for (var col = 0; col < columns; col++)
              _dot(
                map.connections[start + offset + col],
                offset + col + 1,
                compact,
              ),
          ],
        ),
    ],
  );
  Widget _dot(PatchConnection row, int number, bool compact) {
    final selected = _selected == row.socket;
    final scheme = Theme.of(context).colorScheme;
    final label =
        '${row.socketLabel}, ${row.connected ? row.destination : 'Unused'}, ${PatchMap.colours[row.colour]}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: compact ? 48 : 30,
          height: compact ? 48 : 36,
          child: TextButton(
            key: ValueKey('socket-dot-${row.socket}'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              backgroundColor: selected ? scheme.secondaryContainer : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: selected
                    ? BorderSide(color: scheme.primary)
                    : BorderSide.none,
              ),
            ),
            onPressed: () => _jump(row.socket),
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    key: ValueKey('socket-colour-${row.socket}'),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: row.connected || row.colour != 0
                          ? (row.colour == 0
                                ? scheme.onSurfaceVariant
                                : patchCableColours[row.colour])
                          : null,
                      border: Border.all(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '$number',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PatchMapRow extends StatefulWidget {
  const PatchMapRow({
    super.key,
    required this.row,
    required this.enabled,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
  });
  final PatchConnection row;
  final bool enabled, selected;
  final VoidCallback onSelected;
  final void Function(String field, Object value) onEdit;
  @override
  State<PatchMapRow> createState() => _PatchMapRowState();
}

class _PatchMapRowState extends State<PatchMapRow> {
  final _destination = TextEditingController(),
      _group = TextEditingController(),
      _tag = TextEditingController();
  late int _colour;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _destination.text = widget.row.destination;
    _group.text = widget.row.group;
    _colour = widget.row.colour;
    _tag.text = widget.row.tag == 0 ? '' : '${widget.row.tag}';
  }

  @override
  void didUpdateWidget(PatchMapRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.destination != widget.row.destination &&
        _destination.text != widget.row.destination) {
      _destination.text = widget.row.destination;
    }
    if (oldWidget.row.group != widget.row.group &&
        _group.text != widget.row.group) {
      _group.text = widget.row.group;
    }
    if (oldWidget.row.tag != widget.row.tag) {
      final text = widget.row.tag == 0 ? '' : '${widget.row.tag}';
      if (_tag.text != text) _tag.text = text;
    }
    _colour = widget.row.colour;
  }

  @override
  void dispose() {
    _destination.dispose();
    _group.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _edit(String field, Object value) {
    try {
      if (field == 'tag') {
        final text = value as String;
        final tag = text.isEmpty ? 0 : int.tryParse(text);
        if (tag == null || (text.isNotEmpty && (tag < 1 || tag > 12))) {
          throw const FormatException(
            'Tag must be an integer from 1 to 12, or blank.',
          );
        }
        value = tag;
      }
      widget.onEdit(field, value);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focus) {
      if (focus) widget.onSelected();
    },
    child: Semantics(
      selected: widget.selected,
      child: Container(
        decoration: BoxDecoration(
          color: widget.selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 96, child: Text(widget.row.socketLabel)),
                Expanded(
                  flex: 3,
                  child: Semantics(
                    label: '${widget.row.socketLabel} destination',
                    child: TextField(
                      controller: _destination,
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Unused',

                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (value) => _edit('destination', value),
                    ),
                  ),
                ),
                SizedBox(
                  width: 126,
                  child: Semantics(
                    label: '${widget.row.socketLabel} cable colour',
                    child: DropdownButton<int>(
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      isExpanded: true,
                      value: _colour,
                      onChanged: widget.enabled
                          ? (v) {
                              _colour = v!;
                              _edit('colour', v);
                            }
                          : null,
                      items: [
                        for (var i = 0; i < PatchMap.colours.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: patchCableColours[i],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(PatchMap.colours[i]),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Semantics(
                    label: '${widget.row.socketLabel} tag',
                    child: TextField(
                      key: ValueKey('tag-${widget.row.socket}'),
                      controller: _tag,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '—',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (value) => _edit('tag', value),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Semantics(
                    label: '${widget.row.socketLabel} group',
                    child: TextField(
                      controller: _group,
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '—',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (value) => _edit('group', value),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
