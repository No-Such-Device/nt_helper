import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/decent_sampler_converter.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_import_service.dart';
import 'package:nt_helper/ui/poly_multisample/dialogs/poly_decent_import_dialog.dart';
import 'package:nt_helper/ui/poly_multisample/poly_decent_import_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';

void main() {
  testWidgets('shows analysis summary and handling modes', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyDecentImportCubit()..setTestState(_readyState());
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('2 presets, 2 groups, 2 tags'), findsOneWidget);
    expect(find.text('Automatic (recommended)'), findsOneWidget);
    expect(find.text('Map groups by tags'), findsOneWidget);
    expect(find.text('Groups as velocity layers'), findsOneWidget);
    expect(find.text('Groups as manual key ranges'), findsOneWidget);
    expect(find.text('Split groups into separate folders'), findsOneWidget);
    expect(find.text('Import one group only'), findsOneWidget);
    expect(find.text('Import selected tags only'), findsOneWidget);
    expect(find.bySemanticsLabel('Group handling'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('selectedTags mode reveals per-tag range steppers', (
    tester,
  ) async {
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        _readyState().copyWith(
          groupHandling: DecentSamplerGroupHandling.selectedTags,
          selectedTagKeys: {'tag:soft'},
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('soft'), findsOneWidget);
    expect(find.byTooltip('Increase Low'), findsAtLeastNWidgets(1));
  });

  testWidgets('tagMapping exposes per-tag controls', (tester) async {
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        _readyState().copyWith(
          groupHandling: DecentSamplerGroupHandling.tagMapping,
          selectedTagKeys: {'tag:soft'},
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('soft'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Select soft, 2 samples, C4 - D4'),
      findsOneWidget,
    );
    expect(find.byTooltip('Increase Velocity'), findsAtLeastNWidgets(1));
  });

  testWidgets('failure state is announced as live status', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        const PolyDecentImportState(
          status: PolyDecentImportStatus.failure,
          error: 'Import failed.',
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Import failed.'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('import disabled while warnings present', (tester) async {
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(_readyState().copyWith(warnings: ['Ranges overlap']));
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import'),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('cancel disabled while staging import', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        _readyState().copyWith(status: PolyDecentImportStatus.staging),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );

    expect(button.onPressed, isNull);
    expect(
      find.bySemanticsLabel('Importing Decent Sampler source'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('option controls are disabled while staging import', (
    tester,
  ) async {
    final importService = _DelayedImportService();
    final cubit = _TestPolyDecentImportCubit(importService: importService)
      ..setTestState(
        _readyState().copyWith(
          groupHandling: DecentSamplerGroupHandling.selectedTags,
          selectedTagKeys: {'tag:soft'},
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();

    expect(cubit.state.status, PolyDecentImportStatus.staging);
    expect(importService.lastOptions?.selectedTagKeys, ['tag:soft']);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('Preserve XML mapping'));
    await tester.tap(find.text('Preserve XML mapping'));
    await tester.ensureVisible(find.text('soft'));
    await tester.tap(find.text('soft'));
    await tester.ensureVisible(find.byTooltip('Increase Velocity').first);
    await tester.tap(find.byTooltip('Increase Velocity').first);
    await tester.pump();

    expect(cubit.state.preserveXmlMapping, isFalse);
    expect(cubit.state.selectedTagKeys, {'tag:soft'});
    expect(cubit.state.tagVelocityLayers, isEmpty);

    importService.complete();
    await tester.pumpAndSettle();
    expect(find.text('Import Decent Sampler'), findsNothing);
  });

  testWidgets('cancel disabled while analyzing source', (tester) async {
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        const PolyDecentImportState(
          status: PolyDecentImportStatus.analyzing,
          sourcePath: '/tmp/Layered.dspreset',
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pump();

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(button.onPressed, isNull);

    await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
    await tester.pump();

    expect(find.text('Import Decent Sampler'), findsOneWidget);
  });

  testWidgets('selected tag checkbox includes mapping context', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        _readyState().copyWith(
          groupHandling: DecentSamplerGroupHandling.selectedTags,
        ),
      );
    addTearDown(cubit.close);

    await _pumpDialogButton(tester, cubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Select soft, 2 samples, C4 - D4'),
      findsOneWidget,
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('Select soft, 2 samples, C4 - D4'),
    );
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    await tester.ensureVisible(
      find.bySemanticsLabel('Select soft, 2 samples, C4 - D4'),
    );
    await tester.tap(find.bySemanticsLabel('Select soft, 2 samples, C4 - D4'));
    await tester.pumpAndSettle();

    expect(cubit.state.selectedTagKeys, contains('tag:soft'));

    semantics.dispose();
  });

  testWidgets('cancel stops an active Decent preview', (tester) async {
    final fixture = _previewFixture();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        fixture.state.copyWith(
          groupHandling: DecentSamplerGroupHandling.velocityLayers,
        ),
      );
    addTearDown(cubit.close);
    final adapter = _FakePreviewAdapter();
    final previewCubit = PolyMultisampleBuilderCubit(
      previewService: PolyAudioPreviewService(adapter: adapter),
    );
    addTearDown(previewCubit.close);

    await _pumpDialogButton(tester, cubit, previewCubit: previewCubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _startSoftPreview(tester);

    expect(adapter.playedPaths, [fixture.softPreviewPath]);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(adapter.stopCount, 1);
    expect(find.text('Import Decent Sampler'), findsNothing);
  });

  testWidgets('archive source disables Decent preview buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        _readyState(
          sourcePath: '/tmp/Layered.dslibrary',
        ).copyWith(groupHandling: DecentSamplerGroupHandling.velocityLayers),
      );
    addTearDown(cubit.close);
    final previewCubit = PolyMultisampleBuilderCubit(
      previewService: PolyAudioPreviewService(adapter: _FakePreviewAdapter()),
    );
    addTearDown(previewCubit.close);

    await _pumpDialogButton(tester, cubit, previewCubit: previewCubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final disabledPreview = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Preview unavailable: Soft',
    );
    expect(disabledPreview, findsOneWidget);
    expect(tester.widget<IconButton>(disabledPreview).onPressed, isNull);
    expect(find.byTooltip('Preview sample: Soft'), findsNothing);
    expect(find.bySemanticsLabel('Preview unavailable: Soft'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Preview unavailable: Soft'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    semantics.dispose();
  });

  testWidgets('route dismissal stops an active Decent preview', (tester) async {
    final fixture = _previewFixture();
    final cubit = _TestPolyDecentImportCubit()
      ..setTestState(
        fixture.state.copyWith(
          groupHandling: DecentSamplerGroupHandling.velocityLayers,
        ),
      );
    addTearDown(cubit.close);
    final adapter = _FakePreviewAdapter();
    final previewCubit = PolyMultisampleBuilderCubit(
      previewService: PolyAudioPreviewService(adapter: adapter),
    );
    addTearDown(previewCubit.close);

    await _pumpDialogButton(tester, cubit, previewCubit: previewCubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _startSoftPreview(tester);

    await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
    await tester.pumpAndSettle();

    expect(adapter.stopCount, 1);
    expect(find.text('Import Decent Sampler'), findsNothing);
  });

  testWidgets('failed import stops an active Decent preview', (tester) async {
    final fixture = _previewFixture();
    final cubit = _FailingPolyDecentImportCubit()
      ..setTestState(
        fixture.state.copyWith(
          groupHandling: DecentSamplerGroupHandling.velocityLayers,
        ),
      );
    addTearDown(cubit.close);
    final adapter = _FakePreviewAdapter();
    final previewCubit = PolyMultisampleBuilderCubit(
      previewService: PolyAudioPreviewService(adapter: adapter),
    );
    addTearDown(previewCubit.close);

    await _pumpDialogButton(tester, cubit, previewCubit: previewCubit);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _startSoftPreview(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(adapter.stopCount, 1);
    expect(find.text('Import Decent Sampler'), findsOneWidget);
  }, tags: ['regression']);
}

_PreviewFixture _previewFixture() {
  final tempDir = Directory.systemTemp.createTempSync(
    'poly_decent_import_preview_test_',
  );
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final samplesDir = Directory('${tempDir.path}/Samples')..createSync();
  final softSample = File('${samplesDir.path}/soft_c4.wav')
    ..writeAsBytesSync(const []);
  File('${samplesDir.path}/hard_e4.wav').writeAsBytesSync(const []);
  final preset = File('${tempDir.path}/Layered.dspreset')
    ..writeAsStringSync('<DecentSampler/>');
  return _PreviewFixture(
    state: _readyState(
      sourcePath: preset.path,
      softPreviewPath: 'Samples/soft_c4.wav',
      hardPreviewPath: 'Samples/hard_e4.wav',
    ),
    softPreviewPath: softSample.absolute.path,
  );
}

class _PreviewFixture {
  const _PreviewFixture({required this.state, required this.softPreviewPath});

  final PolyDecentImportState state;
  final String softPreviewPath;
}

Future<void> _startSoftPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Preview sample: Soft'));
  await tester.pump();
  await tester.tap(find.byTooltip('Preview sample: Soft'));
  await tester.pump();
}

Future<void> _pumpDialogButton(
  WidgetTester tester,
  PolyDecentImportCubit cubit, {
  PolyMultisampleBuilderCubit? previewCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showPolyDecentImportDialog(
                  context,
                  sourcePath: '/tmp/Layered.dspreset',
                  cubit: cubit,
                  previewCubit: previewCubit,
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

PolyDecentImportState _readyState({
  String sourcePath = '/tmp/Layered.dspreset',
  String softPreviewPath = 'soft_c4.wav',
  String hardPreviewPath = 'hard_e4.wav',
}) {
  return PolyDecentImportState(
    status: PolyDecentImportStatus.ready,
    sourcePath: sourcePath,
    analysis: _analysis(
      softPreviewPath: softPreviewPath,
      hardPreviewPath: hardPreviewPath,
    ),
    groupHandling: DecentSamplerGroupHandling.auto,
    manualGroupRanges: const {
      'group:soft': DecentSamplerTagKeyRange(
        lowMidi: 60,
        rootMidi: 60,
        highMidi: 61,
      ),
      'group:hard': DecentSamplerTagKeyRange(
        lowMidi: 62,
        rootMidi: 62,
        highMidi: 63,
      ),
    },
    tagKeyRanges: const {
      'tag:soft': DecentSamplerTagKeyRange(
        lowMidi: 60,
        rootMidi: 60,
        highMidi: 61,
      ),
      'tag:hard': DecentSamplerTagKeyRange(
        lowMidi: 62,
        rootMidi: 62,
        highMidi: 63,
      ),
    },
    selectedPresetNames: const {'Preset A', 'Preset B'},
  );
}

DecentSamplerImportAnalysis _analysis({
  String softPreviewPath = 'soft_c4.wav',
  String hardPreviewPath = 'hard_e4.wav',
}) {
  return DecentSamplerImportAnalysis(
    presetName: 'Layered',
    presets: [
      DecentSamplerPresetInfo(
        name: 'Preset A',
        groupCount: 1,
        sampleCount: 2,
        tagCount: 1,
      ),
      DecentSamplerPresetInfo(
        name: 'Preset B',
        groupCount: 1,
        sampleCount: 2,
        tagCount: 1,
      ),
    ],
    groups: [
      DecentSamplerGroupInfo(
        key: 'group:soft',
        name: 'Soft',
        xmlSummary: 'Soft',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-64',
        roundRobinSummary: 'No seqPosition',
        examples: ['soft_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
        previewSourcePath: softPreviewPath,
      ),
      DecentSamplerGroupInfo(
        key: 'group:hard',
        name: 'Hard',
        xmlSummary: 'Hard',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'E4-F4',
        noteRange: 'E4 - F4',
        velocitySummary: '65-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['hard_e4.wav'],
        defaultLowMidi: 62,
        defaultRootMidi: 62,
        defaultHighMidi: 63,
        defaultVelocityLayer: 1,
        previewSourcePath: hardPreviewPath,
      ),
    ],
    tags: [
      DecentSamplerTag(
        key: 'tag:soft',
        label: 'soft',
        groupKeys: ['group:soft'],
        sampleCount: 2,
        confidence: 1.0,
        evidence: '',
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-64',
        roundRobinSummary: 'No seqPosition',
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
        previewSourcePath: softPreviewPath,
      ),
      DecentSamplerTag(
        key: 'tag:hard',
        label: 'hard',
        groupKeys: ['group:hard'],
        sampleCount: 2,
        confidence: 1.0,
        evidence: '',
        structureSummary: 'E4-F4',
        noteRange: 'E4 - F4',
        velocitySummary: '65-127',
        roundRobinSummary: 'No seqPosition',
        defaultLowMidi: 62,
        defaultRootMidi: 62,
        defaultHighMidi: 63,
        defaultVelocityLayer: 1,
        previewSourcePath: hardPreviewPath,
      ),
    ],
    hasAmbiguousOverlaps: false,
    structureSummary: '2 presets, 2 groups, 2 tags',
    recommendedGroupHandling: DecentSamplerGroupHandling.auto,
  );
}

class _TestPolyDecentImportCubit extends PolyDecentImportCubit {
  _TestPolyDecentImportCubit({super.importService});

  void setTestState(PolyDecentImportState state) {
    emit(state);
  }
}

class _DelayedImportService extends PolySampleImportService {
  final _completer = Completer<PolyStagedImport>();
  DecentSamplerConvertOptions? lastOptions;

  @override
  Future<PolyStagedImport> stageDecentSource(
    String path, {
    DecentSamplerConvertOptions options = const DecentSamplerConvertOptions(),
    String? outputParentPath,
  }) {
    lastOptions = options;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const PolyStagedImport(
        name: 'Layered',
        sourceLabel: '/tmp/Layered.dspreset',
        regions: [],
      ),
    );
  }
}

class _FailingPolyDecentImportCubit extends _TestPolyDecentImportCubit {
  @override
  Future<void> continueImport() async {
    emit(
      state.copyWith(
        status: PolyDecentImportStatus.failure,
        error: 'Import failed.',
      ),
    );
  }
}

class _FakePreviewAdapter implements PolyAudioPreviewAdapter {
  final playedPaths = <String>[];
  var stopCount = 0;

  @override
  Stream<void> get completed => const Stream.empty();

  @override
  Future<void> play(String path, {required double volume}) async {
    playedPaths.add(path);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}
