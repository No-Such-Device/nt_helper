import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_preview.dart';

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

    expect(segments, hasLength(3));
    expect(painter.strokeWidth, 2);
    expect(segments[0].start.dy, closeTo(1, 0.001));
    expect(segments[0].end.dx, 100);
    expect(segments[1].start.dy, closeTo(39, 0.001));
    expect(segments[2].start.dx, closeTo(1, 0.001));
    expect(segments[2].start.dy, closeTo(1, 0.001));
    expect(segments[2].end.dy, closeTo(39, 0.001));
  });

  test('full rules replace overlapping bracket hooks', () {
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
    final topSegments = segments.where(
      (segment) =>
          segment.start.dy == segment.end.dy &&
          segment.start.dy < size.height / 2,
    );

    expect(topSegments, hasLength(1));
    expect(topSegments.single.start.dx, closeTo(1, 0.001));
    expect(topSegments.single.end.dx, size.width);
  });

  testWidgets('indent values offset the preview content on both sides', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlgorithmVisualStylePreview(
            style: AlgorithmVisualStyle(leftIndent: 3, rightIndent: 2),
            child: Text('Algorithm'),
          ),
        ),
      ),
    );

    final outerPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('algorithm-style-indent')),
    );
    expect(outerPadding.padding, const EdgeInsets.only(left: 9, right: 6));
  });

  testWidgets('decoration strokes are always fully opaque', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlgorithmVisualStylePreview(
            style: AlgorithmVisualStyle(lineAbove: true),
            color: Colors.white70,
            child: Text('Algorithm'),
          ),
        ),
      ),
    );

    final customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AlgorithmVisualStylePreview),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter =
        customPaint.foregroundPainter! as AlgorithmVisualStylePainter;
    expect(painter.color.a, 1);
  });

  testWidgets('decoration frame stays the same size while style changes', (
    tester,
  ) async {
    Future<Size> measure(AlgorithmVisualStyle style) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AlgorithmVisualStylePreview(
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
        lineAbove: true,
        lineBelow: true,
        bracket: AlgorithmVisualBracket.openAndClose,
      ),
    );

    expect(decoratedSize, undecoratedSize);
  });
}
