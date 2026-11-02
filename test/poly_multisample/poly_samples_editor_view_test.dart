import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_region_math.dart';
import 'package:nt_helper/ui/poly_multisample/poly_samples_editor_view.dart';
import 'package:nt_helper/ui/poly_multisample/poly_samples_landing_view.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_key_map.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_inspector.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_list.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_sample_sidebar_layout.dart';

void main() {
  testWidgets('shows toolbar stats, key map, list and inspector', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(find.text('2 samples'), findsOneWidget);
    expect(find.text('2 mapped'), findsOneWidget);
    expect(find.byType(PolyKeyMap), findsOneWidget);
    expect(find.byType(PolySampleList), findsOneWidget);
    expect(find.byType(PolySampleInspector), findsOneWidget);
    expect(
      tester.getSize(find.byType(PolySampleInspector)).width,
      PolySampleSidebarLayout.panelWidth,
    );
  });

  testWidgets('keyboard note semantics invokes cubit note preview', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    await tester.tap(find.bySemanticsLabel('Preview C4'), warnIfMissed: false);
    await tester.pump();

    expect(cubit.previewedNotes, [60]);
    semantics.dispose();
  });

  testWidgets('unsupported regions remain in the total warning count', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          editedRegions: const [
            PolySampleRegion(
              path: '/tmp/Kick.wav',
              fileName: 'Kick.wav',
              displayName: 'Kick.wav',
            ),
            PolySampleRegion(
              path: '/tmp/readme.txt',
              fileName: 'readme.txt',
              displayName: 'readme.txt',
            ),
          ],
        ),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(find.text('1 mapped'), findsOneWidget);
    expect(find.text('1 warnings'), findsOneWidget);
    expect(find.text('Mapping warnings (1)'), findsOneWidget);
    await tester.tap(find.text('Mapping warnings (1)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unsupported sample: readme.txt has an unsupported file type.'),
      findsOneWidget,
    );
  });

  testWidgets('keyboard map semantics explains note preview affordance', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    final node = tester.getSemantics(
      find.bySemanticsLabel('Keyboard map with 2 mapped samples'),
    );
    expect(
      node.hint,
      'Tap sample ranges to select. Tap piano keys to preview notes.',
    );
    semantics.dispose();
  });

  testWidgets('draft mode shows Save As instead of Apply', (tester) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(_state(sourceMode: PolySampleSourceMode.importDraft));
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(find.text('Save As…'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });

  testWidgets('dirty state enables Apply and Discard', (tester) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          dirty: true,
        ).copyWith(selectedPaths: const {}, clearFocusedPath: true),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    final discard = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Discard all'),
    );

    expect(apply.onPressed, isNotNull);
    expect(discard.onPressed, isNotNull);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('discard with no selection shows confirmation dialog', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          dirty: true,
        ).copyWith(selectedPaths: const {}, clearFocusedPath: true),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);
    await tester.tap(find.widgetWithText(TextButton, 'Discard all'));
    await tester.pumpAndSettle();

    expect(find.text('Discard all?'), findsOneWidget);
    expect(
      find.text('This reverts every sample in the draft.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Discard all'));
    await tester.pumpAndSettle();
    expect(find.text('Discard all?'), findsNothing);
    expect(cubit.clearDraftCount, 0);
    expect(cubit.discardChangesCount, 1);
  });

  testWidgets('Use automatic notes preserves rows and variant lanes', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          dirty: true,
          editedRegions: const [
            PolySampleRegion(
              path: '/tmp/Piano/Piano_C3.wav',
              fileName: 'Piano_C3.wav',
              displayName: 'Piano_C3.wav',
              rootMidi: 48,
              rootName: 'C3',
              switchPoint: 40,
              velocityLayer: 2,
              roundRobin: 3,
            ),
            PolySampleRegion(
              path: '/tmp/Piano/Piano_Unmapped.wav',
              fileName: 'Piano_Unmapped.wav',
              displayName: 'Piano_Unmapped.wav',
            ),
          ],
        ).copyWith(
          selectedPaths: const {'/tmp/Piano/Piano_C3.wav'},
          clearFocusedPath: true,
        ),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);
    await tester.tap(find.widgetWithText(TextButton, 'Use automatic notes'));
    await tester.pumpAndSettle();

    expect(cubit.state.editedRegions, hasLength(2));
    expect(cubit.state.editedRegions.first.rootMidi, isNull);
    expect(cubit.state.editedRegions.first.rootName, isNull);
    expect(cubit.state.editedRegions.first.switchPoint, isNull);
    expect(cubit.state.editedRegions.first.velocityLayer, 2);
    expect(cubit.state.editedRegions.first.roundRobin, 3);
    expect(cubit.removeSelectedRegionsCount, 0);
    expect(cubit.clearDraftCount, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.bySemanticsLabel('Keyboard map with 2 mapped samples'),
      findsOneWidget,
    );
  });

  testWidgets('waveform drafts explain disabled primary save action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          sourceMode: PolySampleSourceMode.customDraft,
          wavEditDrafts: const {
            '/tmp/Piano/Piano_C3.wav': PolyWaveformDraft(trimStart: 10),
          },
        ),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    final saveAs = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save As…'),
    );
    expect(saveAs.onPressed, isNull);
    expect(
      find.text(
        'Save or discard waveform edits before applying or saving this sample set.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Save or discard waveform edits before applying or saving this sample set.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('toolbar Upload button invokes callback for local sample sets', (
    tester,
  ) async {
    var uploadCount = 0;
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit, onUpload: () => uploadCount++);

    await tester.tap(find.text('Upload'));
    await tester.pump();

    expect(uploadCount, 1);
  });

  testWidgets('toolbar Upload button is disabled for hardware sample sets', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(_state(sourceMode: PolySampleSourceMode.hardware));
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    final upload = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Upload'),
    );
    expect(upload.onPressed, isNull);
  });

  testWidgets('toolbar shows upload progress as a live status', (tester) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(
          activeOperation: PolyMultisampleActiveOperation.uploading,
          progressText: 'Uploading fake sample...',
        ),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(find.text('Uploading fake sample...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'warnings disclosure is collapsed by default when warnings exist',
    (tester) async {
      final cubit = _TestPolyMultisampleBuilderCubit()
        ..setTestState(
          _state(warnings: const ['Missing root note', 'Overlapping range']),
        );
      addTearDown(cubit.close);

      await _pumpEditor(tester, cubit);

      expect(find.text('Warnings (2)'), findsOneWidget);
      expect(find.text('Missing root note'), findsNothing);
      expect(
        find.byKey(const ValueKey('poly-samples-warnings-scroll-box')),
        findsNothing,
      );
    },
  );

  testWidgets('warnings disclosure header shows warning count', (tester) async {
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(
        _state(warnings: const ['Missing source sample: Piano_C3.wav']),
      );
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(find.text('Warnings (1)'), findsOneWidget);
    expect(find.text('1 warning available. Expand to review.'), findsWidgets);
  });

  testWidgets(
    'mapping warnings panel renders separately from import warnings',
    (tester) async {
      final cubit = _TestPolyMultisampleBuilderCubit()
        ..setTestState(
          _state(
            warnings: const ['Import warning'],
            mappingWarnings: const [
              'Mapping impossible: Piano_C3.wav root C3 is outside C4–C5.',
            ],
          ),
        );
      addTearDown(cubit.close);

      await _pumpEditor(tester, cubit);

      expect(find.text('Warnings (1)'), findsOneWidget);
      expect(find.text('Mapping warnings (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanding warnings reveals a bounded scrollable list', (
    tester,
  ) async {
    final warnings = List<String>.generate(
      12,
      (index) => 'Warning ${index + 1}',
    );
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(_state(warnings: warnings));
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);
    await tester.tap(find.text('Warnings (12)'));
    await tester.pumpAndSettle();

    final scrollBox = find.byKey(
      const ValueKey('poly-samples-warnings-scroll-box'),
    );
    expect(scrollBox, findsOneWidget);
    expect(
      find.byKey(const PageStorageKey<String>('poly-samples-warnings-list')),
      findsOneWidget,
    );
    expect(tester.getSize(scrollBox).height, lessThanOrEqualTo(200));
    expect(find.text('Warning 1'), findsOneWidget);
    await tester.drag(scrollBox, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.text('Warning 12'), findsOneWidget);
  });

  testWidgets('many expanded warnings stay bounded without layout overflow', (
    tester,
  ) async {
    final warnings = List<String>.generate(
      60,
      (index) => 'Overflow warning ${index + 1}',
    );
    final cubit = _TestPolyMultisampleBuilderCubit()
      ..setTestState(_state(warnings: warnings));
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);
    await tester.tap(find.text('Warnings (60)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('poly-samples-warnings-scroll-box')),
          )
          .height,
      lessThanOrEqualTo(200),
    );
    expect(find.byType(PolySampleList), findsOneWidget);
    expect(find.byType(PolySampleInspector), findsOneWidget);
  }, tags: ['regression']);

  testWidgets('toolbar discard label is selection scoped', (tester) async {
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    expect(
      find.widgetWithText(TextButton, 'Use automatic notes'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Discard all'), findsNothing);
  });

  testWidgets('inline row stepper focuses row and updates inspector', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    await tester.tap(find.byTooltip('Increase Root for Piano_Unmapped.wav'));
    await tester.pump();

    expect(cubit.state.focusedPath, '/tmp/Piano/Piano_Unmapped.wav');
    expect(cubit.state.selectedPaths, {'/tmp/Piano/Piano_Unmapped.wav'});
    final region = cubit.state.editedRegions.singleWhere(
      (region) => region.path == '/tmp/Piano/Piano_Unmapped.wav',
    );
    expect(region.rootMidi, 49);
    expect(region.rootName, 'C#3');
    expect(find.text('Editing Piano_Unmapped.wav'), findsOneWidget);
  });

  testWidgets('inline Low stepper writes a Disting switch point', (
    tester,
  ) async {
    final cubit = _TestPolyMultisampleBuilderCubit()..setTestState(_state());
    addTearDown(cubit.close);

    await _pumpEditor(tester, cubit);

    await tester.tap(find.byTooltip('Increase Low for Piano_Unmapped.wav'));
    await tester.pump();

    final region = cubit.state.editedRegions.singleWhere(
      (region) => region.path == '/tmp/Piano/Piano_Unmapped.wav',
    );
    expect(region.switchPoint, 1);
    expect(
      cubit.state.mappingResolution.mappingForRegion(region)!.switchIsAutomatic,
      isFalse,
    );
  });

  testWidgets('landing shows three source cards and empty draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolySamplesLandingView(
            state: const PolyMultisampleBuilderState(),
            onOpenHardware: () {},
            onOpenLocal: () {},
            onImport: () {},
            onOpenRecent: null,
            onStartEmptyDraft: () {},
          ),
        ),
      ),
    );

    expect(find.text('NT Hardware'), findsOneWidget);
    expect(find.text('Local Folder'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Start empty draft'), findsOneWidget);
    expect(
      find.text('Build or edit a Disting NT multisample folder'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  PolyMultisampleBuilderCubit cubit, {
  VoidCallback? onUpload,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<PolyMultisampleBuilderCubit>.value(
          value: cubit,
          child: SizedBox(
            width: 1200,
            height: 800,
            child:
                BlocBuilder<
                  PolyMultisampleBuilderCubit,
                  PolyMultisampleBuilderState
                >(
                  builder: (context, state) {
                    return PolySamplesEditorView(
                      state: state,
                      manager: null,
                      onAddFiles: () {},
                      onAddFolder: () {},
                      onSaveAs: () {},
                      onUpload: onUpload ?? () {},
                      onBackToSources: () {},
                    );
                  },
                ),
          ),
        ),
      ),
    ),
  );
}

PolyMultisampleBuilderState _state({
  PolySampleSourceMode sourceMode = PolySampleSourceMode.local,
  bool dirty = false,
  Map<String, PolyWaveformDraft> wavEditDrafts = const {},
  PolyMultisampleActiveOperation activeOperation =
      PolyMultisampleActiveOperation.none,
  String? progressText,
  List<String> warnings = const [],
  List<String> mappingWarnings = const [],
  Set<String>? selectedPaths,
  String? focusedPath,
  List<PolySampleRegion>? editedRegions,
}) {
  final currentRegions = editedRegions ?? _regions;
  final mappingResolution = const PolySampleMappingResolver().resolve(
    currentRegions,
  );
  final baseline = dirty
      ? const [
          PolySampleRegion(
            path: '/tmp/Piano/Piano_C3.wav',
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 47,
            rootName: 'B2',
          ),
          PolySampleRegion(
            path: '/tmp/Piano/Piano_Unmapped.wav',
            fileName: 'Piano_Unmapped.wav',
            displayName: 'Piano_Unmapped.wav',
          ),
        ]
      : currentRegions;
  return PolyMultisampleBuilderState(
    sourceMode: sourceMode,
    status: PolyMultisampleLoadStatus.ready,
    activeOperation: activeOperation,
    progressText: progressText,
    currentInstrument: PolySampleInstrument(
      name: 'Piano',
      sourcePath: '/tmp/Piano',
      regions: currentRegions,
    ),
    baselineRegions: baseline,
    editedRegions: currentRegions,
    mappingResolution: mappingResolution,
    selectedPaths: selectedPaths ?? const {'/tmp/Piano/Piano_C3.wav'},
    focusedPath: focusedPath ?? '/tmp/Piano/Piano_C3.wav',
    wavEditDrafts: wavEditDrafts,
    warnings: warnings,
    mappingWarnings: mappingWarnings,
  );
}

const _regions = [
  PolySampleRegion(
    path: '/tmp/Piano/Piano_C3.wav',
    fileName: 'Piano_C3.wav',
    displayName: 'Piano_C3.wav',
    rootMidi: 48,
    rootName: 'C3',
  ),
  PolySampleRegion(
    path: '/tmp/Piano/Piano_Unmapped.wav',
    fileName: 'Piano_Unmapped.wav',
    displayName: 'Piano_Unmapped.wav',
  ),
];

class _TestPolyMultisampleBuilderCubit extends PolyMultisampleBuilderCubit {
  _TestPolyMultisampleBuilderCubit()
    : super(
        previewService: PolyAudioPreviewService(adapter: _FakePreviewAdapter()),
      );

  final previewedNotes = <int>[];
  var removeSelectedRegionsCount = 0;
  var discardChangesCount = 0;
  var clearDraftCount = 0;

  @override
  Future<void> playKeyboardNotePreview(int midi) async {
    previewedNotes.add(midi);
  }

  @override
  Future<void> startKeyboardNotePreview(int midi) async {
    previewedNotes.add(midi);
  }

  @override
  void removeSelectedRegions() {
    removeSelectedRegionsCount++;
  }

  @override
  void discardChanges() {
    discardChangesCount++;
  }

  @override
  void clearDraft() {
    clearDraftCount++;
  }

  void setTestState(PolyMultisampleBuilderState state) {
    final mappingResolution = const PolySampleMappingResolver().resolve(
      state.editedRegions,
    );
    emit(
      state.copyWith(
        mappingResolution: mappingResolution,
        mappingWarnings: mappingWarningMessages(
          state.editedRegions,
          mappingResolution,
        ),
      ),
    );
  }
}

class _FakePreviewAdapter implements PolyAudioPreviewAdapter {
  @override
  Stream<void> get completed => const Stream.empty();

  @override
  Future<void> play(String path, {required double volume}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
