import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/poly_multisample/decent_sampler_converter.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/ui/poly_multisample/poly_decent_import_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:path/path.dart' as p;

Future<PolyStagedImport?> showPolyDecentImportDialog(
  BuildContext context, {
  required String sourcePath,
  PolyMultisampleBuilderCubit? previewCubit,
  @visibleForTesting PolyDecentImportCubit? cubit,
}) {
  return showDialog<PolyStagedImport>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final provided = cubit;
      if (provided != null) {
        return BlocProvider.value(
          value: provided,
          child: _PolyDecentImportDialog(previewCubit: previewCubit),
        );
      }
      return BlocProvider(
        create: (_) => PolyDecentImportCubit()..analyzeSource(sourcePath),
        child: _PolyDecentImportDialog(previewCubit: previewCubit),
      );
    },
  );
}

class _PolyDecentImportDialog extends StatelessWidget {
  const _PolyDecentImportDialog({required this.previewCubit});

  final PolyMultisampleBuilderCubit? previewCubit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocBuilder<PolyDecentImportCubit, PolyDecentImportState>(
      builder: (context, state) {
        final cubit = context.read<PolyDecentImportCubit>();
        final busy =
            state.status == PolyDecentImportStatus.analyzing ||
            state.status == PolyDecentImportStatus.staging;
        final optionsEnabled = state.status == PolyDecentImportStatus.ready;
        return PopScope(
          canPop: !busy,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) unawaited(previewCubit?.stopPreview());
          },
          child: AlertDialog(
            title: const Text('Import Decent Sampler'),
            content: SizedBox(
              width: 640,
              height: 560,
              child: _DialogBody(
                state: state,
                cubit: cubit,
                previewCubit: previewCubit,
                colorScheme: colorScheme,
                optionsEnabled: optionsEnabled,
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await previewCubit?.stopPreview();
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy || !state.canContinue
                    ? null
                    : () async {
                        await cubit.continueImport();
                        if (!context.mounted) return;
                        if (cubit.state.status ==
                            PolyDecentImportStatus.completed) {
                          await previewCubit?.stopPreview();
                          if (!context.mounted) return;
                          Navigator.of(context).pop(cubit.state.stagedImport);
                        } else {
                          await previewCubit?.stopPreview();
                        }
                      },
                child: const Text('Import'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.state,
    required this.cubit,
    required this.previewCubit,
    required this.colorScheme,
    required this.optionsEnabled,
  });

  final PolyDecentImportState state;
  final PolyDecentImportCubit cubit;
  final PolyMultisampleBuilderCubit? previewCubit;
  final ColorScheme colorScheme;
  final bool optionsEnabled;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case PolyDecentImportStatus.initial:
      case PolyDecentImportStatus.analyzing:
        return Semantics(
          liveRegion: true,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Analyzing Decent source…'),
              ],
            ),
          ),
        );
      case PolyDecentImportStatus.failure:
        return Semantics(
          liveRegion: true,
          child: Text(state.error ?? 'Analysis failed.'),
        );
      case PolyDecentImportStatus.ready:
      case PolyDecentImportStatus.staging:
      case PolyDecentImportStatus.completed:
        final analysis = state.analysis;
        if (analysis == null) return const Text('Analysis failed.');
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.status == PolyDecentImportStatus.staging) ...[
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: 'Importing Decent Sampler source',
                  child: const ExcludeSemantics(
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_empty, size: 18),
                        SizedBox(width: 12),
                        Text('Importing Decent Sampler source...'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(analysis.structureSummary),
              const SizedBox(height: 12),
              if (analysis.presets.length > 1) ...[
                Semantics(
                  header: true,
                  child: Text(
                    'Presets',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final preset in analysis.presets)
                  CheckboxListTile(
                    dense: true,
                    title: Text(preset.name),
                    subtitle: Text(
                      '${preset.groupCount} groups, ${preset.sampleCount} samples',
                    ),
                    value: state.selectedPresetNames.contains(preset.name),
                    onChanged: optionsEnabled
                        ? (_) => cubit.togglePreset(preset.name)
                        : null,
                  ),
                const SizedBox(height: 12),
              ],
              Semantics(
                header: true,
                child: Text(
                  'Group handling',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              RadioGroup<DecentSamplerGroupHandling>(
                groupValue: state.groupHandling,
                onChanged: (value) {
                  if (!optionsEnabled || value == null) return;
                  cubit.setGroupHandling(value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final handling in DecentSamplerGroupHandling.values)
                      RadioListTile<DecentSamplerGroupHandling>(
                        dense: true,
                        value: handling,
                        title: Text(_handlingLabel(handling)),
                        enabled: optionsEnabled,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _ModeEditor(
                state: state,
                analysis: analysis,
                cubit: cubit,
                previewCubit: previewCubit,
                sourcePath: state.sourcePath,
                enabled: optionsEnabled,
              ),
              SwitchListTile(
                title: const Text('Preserve XML mapping'),
                value: state.preserveXmlMapping,
                onChanged: optionsEnabled ? cubit.setPreserveXmlMapping : null,
              ),
              SwitchListTile(
                title: const Text('Include unmapped samples'),
                value: state.addUnmapped,
                onChanged: optionsEnabled ? cubit.setAddUnmapped : null,
              ),
              if (state.warnings.isNotEmpty)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final warning in state.warnings)
                        Text(
                          warning,
                          style: TextStyle(color: colorScheme.error),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
    }
  }
}

class _ModeEditor extends StatelessWidget {
  const _ModeEditor({
    required this.state,
    required this.analysis,
    required this.cubit,
    required this.previewCubit,
    required this.sourcePath,
    required this.enabled,
  });

  final PolyDecentImportState state;
  final DecentSamplerImportAnalysis analysis;
  final PolyDecentImportCubit cubit;
  final PolyMultisampleBuilderCubit? previewCubit;
  final String? sourcePath;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return switch (state.groupHandling) {
      DecentSamplerGroupHandling.velocityLayers => Column(
        children: [
          for (final group in analysis.groups)
            _GroupRow(
              group: group,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
              trailing: _IntStepper(
                label: 'Velocity',
                value:
                    state.groupVelocityLayers[group.key] ??
                    group.defaultVelocityLayer,
                onChanged: (value) => cubit.setGroupVelocity(group.key, value),
                enabled: enabled,
              ),
            ),
        ],
      ),
      DecentSamplerGroupHandling.keyRanges => Column(
        children: [
          for (final group in analysis.groups)
            _GroupRangeRow(
              group: group,
              state: state,
              cubit: cubit,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
              enabled: enabled,
            ),
        ],
      ),
      DecentSamplerGroupHandling.selectedGroup => RadioGroup<String?>(
        groupValue: state.selectedGroupKey,
        onChanged: (value) {
          if (!enabled) return;
          cubit.setSelectedGroup(value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final group in analysis.groups)
              RadioListTile<String?>(
                dense: true,
                value: group.key,
                title: Text(group.name),
                subtitle: Text(group.structureSummary),
                enabled: enabled,
              ),
          ],
        ),
      ),
      DecentSamplerGroupHandling.tagMapping => Column(
        children: [
          for (final tag in analysis.tags)
            _TagRow(
              tag: tag,
              state: state,
              cubit: cubit,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
              enabled: enabled,
            ),
        ],
      ),
      DecentSamplerGroupHandling.selectedTags => Column(
        children: [
          for (final tag in analysis.tags)
            _TagRow(
              tag: tag,
              state: state,
              cubit: cubit,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
              enabled: enabled,
            ),
        ],
      ),
      DecentSamplerGroupHandling.auto ||
      DecentSamplerGroupHandling.splitFolders => const Align(
        alignment: Alignment.centerLeft,
        child: Text('No further options.'),
      ),
    };
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.previewCubit,
    required this.sourcePath,
    required this.trailing,
  });

  final DecentSamplerGroupInfo group;
  final PolyMultisampleBuilderCubit? previewCubit;
  final String? sourcePath;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(group.name)),
        _PreviewButton(
          path: group.previewSourcePath,
          label: group.name,
          previewCubit: previewCubit,
          sourcePath: sourcePath,
        ),
        trailing,
      ],
    );
  }
}

