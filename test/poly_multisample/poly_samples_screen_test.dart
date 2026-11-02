import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_samples_screen.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  group('PolySamplesView', () {
    late MockDistingCubit distingCubit;

    setUp(() {
      distingCubit = MockDistingCubit();
      when(() => distingCubit.disting()).thenReturn(null);
    });

    testWidgets('does not re-announce stale success when clearing an error', (
      tester,
    ) async {
      final accessibilityMessages = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            Object? message,
          ) async {
            accessibilityMessages.add(message);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            );
      });
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);

      await _pumpView(tester, cubit, distingCubit);

      cubit.setTestState(
        const PolyMultisampleBuilderState(
          status: PolyMultisampleLoadStatus.ready,
          effect: 'Saved custom sample draft.',
          effectId: 1,
        ),
      );
      await tester.pump();
      cubit.setTestState(
        const PolyMultisampleBuilderState(
          status: PolyMultisampleLoadStatus.failure,
          effect: 'Saved custom sample draft.',
          effectId: 1,
          error: 'Apply failed.',
        ),
      );
      await tester.pump();
      cubit.setTestState(
        const PolyMultisampleBuilderState(
          status: PolyMultisampleLoadStatus.loading,
          effect: 'Saved custom sample draft.',
          effectId: 1,
        ),
      );
      await tester.pump();

      final payload = accessibilityMessages.map((m) => m.toString()).join('\n');
      expect(payload, contains('Saved custom sample draft.'));
      expect(payload, contains('Apply failed.'));
      expect(
        RegExp('Saved custom sample draft.').allMatches(payload),
        hasLength(1),
      );
    }, tags: ['regression']);

    testWidgets('hardware empty state can return to sample sources', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        const PolyMultisampleBuilderState(
          sourceMode: PolySampleSourceMode.hardware,
          status: PolyMultisampleLoadStatus.ready,
          hardwareFolders: [],
        ),
      );

      await _pumpView(tester, cubit, distingCubit);

      expect(find.text('No sample folders found on /samples.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('No sample folders found on /samples.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();

      expect(
        find.text('Build or edit a Disting NT multisample folder'),
        findsOneWidget,
      );
      expect(cubit.state.sourceMode, PolySampleSourceMode.none);
      semantics.dispose();
    });

    testWidgets('hardware folder list back returns to source cards', (
      tester,
    ) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        const PolyMultisampleBuilderState(
          sourceMode: PolySampleSourceMode.hardware,
          status: PolyMultisampleLoadStatus.ready,
          hardwareFolders: ['/samples/Piano'],
        ),
      );

      await _pumpView(tester, cubit, distingCubit);

      expect(find.text('/samples/Piano'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();

      expect(
        find.text('Build or edit a Disting NT multisample folder'),
        findsOneWidget,
      );
      expect(cubit.state.hardwareFolders, isEmpty);
      expect(cubit.state.sourceMode, PolySampleSourceMode.none);
    });

    testWidgets('shows landing source cards', (tester) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);

      await _pumpView(tester, cubit, distingCubit);

      expect(find.text('Samples'), findsOneWidget);
      expect(find.text('NT Hardware'), findsOneWidget);
      expect(find.text('Local Folder'), findsOneWidget);
      expect(find.text('Import Files'), findsOneWidget);
    });

    testWidgets('shows a keyboard editor with a working back button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(_pianoState());

      await _pumpView(tester, cubit, distingCubit);

      expect(
        find.bySemanticsLabel('Keyboard map with 1 mapped samples'),
        findsOneWidget,
      );
      final rootRow = find.byKey(
        const ValueKey('poly-sidebar-mapping-root-row'),
      );
      expect(
        find.descendant(of: rootRow, matching: find.text('Root')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rootRow, matching: find.text('C3')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();

      expect(
        find.text('Build or edit a Disting NT multisample folder'),
        findsOneWidget,
      );
      expect(cubit.state.currentInstrument, isNull);
      semantics.dispose();
    });

    testWidgets('dirty editor back asks before returning to sources', (
      tester,
    ) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(_pianoState(dirty: true));

      await _pumpView(tester, cubit, distingCubit);

      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(cubit.state.currentInstrument, isNotNull);
      expect(find.text('Samples'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(cubit.state.currentInstrument, isNull);
      expect(
        find.text('Build or edit a Disting NT multisample folder'),
        findsOneWidget,
      );
    });

    testWidgets('waveform drafts ask before returning to sources', (
      tester,
    ) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        _pianoState().copyWith(
          wavEditDrafts: const {
            '/tmp/Piano/Piano_C3.wav': PolyWaveformDraft(trimStart: 10),
          },
        ),
      );

      await _pumpView(tester, cubit, distingCubit);

      await tester.tap(find.byTooltip('Back to sample sources'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(cubit.state.currentInstrument, isNotNull);
    });

    testWidgets('pop is guarded while dirty', (tester) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(_pianoState(dirty: true));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) {
                        return BlocProvider<PolyMultisampleBuilderCubit>.value(
                          value: cubit,
                          child: PolySamplesView(distingCubit: distingCubit),
                        );
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Samples'), findsOneWidget);

      await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Samples'), findsNothing);
    });

    testWidgets('pop discard exits from a non-dirty import draft', (
      tester,
    ) async {
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        _pianoState().copyWith(sourceMode: PolySampleSourceMode.importDraft),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) {
                        return BlocProvider<PolyMultisampleBuilderCubit>.value(
                          value: cubit,
                          child: PolySamplesView(distingCubit: distingCubit),
                        );
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Samples'), findsNothing);
    });

    testWidgets(
      'upload button opens path dialog with SysEx disabled when disconnected',
      (tester) async {
        final cubit = _TestPolyMultisampleBuilderCubit();
        addTearDown(cubit.close);
        cubit.setTestState(_pianoState());

        await _pumpView(tester, cubit, distingCubit);
        await tester.tap(find.text('Upload'));
        await tester.pumpAndSettle();

        expect(find.text('Upload sample folder'), findsOneWidget);
        expect(find.text('Mounted SD-card folder'), findsOneWidget);
        expect(
          find.text('Connect to Disting NT to use SysEx upload.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('save as can create a new output folder', (tester) async {
      final tempRoot = Directory.systemTemp.createTempSync(
        'poly_samples_save_as_test_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        _pianoState().copyWith(sourceMode: PolySampleSourceMode.customDraft),
      );

      await _pumpView(tester, cubit, distingCubit);
      await tester.tap(find.text('Save As…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Parent folder'),
        tempRoot.path,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New or existing folder name'),
        'CreatedSamples',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final expectedPath = '${tempRoot.path}/CreatedSamples';
      expect(Directory(expectedPath).existsSync(), isTrue);
      expect(cubit.savedCustomDraftPath, expectedPath);
    });

    testWidgets('save as defaults local folder parent to sibling folder', (
      tester,
    ) async {
      final tempRoot = Directory.systemTemp.createTempSync(
        'poly_samples_save_as_parent_test_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });
      final sourceFolder = Directory('${tempRoot.path}/Piano')
        ..createSync(recursive: true);
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        _pianoState().copyWith(
          sourceMode: PolySampleSourceMode.customDraft,
          lastLocalFolder: sourceFolder.path,
        ),
      );

      await _pumpView(tester, cubit, distingCubit);
      await tester.tap(find.text('Save As…'));
      await tester.pumpAndSettle();

      final parentField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Parent folder'),
      );
      expect(parentField.controller!.text, tempRoot.path);
    });

    testWidgets('save as shows folder creation errors inline', (tester) async {
      final semantics = tester.ensureSemantics();
      final tempRoot = Directory.systemTemp.createTempSync(
        'poly_samples_save_as_error_test_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });
      try {
        File('${tempRoot.path}/ExistingFile').writeAsStringSync('not a folder');
        final cubit = _TestPolyMultisampleBuilderCubit();
        addTearDown(cubit.close);
        cubit.setTestState(
          _pianoState().copyWith(sourceMode: PolySampleSourceMode.customDraft),
        );

        await _pumpView(tester, cubit, distingCubit);
        await tester.tap(find.text('Save As…'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Parent folder'),
          tempRoot.path,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'New or existing folder name'),
          'ExistingFile',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Could not create folder:'),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.bySemanticsLabel(RegExp(r'Folder creation failed: .*')),
          findsOneWidget,
        );
        expect(find.text('Save samples as folder'), findsOneWidget);
        expect(cubit.savedCustomDraftPath, isNull);
      } finally {
        semantics.dispose();
      }
    }, tags: ['regression']);

    testWidgets('save as rejects relative folder names', (tester) async {
      final tempRoot = Directory.systemTemp.createTempSync(
        'poly_samples_save_as_relative_test_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });
      final cubit = _TestPolyMultisampleBuilderCubit();
      addTearDown(cubit.close);
      cubit.setTestState(
        _pianoState().copyWith(sourceMode: PolySampleSourceMode.customDraft),
      );

      await _pumpView(tester, cubit, distingCubit);
      await tester.tap(find.text('Save As…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Parent folder'),
        tempRoot.path,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New or existing folder name'),
        '..',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a folder name, not a relative path.'),
        findsOneWidget,
      );
      expect(cubit.savedCustomDraftPath, isNull);
    });
  });
}

Future<void> _pumpView(
  WidgetTester tester,
  PolyMultisampleBuilderCubit cubit,
  DistingCubit distingCubit,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<PolyMultisampleBuilderCubit>.value(
        value: cubit,
        child: PolySamplesView(distingCubit: distingCubit),
      ),
    ),
  );
}

