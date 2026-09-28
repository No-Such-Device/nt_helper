import 'dart:typed_data';
import 'package:flutter/material.dart';
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
        return const Center(
          child: Text('Connect to an NT over USB to edit its patch map.'),
        );
      }
      return PatchMapEditor(
        key: ValueKey((manager, slotIndex)),
        transport: manager as PatchMapTransport,
        slotIndex: slotIndex,
        download: manager.requestFileDownload,
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
  });
  final Future<Uint8List?> Function(String) download;
  final Duration? watchInterval;
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
  final _title = TextEditingController();
  final _rows = <int, GlobalKey>{};
  final _dirty = <int>{};
  int? _selected;
  int _expanderType = 0;
  bool _titleDirty = false;
  bool _expanderDraftOpen = false;
  PatchMap? _acknowledged;
  bool _compactMapOpen = false;

  @override
  void initState() {
    super.initState();
    _cubit = PatchMapEditorCubit(
      PatchMapClient(widget.transport, widget.slotIndex),
      widget.download,
      watchInterval: widget.watchInterval,
      hasUnsentEdits: () =>
          _dirty.isNotEmpty || _titleDirty || _expanderDraftOpen,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWatching();
  }

  void _updateWatching() => _cubit.setWatching(
    TickerMode.valuesOf(context).enabled &&
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
    _title.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_dirty.isNotEmpty || _titleDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsent edits?'),
          content: const Text(
            'Reload reads the map from the NT and replaces unsent edits in this editor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    await _cubit.load();
    if (mounted && _cubit.state.error == null) {
      setState(() {
        _dirty.clear();
        _titleDirty = false;
      });
    }
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
      if (state.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error!)));
      }
      if (!state.busy && state.error == null && state.map != null) {
        final next = state.map!;
        if (!state.applied && !state.fromDevice) {
          _dirty.clear();
          _titleDirty = false;
        } else if (_acknowledged != null) {
          _dirty.removeWhere(
            (socket) => !identical(
              _acknowledged!.connections[socket],
              next.connections[socket],
            ),
          );
        }
        if (!_titleDirty) _title.text = next.title;
        _acknowledged = next;
        final focus = state.document?.focusSocket;
        if (state.fromDevice &&
            focus != null &&
            _dirty.isEmpty &&
            !_titleDirty &&
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
          child: state.busy
              ? const CircularProgressIndicator(
                  semanticsLabel: 'Loading patch map',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.error ??
                          'Load /programs/helper/ThPh.lua from the NT SD card to open its editor. The companion runs on this computer.',
                    ),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Load SD companion'),
                    ),
                  ],
                ),
        );
      }
      return Shortcuts(
        shortcuts: {
          for (final key in KeyBindingService().globalShortcuts.keys)
            key: const DoNothingAndStopPropagationTextIntent(),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1050;
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _title,
                          enabled: state.editable,
                          decoration: const InputDecoration(
                            labelText: 'Patch title',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() => _titleDirty = true),
                          onSubmitted: (_) => _saveTitle(),
                        ),
                      ),
                      TextButton(
                        onPressed: state.editable && _titleDirty
                            ? _saveTitle
                            : null,
                        child: const Text('Apply title'),
                      ),
                      DropdownButton<int>(
                        value: _expanderType,
                        onChanged: state.editable
                            ? (value) => setState(() => _expanderType = value!)
                            : null,
                        items: [
                          for (
                            var i = 0;
                            i < PatchMap.expanderTypes.length;
                            i++
                          )
                            DropdownMenuItem(
                              value: i,
                              child: Text(PatchMap.expanderTypes[i]),
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed:
                            state.editable &&
                                map.expanders.length < PatchMap.maxExpanders
                            ? () => _cubit.addExpander(_expanderType)
                            : null,
                        child: const Text('Add expander'),
                      ),
                      TextButton(
                        onPressed: state.busy ? null : _reload,
                        child: const Text('Reload companion & map'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      state.busy
                          ? 'Waiting for the NT…'
                          : state.error != null
                          ? '${state.error} Edits are disabled until reload.'
                          : state.fromDevice
                          ? 'Updated from the NT. Save the preset to keep changes.'
                          : state.applied
                          ? 'Applied to the NT. Save the preset to keep your changes.'
                          : 'Press Enter or Apply row to send edits. Save the preset to keep them.',
                    ),
                  ),
                  if (_dirty.isNotEmpty)
                    Text('${_dirty.length} rows with unsent edits'),
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
                                  key: const ValueKey('desktop-minimap-scroll'),
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
                                  label: const Text('Socket minimap'),
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
      );
    },
  );

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
                        enabled: !state.busy,
                        decoration: InputDecoration(errorText: validationError),
                      ),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${state.error} Copy your name before closing, then reload the map.',
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: !state.editable
                          ? null
                          : () async {
                              try {
                                PatchExpander(
                                  type: state.map!.expanders[index].type,
                                  name: controller.text,
                                );
                              } on FormatException catch (error) {
                                setDialogState(
                                  () => validationError = error.message,
                                );
                                return;
                              }
                              await _cubit.renameExpander(
                                index,
                                controller.text,
                              );
                              if (dialogContext.mounted &&
                                  !_cubit.isClosed &&
                                  _cubit.state.error == null) {
                                Navigator.pop(dialogContext);
                              }
                            },
                      child: const Text('Apply'),
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
      controller.dispose();
    }
  }

  Future<void> _saveTitle() async {
    try {
      final current = _cubit.state.map!;
      PatchMap(
        title: _title.text,
        connections: current.connections,
        expanders: current.expanders,
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    await _cubit.setTitle(_title.text);
    if (mounted && _cubit.state.error == null) {
      setState(() => _titleDirty = false);
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
                    SizedBox(width: 84),
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
                                          _dirty.isEmpty &&
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
                                          _dirty.isEmpty &&
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
                            enabled: state.editable,
                            selected: _selected == row.socket,
                            onSelected: () =>
                                setState(() => _selected = row.socket),
                            onDirty: (dirty) => setState(() {
                              if (dirty) {
                                _dirty.add(row.socket);
                              } else {
                                _dirty.remove(row.socket);
                              }
                            }),
                            onSave: _cubit.setConnection,
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
        Semantics(header: true, child: const Text('Socket minimap')),
        const Text('Select a dot to find its row.'),
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
        if (_selected != null && _selected! < map.connections.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                '${map.connections[_selected!].socketLabel}: ${map.connections[_selected!].destination.isEmpty ? 'Unused' : map.connections[_selected!].destination}',
              ),
            ),
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
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: row.connected
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
    required this.onDirty,
    required this.onSave,
  });
  final PatchConnection row;
  final bool enabled, selected;
  final VoidCallback onSelected;
  final ValueChanged<bool> onDirty;
  final Future<void> Function(PatchConnection) onSave;
  @override
  State<PatchMapRow> createState() => _PatchMapRowState();
}

