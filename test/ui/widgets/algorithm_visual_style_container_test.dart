import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_container.dart';

void main() {
  test('painter maps NT rules and bracket modes to line segments', () {
    const size = Size(100, 40);
    const rules = AlgorithmVisualStyle(
      lineAbove: true,
      lineBelow: true,
      bracket: AlgorithmVisualBracket.openAndClose,
    );
    final painter = AlgorithmVisualStylePainter(
      style: rules,
      color: Colors.white,
    );

    final segments = painter.segmentsFor(size);

    expect(segments, hasLength(5));
    expect(painter.strokeWidth, 2);
    expect(
      segments[0],
      const AlgorithmVisualStyleSegment(Offset(0, 0), Offset(92, 0)),
    );
    expect(
      segments[1],
      const AlgorithmVisualStyleSegment(Offset(0, 40), Offset(92, 40)),
    );
    expect(
      segments[2],
      const AlgorithmVisualStyleSegment(Offset(98, 4), Offset(98, 36)),
    );
    expect(
      segments[3],
      const AlgorithmVisualStyleSegment(Offset(94, 4), Offset(98, 4)),
    );
    expect(
      segments[4],
      const AlgorithmVisualStyleSegment(Offset(94, 36), Offset(98, 36)),
    );
  });

  test('rules and bracket hooks occupy distinct NT overview rows', () {
    const size = Size(100, 40);
    const style = AlgorithmVisualStyle(
      lineAbove: true,
      bracket: AlgorithmVisualBracket.openAndClose,
    );
    final painter = AlgorithmVisualStylePainter(
      style: style,
      color: Colors.white70,
    );

    final segments = painter.segmentsFor(size);
    final horizontalSegments = segments.where(
      (segment) => segment.start.dy == segment.end.dy,
    );

    expect(horizontalSegments, hasLength(3));
    expect(horizontalSegments.map((segment) => segment.start.dy), [0, 4, 36]);
  });

  test('open, line, and close brackets meet at adjacent row boundaries', () {
    const size = Size(100, 40);

    AlgorithmVisualStyleSegment vertical(AlgorithmVisualBracket bracket) {
      return AlgorithmVisualStylePainter(
        style: AlgorithmVisualStyle(bracket: bracket),
        color: Colors.white,
      ).segmentsFor(size).first;
    }

    expect(
      vertical(AlgorithmVisualBracket.open),
      const AlgorithmVisualStyleSegment(Offset(98, 4), Offset(98, 40)),
    );
    expect(
      vertical(AlgorithmVisualBracket.line),
      const AlgorithmVisualStyleSegment(Offset(98, 0), Offset(98, 40)),
    );
    expect(
      vertical(AlgorithmVisualBracket.close),
      const AlgorithmVisualStyleSegment(Offset(98, 0), Offset(98, 36)),
    );
  });

  testWidgets('indent values inset only the algorithm box', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              child: AlgorithmVisualStyleContainer(
                style: AlgorithmVisualStyle(
                  leftIndent: 3,
                  rightIndent: 2,
                  lineAbove: true,
                  bracket: AlgorithmVisualBracket.open,
                ),
                child: Text('Algorithm'),
              ),
            ),
          ),
        ),
      ),
    );

    final outerPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('algorithm-style-indent')),
    );
    expect(outerPadding.padding, const EdgeInsets.only(left: 15, right: 10));

    final frame = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('algorithm-style-frame')),
    );
    final painter = frame.foregroundPainter! as AlgorithmVisualStylePainter;
    expect(
      painter.segmentsFor(const Size(100, 40)),
      containsAll(const [
        AlgorithmVisualStyleSegment(Offset(0, 0), Offset(92, 0)),
        AlgorithmVisualStyleSegment(Offset(98, 4), Offset(98, 40)),
      ]),
    );
  });

  testWidgets('algorithm style strokes are always fully opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlgorithmVisualStyleContainer(
            style: AlgorithmVisualStyle(lineAbove: true),
            color: Colors.white70,
            child: Text('Algorithm'),
          ),
        ),
      ),
    );

    final customPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('algorithm-style-frame')),
    );
    final painter =
        customPaint.foregroundPainter! as AlgorithmVisualStylePainter;
    expect(painter.color.a, 1);
  });

  testWidgets('style frame stays the same size while style changes', (
    tester,
  ) async {
    Future<Size> measure(AlgorithmVisualStyle style) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AlgorithmVisualStyleContainer(
                key: const ValueKey('preview'),
                style: style,
                child: const Text('Algorithm'),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const ValueKey('preview')));
    }

    final undecoratedSize = await measure(const AlgorithmVisualStyle());
    final decoratedSize = await measure(
      const AlgorithmVisualStyle(
        leftIndent: 4,
        rightIndent: 3,
        lineAbove: true,
        lineBelow: true,
        bracket: AlgorithmVisualBracket.openAndClose,
      ),
    );

    expect(decoratedSize, undecoratedSize);
  });
}
