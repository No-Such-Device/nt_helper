import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';

enum _TemplateApplyTarget { device, preset }

class TemplateApplyDialog extends StatefulWidget {
  final AppDatabase? database;
  final FullPresetDetails template;
  final Set<int> selectedIndices;
  final Future<void> Function()? onApplyDevice;
  final VoidCallback? onCancelDeviceApply;

  const TemplateApplyDialog({
    super.key,
    this.database,
    required this.template,
    required this.selectedIndices,
    this.onApplyDevice,
    this.onCancelDeviceApply,
  });

  static Future<void> show(
    BuildContext context, {
    AppDatabase? database,
    required FullPresetDetails template,
    required Set<int> selectedIndices,
    Future<void> Function()? onApplyDevice,
    VoidCallback? onCancelDeviceApply,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 560,
          child: TemplateApplyDialog(
            database: database,
            template: template,
            selectedIndices: selectedIndices,
            onApplyDevice: onApplyDevice,
            onCancelDeviceApply: onCancelDeviceApply,
          ),
        ),
      ),
    );
  }

  @override
  State<TemplateApplyDialog> createState() => _TemplateApplyDialogState();
}

class _TemplateApplyDialogState extends State<TemplateApplyDialog> {
  late Future<List<FullPresetDetails>> _targetsFuture;
  late _TemplateApplyTarget _target;
  int? _targetPresetId;
  bool _inFlight = false;
  bool _overwrite = false;
  int _insertionOffset = 0;
  String? _message;
  String? _error;

  AppDatabase get _database => widget.database ?? context.read<AppDatabase>();

  @override
  void initState() {
    super.initState();
    _target = widget.onApplyDevice == null
        ? _TemplateApplyTarget.preset
        : _TemplateApplyTarget.device;
    _targetsFuture = _database.presetsDao.getNonTemplates();
  }

  @override
  void dispose() {
    if (_inFlight && _target == _TemplateApplyTarget.device) {
      widget.onCancelDeviceApply?.call();
    }
    super.dispose();
  }