PolyMultisampleBuilderState _pianoState({bool dirty = false}) {
  final baseline = dirty
      ? const [
          PolySampleRegion(
            path: '/tmp/Piano/Piano_C3.wav',
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 47,
            rootName: 'B2',
          ),
        ]
      : const [
          PolySampleRegion(
            path: '/tmp/Piano/Piano_C3.wav',
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
            rootName: 'C3',
          ),
        ];
  return PolyMultisampleBuilderState(
    sourceMode: PolySampleSourceMode.local,
    status: PolyMultisampleLoadStatus.ready,
    currentInstrument: const PolySampleInstrument(
      name: 'Piano',
      sourcePath: '/tmp/Piano',
      regions: [
        PolySampleRegion(
          path: '/tmp/Piano/Piano_C3.wav',
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
          rootName: 'C3',
        ),
      ],
    ),
    baselineRegions: baseline,
    editedRegions: const [
      PolySampleRegion(
        path: '/tmp/Piano/Piano_C3.wav',
        fileName: 'Piano_C3.wav',
        displayName: 'Piano_C3.wav',
        rootMidi: 48,
        rootName: 'C3',
      ),
    ],
    selectedPaths: const {'/tmp/Piano/Piano_C3.wav'},
    focusedPath: '/tmp/Piano/Piano_C3.wav',
  );
}

class _TestPolyMultisampleBuilderCubit extends PolyMultisampleBuilderCubit {
  _TestPolyMultisampleBuilderCubit()
    : super(
        previewService: PolyAudioPreviewService(adapter: _FakePreviewAdapter()),
      );

  String? savedCustomDraftPath;

  void setTestState(PolyMultisampleBuilderState state) {
    emit(
      state.copyWith(
        mappingResolution: const PolySampleMappingResolver().resolve(
          state.editedRegions,
        ),
      ),
    );
  }

  @override
  Future<void> saveCustomDraft(String outputFolderPath) async {
    savedCustomDraftPath = outputFolderPath;
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
