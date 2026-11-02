import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/wav_metadata.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_waveform_editor.dart';

void main() {
  testWidgets('drag near start handle emits snapped frames', (tester) async {
    int? startFrame;
    int? endFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              onChanged: (start, end) {
                startFrame = start;
                endFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.dragFrom(topLeft + const Offset(1, 60), const Offset(100, 0));

    expect(startFrame, isNotNull);
    expect(_overview().zeroCrossings, contains(startFrame));
    expect(startFrame!, lessThan(endFrame!));
  });

  testWidgets('has waveform editor semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolyWaveformEditor(
            overview: _overview(),
            mode: PolyWaveformEditorMode.trim,
            startFrame: 0,
            endFrame: 999,
            onChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Waveform editor'), findsOneWidget);
    final data = tester
        .getSemantics(find.bySemanticsLabel('Waveform editor'))
        .getSemanticsData();
    expect(data.value, 'Start 0 frames, end 999 frames');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    expect(data.customSemanticsActionIds, isNotEmpty);
    semantics.dispose();
  });

  testWidgets('waveform semantics include loop points and actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolyWaveformEditor(
            overview: _overview(),
            mode: PolyWaveformEditorMode.trim,
            startFrame: 0,
            endFrame: 999,
            loopStartFrame: 250,
            loopEndFrame: 750,
            onChanged: (_, _) {},
            onLoopChanged: (_, _) {},
          ),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Waveform editor'))
        .getSemanticsData();
    expect(
      data.value,
      'Start 0 frames, end 999 frames, loop start 250 frames, loop end 750 frames',
    );
    expect(data.customSemanticsActionIds, hasLength(greaterThanOrEqualTo(8)));
    semantics.dispose();
  });

  testWidgets('waveform semantics include active playback head', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolyWaveformEditor(
            overview: _overview(),
            mode: PolyWaveformEditorMode.trim,
            startFrame: 0,
            endFrame: 999,
            playback: PolyAudioPreviewSourcePlayback(
              sourcePath: '/tmp/Piano_C4.wav',
              startedAt: DateTime.now(),
              startFrame: 0,
              endFrame: 999,
              sampleRate: 1000,
            ),
            onChanged: (_, _) {},
          ),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Waveform editor'))
        .getSemanticsData();
    expect(data.value, contains('playback head'));
    semantics.dispose();
  });

  testWidgets('waveform editor paints fade overlays', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              fadeInFrames: 250,
              fadeOutFrames: 250,
              fadeInCurve: WavFadeCurve.equalPower,
              fadeOutCurve: WavFadeCurve.sCurve,
              fadeInStrength: 0.9,
              fadeOutStrength: 0.7,
              onChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('poly-waveform-fade-overlay')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap sets the nearest trim boundary', (tester) async {
    int? startFrame;
    int? endFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              onChanged: (start, end) {
                startFrame = start;
                endFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(topLeft + const Offset(100, 60));

    expect(startFrame, 250);
    expect(endFrame, 999);
  });

  testWidgets('command tap sets the nearest loop boundary', (tester) async {
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 0,
              loopEndFrame: 999,
              onChanged: (_, _) {},
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(topLeft + const Offset(300, 60));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(loopStartFrame, 0);
    expect(loopEndFrame, 750);
  });

  testWidgets('secondary tap sets the nearest loop boundary', (tester) async {
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 0,
              loopEndFrame: 999,
              onChanged: (_, _) {},
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(
      topLeft + const Offset(300, 60),
      buttons: kSecondaryButton,
    );

    expect(loopStartFrame, 0);
    expect(loopEndFrame, 750);
  });

  testWidgets('plain drag near loop handle does not move loop points', (
    tester,
  ) async {
    int? trimStartFrame;
    int? loopStartFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _denseOverview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 200,
              loopEndFrame: 800,
              onChanged: (start, _) => trimStartFrame = start,
              onLoopChanged: (start, _) => loopStartFrame = start,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.dragFrom(topLeft + const Offset(80, 60), const Offset(40, 0));

    expect(trimStartFrame, isNull);
    expect(loopStartFrame, isNull);
  });

  testWidgets('modified drag near loop handle emits loop changes', (
    tester,
  ) async {
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _denseOverview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 200,
              loopEndFrame: 800,
              onChanged: (_, _) {},
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.dragFrom(topLeft + const Offset(80, 60), const Offset(40, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(loopStartFrame, 300);
    expect(loopEndFrame, 800);
  });

  testWidgets('secondary drag near loop handle emits loop changes', (
    tester,
  ) async {
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _denseOverview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 200,
              loopEndFrame: 800,
              onChanged: (_, _) {},
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    final gesture = await tester.startGesture(
      topLeft + const Offset(80, 60),
      buttons: kSecondaryButton,
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();

    expect(loopStartFrame, 300);
    expect(loopEndFrame, 800);
  });

  testWidgets('one-frame waveforms do not throw while editing', (tester) async {
    int? startFrame;
    int? endFrame;
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _oneFrameOverview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 0,
              loopStartFrame: 0,
              loopEndFrame: 0,
              onChanged: (start, end) {
                startFrame = start;
                endFrame = end;
              },
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(topLeft + const Offset(1, 60));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tapAt(topLeft + const Offset(300, 60));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.dragFrom(topLeft + const Offset(1, 60), const Offset(100, 0));

    expect(tester.takeException(), isNull);
    expect(startFrame, 0);
    expect(endFrame, 0);
    expect(loopStartFrame, 0);
    expect(loopEndFrame, 0);
  }, tags: ['regression']);

  testWidgets('modified drag selects loop handle when handles overlap', (
    tester,
  ) async {
    int? trimStartFrame;
    int? loopStartFrame;
    int? loopEndFrame;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PolyWaveformEditor(
              overview: _overview(),
              mode: PolyWaveformEditorMode.trim,
              startFrame: 0,
              endFrame: 999,
              loopStartFrame: 0,
              loopEndFrame: 999,
              onChanged: (start, _) => trimStartFrame = start,
              onLoopChanged: (start, end) {
                loopStartFrame = start;
                loopEndFrame = end;
              },
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.dragFrom(topLeft + const Offset(1, 60), const Offset(100, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(trimStartFrame, isNull);
    expect(loopStartFrame, 250);
    expect(loopEndFrame, 999);
  }, tags: ['regression']);

  testWidgets('keyboard nudges waveform boundaries', (tester) async {
    int startFrame = 0;
    int endFrame = 999;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: PolyWaveformEditor(
                  overview: _denseOverview(),
                  mode: PolyWaveformEditorMode.trim,
                  startFrame: startFrame,
                  endFrame: endFrame,
                  onChanged: (start, end) {
                    setState(() {
                      startFrame = start;
                      endFrame = end;
                    });
                  },
                ),
              ),
            ),
          );
        },
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(topLeft + const Offset(1, 60));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(startFrame, 100);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(endFrame, 900);
  });

  testWidgets('keyboard nudges loop boundaries', (tester) async {
    int loopStartFrame = 200;
    int loopEndFrame = 800;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: PolyWaveformEditor(
                  overview: _denseOverview(),
                  mode: PolyWaveformEditorMode.trim,
                  startFrame: 0,
                  endFrame: 999,
                  loopStartFrame: loopStartFrame,
                  loopEndFrame: loopEndFrame,
                  onChanged: (_, _) {},
                  onLoopChanged: (start, end) {
                    setState(() {
                      loopStartFrame = start;
                      loopEndFrame = end;
                    });
                  },
                ),
              ),
            ),
          );
        },
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyWaveformEditor));
    await tester.tapAt(topLeft + const Offset(1, 60));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(loopStartFrame, 300);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(loopEndFrame, 700);
  });

  testWidgets('tab focus shows waveform outline and enables keyboard nudges', (
    tester,
  ) async {
    int startFrame = 0;
    int endFrame = 999;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('Before')),
                  SizedBox(
                    width: 400,
                    child: PolyWaveformEditor(
                      overview: _denseOverview(),
                      mode: PolyWaveformEditorMode.trim,
                      startFrame: startFrame,
                      endFrame: endFrame,
                      onChanged: (start, end) {
                        setState(() {
                          startFrame = start;
                          endFrame = end;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('poly-waveform-focus-outline')),
                )
                .decoration
            as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.color, isNot(Colors.transparent));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(startFrame, 100);
  });
}

WavOverview _overview() {
  return WavOverview(
    sampleRate: 44100,
    frameCount: 1000,
    peaks: List<WavPeak>.filled(40, const WavPeak(min: -0.5, max: 0.5)),
    zeroCrossings: const [0, 250, 500, 750, 999],
  );
}

WavOverview _denseOverview() {
  return WavOverview(
    sampleRate: 44100,
    frameCount: 1000,
    peaks: List<WavPeak>.filled(40, const WavPeak(min: -0.5, max: 0.5)),
    zeroCrossings: const [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 999],
  );
}

WavOverview _oneFrameOverview() {
  return const WavOverview(
    sampleRate: 44100,
    frameCount: 1,
    peaks: [WavPeak(min: -0.5, max: 0.5)],
    zeroCrossings: [0],
  );
}
