import 'dart:convert';
import 'dart:math' as math;
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
        slotName:
            state is DistingStateSynchronized && slotIndex < state.slots.length
            ? state.slots[slotIndex].algorithm.name.trim()
            : 'Patch Helper',
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
    this.slotName = 'Patch Helper',
  });
  final Future<Uint8List?> Function(String) download;
  final Duration? watchInterval;
  final String? companionCacheKey;
  final String slotName;
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
  final _rows = <Object, GlobalKey>{};
  Object? _selected;
  final _widths = SettingsService().companionColumnWidths;
  String? _focusedColumn;
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

  void _jump(Object socket) {
    setState(() => _selected = socket);
    // All rows are mounted; ensureVisible accounts for text scaling and headers.
    final row = _rows[socket]?.currentContext;
    if (row != null && _scroll.hasClients) {
      _scroll.position.ensureVisible(
        row.findRenderObject()!,
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
        final Object? focus =
            state.document?.focusRecord ?? state.document?.focusSocket;
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
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                widget.slotName.isEmpty
                                    ? 'Patch Helper'
                                    : widget.slotName,
                                key: const ValueKey('patch-map-slot-name'),
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          for (final action in state.document!.actions.where(
                            (action) => !state.document!.recordSections.any(
                              (section) => section.addAction == action.id,
                            ),
                          ))
                            IconButton(
                              tooltip: action.label,
                              onPressed:
                                  state.editable &&
                                      !state.pending &&
                                      _cubit.canChooseAction(action.id)
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
                                    _cubit.canChooseAction(action.id)
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

  String _widthKey(String table, String column) =>
      jsonEncode(['ThPh', table, column]);

  Map<String, double> _resolveWidths(
    String table,
    List<CompanionColumn> columns,
    double available,
  ) {
    final result = {
      for (final column in columns)
        column.key: (_widths[_widthKey(table, column.key)] ?? column.width)
            .clamp(column.minWidth, column.maxWidth)
            .toDouble(),
    };
    final extra = math.max(
      0.0,
      available - 16 - result.values.fold(0.0, (a, b) => a + b),
    );
    final flex = columns
        .where((column) => !_widths.containsKey(_widthKey(table, column.key)))
        .fold(0, (sum, column) => sum + column.flex);
    if (flex > 0) {
      for (final column in columns) {
        if (!_widths.containsKey(_widthKey(table, column.key))) {
          result[column.key] =
              (result[column.key]! + extra * column.flex / flex)
                  .clamp(column.minWidth, column.maxWidth)
                  .toDouble();
        }
      }
    }
    return result;
  }

  void _resizeColumn(String table, CompanionColumn column, double value) {
    setState(
      () => _widths[_widthKey(table, column.key)] = value
          .clamp(column.minWidth, column.maxWidth)
          .toDouble(),
    );
  }

  Future<void> _saveColumnWidth(String table, CompanionColumn column) async {
    final value = _widths[_widthKey(table, column.key)];
    if (value == null) return;
    final saved = await SettingsService().setCompanionColumnWidth(
      'ThPh',
      table,
      column.key,
      value,
    );
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remember the column width.')),
      );
    }
  }

  Widget _columnHeader(
    String table,
    List<CompanionColumn> columns,
    Map<String, double> widths,
  ) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    height: 48,
    child: Row(
      children: [
        for (final column in columns)
          SizedBox(
            key: ValueKey('column-$table-${column.key}'),
            width: widths[column.key],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Semantics(
                  label: 'Resize ${column.label} column',
                  slider: true,
                  value: '${widths[column.key]!.round()} pixels',
                  increasedValue:
                      '${(widths[column.key]! + 12).clamp(column.minWidth, column.maxWidth).round()} pixels',
                  decreasedValue:
                      '${(widths[column.key]! - 12).clamp(column.minWidth, column.maxWidth).round()} pixels',
                  onIncrease: () {
                    _resizeColumn(table, column, widths[column.key]! + 12);
                    _saveColumnWidth(table, column);
                  },
                  onDecrease: () {
                    _resizeColumn(table, column, widths[column.key]! - 12);
                    _saveColumnWidth(table, column);
                  },
                  child: Focus(
                    onFocusChange: (focused) => setState(
                      () => _focusedColumn = focused
                          ? _widthKey(table, column.key)
                          : null,
                    ),
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent ||
                          (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
                              event.logicalKey !=
                                  LogicalKeyboardKey.arrowRight)) {
                        return KeyEventResult.ignored;
                      }
                      _resizeColumn(
                        table,
                        column,
                        widths[column.key]! +
                            (event.logicalKey == LogicalKeyboardKey.arrowRight
                                ? 12
                                : -12),
                      );
                      _saveColumnWidth(table, column);
                      return KeyEventResult.handled;
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        key: ValueKey('resize-$table-${column.key}'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onHorizontalDragUpdate: (details) => _resizeColumn(
                          table,
                          column,
                          (_widths[_widthKey(table, column.key)] ??
                                  widths[column.key]!) +
                              details.delta.dx,
                        ),
                        onHorizontalDragEnd: (_) =>
                            _saveColumnWidth(table, column),
                        child: SizedBox(
                          width: 16,
                          height: 48,
                          child: Center(
                            child: Container(
                              width: 1,
                              height: 20,
                              color:
                                  _focusedColumn == _widthKey(table, column.key)
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _table(
    PatchMap map,
    PatchMapEditorState state,
    CompanionTable document,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final widths = _resolveWidths(
        document.tableId,
        document.columns,
        constraints.maxWidth,
      );
      final recordWidths = {
        for (final section in document.recordSections)
          section.id: _resolveWidths(
            section.id,
            section.columns,
            constraints.maxWidth,
          ),
      };
      final contentWidth = [
        widths.values.fold(16.0, (a, b) => a + b),
        for (final values in recordWidths.values)
          values.values.fold(16.0, (a, b) => a + b),
      ].fold(constraints.maxWidth, math.max);
      return Scrollbar(
        controller: _horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: Column(
              children: [
                _columnHeader(document.tableId, document.columns, widths),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      children: [
                        for (final section in document.groups) ...[
                          Container(
                            width: double.infinity,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
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
                              columns: document.columns,
                              widths: widths,
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
                          for (final records in document.recordSections.where(
                            (records) =>
                                records.afterSocket ==
                                section.start + section.count - 1,
                          ))
                            _recordTable(
                              map,
                              state,
                              document,
                              records,
                              recordWidths[records.id]!,
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
      );
    },
  );

  Widget _recordTable(
    PatchMap map,
    PatchMapEditorState state,
    CompanionTable document,
    CompanionRecordSection section,
    Map<String, double> widths,
  ) {
    final records = map.companionRecordSets[section.source]!;
    final add = document.actions.where(
      (action) => action.id == section.addAction,
    );
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(section.title)),
              ),
              if (add.isNotEmpty)
                TextButton.icon(
                  key: ValueKey('add-${section.id}'),
                  onPressed:
                      state.editable &&
                          !state.pending &&
                          _cubit.canChooseAction(add.first.id)
                      ? () => _chooseAction(add.first)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(add.first.label),
                ),
            ],
          ),
        ),
        if (records.isNotEmpty)
          _columnHeader(section.id, section.columns, widths),
        for (final record in records)
          CompanionRecordRow(
            key: _rows.putIfAbsent((
              section.source,
              record[section.identity] as int,
            ), GlobalKey.new),
            section: section,
            record: record,
            widths: widths,
            selected: _selected == (section.source, record[section.identity]),
            onSelected: () => setState(
              () =>
                  _selected = (section.source, record[section.identity] as int),
            ),
            onEdit: (field, value) => _cubit.queueRecord(
              section.source,
              record[section.identity] as int,
              field,
              value,
            ),
            onRemove: state.editable && !state.pending
                ? () => _removeRecord(section, record)
                : null,
          ),
      ],
    );
  }

  Future<void> _removeRecord(
    CompanionRecordSection section,
    Map<String, dynamic> record,
  ) async {
    _expanderDraftOpen = true;
    try {
      if (record.values.whereType<String>().any((value) => value.isNotEmpty)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Semantics(
              header: true,
              child: Text(
                section.confirmation.title.replaceAll(
                  '{record}',
                  section.label(record),
                ),
              ),
            ),
            content: Text(section.confirmation.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(section.confirmation.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(section.confirmation.confirm),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final identity = record[section.identity] as int;
      await _cubit.removeRecord(section.removeEvent, section.source, identity);
      if (mounted &&
          !_cubit.state.map!.companionRecordSets[section.source]!.any(
            (row) => row[section.identity] == identity,
          )) {
        setState(() {
          if (_selected == (section.source, identity)) _selected = null;
        });
      }
    } finally {
      _expanderDraftOpen = false;
      if (mounted) _updateWatching();
    }
  }

  String _selectionLabel(PatchMap map) {
    final selected = _selected;
    if (selected is (String, int)) {
      for (final section in _cubit.state.document!.recordSections.where(
        (section) => section.source == selected.$1,
      )) {
        final records = map.companionRecordSets[section.source]!.where(
          (row) => row[section.identity] == selected.$2,
        );
        if (records.isNotEmpty) {
          return '${section.label(records.first)}: ${records.first[section.fields.first.key]}';
        }
      }
    }
    if (selected is! int ||
        selected < 0 ||
        selected >= map.connections.length) {
      return '';
    }
    final row = map.connections[selected];
    return '${row.socketLabel}: ${row.destination.isEmpty ? 'Unused' : row.destination}';
  }

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
                const SizedBox(width: 16),
                for (final records in document.recordSections.where(
                  (records) =>
                      records.afterSocket ==
                          section.start + section.count - 1 &&
                      map.companionRecordSets[records.source]!.isNotEmpty,
                )) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 8 * (compact ? 48.0 : 30.0),
                        child: Text(
                          records.short,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      for (
                        var offset = 0;
                        offset <
                            map.companionRecordSets[records.source]!.length;
                        offset += 8
                      )
                        Row(
                          children: [
                            for (final record
                                in map.companionRecordSets[records.source]!
                                    .skip(offset)
                                    .take(8))
                              _recordMarker(records, record, compact),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                ],
              ],
            ],
          ),
        ),
        SizedBox(
          height: 32,
          child: _selectionLabel(map).isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _selectionLabel(map),
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

  Widget _recordMarker(
    CompanionRecordSection section,
    Map<String, dynamic> record,
    bool compact,
  ) {
    final identity = (section.source, record[section.identity] as int);
    return Semantics(
      button: true,
      selected: _selected == identity,
      label: '${section.label(record)}, ${record[section.fields.first.key]}',
      child: SizedBox(
        width: compact ? 48 : 30,
        height: compact ? 48 : 36,
        child: TextButton(
          key: ValueKey('${section.id}-dot-${identity.$2}'),
          onPressed: () => _jump(identity),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: _selected == identity
                  ? BorderSide(color: Theme.of(context).colorScheme.primary)
                  : BorderSide.none,
            ),
            backgroundColor: _selected == identity
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  key: ValueKey('${section.id}-circle-${identity.$2}'),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${identity.$2}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dotGroup(
    PatchMap map,
    String name,
    int start,
    int count,
    int columns,
    bool compact,
  ) => Column(
    children: [
      SizedBox(
        width: columns * (compact ? 48.0 : 30.0),
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
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
    required this.columns,
    required this.widths,
    required this.enabled,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
  });
  final PatchConnection row;
  final List<CompanionColumn> columns;
  final Map<String, double> widths;
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
      // Keep rejected text out of the visible, synchronized row as well.
      if (field == 'destination' || field == 'group') {
        final controller = field == 'destination' ? _destination : _group;
        final previous = field == 'destination'
            ? widget.row.destination
            : widget.row.group;
        controller.value = TextEditingValue(
          text: previous,
          selection: TextSelection.collapsed(offset: previous.length),
        );
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Widget _cell(CompanionColumn column) {
    if (column.key == 'socket') return Text(widget.row.socketLabel);
    if (column.type == 'colour') {
      return Semantics(
        label: '${widget.row.socketLabel} ${column.label.toLowerCase()}',
        child: DropdownButton<int>(
          underline: const SizedBox.shrink(),
          isDense: true,
          isExpanded: true,
          value: _colour,
          onChanged: widget.enabled
              ? (value) {
                  _colour = value!;
                  _edit('colour', value);
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
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        PatchMap.colours[i],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    final controller = column.key == 'destination'
        ? _destination
        : column.key == 'group'
        ? _group
        : _tag;
    return Semantics(
      label: '${widget.row.socketLabel} ${column.label.toLowerCase()}',
      child: TextField(
        key: column.key == 'tag' ? ValueKey('tag-${widget.row.socket}') : null,
        controller: controller,
        enabled: widget.enabled,
        keyboardType: column.type == 'integer'
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          isDense: true,
          hintText: column.key == 'destination' ? 'Unused' : '—',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (value) {
          if (column.type == 'text' &&
              value.length > column.maxLength &&
              value !=
                  (column.key == 'destination'
                      ? widget.row.destination
                      : widget.row.group)) {
            controller.text = column.key == 'destination'
                ? widget.row.destination
                : widget.row.group;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${column.label} must be at most ${column.maxLength} characters',
                ),
              ),
            );
            return;
          }
          _edit(column.key, value);
        },
      ),
    );
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
        child: Row(
          children: [
            for (final column in widget.columns)
              SizedBox(
                width: widget.widths[column.key],
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _cell(column),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A reusable text-record row. Domain operations stay in the algorithm adapter.
class CompanionRecordRow extends StatefulWidget {
  const CompanionRecordRow({
    super.key,
    required this.section,
    required this.record,
    required this.widths,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
    this.onRemove,
  });
  final CompanionRecordSection section;
  final Map<String, dynamic> record;
  final Map<String, double> widths;
  final bool selected;
  final VoidCallback onSelected;
  final void Function(String, String) onEdit;
  final VoidCallback? onRemove;
  @override
  State<CompanionRecordRow> createState() => _CompanionRecordRowState();
}

class _CompanionRecordRowState extends State<CompanionRecordRow> {
  final _controllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    _update();
  }

  void _update() {
    final keys = widget.section.fields.map((field) => field.key).toSet();
    for (final key
        in _controllers.keys.where((key) => !keys.contains(key)).toList()) {
      _controllers.remove(key)!.dispose();
    }
    for (final field in widget.section.fields) {
      final controller = _controllers.putIfAbsent(
        field.key,
        TextEditingController.new,
      );
      final text = widget.record[field.key] as String;
      if (controller.text != text) controller.text = text;
    }
  }

  @override
  void didUpdateWidget(CompanionRecordRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edit(CompanionColumn field, String value) {
    try {
      if (value.length > field.maxLength) {
        throw FormatException(
          '${field.label} must be at most ${field.maxLength} characters',
        );
      }
      widget.onEdit(field.key, value);
    } on FormatException catch (error) {
      _update();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.section.label(widget.record);
    return Focus(
      onFocusChange: (focused) {
        if (focused) widget.onSelected();
      },
      child: Semantics(
        selected: widget.selected,
        child: Container(
          color: widget.selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final column in widget.section.columns)
                SizedBox(
                  width: widget.widths[column.key],
                  child: column.type == 'label'
                      ? Text(label)
                      : column.type == 'remove'
                      ? Semantics(
                          button: true,
                          enabled: widget.onRemove != null,
                          label: '${widget.section.removeLabel} $label',
                          child: ExcludeSemantics(
                            child: IconButton(
                              tooltip: '${widget.section.removeLabel} $label',
                              onPressed: widget.onRemove,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Semantics(
                            label: '$label ${column.label.toLowerCase()}',
                            child: TextField(
                              key: ValueKey(
                                '${widget.section.source}-${column.key}-${widget.record[widget.section.identity]}',
                              ),
                              controller: _controllers[column.key],
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: column.label,
                                border: InputBorder.none,
                              ),
                              onChanged: (value) => _edit(column, value),
                            ),
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