class _GroupRangeRow extends StatelessWidget {
  const _GroupRangeRow({
    required this.group,
    required this.state,
    required this.cubit,
    required this.previewCubit,
    required this.sourcePath,
    required this.enabled,
  });

  final DecentSamplerGroupInfo group;
  final PolyDecentImportState state;
  final PolyDecentImportCubit cubit;
  final PolyMultisampleBuilderCubit? previewCubit;
  final String? sourcePath;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final range =
        state.manualGroupRanges[group.key] ??
        DecentSamplerTagKeyRange(
          lowMidi: group.defaultLowMidi,
          rootMidi: group.defaultRootMidi,
          highMidi: group.defaultHighMidi,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: 'Enable ${group.name}',
              checked: range.enabled,
              child: Checkbox(
                value: range.enabled,
                onChanged: enabled
                    ? (checked) => cubit.updateGroupRange(
                        group.key,
                        _rangeWith(range, enabled: checked ?? true),
                      )
                    : null,
              ),
            ),
            Expanded(child: Text(group.name)),
            _PreviewButton(
              path: group.previewSourcePath,
              label: group.name,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            _NoteStepper(
              label: 'Low',
              value: range.lowMidi,
              onChanged: (value) => cubit.updateGroupRange(
                group.key,
                _rangeWith(range, lowMidi: value),
              ),
              enabled: enabled,
            ),
            _NoteStepper(
              label: 'Root',
              value: range.rootMidi,
              onChanged: (value) => cubit.updateGroupRange(
                group.key,
                _rangeWith(range, rootMidi: value),
              ),
              enabled: enabled,
            ),
            _NoteStepper(
              label: 'High',
              value: range.highMidi,
              onChanged: (value) => cubit.updateGroupRange(
                group.key,
                _rangeWith(range, highMidi: value),
              ),
              enabled: enabled,
            ),
            _IntStepper(
              label: 'RR',
              value: state.groupRoundRobins[group.key] ?? 1,
              onChanged: (value) => cubit.setGroupRoundRobin(group.key, value),
              enabled: enabled,
            ),
          ],
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.state,
    required this.cubit,
    required this.previewCubit,
    required this.sourcePath,
    required this.enabled,
  });

  final DecentSamplerTag tag;
  final PolyDecentImportState state;
  final PolyDecentImportCubit cubit;
  final PolyMultisampleBuilderCubit? previewCubit;
  final String? sourcePath;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedTagKeys.contains(tag.key);
    final range =
        state.tagKeyRanges[tag.key] ??
        DecentSamplerTagKeyRange(
          lowMidi: tag.defaultLowMidi,
          rootMidi: tag.defaultRootMidi,
          highMidi: tag.defaultHighMidi,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                label:
                    'Select ${tag.label}, ${tag.sampleCount} samples, ${tag.noteRange}',
                checked: selected,
                button: true,
                onTap: enabled ? () => cubit.toggleTag(tag.key) : null,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: enabled ? () => cubit.toggleTag(tag.key) : null,
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: enabled
                              ? (_) => cubit.toggleTag(tag.key)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tag.label),
                              Text(
                                '${tag.sampleCount} samples  ${tag.noteRange}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _PreviewButton(
              path: tag.previewSourcePath,
              label: tag.label,
              previewCubit: previewCubit,
              sourcePath: sourcePath,
            ),
          ],
        ),
        if (selected &&
            (state.groupHandling == DecentSamplerGroupHandling.selectedTags ||
                state.groupHandling == DecentSamplerGroupHandling.tagMapping))
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 8,
              children: [
                _NoteStepper(
                  label: 'Low',
                  value: range.lowMidi,
                  onChanged: (value) => cubit.setTagRange(
                    tag.key,
                    _rangeWith(range, lowMidi: value),
                  ),
                  enabled: enabled,
                ),
                _NoteStepper(
                  label: 'Root',
                  value: range.rootMidi,
                  onChanged: (value) => cubit.setTagRange(
                    tag.key,
                    _rangeWith(range, rootMidi: value),
                  ),
                  enabled: enabled,
                ),
                _NoteStepper(
                  label: 'High',
                  value: range.highMidi,
                  onChanged: (value) => cubit.setTagRange(
                    tag.key,
                    _rangeWith(range, highMidi: value),
                  ),
                  enabled: enabled,
                ),
                _IntStepper(
                  label: 'Velocity',
                  value:
                      state.tagVelocityLayers[tag.key] ??
                      tag.defaultVelocityLayer,
                  onChanged: (value) => cubit.setTagVelocity(tag.key, value),
                  enabled: enabled,
                ),
                _IntStepper(
                  label: 'RR',
                  value: state.tagRoundRobins[tag.key] ?? 1,
                  onChanged: (value) => cubit.setTagRoundRobin(tag.key, value),
                  enabled: enabled,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.path,
    required this.label,
    required this.previewCubit,
    required this.sourcePath,
  });

  final String? path;
  final String label;
  final PolyMultisampleBuilderCubit? previewCubit;
  final String? sourcePath;

  @override
  Widget build(BuildContext context) {
    final cubit = previewCubit;
    final previewPath = _resolvedLocalPreviewPath(
      sourcePath: sourcePath,
      samplePath: path,
    );
    if (cubit == null || path == null) return const SizedBox.shrink();
    return BlocBuilder<
      PolyMultisampleBuilderCubit,
      PolyMultisampleBuilderState
    >(
      bloc: cubit,
      buildWhen: (previous, current) {
        return previous.previewState.visiblePath !=
            current.previewState.visiblePath;
      },
      builder: (context, state) {
        final canPreview = previewPath != null;
        final playing =
            canPreview && state.previewState.visiblePath == previewPath;
        final action = playing ? 'Stop preview' : 'Preview sample';
        final tooltip = canPreview
            ? '$action: $label'
            : 'Preview unavailable: $label';
        final button = IconButton(
          tooltip: tooltip,
          icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          onPressed: canPreview
              ? () => cubit.playOrStopPreview(previewPath)
              : null,
        );
        return SizedBox.square(
          dimension: 48,
          child: canPreview
              ? button
              : Semantics(
                  label: tooltip,
                  button: true,
                  enabled: false,
                  child: ExcludeSemantics(child: button),
                ),
        );
      },
    );
  }
}