  Future<void> _apply(List<FullPresetDetails> targets) async {
    if (_inFlight || widget.selectedIndices.isEmpty) return;
    setState(() {
      _inFlight = true;
      _message = null;
      _error = null;
    });

    try {
      if (_target == _TemplateApplyTarget.device) {
        final applyDevice = widget.onApplyDevice;
        if (applyDevice == null) {
          throw StateError('Current device apply is unavailable.');
        }
        await applyDevice();
        if (!mounted) return;
        setState(() {
          _message = _appliedMessage(widget.selectedIndices.length);
        });
      } else {
        final targetId =
            _targetPresetId ??
            (targets.isEmpty ? null : targets.first.preset.id);
        if (targetId == null) {
          throw StateError('No target preset available.');
        }
        final target = targets.firstWhere((t) => t.preset.id == targetId);
        final selected = widget.selectedIndices.toList()..sort();
        final result = await _database.presetsDao.applyTemplateSlots(
          templateId: widget.template.preset.id,
          targetPresetId: targetId,
          templateSlotIndices: selected,
          insertionOffset: _normalizedInsertionOffset(target),
          overwrite: _overwrite,
        );
        if (!mounted) return;
        final applied = result.insertedSlotIndices.length;
        setState(() {
          _message = result.warning == null
              ? _appliedMessage(applied)
              : '${_appliedMessage(applied)} ${result.warning}';
        });
      }
    } on TemplateSpaceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            '${error.current} existing + ${error.applied} selected exceeds the '
            '${error.limit}-slot limit.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _inFlight = false);
      }
    }
  }

  String _appliedMessage(int count) {
    return 'Applied $count ${count == 1 ? 'slot' : 'slots'}';
  }

  String _slotOffsetLabel(FullPresetDetails target, int offset) {
    if (offset >= target.slots.length) {
      return 'End (${target.slots.length})';
    }
    return 'Slot $offset';
  }

  int _normalizedInsertionOffset(FullPresetDetails target) {
    final maxOffset = _maxInsertionOffset(target);
    if (_insertionOffset > maxOffset) return maxOffset;
    return _insertionOffset;
  }

  int _maxInsertionOffset(FullPresetDetails target) {
    if (_overwrite && target.slots.isNotEmpty) {
      return target.slots.length - 1;
    }
    return target.slots.length;
  }

  FullPresetDetails? _selectedTarget(List<FullPresetDetails> targets) {
    final targetId =
        _targetPresetId ?? (targets.isEmpty ? null : targets.first.preset.id);
    if (targetId == null) return null;
    return targets.firstWhereOrNull((target) => target.preset.id == targetId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FullPresetDetails>>(
      future: _targetsFuture,
      builder: (context, snapshot) {
        final targets = snapshot.data ?? const <FullPresetDetails>[];
        if (_targetPresetId == null && targets.isNotEmpty) {
          _targetPresetId = targets.first.preset.id;
        }
        final selectedTarget = _selectedTarget(targets);
        if (selectedTarget != null &&
            _insertionOffset > _maxInsertionOffset(selectedTarget)) {
          _insertionOffset = _maxInsertionOffset(selectedTarget);
        }

        return PopScope(
          canPop: true,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Apply template slots',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.selectedIndices.length} selected from '
                  '${widget.template.preset.name}',
                ),
                const SizedBox(height: 12),
                SegmentedButton<_TemplateApplyTarget>(
                  segments: [
                    const ButtonSegment(
                      value: _TemplateApplyTarget.preset,
                      icon: Icon(Icons.library_music_outlined),
                      label: Text('Local preset'),
                    ),
                    ButtonSegment(
                      value: _TemplateApplyTarget.device,
                      icon: Icon(Icons.memory),
                      label: Text('Current device'),
                      enabled: widget.onApplyDevice != null,
                    ),
                  ],
                  selected: {_target},
                  onSelectionChanged: _inFlight
                      ? null
                      : (next) => setState(() {
                          _target = next.single;
                          _message = null;
                          _error = null;
                        }),
                ),
                const SizedBox(height: 12),
                if (_target == _TemplateApplyTarget.preset)
                  snapshot.connectionState == ConnectionState.waiting
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<int>(
                          initialValue: _targetPresetId,
                          decoration: const InputDecoration(
                            labelText: 'Target preset',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final target in targets)
                              DropdownMenuItem(
                                value: target.preset.id,
                                child: Text(target.preset.name),
                              ),
                          ],
                          onChanged: _inFlight
                              ? null
                              : (value) => setState(() {
                                  _targetPresetId = value;
                                  _insertionOffset = 0;
                                }),
                        ),
                if (_target == _TemplateApplyTarget.preset &&
                    selectedTarget != null) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _normalizedInsertionOffset(selectedTarget),
                    decoration: const InputDecoration(
                      labelText: 'Start slot',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (
                        var i = 0;
                        i <= _maxInsertionOffset(selectedTarget);
                        i++
                      )
                        DropdownMenuItem(
                          value: i,
                          child: Text(_slotOffsetLabel(selectedTarget, i)),
                        ),
                    ],
                    onChanged: _inFlight
                        ? null
                        : (value) => setState(() {
                            _insertionOffset = value ?? 0;
                          }),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _overwrite,
                    onChanged: _inFlight
                        ? null
                        : (value) => setState(() {
                            _overwrite = value;
                            _insertionOffset = _normalizedInsertionOffset(
                              selectedTarget,
                            );
                          }),
                    title: const Text('Replace existing slots'),
                  ),
                ],
                if (_message != null)
                  Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_inFlight &&
                            _target == _TemplateApplyTarget.device) {
                          widget.onCancelDeviceApply?.call();
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text(_message == null ? 'Cancel' : 'Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: _inFlight
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add),
                      label: const Text('Apply selected'),
                      onPressed: _inFlight || widget.selectedIndices.isEmpty
                          ? null
                          : () => _apply(targets),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
