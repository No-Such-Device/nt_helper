import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';
import 'package:nt_helper/ui/poly_multisample/widgets/poly_key_map.dart';

Widget _keyMap({
  required List<PolySampleRegion> regions,
  required String? selectedPath,
  required ValueChanged<PolySampleRegion> onSelect,
  double height = 180,
  ValueChanged<int>? onPreviewNote,
  ValueChanged<int>? onPreviewNoteStart,
  VoidCallback? onPreviewNoteEnd,
  int? playedMidiNote,
}) {
  return PolyKeyMap(
    regions: regions,
    mappingResolution: const PolySampleMappingResolver().resolve(regions),
    selectedPath: selectedPath,
    onSelect: onSelect,
    height: height,
    onPreviewNote: onPreviewNote,
    onPreviewNoteStart: onPreviewNoteStart,
    onPreviewNoteEnd: onPreviewNoteEnd,
    playedMidiNote: playedMidiNote,
  );
}

void main() {
  test('piano geometry renders black keys only at standard pitch classes', () {
    final geometry = PolyKeyboardGeometry(
      keyboardRect: const Rect.fromLTWH(0, 0, 700, 100),
      minMidi: 48,
      maxMidi: 71,
    );

    expect(geometry.blackKeys.map((key) => key.pitchClass).toSet(), {
      1,
      3,
      6,
      8,
      10,
    });
    expect(geometry.blackKeys, hasLength(10));
    expect(
      geometry.blackKeys.every(
        (key) =>
            PolyKeyboardGeometry.blackPitchClasses.contains(key.pitchClass),
      ),
      isTrue,
    );
  });

  test('piano geometry leaves no black key between E-F or B-C', () {
    final keyboardRect = const Rect.fromLTWH(0, 0, 700, 100);
    final geometry = PolyKeyboardGeometry(
      keyboardRect: keyboardRect,
      minMidi: 48,
      maxMidi: 71,
    );

    final e3 = geometry.whiteKeys.singleWhere((key) => key.midi == 52);
    final f3 = geometry.whiteKeys.singleWhere((key) => key.midi == 53);
    final b3 = geometry.whiteKeys.singleWhere((key) => key.midi == 59);
    final c4 = geometry.whiteKeys.singleWhere((key) => key.midi == 60);
    final blackKeyY = keyboardRect.top + keyboardRect.height * 0.31;

    expect(e3.rect.right, closeTo(f3.rect.left, 0.001));
    expect(b3.rect.right, closeTo(c4.rect.left, 0.001));
    expect(
      geometry.blackKeys.any(
        (key) => key.rect.contains(Offset(f3.rect.left, blackKeyY)),
      ),
      isFalse,
    );
    expect(
      geometry.blackKeys.any(
        (key) => key.rect.contains(Offset(c4.rect.left, blackKeyY)),
      ),
      isFalse,
    );
  }, tags: ['regression']);

  test('piano geometry lays out white keys in C-D-E-F-G-A-B order', () {
    final geometry = PolyKeyboardGeometry(
      keyboardRect: const Rect.fromLTWH(0, 0, 700, 100),
      minMidi: 48,
      maxMidi: 71,
    );

    expect(geometry.whiteKeys, hasLength(14));
    expect(geometry.whiteKeys.map((key) => key.pitchClass), [
      0,
      2,
      4,
      5,
      7,
      9,
      11,
      0,
      2,
      4,
      5,
      7,
      9,
      11,
    ]);
    for (var i = 0; i < geometry.whiteKeys.length - 1; i++) {
      expect(
        geometry.whiteKeys[i].rect.right,
        closeTo(geometry.whiteKeys[i + 1].rect.left, 0.001),
      );
    }
  });

  test('piano geometry hit testing prefers raised black key overlays', () {
    final geometry = PolyKeyboardGeometry(
      keyboardRect: const Rect.fromLTWH(0, 0, 700, 100),
      minMidi: 48,
      maxMidi: 71,
    );

    final c3 = geometry.whiteKeys.singleWhere((key) => key.midi == 48);
    final cSharp3 = geometry.blackKeys.singleWhere((key) => key.midi == 49);

    expect(geometry.hitTest(c3.rect.center), 48);
    expect(geometry.hitTest(cSharp3.rect.center), 49);
    expect(
      geometry.hitTest(
        Offset(cSharp3.rect.center.dx, cSharp3.rect.bottom + 10),
      ),
      50,
    );
  });

  testWidgets('exposes a keyboard map semantics label', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [
                PolySampleRegion(
                  path: '/tmp/a.wav',
                  fileName: 'a.wav',
                  displayName: 'a.wav',
                  rootMidi: 48,
                ),
                PolySampleRegion(
                  path: '/tmp/b.wav',
                  fileName: 'b.wav',
                  displayName: 'b.wav',
                  rootMidi: 60,
                ),
              ],
              selectedPath: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Keyboard map with 2 mapped samples'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('a.wav, root C3, range C-1 to E3, velocity 1'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('tap on a mapped zone selects the region', (tester) async {
    PolySampleRegion? selected;
    const region = PolySampleRegion(
      path: '/tmp/c3.wav',
      fileName: 'c3.wav',
      displayName: 'c3.wav',
      rootMidi: 48,
      switchPoint: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [region],
              selectedPath: null,
              onSelect: (region) => selected = region,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyKeyMap));
    await tester.tapAt(topLeft + const Offset(800 / 2, (24 + (200 - 50)) / 2));

    expect(selected, region);
  });

  testWidgets('tap on keyboard strip previews the tapped midi note', (
    tester,
  ) async {
    PolySampleRegion? selected;
    int? previewedNote;
    const region = PolySampleRegion(
      path: '/tmp/c3.wav',
      fileName: 'c3.wav',
      displayName: 'c3.wav',
      rootMidi: 60,
      switchPoint: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [region],
              selectedPath: null,
              onSelect: (region) => selected = region,
              onPreviewNote: (midi) => previewedNote = midi,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyKeyMap));
    final geometry = PolyKeyboardGeometry(
      keyboardRect: const Rect.fromLTRB(16, 158, 784, 192),
      minMidi: 0,
      maxMidi: 127,
    );
    final c4 = geometry.whiteKeys.singleWhere((key) => key.midi == 60);
    await tester.tapAt(topLeft + c4.rect.center);

    expect(previewedNote, 60);
    expect(selected, isNull);
  });

  testWidgets('keyboard note preview starts on pointer down and stops on up', (
    tester,
  ) async {
    final startedNotes = <int>[];
    var stopCount = 0;
    const region = PolySampleRegion(
      path: '/tmp/c3.wav',
      fileName: 'c3.wav',
      displayName: 'c3.wav',
      rootMidi: 60,
      switchPoint: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [region],
              selectedPath: null,
              onSelect: (_) {},
              onPreviewNoteStart: startedNotes.add,
              onPreviewNoteEnd: () => stopCount++,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyKeyMap));
    final geometry = PolyKeyboardGeometry(
      keyboardRect: const Rect.fromLTRB(16, 158, 784, 192),
      minMidi: 0,
      maxMidi: 127,
    );
    final c4 = geometry.whiteKeys.singleWhere((key) => key.midi == 60);
    final gesture = await tester.startGesture(topLeft + c4.rect.center);

    expect(startedNotes, [60]);
    expect(stopCount, 0);

    await gesture.up();

    expect(stopCount, 1);
  });

  testWidgets('tap on mapped zone still selects without previewing', (
    tester,
  ) async {
    PolySampleRegion? selected;
    int? previewedNote;
    const region = PolySampleRegion(
      path: '/tmp/c3.wav',
      fileName: 'c3.wav',
      displayName: 'c3.wav',
      rootMidi: 48,
      switchPoint: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [region],
              selectedPath: null,
              onSelect: (region) => selected = region,
              onPreviewNote: (midi) => previewedNote = midi,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(PolyKeyMap));
    await tester.tapAt(topLeft + const Offset(800 / 2, (24 + (200 - 50)) / 2));

    expect(selected, region);
    expect(previewedNote, isNull);
  });

  testWidgets(
    'played key uses tertiary highlight without replacing selection',
    (tester) async {
      const tertiary = Color(0xff00aa55);
      const region = PolySampleRegion(
        path: '/tmp/c4.wav',
        fileName: 'c4.wav',
        displayName: 'c4.wav',
        rootMidi: 60,
        switchPoint: 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(tertiary: tertiary),
          ),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 200,
              child: _keyMap(
                height: 200,
                regions: const [region],
                selectedPath: region.path,
                playedMidiNote: 60,
                onSelect: (_) {},
                onPreviewNote: (_) {},
              ),
            ),
          ),
        ),
      );

      final customPaint = find.descendant(
        of: find.byType(PolyKeyMap),
        matching: find.byType(CustomPaint),
      );
      expect(
        customPaint,
        paints..rect(color: tertiary.withValues(alpha: 0.70)),
      );

      final customPaintWidget = tester.widget<CustomPaint>(customPaint);
      final painter = customPaintWidget.painter as dynamic;
      expect(painter.playedMidiNote, 60);
      expect(painter.colorScheme.tertiary, tertiary);
    },
  );

  testWidgets('exposes piano note preview semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [
                PolySampleRegion(
                  path: '/tmp/c4.wav',
                  fileName: 'c4.wav',
                  displayName: 'c4.wav',
                  rootMidi: 60,
                ),
              ],
              selectedPath: null,
              onSelect: (_) {},
              onPreviewNote: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Preview C4'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('keyboard focus can activate a mapped region', (tester) async {
    PolySampleRegion? selected;
    const region = PolySampleRegion(
      path: '/tmp/c3.wav',
      fileName: 'c3.wav',
      displayName: 'c3.wav',
      rootMidi: 48,
      switchPoint: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('Before')),
              SizedBox(
                width: 800,
                height: 200,
                child: _keyMap(
                  height: 200,
                  regions: const [region],
                  selectedPath: null,
                  onSelect: (region) => selected = region,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, region);
  });

  testWidgets('disambiguates duplicate sample names in semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [
                PolySampleRegion(
                  path: '/tmp/Kit/close/C4.wav',
                  fileName: 'C4.wav',
                  displayName: 'C4.wav',
                  rootMidi: 60,
                ),
                PolySampleRegion(
                  path: '/tmp/Kit/room/C4.wav',
                  fileName: 'C4.wav',
                  displayName: 'C4.wav',
                  rootMidi: 62,
                ),
              ],
              selectedPath: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        'close/C4.wav, root C4, range C-1 to C4, velocity 1',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'room/C4.wav, root D4, range C#4 to G9, velocity 1',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  }, tags: ['regression']);

  testWidgets('renders without mapped regions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: const [],
              selectedPath: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(PolyKeyMap),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('rootless zones are mapped focusable and selectable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    PolySampleRegion? selected;
    const regions = [
      PolySampleRegion(
        path: '/tmp/Kick.wav',
        fileName: 'Kick.wav',
        displayName: 'Kick.wav',
      ),
      PolySampleRegion(
        path: '/tmp/Snare.wav',
        fileName: 'Snare.wav',
        displayName: 'Snare.wav',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: regions,
              selectedPath: null,
              onSelect: (region) => selected = region,
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Keyboard map with 2 mapped samples'),
      findsOneWidget,
    );
    final kick = find.bySemanticsLabel(
      'Kick.wav, root C3, automatic, range C-1 to C3, velocity 1',
    );
    expect(kick, findsOneWidget);
    expect(
      tester
          .getSemantics(kick)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(kick);
    await tester.pump();
    expect(selected, regions.first);
    semantics.dispose();
  });

  testWidgets('EVOS A1 semantic range is F1 through B1', (tester) async {
    final semantics = tester.ensureSemantics();
    const naturals = [12, 19, 26, 33, 40, 47, 54, 61, 68, 75];
    final regions = [
      for (final natural in naturals)
        PolySampleRegion(
          path: '/tmp/EVOS_$natural.wav',
          fileName: 'EVOS_$natural.wav',
          displayName: 'EVOS_$natural.wav',
          rootMidi: natural,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: _keyMap(
              height: 200,
              regions: regions,
              selectedPath: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('EVOS_33.wav, root A1, range F1 to B1, velocity 1'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