class _PatchMapRowState extends State<PatchMapRow> {
  final _destination = TextEditingController(),
      _group = TextEditingController(),
      _tag = TextEditingController();
  late int _colour;
  bool _dirty = false;
  String? _error;
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
    _dirty = false;
    _error = null;
  }

  @override
  void didUpdateWidget(PatchMapRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.row, widget.row)) _reset();
  }

  @override
  void dispose() {
    _destination.dispose();
    _group.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() => _dirty = true);
    widget.onDirty(true);
  }

  Future<void> _save() async {
    if (!widget.enabled || !_dirty) return;
    try {
      final tag = _tag.text.isEmpty ? 0 : int.tryParse(_tag.text);
      if (tag == null || (_tag.text.isNotEmpty && (tag < 1 || tag > 12))) {
        throw const FormatException(
          'Tag must be an integer from 1 to 12, or blank.',
        );
      }
      final row = PatchConnection(
        socket: widget.row.socket,
        destination: _destination.text,
        colour: _colour,
        tag: tag,
        group: _group.text,
      );
      await widget.onSave(row);
      // Only a new acknowledged row clears the draft; errors retain it.
      if (mounted && !_dirty) widget.onDirty(false);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
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
                      onChanged: (_) => _changed(),
                      onSubmitted: (_) => _save(),
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
                              _changed();
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
                      onChanged: (_) => _changed(),
                      onSubmitted: (_) => _save(),
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
                      onChanged: (_) => _changed(),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: !_dirty
                      ? const SizedBox(height: 32)
                      : TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            textStyle: Theme.of(context).textTheme.labelMedium,
                          ),
                          onPressed: widget.enabled && _dirty ? _save : null,
                          child: const Text('Apply row'),
                        ),
                ),
              ],
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
