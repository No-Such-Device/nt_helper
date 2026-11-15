import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_sample_import_service.dart';
import 'package:nt_helper/ui/poly_multisample/poly_loose_wav_import_cubit.dart';
import 'package:path/path.dart' as p;

Future<PolyStagedImport?> showPolyLooseWavImportDialog(
  BuildContext context, {
  required List<String> paths,
  PolySampleImportService? importService,
}) {
  return showDialog<PolyStagedImport>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return BlocProvider(
        create: (_) =>
            PolyLooseWavImportCubit(importService: importService)
              ..setFiles(paths),
        child: const _PolyLooseWavImportDialog(),
      );
    },
  );
}

class _PolyLooseWavImportDialog extends StatelessWidget {
  const _PolyLooseWavImportDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocBuilder<PolyLooseWavImportCubit, PolyLooseWavImportState>(
      builder: (context, state) {
        final cubit = context.read<PolyLooseWavImportCubit>();
        final staging = state.status == PolyLooseWavImportStatus.staging;
        return PopScope(
          canPop: !staging,
          child: AlertDialog(
            title: const Text('Import WAV files'),
            content: SizedBox(
              width: 520,
              height: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (staging) ...[
                      Semantics(
                        container: true,
                        liveRegion: true,
                        label: 'Importing WAV files',
                        child: const ExcludeSemantics(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Importing WAV files...'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        TextButton(
                          onPressed: staging ? null : cubit.selectAll,
                          child: const Text('All'),
                        ),
                        TextButton(
                          onPressed: staging ? null : cubit.clearSelection,
                          child: const Text('None'),
                        ),
                      ],
                    ),
                    for (final path in state.paths)
                      CheckboxListTile(
                        dense: true,
                        title: Text(p.basename(path)),
                        subtitle: Text(p.dirname(path)),
                        value: state.selectedPaths.contains(path),
                        onChanged: staging
                            ? null
                            : (_) => cubit.toggleSelection(path),
                      ),
                    const SizedBox(height: 8),
                    RadioGroup<PolyLooseWavMappingMode>(
                      groupValue: state.mappingOptions.mode,
                      onChanged: (mode) {
                        if (staging || mode == null) return;
                        cubit.setMappingOptions(
                          PolyLooseWavMappingOptions(
                            mode: mode,
                            startMidi: state.mappingOptions.startMidi,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final mode in PolyLooseWavMappingMode.values)
                            RadioListTile<PolyLooseWavMappingMode>(
                              dense: true,
                              value: mode,
                              title: Text(_mappingModeLabel(mode)),
                            ),
                        ],
                      ),
                    ),
                    if (_showsStartNote(state.mappingOptions.mode))
                      _StartNoteRow(
                        options: state.mappingOptions,
                        enabled: !staging,
                      ),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          label: 'Loose WAV import failed: ${state.error!}',
                          liveRegion: true,
                          child: ExcludeSemantics(
                            child: Text(
                              state.error!,
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: staging ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: staging || !state.canContinue
                    ? null
                    : () async {
                        await cubit.continueImport();
                        if (!context.mounted) return;
                        if (cubit.state.status ==
                            PolyLooseWavImportStatus.completed) {
                          Navigator.of(context).pop(cubit.state.stagedImport);
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

class _StartNoteRow extends StatelessWidget {
  const _StartNoteRow({required this.options, required this.enabled});

  final PolyLooseWavMappingOptions options;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PolyLooseWavImportCubit>();
    return Row(
      children: [
        Text(
          'Start note: ${PolyMultisampleParser.midiToNoteName(options.startMidi)}',
        ),
        IconButton(
          tooltip: 'Decrease start note',
          onPressed: enabled
              ? () => cubit.setMappingOptions(
                  PolyLooseWavMappingOptions(
                    mode: options.mode,
                    startMidi: (options.startMidi - 1).clamp(0, 127).toInt(),
                  ),
                )
              : null,
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'Increase start note',
          onPressed: enabled
              ? () => cubit.setMappingOptions(
                  PolyLooseWavMappingOptions(
                    mode: options.mode,
                    startMidi: (options.startMidi + 1).clamp(0, 127).toInt(),
                  ),
                )
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

String _mappingModeLabel(PolyLooseWavMappingMode mode) {
  return switch (mode) {
    PolyLooseWavMappingMode.preserve => 'Use note names from file names',
    PolyLooseWavMappingMode.automaticNotes =>
      'Use Disting automatic notes from C3',
    PolyLooseWavMappingMode.chromaticSpread =>
      'Spread chromatically from start note',
    PolyLooseWavMappingMode.roundRobinStack =>
      'Stack as round robins on one note',
    PolyLooseWavMappingMode.velocityLayers =>
      'Stack as velocity layers on one note',
  };
}

bool _showsStartNote(PolyLooseWavMappingMode mode) {
  return switch (mode) {
    PolyLooseWavMappingMode.preserve ||
    PolyLooseWavMappingMode.automaticNotes => false,
    PolyLooseWavMappingMode.chromaticSpread ||
    PolyLooseWavMappingMode.roundRobinStack ||
    PolyLooseWavMappingMode.velocityLayers => true,
  };
}