class _NoteStepper extends StatelessWidget {
  const _NoteStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ${PolyMultisampleParser.midiToNoteName(value)}'),
        IconButton(
          tooltip: 'Decrease $label',
          visualDensity: VisualDensity.compact,
          onPressed: enabled
              ? () => onChanged((value - 1).clamp(0, 127).toInt())
              : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        IconButton(
          tooltip: 'Increase $label',
          visualDensity: VisualDensity.compact,
          onPressed: enabled
              ? () => onChanged((value + 1).clamp(0, 127).toInt())
              : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

class _IntStepper extends StatelessWidget {
  const _IntStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: $value'),
        IconButton(
          tooltip: 'Decrease $label',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onChanged(math.max(1, value - 1)) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        IconButton(
          tooltip: 'Increase $label',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

String? _resolvedLocalPreviewPath({
  required String? sourcePath,
  required String? samplePath,
}) {
  final rawSamplePath = samplePath?.trim();
  if (rawSamplePath == null || rawSamplePath.isEmpty) return null;
  if (!rawSamplePath.toLowerCase().endsWith('.wav')) return null;

  final normalizedSamplePath = rawSamplePath.replaceAll('\\', p.separator);
  final candidates = <String>[];
  if (p.isAbsolute(normalizedSamplePath)) {
    candidates.add(normalizedSamplePath);
  }

  final rawSourcePath = sourcePath?.trim();
  if (rawSourcePath != null && rawSourcePath.isNotEmpty) {
    final sourceDirectory = Directory(rawSourcePath);
    if (sourceDirectory.existsSync()) {
      candidates.add(p.join(sourceDirectory.path, normalizedSamplePath));
    } else {
      final sourceFile = File(rawSourcePath);
      if (sourceFile.existsSync() &&
          p.extension(sourceFile.path).toLowerCase() == '.dspreset') {
        candidates.add(p.join(sourceFile.parent.path, normalizedSamplePath));
      }
    }
  }

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}

String _handlingLabel(DecentSamplerGroupHandling handling) {
  return switch (handling) {
    DecentSamplerGroupHandling.auto => 'Automatic (recommended)',
    DecentSamplerGroupHandling.tagMapping => 'Map groups by tags',
    DecentSamplerGroupHandling.velocityLayers => 'Groups as velocity layers',
    DecentSamplerGroupHandling.keyRanges => 'Groups as manual key ranges',
    DecentSamplerGroupHandling.splitFolders =>
      'Split groups into separate folders',
    DecentSamplerGroupHandling.selectedGroup => 'Import one group only',
    DecentSamplerGroupHandling.selectedTags => 'Import selected tags only',
  };
}

DecentSamplerTagKeyRange _rangeWith(
  DecentSamplerTagKeyRange range, {
  int? lowMidi,
  int? rootMidi,
  int? highMidi,
  bool? enabled,
}) {
  return DecentSamplerTagKeyRange(
    lowMidi: lowMidi ?? range.lowMidi,
    rootMidi: rootMidi ?? range.rootMidi,
    highMidi: highMidi ?? range.highMidi,
    enabled: enabled ?? range.enabled,
  );
}
