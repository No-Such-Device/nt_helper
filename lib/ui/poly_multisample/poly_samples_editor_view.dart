import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_region_math.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_key_map.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_inspector.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_list.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_sidebar_layout.dart';

class PolySamplesEditorView extends StatelessWidget {
  const PolySamplesEditorView({
    super.key,
    required this.state,
    required this.manager,
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onSaveAs,
    required this.onUpload,
    required this.onBackToSources,
  });

  final PolyMultisampleBuilderState state;
  final IDistingMidiManager? manager;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback onSaveAs;
  final VoidCallback onUpload;
  final VoidCallback onBackToSources;

  @override
  Widget build(BuildContext context) {
    final instrument = state.currentInstrument;
    if (instrument == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          state: state,
          instrument: instrument,
          manager: manager,
          onAddFiles: onAddFiles,
          onAddFolder: onAddFolder,
          onSaveAs: onSaveAs,
          onUpload: onUpload,
          onBackToSources: onBackToSources,
        ),
        if (state.warnings.isNotEmpty)
          _WarningPanel(
            title: 'Warnings',
            messages: state.warnings,
            storageKey: const PageStorageKey<String>(
              'poly-samples-import-warnings-tile',
            ),
          ),
        if (state.mappingWarnings.isNotEmpty)
          _WarningPanel(
            title: 'Mapping warnings',
            messages: state.mappingWarnings,
            storageKey: const PageStorageKey<String>(
              'poly-samples-mapping-warnings-tile',
            ),
          ),
        Expanded(
          child: _EditorBody(state: state, manager: manager),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.instrument,
    required this.manager,
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onSaveAs,
    required this.onUpload,
    required this.onBackToSources,
  });

  final PolyMultisampleBuilderState state;
  final PolySampleInstrument instrument;
  final IDistingMidiManager? manager;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback onSaveAs;
  final VoidCallback onUpload;
  final VoidCallback onBackToSources;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PolyMultisampleBuilderCubit>();
    final applying =
        state.activeOperation == PolyMultisampleActiveOperation.applying;
    final saving =
        state.activeOperation == PolyMultisampleActiveOperation.saving;
    final uploading =
        state.activeOperation == PolyMultisampleActiveOperation.uploading;
    final canUpload =
        state.sourceMode != PolySampleSourceMode.hardware &&
        state.editedRegions.isNotEmpty &&
        !state.hasWaveformDrafts &&
        state.activeOperation != PolyMultisampleActiveOperation.uploading &&
        state.activeOperation != PolyMultisampleActiveOperation.applying &&
        state.activeOperation != PolyMultisampleActiveOperation.saving;
    final draftMode =
        state.sourceMode == PolySampleSourceMode.importDraft ||
        state.sourceMode == PolySampleSourceMode.customDraft;
    final canSaveMappingChanges =
        !state.hasWaveformDrafts && state.hasRegionChanges;
    final hasSelection = state.selectedPaths.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: 'Back to sample sources',
                child: OutlinedButton.icon(
                  onPressed: onBackToSources,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Sources'),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  instrument.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${instrument.regions.length} samples'),
              Text('${state.mappingResolution.mappedCount} mapped'),
              if (state.mappingWarnings.isNotEmpty)
                Text('${state.mappingWarnings.length} warnings'),
              if (state.isDirty) const Chip(label: Text('Unsaved changes')),
              FilledButton.tonalIcon(
                onPressed: canUpload ? onUpload : null,
                icon: uploading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
              if (draftMode)
                FilledButton.icon(
                  onPressed:
                      state.editedRegions.isNotEmpty &&
                          !state.hasWaveformDrafts &&
                          !saving
                      ? onSaveAs
                      : null,
                  icon: const Icon(Icons.save_as),
                  label: const Text('Save As…'),
                )
              else
                FilledButton.icon(
                  onPressed: canSaveMappingChanges && !applying
                      ? () => cubit.applyChanges(manager)
                      : null,
                  icon: applying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              Builder(
                builder: (context) {
                  final destructiveLabel = hasSelection
                      ? 'Use automatic notes'
                      : 'Discard all';
                  final canUseDestructiveAction =
                      hasSelection || state.editedRegions.isNotEmpty;
                  return Tooltip(
                    message: destructiveLabel,
                    child: Semantics(
                      label: destructiveLabel,
                      button: true,
                      child: TextButton.icon(
                        onPressed: canUseDestructiveAction
                            ? () async {
                                if (hasSelection) {
                                  cubit.resetSelectedToAutomaticNotes();
                                  return;
                                }
                                final discardAll = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Discard all?'),
                                    content: const Text(
                                      'This reverts every sample in the draft.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(true),
                                        child: const Text('Discard all'),
                                      ),
                                    ],
                                  ),
                                );
                                if (discardAll == true) {
                                  cubit.discardChanges();
                                }
                              }
                            : null,
                        icon: Icon(
                          hasSelection ? Icons.auto_fix_high : Icons.restore,
                        ),
                        label: Text(destructiveLabel),
                      ),
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                tooltip: 'More sample actions',
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  switch (value) {
                    case 'add_files':
                      onAddFiles();
                      break;
                    case 'add_folder':
                      onAddFolder();
                      break;
                    case 'remove_selected':
                      cubit.removeSelectedRegions();
                      break;
                    case 'clear_all':
                      cubit.clearDraft();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add_files',
                    child: Text('Add files…'),
                  ),
                  const PopupMenuItem(
                    value: 'add_folder',
                    child: Text('Add folder…'),
                  ),
                  PopupMenuItem(
                    value: 'remove_selected',
                    enabled: state.selectedPaths.isNotEmpty,
                    child: const Text('Remove selected samples'),
                  ),
                  PopupMenuItem(
                    value: 'clear_all',
                    enabled: state.editedRegions.isNotEmpty,
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ],
          ),
          if (uploading) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(state.progressText ?? 'Uploading sample folder...'),
            ),
          ],
          if (state.hasWaveformDrafts) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                'Save or discard waveform edits before applying or saving this sample set.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.state, required this.manager});

