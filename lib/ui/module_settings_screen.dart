import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/module_settings.dart';
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
    final changes = snapshot.tree!.groups[group]!.children
        .where((c) => !c.isGroup)
        .map((c) => snapshot.settings[c.id]!)
        .where((edit) => edit.changed);
    final warning = [
      if (changes.any((e) => e.info.restartsEngine)) 'Restarts audio.',
      if (changes.any((e) => e.info.needsReboot)) 'Reboot required.',
      'MIDI may disconnect. Applied one at a time; not saved to flash.',
    ].join(' ');
    if (!await _confirm('Apply changes to $name?', warning, 'Apply changes')) {
      return;
    }
    if (!mounted ||
        widget.cubit.moduleSettingsState.connectionId != connectionId) {
      return;
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
    if (!approved ||
        !mounted ||
        widget.cubit.moduleSettingsState.connectionId != connectionId) {
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
    builder: (context, snapshot) {
      final state = snapshot.data!;
      return Scaffold(
        appBar: AppBar(
          title: const Text('NT Settings'),
          actions: [
            IconButton(
              tooltip: 'Discard drafts',
              onPressed: state.ready && state.hasDrafts
                  ? widget.cubit.discardModuleSettingsDrafts
                  : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              key: const Key('refresh-module-settings'),
              tooltip: 'Refresh module settings',
              onPressed: state.unavailableReason != null || state.busy
                  ? null
                  : () => widget.cubit.loadModuleSettings(force: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: FocusTraversalGroup(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              constraints.maxWidth < 340 ||
                              MediaQuery.textScalerOf(context).scale(16) > 24;
                          final buttons = [
                            FilledButton(
                              onPressed: state.canCommit
                                  ? () => _action(false, state.connectionId)
                                  : null,
                              child: const Text('Commit to flash'),
                            ),
                            OutlinedButton(
                              onPressed: state.canCommit
                                  ? () => _action(true, state.connectionId)
                                  : null,
                              child: const Text('Revert to saved'),
                            ),
                          ];
                          return compact
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < buttons.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(height: 8),
                                      SizedBox(height: 56, child: buttons[i]),
                                    ],
                                  ],
                                )
                              : Row(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < buttons.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(width: 12),
                                      Expanded(
                                        child: SizedBox(
                                          height: 48,
                                          child: buttons[i],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                        },
                      ),
                      _SettingsFeedback(
                        key: const Key('module-settings-status'),
                        message: state.unavailableReason ?? state.message,
                        busy: state.busy,
                      ),
                      if (state.tree != null) ..._group(context, state, 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _group(BuildContext context, ModuleSettingsState state, int id) {
    final group = state.tree!.groups[id]!;
    final direct = group.children.where((c) => !c.isGroup).toList();
    final lastSetting = group.children.lastIndexWhere((c) => !c.isGroup);
    final hasChanges = direct.any((c) => state.settings[c.id]!.changed);
    final valid = direct.every((c) => state.settings[c.id]!.error == null);
    final editable = direct.any((c) => state.settings[c.id]!.info.writable);
    final name = group.name.isEmpty ? 'module settings' : group.name;
    return [
      if (id != 0) ...[
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            group.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
      ],
      for (var index = 0; index < group.children.length; index++) ...[
        if (group.children[index].isGroup)
          ..._group(context, state, group.children[index].id)
        else
          _ModuleSettingField(
            key: ValueKey(
              'module-setting-${state.connectionId}-${group.children[index].id}',
            ),
            edit: state.settings[group.children[index].id]!,
            enabled: state.ready,
            units: widget.cubit.state is DistingStateSynchronized
                ? (widget.cubit.state as DistingStateSynchronized).unitStrings
                : const [],
            onChanged: (value) =>
                widget.cubit.editModuleSetting(group.children[index].id, value),
          ),
        if (index == lastSetting && editable)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              height: 56,
              child: Semantics(
                label: 'Apply changes to $name',
                excludeSemantics: true,
                button: true,
                enabled:
                    state.ready && !state.hasUncertainty && hasChanges && valid,
                onTap:
                    state.ready && !state.hasUncertainty && hasChanges && valid
                    ? () => _apply(id, name, state.connectionId)
                    : null,
                child: OutlinedButton(
                  key: ValueKey('module-settings-apply-$id'),
                  onPressed:
                      state.ready &&
                          !state.hasUncertainty &&
                          hasChanges &&
                          valid
                      ? () => _apply(id, name, state.connectionId)
                      : null,
                  child: Text(
                    id == 0 ? 'Apply changes' : 'Apply ${group.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    ];
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
  });
  final String message;
  final String detail;
  final String subject;
  final bool busy;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(14) * 1.5;
    final fullMessage = detail.isEmpty ? message : '$message\n$detail';
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: isError ? Theme.of(context).colorScheme.error : null);
    return SizedBox(
      height: line * 2 + 16,
      child: Row(
        children: [
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
          Expanded(
            child: Tooltip(
              message: fullMessage,
              child: Semantics(
                liveRegion: true,
                label: fullMessage.isEmpty ? '' : '$subject: $fullMessage',
                excludeSemantics: true,
                child: detail.isEmpty
                    ? Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: message.isEmpty
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
    final value = widget.edit.displayed.value.toString();
    if (_text.text != value) {
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
    final enabled = widget.enabled && info.writable;
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
            subject: info.name,
            message:
                edit.error ??
                (edit.changed
                    ? (info.restartsEngine
                          ? 'Draft · Restarts audio on Apply'
                          : 'Draft')
                    : info.needsReboot
                    ? 'Reboot required'
                    : info.unit == 16
                    ? edit.observed.presentation
                    : ''),
            detail: edit.changed || edit.uncertain || edit.error != null
                ? 'Last read: $observedLabel'
                : '',
            isError: edit.error != null,
          ),
        ],
      ),
    );
  }
}
