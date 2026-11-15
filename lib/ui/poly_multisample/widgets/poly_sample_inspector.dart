import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/wav_metadata.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_region_math.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_sidebar_layout.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_waveform_editor.dart';
import 'package:path/path.dart' as p;

class PolySampleInspector extends StatelessWidget {
  const PolySampleInspector({
    super.key,
    required this.state,
    required this.manager,
  });

  final PolyMultisampleBuilderState state;
  final IDistingMidiManager? manager;

  @override
  Widget build(BuildContext context) {
    final region = selectedRegionFor(state);
    if (region == null) {
      return const Center(child: Text('No sample selected'));
    }
    final cubit = context.read<PolyMultisampleBuilderCubit>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PolySampleSidebarLayout.outerPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderRow(state: state, region: region, manager: manager),
          const SizedBox(height: 12),
          _PreviewControls(state: state),
          const SizedBox(height: 16),
          _MappingSection(
            state: state,
            region: region,
            cubit: cubit,
            manager: manager,
          ),
          const SizedBox(height: 8),
          _WaveformSection(state: state, region: region, cubit: cubit),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.state,
    required this.region,
    required this.manager,
  });

  final PolyMultisampleBuilderState state;
  final PolySampleRegion region;
  final IDistingMidiManager? manager;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PolyMultisampleBuilderCubit>();
    final index = state.editedRegions.indexWhere(
      (candidate) => candidate.path == region.path,
    );
    final label = sampleDisplayLabel(region, state.editedRegions);
    final playing = state.previewState.visiblePath == region.path;
    final canPreview = region.path.toLowerCase().endsWith('.wav');
    final canReveal = _isLocalPath(state, region);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous sample',
          icon: const Icon(Icons.chevron_left),
          onPressed: index > 0
              ? () => cubit.selectRegion(
                  state.editedRegions[index - 1].path,
                  PolyRegionSelectionMode.replace,
                  manager: manager,
                )
              : null,
        ),
        IconButton(
          tooltip: 'Next sample',
          icon: const Icon(Icons.chevron_right),
          onPressed: index >= 0 && index < state.editedRegions.length - 1
              ? () => cubit.selectRegion(
                  state.editedRegions[index + 1].path,
                  PolyRegionSelectionMode.replace,
                  manager: manager,
                )
              : null,
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: playing ? 'Stop preview' : 'Preview sample',
          onPressed: canPreview
              ? () => cubit.playOrStopPreview(region.path, manager: manager)
              : null,
          icon: Icon(playing ? Icons.stop : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Reveal in file manager',
          icon: const Icon(Icons.folder_open),
          onPressed: canReveal
              ? () => _revealFolder(context, region.path)
              : null,
        ),
      ],
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({required this.state});

  final PolyMultisampleBuilderState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PolyMultisampleBuilderCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Auto-preview'),
          value: state.autoPreview,
          onChanged: cubit.setAutoPreview,
        ),
        SizedBox(
          height: PolySampleSidebarLayout.rowHeight,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: PolySampleSidebarLayout.iconButtonExtent,
                child: Icon(Icons.volume_down),
              ),
              Expanded(
                child: Semantics(
                  label: 'Preview gain',
                  value: '${state.previewGainDb.round()} dB',
                  child: Slider(
                    min: -36,
                    max: 6,
                    divisions: 42,
                    value: state.previewGainDb,
                    label: '${state.previewGainDb.round()} dB',
                    semanticFormatterCallback: (value) => '${value.round()} dB',
                    onChanged: cubit.setPreviewGain,
                  ),
                ),
              ),
              PolySampleSidebarSliderValue(
                key: const ValueKey('poly-sidebar-preview-gain-value'),
                width: PolySampleSidebarLayout.dbValueWidth,
                semanticLabel: 'Preview gain value',
                value: '${state.previewGainDb.round()} dB',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MappingSection extends StatelessWidget {
  const _MappingSection({
    required this.state,
    required this.region,
    required this.cubit,
    required this.manager,
  });

  final PolyMultisampleBuilderState state;
  final PolySampleRegion region;
  final PolyMultisampleBuilderCubit cubit;
  final IDistingMidiManager? manager;

  @override
  Widget build(BuildContext context) {
    final selectedRegions = _selectedRegionsForMapping(state, region);
    final selectedCount = selectedRegions.length;
    final rootSelection = _selectionValue<_AutomaticMidiValue>(
      selectedRegions,
      (region) {
        final mapping = state.mappingResolution.mappingForRegion(region);
        if (mapping?.isPlayable != true) return null;
        return (
          midi: mapping!.naturalMidi,
          automatic: mapping.naturalIsAutomatic,
        );
      },
    );
    final rootDisplay = _automaticMidiDisplay(rootSelection);
    final lowSelection = _selectionValue<_AutomaticMidiValue>(selectedRegions, (
      region,
    ) {
      final mapping = state.mappingResolution.mappingForRegion(region);
      if (mapping?.isPlayable != true) return null;
      return (midi: mapping!.lowMidi!, automatic: mapping.switchIsAutomatic);
    });
    final lowDisplay = _automaticMidiDisplay(lowSelection);
    final lowDropdownSelection = lowSelection.mixed
        ? const _SelectionValue<int>.mixed()
        : lowSelection.value == null || lowSelection.value!.automatic
        ? const _SelectionValue<int>.value(null)
        : _SelectionValue<int>.value(lowSelection.value!.midi);
    final highSelection = _selectionValue<int>(selectedRegions, (region) {
      final mapping = state.mappingResolution.mappingForRegion(region);
      return mapping?.isPlayable == true ? mapping!.highMidi : null;
    });
    final highDisplay = highSelection.mixed
        ? 'Mixed'
        : highSelection.value == null
        ? 'Unresolved'
        : PolyMultisampleParser.midiToNoteName(highSelection.value!);
    final velocitySelection = _selectionValue<int>(
      selectedRegions,
      (region) => region.velocityLayer ?? 1,
    );
    final rrSelection = _selectionValue<int>(
      selectedRegions,
      (region) => region.roundRobin ?? 1,
    );
    final maxVelocityLane = selectedRegions.fold<int>(
      32,
      (maximum, region) => math.max(maximum, region.velocityLayer ?? 1),
    );
    final maxRoundRobinLane = selectedRegions.fold<int>(
      32,
      (maximum, region) => math.max(maximum, region.roundRobin ?? 1),
    );
    final focusedMapping = state.mappingResolution.mappingForRegion(region);
    final focusedPlayable = focusedMapping?.isPlayable == true;
    final root = focusedPlayable ? focusedMapping!.naturalMidi : null;
    final low = focusedPlayable ? focusedMapping!.lowMidi : null;
    final focusedRootDisplay = root == null
        ? 'Unresolved'
        : focusedMapping!.naturalIsAutomatic
        ? 'Auto ${PolyMultisampleParser.midiToNoteName(root)}'
        : PolyMultisampleParser.midiToNoteName(root);
    final focusedLowDisplay = low == null
        ? 'Unresolved'
        : focusedMapping!.switchIsAutomatic
        ? 'Auto ${PolyMultisampleParser.midiToNoteName(low)}'
        : PolyMultisampleParser.midiToNoteName(low);
    final velocity = region.velocityLayer ?? 1;
    final roundRobin = region.roundRobin ?? 1;
    final title = selectedCount == 1 ? 'Mapping' : 'Mapping selection';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (selectedCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$selectedCount samples selected'),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: PolySampleSidebarLayout.rowHeight,
          child: Row(
            children: [
              SizedBox(
                width: PolySampleSidebarLayout.mappingLabelWidth,
                child: const Text('Root'),
              ),
              Expanded(
                child: MergeSemantics(
                  key: const ValueKey('poly-mapping-root-semantics'),
                  child: Semantics(
                    label: 'Root value',
                    value: rootDisplay,
                    button: true,
                    child: PopupMenuButton<int>(
                      key: const ValueKey('poly-mapping-root-menu'),
                      tooltip: 'Choose root note',
                      padding: EdgeInsets.zero,
                      initialValue:
                          rootSelection.mixed ||
                              rootSelection.value == null ||
                              rootSelection.value!.automatic
                          ? null
                          : rootSelection.value!.midi,
                      itemBuilder: (context) => _rootNoteMenuEntries(),
                      onSelected: (value) {
                        cubit.updateSelectedRoot(value, manager: manager);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              rootDisplay,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _MappingDropdownRow<int>(
          dropdownKey: const ValueKey('poly-mapping-low-dropdown'),
          label: 'Low',
          selected: lowDropdownSelection,
          items: _noteMenuItems(),
          unsetHint: lowSelection.value == null ? 'Unresolved' : lowDisplay,
          onChanged: (value) {
            if (value == null) return;
            cubit.updateSelectedSwitchPoint(value, manager: manager);
          },
        ),
        _MappingReadOnlyRow(
          key: const ValueKey('poly-mapping-high-value'),
          label: 'High',
          value: highDisplay,
          hint: 'Calculated from the next sample switch point.',
        ),
        _MappingDropdownRow<int>(
          dropdownKey: const ValueKey('poly-mapping-velocity-dropdown'),
          label: 'Velocity',
          selected: velocitySelection,
          items: _laneMenuItems(maxVelocityLane),
          onChanged: (value) {
            if (value == null) return;
            cubit.updateSelectedVelocity(value, manager: manager);
          },
        ),
        _MappingDropdownRow<int>(
          dropdownKey: const ValueKey('poly-mapping-rr-dropdown'),
          label: 'RR',
          selected: rrSelection,
          items: _laneMenuItems(maxRoundRobinLane),
          onChanged: (value) {
            if (value == null) return;
            cubit.updateSelectedRoundRobin(value, manager: manager);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('poly-mapping-use-automatic'),
            onPressed: cubit.resetSelectedToAutomaticNotes,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(
              selectedCount == 1 ? 'Use automatic note' : 'Use automatic notes',
            ),
          ),
        ),
        const SizedBox(height: 8),
        _StepRow(
          rowKeySuffix: 'root',
          label: 'Root',
          value: focusedRootDisplay,
          onMinus: root == null
              ? null
              : () => cubit.updateSelectedRoot(root - 1, manager: manager),
          onPlus: root == null
              ? null
              : () => cubit.updateSelectedRoot(root + 1, manager: manager),
        ),
        _StepRow(
          rowKeySuffix: 'low',
          label: 'Low',
          value: focusedLowDisplay,
          onMinus: low == null
              ? null
              : () =>
                    cubit.updateSelectedSwitchPoint(low - 1, manager: manager),
          onPlus: low == null
              ? null
              : () =>
                    cubit.updateSelectedSwitchPoint(low + 1, manager: manager),
        ),
        _StepRow(
          rowKeySuffix: 'velocity',
          label: 'Velocity',
          value: '$velocity',
          onMinus: () => cubit.updateSelectedVelocity(
            math.max(1, velocity - 1),
            manager: manager,
          ),
          onPlus: () =>
              cubit.updateSelectedVelocity(velocity + 1, manager: manager),
        ),
        _StepRow(
          rowKeySuffix: 'round-robin',
          label: 'Round robin',
          value: '$roundRobin',
          onMinus: () => cubit.updateSelectedRoundRobin(
            math.max(1, roundRobin - 1),
            manager: manager,
          ),
          onPlus: () =>
              cubit.updateSelectedRoundRobin(roundRobin + 1, manager: manager),
        ),
      ],
    );
  }
}

typedef _AutomaticMidiValue = ({int midi, bool automatic});

String _automaticMidiDisplay(_SelectionValue<_AutomaticMidiValue> selection) {
  if (selection.mixed) return 'Mixed';
  final value = selection.value;
  if (value == null) return 'Unresolved';
  final note = PolyMultisampleParser.midiToNoteName(value.midi);
  return value.automatic ? 'Auto $note' : note;
}

class _SelectionValue<T extends Object> {
  const _SelectionValue.value(this.value) : mixed = false;
  const _SelectionValue.mixed() : value = null, mixed = true;

  final T? value;
  final bool mixed;
}

List<PolySampleRegion> _selectedRegionsForMapping(
  PolyMultisampleBuilderState state,
  PolySampleRegion fallback,
) {
  final selected = state.editedRegions
      .where((region) => state.selectedPaths.contains(region.path))
      .toList();
  return selected.isEmpty ? [fallback] : selected;
}

_SelectionValue<T> _selectionValue<T extends Object>(
  List<PolySampleRegion> regions,
  T? Function(PolySampleRegion region) valueFor,
) {
  if (regions.isEmpty) return const _SelectionValue.mixed();
  final values = [for (final region in regions) valueFor(region)];
  final first = values.first;
  if (values.every((value) => value == first)) {
    return _SelectionValue.value(first);
  }
  if (values.every((value) => value == null)) {
    return const _SelectionValue.value(null);
  }
  return const _SelectionValue.mixed();
}

class _MappingDropdownRow<T extends Object> extends StatelessWidget {
  const _MappingDropdownRow({
    super.key,
    required this.dropdownKey,
    required this.label,
    required this.selected,
    required this.items,
    required this.onChanged,
    this.unsetHint = 'Unset',
  });

  final Key? dropdownKey;
  final String label;
  final _SelectionValue<T> selected;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String unsetHint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PolySampleSidebarLayout.rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: PolySampleSidebarLayout.mappingLabelWidth,
            child: Text(label),
          ),
          Expanded(
            child: DropdownButton<T>(
              key: dropdownKey,
              isExpanded: true,
              value: selected.mixed ? null : selected.value,
              hint: Text(selected.mixed ? 'Mixed' : unsetHint),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _MappingReadOnlyRow extends StatelessWidget {
  const _MappingReadOnlyRow({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PolySampleSidebarLayout.rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: PolySampleSidebarLayout.mappingLabelWidth,
            child: Text(label),
          ),
          Expanded(
            child: Semantics(
              label: '$label value',
              value: value,
              hint: hint,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<PopupMenuEntry<int>> _rootNoteMenuEntries() {
  return [
    for (var value = 0; value < 128; value++)
      PopupMenuItem<int>(
        key: ValueKey('poly-root-note-$value'),
        value: value,
        child: Text(PolyMultisampleParser.midiToNoteName(value)),
      ),
  ];
}

List<DropdownMenuItem<int>> _noteMenuItems() {
  return [
    for (var value = 0; value < 128; value++)
      DropdownMenuItem<int>(
        value: value,
        child: Text(PolyMultisampleParser.midiToNoteName(value)),
      ),
  ];
}

List<DropdownMenuItem<int>> _laneMenuItems(int maxValue) {
  return [
    for (var value = 1; value <= maxValue; value++)
      DropdownMenuItem<int>(value: value, child: Text('$value')),
  ];
}

class _WaveformSection extends StatelessWidget {
  const _WaveformSection({
    required this.state,
    required this.region,
    required this.cubit,
  });

  final PolyMultisampleBuilderState state;
  final PolySampleRegion region;
  final PolyMultisampleBuilderCubit cubit;

  @override
  Widget build(BuildContext context) {
    final canEdit =
        _isLocalPath(state, region) &&
        region.path.toLowerCase().endsWith('.wav');
    if (!canEdit) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('Waveform editing needs a local or mounted WAV file.'),
      );
    }
    final overview = state.waveformSummaries[region.path];
    final loading = state.waveformLoadingPaths.contains(region.path);
    final failed = state.waveformFailedPaths.contains(region.path);
    final playback =
        p.normalize(state.previewState.sourcePlayback?.sourcePath ?? '') ==
            p.normalize(region.path)
        ? state.previewState.sourcePlayback
        : null;
    if (overview == null) {
      if (!loading && !failed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          cubit.loadWaveform(region.path);
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Waveform',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Text('Editing ${sampleDisplayLabel(region, state.editedRegions)}'),
          const SizedBox(height: 8),
          _WaveformLoadingPlaceholder(failed: failed, playback: playback),
          const SizedBox(height: 8),
          if (failed)
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Waveform loading failed.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => cubit.loadWaveform(region.path),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry waveform'),
                  ),
                ],
              ),
            )
          else
            Semantics(
              liveRegion: true,
              child: const Text('Loading waveform...'),
            ),
        ],
      );
    }

    final loopDraft =
        state.loopDrafts[region.path] ??
        PolyWaveformDraft(
          loopStart: overview.loopStart,
          loopEnd: overview.loopEnd,
        );
    final wavDraft =
        state.wavEditDrafts[region.path] ??
        PolyWaveformDraft(trimStart: 0, trimEnd: overview.frameCount - 1);
    final maxFrame = math.max(0, overview.frameCount - 1);
    final loopChanged =
        loopDraft.loopStart != overview.loopStart ||
        loopDraft.loopEnd != overview.loopEnd;
    final label = sampleDisplayLabel(region, state.editedRegions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Waveform',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text('Editing $label', overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Tooltip(
          message: 'Click to set trim start/end. Command/Ctrl-click or right-click to set loop start/end.',
          child: PolyWaveformEditor(
            overview: overview,
            mode: PolyWaveformEditorMode.trim,
            startFrame: wavDraft.trimStart ?? 0,
            endFrame: wavDraft.trimEnd ?? maxFrame,
            loopStartFrame: loopDraft.loopStart,
            loopEndFrame: loopDraft.loopEnd,
            fadeInFrames: wavDraft.fadeInFrames,
            fadeOutFrames: wavDraft.fadeOutFrames,
            fadeInCurve: wavDraft.fadeInCurve,
            fadeOutCurve: wavDraft.fadeOutCurve,
            fadeInStrength: wavDraft.fadeInStrength,
            fadeOutStrength: wavDraft.fadeOutStrength,
            playback: playback,
            onChanged: (start, end) {
              cubit.updateWavEditDraft(
                region.path,
                wavDraft.copyWith(trimStart: start, trimEnd: end),
              );
            },
            onLoopChanged: (start, end) {
              cubit.updateLoopDraft(
                region.path,
                loopDraft.copyWith(loopStart: start, loopEnd: end),
              );
            },
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Loop enabled'),
          value: loopDraft.loopStart != null && loopDraft.loopEnd != null,
          onChanged: (enabled) {
            cubit.updateLoopDraft(
              region.path,
              enabled
                  ? loopDraft.copyWith(
                      loopStart: loopDraft.loopStart ?? 0,
                      loopEnd: loopDraft.loopEnd ?? maxFrame,
                    )
                  : loopDraft.copyWith(
                      clearLoopStart: true,
                      clearLoopEnd: true,
                    ),
            );
          },
        ),
        if (loopDraft.loopStart != null && loopDraft.loopEnd != null) ...[
          _FrameNudgeRow(
            rowKeySuffix: 'loop-start',
            label: 'Loop start',
            value: loopDraft.loopStart ?? 0,
            onNudge: (delta) => cubit.updateLoopDraft(
              region.path,
              loopDraft.copyWith(
                loopStart: ((loopDraft.loopStart ?? 0) + delta)
                    .clamp(0, math.max(0, (loopDraft.loopEnd ?? maxFrame) - 1))
                    .toInt(),
              ),
            ),
          ),
          _FrameNudgeRow(
            rowKeySuffix: 'loop-end',
            label: 'Loop end',
            value: loopDraft.loopEnd ?? maxFrame,
            onNudge: (delta) => cubit.updateLoopDraft(
              region.path,
              loopDraft.copyWith(
                loopEnd: ((loopDraft.loopEnd ?? maxFrame) + delta)
                    .clamp(
                      math.min(maxFrame, (loopDraft.loopStart ?? 0) + 1),
                      maxFrame,
                    )
                    .toInt(),
              ),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: loopChanged
                ? () async => cubit.saveLoopMetadata(region.path)
                : null,
            child: const Text('Save loop'),
          ),
        ),
        _FrameNudgeRow(
          rowKeySuffix: 'trim-start',
          label: 'Trim start',
          value: wavDraft.trimStart ?? 0,
          onNudge: (delta) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(
              trimStart: ((wavDraft.trimStart ?? 0) + delta)
                  .clamp(0, math.max(0, (wavDraft.trimEnd ?? maxFrame) - 1))
                  .toInt(),
            ),
          ),
        ),
        _FrameNudgeRow(
          rowKeySuffix: 'trim-end',
          label: 'Trim end',
          value: wavDraft.trimEnd ?? maxFrame,
          onNudge: (delta) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(
              trimEnd: ((wavDraft.trimEnd ?? maxFrame) + delta)
                  .clamp(
                    math.min(maxFrame, (wavDraft.trimStart ?? 0) + 1),
                    maxFrame,
                  )
                  .toInt(),
            ),
          ),
        ),
        _FadeRow(
          label: 'Fade in',
          overview: overview,
          frames: wavDraft.fadeInFrames,
          curve: wavDraft.fadeInCurve,
          strength: wavDraft.fadeInStrength,
          onFramesChanged: (frames) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeInFrames: frames),
          ),
          onCurveChanged: (curve) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeInCurve: curve),
          ),
          onStrengthChanged: (strength) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeInStrength: strength),
          ),
        ),
        _FadeRow(
          label: 'Fade out',
          overview: overview,
          frames: wavDraft.fadeOutFrames,
          curve: wavDraft.fadeOutCurve,
          strength: wavDraft.fadeOutStrength,
          onFramesChanged: (frames) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeOutFrames: frames),
          ),
          onCurveChanged: (curve) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeOutCurve: curve),
          ),
          onStrengthChanged: (strength) => cubit.updateWavEditDraft(
            region.path,
            wavDraft.copyWith(fadeOutStrength: strength),
          ),
        ),
        SizedBox(
          height: PolySampleSidebarLayout.rowHeight,
          child: Row(
            children: [
              const SizedBox(
                width: PolySampleSidebarLayout.sliderLabelWidth,
                child: Text('Gain'),
              ),
              Expanded(
                child: Semantics(
                  label: 'Audio gain',
                  value: '${wavDraft.gainDb.toStringAsFixed(1)} dB',
                  child: Slider(
                    key: const ValueKey('poly-wav-gain-slider'),
                    min: -24,
                    max: 24,
                    divisions: 96,
                    value: wavDraft.gainDb,
                    label: '${wavDraft.gainDb.toStringAsFixed(1)} dB',
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(1)} dB',
                    onChanged: (value) => cubit.updateWavEditDraft(
                      region.path,
                      wavDraft.copyWith(gainDb: value),
                    ),
                  ),
                ),
              ),
              PolySampleSidebarSliderValue(
                key: const ValueKey('poly-sidebar-wav-gain-value'),
                width: PolySampleSidebarLayout.dbValueWidth,
                semanticLabel: 'Audio gain value',
                value: '${wavDraft.gainDb.toStringAsFixed(1)} dB',
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Normalize'),
          value: wavDraft.normalizePeakDb != null,
          onChanged: (enabled) => cubit.updateWavEditDraft(
            region.path,
            enabled
                ? wavDraft.copyWith(normalizePeakDb: -0.3)
                : wavDraft.copyWith(clearNormalize: true),
          ),
        ),
        SizedBox(
          height: PolySampleSidebarLayout.rowHeight,
          child: Row(
            children: [
              const SizedBox(
                width: PolySampleSidebarLayout.sliderLabelWidth,
                child: Text('Peak'),
              ),
              Expanded(
                child: Semantics(
                  label: 'Normalize peak',
                  value:
                      '${(wavDraft.normalizePeakDb ?? -0.3).toStringAsFixed(1)} dB',
                  child: Slider(
                    key: const ValueKey('poly-sidebar-normalize-peak-slider'),
                    min: -24,
                    max: 0,
                    divisions: 48,
                    value: wavDraft.normalizePeakDb ?? -0.3,
                    label:
                        '${(wavDraft.normalizePeakDb ?? -0.3).toStringAsFixed(1)} dB',
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(1)} dB',
                    onChanged: wavDraft.normalizePeakDb == null
                        ? null
                        : (value) => cubit.updateWavEditDraft(
                            region.path,
                            wavDraft.copyWith(normalizePeakDb: value),
                          ),
                  ),
                ),
              ),
              PolySampleSidebarSliderValue(
                key: const ValueKey('poly-sidebar-normalize-peak-value'),
                width: PolySampleSidebarLayout.dbValueWidth,
                semanticLabel: 'Normalize peak value',
                value:
                    '${(wavDraft.normalizePeakDb ?? -0.3).toStringAsFixed(1)} dB',
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () async {
                final bytes = await cubit.renderDestructiveWav(region.path);
                if (bytes == null) return;
                final target = await FilePicker.saveFile(
                  dialogTitle: 'Save edited WAV as',
                  fileName: p.basename(region.path),
                  mimeType: 'audio/wav',
                  initialDirectory: state.lastWavExportFolder,
                  bytes: bytes,
                );
                if (target == null) return;
                await cubit.completeDestructiveWavSave(region.path, target);
              },
              child: const Text('Save as...'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text('Overwrite $label?'),
                      content: const Text(
                        'This permanently changes the audio file.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Overwrite'),
                        ),
                      ],
                    );
                  },
                );
                if (confirmed != true) return;
                await cubit.saveDestructiveWav(region.path, region.path, true);
              },
              child: const Text('Overwrite'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FadeRow extends StatelessWidget {
  const _FadeRow({
    required this.label,
    required this.overview,
    required this.frames,
    required this.curve,
    required this.strength,
    required this.onFramesChanged,
    required this.onCurveChanged,
    required this.onStrengthChanged,
  });

  final String label;
  final WavOverview overview;
  final int frames;
  final WavFadeCurve curve;
  final double strength;
  final ValueChanged<int> onFramesChanged;
  final ValueChanged<WavFadeCurve> onCurveChanged;
  final ValueChanged<double> onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    final ms = overview.sampleRate <= 0
        ? 0.0
        : frames / overview.sampleRate * 1000;
    final rowKeySuffix = label.toLowerCase().replaceAll(' ', '-');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          SizedBox(
            key: ValueKey('poly-sidebar-$rowKeySuffix-length-row'),
            height: PolySampleSidebarLayout.rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: PolySampleSidebarLayout.sliderLabelWidth,
                  child: ExcludeSemantics(child: Text('$label length')),
                ),
                Expanded(
                  child: Semantics(
                    label: '$label length',
                    value: '${ms.round()} ms',
                    child: Slider(
                      min: 0,
                      max: 5000,
                      divisions: 100,
                      value: ms.clamp(0, 5000).toDouble(),
                      label: '${ms.round()} ms',
                      semanticFormatterCallback: (value) =>
                          '${value.round()} ms',
                      onChanged: (value) {
                        onFramesChanged(
                          (value / 1000 * overview.sampleRate).round(),
                        );
                      },
                    ),
                  ),
                ),
                PolySampleSidebarSliderValue(
                  key: ValueKey('poly-sidebar-$rowKeySuffix-length-value'),
                  width: PolySampleSidebarLayout.msValueWidth,
                  semanticLabel: '$label length value',
                  value: '${ms.round()} ms',
                ),
              ],
            ),
          ),
          SizedBox(
            height: PolySampleSidebarLayout.rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: PolySampleSidebarLayout.sliderLabelWidth,
                  child: ExcludeSemantics(child: Text('$label curve:')),
                ),
                SizedBox(
                  width: PolySampleSidebarLayout.fadeCurveDropdownWidth,
                  child: DropdownButton<WavFadeCurve>(
                    key: ValueKey('poly-sidebar-$rowKeySuffix-curve-dropdown'),
                    isExpanded: true,
                    value: curve,
                    items: [
                      for (final value in WavFadeCurve.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_curveLabel(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) onCurveChanged(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            key: ValueKey('poly-sidebar-$rowKeySuffix-strength-row'),
            height: PolySampleSidebarLayout.rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: PolySampleSidebarLayout.sliderLabelWidth,
                  child: ExcludeSemantics(child: Text('$label strength')),
                ),
                Expanded(
                  child: Semantics(
                    label: '$label strength',
                    value: strength.toStringAsFixed(2),
                    child: Slider(
                      min: 0,
                      max: 1,
                      divisions: 20,
                      value: strength,
                      label: strength.toStringAsFixed(2),
                      semanticFormatterCallback: (value) =>
                          value.toStringAsFixed(2),
                      onChanged: onStrengthChanged,
                    ),
                  ),
                ),
                PolySampleSidebarSliderValue(
                  key: ValueKey('poly-sidebar-$rowKeySuffix-strength-value'),
                  width: PolySampleSidebarLayout.unitValueWidth,
                  semanticLabel: '$label strength value',
                  value: strength.toStringAsFixed(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.rowKeySuffix,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String rowKeySuffix;
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('poly-sidebar-mapping-$rowKeySuffix-row'),
      height: PolySampleSidebarLayout.rowHeight,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        value: value,
        child: Row(
          children: [
            SizedBox(
              width: PolySampleSidebarLayout.mappingLabelWidth,
              child: ExcludeSemantics(
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
            PolySampleSidebarValueText(
              key: ValueKey('poly-sidebar-mapping-$rowKeySuffix-value'),
              width: PolySampleSidebarLayout.mappingValueWidth,
              value: value,
              semanticLabel: '$label value',
            ),
            const SizedBox(width: PolySampleSidebarLayout.rowGap),
            const Spacer(),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-mapping-$rowKeySuffix-decrease'),
              tooltip: 'Decrease $label',
              onPressed: onMinus,
              icon: Icons.remove,
            ),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-mapping-$rowKeySuffix-increase'),
              tooltip: 'Increase $label',
              onPressed: onPlus,
              icon: Icons.add,
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformLoadingPlaceholder extends StatelessWidget {
  const _WaveformLoadingPlaceholder({
    required this.failed,
    required this.playback,
  });

  final bool failed;
  final PolyAudioPreviewSourcePlayback? playback;

  @override
  Widget build(BuildContext context) {
    final frameCount = math.max(1, (playback?.endFrame ?? 1) + 1);
    final overview = WavOverview(
      sampleRate: math.max(1, playback?.sampleRate ?? 44100),
      frameCount: frameCount,
      peaks: const [],
      zeroCrossings: const [],
    );
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const SizedBox(height: 120, width: double.infinity),
          ),
          PolyWaveformEditor(
            overview: overview,
            mode: PolyWaveformEditorMode.trim,
            startFrame: 0,
            endFrame: frameCount - 1,
            playback: playback,
            onChanged: (_, _) {},
          ),
          failed
              ? const Icon(Icons.error_outline)
              : const Icon(Icons.hourglass_empty),
        ],
      ),
    );
  }
}

class _FrameNudgeRow extends StatelessWidget {
  const _FrameNudgeRow({
    required this.rowKeySuffix,
    required this.label,
    required this.value,
    required this.onNudge,
  });

  final String rowKeySuffix;
  final String label;
  final int value;
  final ValueChanged<int> onNudge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('poly-sidebar-frame-$rowKeySuffix-row'),
      height: PolySampleSidebarLayout.rowHeight,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        value: '$value frames',
        child: Row(
          children: [
            SizedBox(
              width: PolySampleSidebarLayout.frameLabelWidth,
              child: ExcludeSemantics(
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
            PolySampleSidebarValueText(
              key: ValueKey('poly-sidebar-frame-$rowKeySuffix-value'),
              width: PolySampleSidebarLayout.frameValueWidth,
              value: '$value',
              semanticLabel: '$label frame value',
            ),
            const SizedBox(width: PolySampleSidebarLayout.rowGap),
            const Spacer(),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-frame-$rowKeySuffix-minus100'),
              tooltip: 'Decrease $label by 100 frames',
              onPressed: () => onNudge(-100),
              icon: Icons.keyboard_double_arrow_left,
            ),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-frame-$rowKeySuffix-minus1'),
              tooltip: 'Decrease $label by 1 frame',
              onPressed: () => onNudge(-1),
              icon: Icons.remove,
            ),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-frame-$rowKeySuffix-plus1'),
              tooltip: 'Increase $label by 1 frame',
              onPressed: () => onNudge(1),
              icon: Icons.add,
            ),
            PolySampleSidebarIconButton(
              key: ValueKey('poly-sidebar-frame-$rowKeySuffix-plus100'),
              tooltip: 'Increase $label by 100 frames',
              onPressed: () => onNudge(100),
              icon: Icons.keyboard_double_arrow_right,
            ),
          ],
        ),
      ),
    );
  }
}

String _curveLabel(WavFadeCurve curve) {
  return switch (curve) {
    WavFadeCurve.linear => 'Linear',
    WavFadeCurve.equalPower => 'Equal power',
    WavFadeCurve.exponential => 'Exponential',
    WavFadeCurve.sCurve => 'S-curve',
  };
}

bool _isLocalPath(PolyMultisampleBuilderState state, PolySampleRegion region) {
  return !(state.sourceMode == PolySampleSourceMode.hardware &&
      region.path.startsWith('/'));
}

Future<void> _revealFolder(BuildContext context, String path) async {
  try {
    final folder = p.dirname(path);
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [folder]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [folder]);
    } else {
      await Process.run('xdg-open', [folder]);
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open folder: $error')));
  }
}