  final PolyMultisampleBuilderState state;
  final IDistingMidiManager? manager;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PolyMultisampleBuilderCubit>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final selected = selectedRegionFor(state);
        final keyMap = PolyKeyMap(
          regions: state.editedRegions,
          mappingResolution: state.mappingResolution,
          selectedPath: selected?.path,
          playedMidiNote: state.previewState.playingMidiNote,
          onSelect: (region) => cubit.selectRegion(
            region.path,
            PolyRegionSelectionMode.replace,
            manager: manager,
          ),
          onPreviewNote: cubit.playKeyboardNotePreview,
          onPreviewNoteStart: cubit.startKeyboardNotePreview,
          onPreviewNoteEnd: cubit.stopKeyboardNotePreview,
        );
        final sampleList = PolySampleList(
          regions: state.editedRegions,
          mappingResolution: state.mappingResolution,
          selectedPaths: state.selectedPaths,
          focusedPath: state.focusedPath,
          previewVisiblePath: state.previewState.visiblePath,
          onSelect: (path, mode) =>
              cubit.selectRegion(path, mode, manager: manager),
          onPreview: (path) => cubit.playOrStopPreview(path, manager: manager),
          onUpdateRoot: (path, midi) =>
              cubit.updateRoot(path, midi, manager: manager, focusRegion: true),
          onUpdateSwitchPoint: (path, midi) => cubit.updateSwitchPoint(
            path,
            midi,
            manager: manager,
            focusRegion: true,
          ),
          onUpdateVelocity: (path, layer) => cubit.updateVelocity(
            path,
            layer,
            manager: manager,
            focusRegion: true,
          ),
          onUpdateRoundRobin: (path, lane) => cubit.updateRoundRobin(
            path,
            lane,
            manager: manager,
            focusRegion: true,
          ),
        );
        final inspector = PolySampleInspector(state: state, manager: manager);
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    keyMap,
                    Expanded(child: sampleList),
                  ],
                ),
              ),
              SizedBox(
                width: PolySampleSidebarLayout.panelWidth,
                child: inspector,
              ),
            ],
          );
        }
        return Column(
          children: [
            PolyKeyMap(
              height: 140,
              regions: state.editedRegions,
              mappingResolution: state.mappingResolution,
              selectedPath: selected?.path,
              playedMidiNote: state.previewState.playingMidiNote,
              onSelect: (region) => cubit.selectRegion(
                region.path,
                PolyRegionSelectionMode.replace,
                manager: manager,
              ),
              onPreviewNote: cubit.playKeyboardNotePreview,
              onPreviewNoteStart: cubit.startKeyboardNotePreview,
              onPreviewNoteEnd: cubit.stopKeyboardNotePreview,
            ),
            Expanded(flex: 3, child: sampleList),
            const Divider(height: 1),
            Expanded(flex: 2, child: inspector),
          ],
        );
      },
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({
    required this.title,
    required this.messages,
    required this.storageKey,
  });

  static const double _maxWarningListHeight = 200;

  final String title;
  final List<String> messages;
  final PageStorageKey<String> storageKey;

  @override
  Widget build(BuildContext context) {
    final warningCount = messages.length;
    final headerText = '$title ($warningCount)';
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: storageKey,
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              leading: const Icon(Icons.warning_amber),
              title: Semantics(
                header: true,
                child: Text(
                  headerText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              subtitle: Text(
                warningCount == 1
                    ? '1 warning available. Expand to review.'
                    : '$warningCount warnings available. Expand to review.',
              ),
              children: [
                Semantics(
                  label: warningCount == 1
                      ? 'Warning messages, 1 total'
                      : 'Warning messages, $warningCount total',
                  container: true,
                  explicitChildNodes: true,
                  child: ConstrainedBox(
                    key: const ValueKey('poly-samples-warnings-scroll-box'),
                    constraints: const BoxConstraints(
                      maxHeight: _maxWarningListHeight,
                    ),
                    child: Scrollbar(
                      child: ListView.separated(
                        key: const PageStorageKey<String>(
                          'poly-samples-warnings-list',
                        ),
                        primary: false,
                        shrinkWrap: true,
                        itemCount: messages.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) => Text(messages[index]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
