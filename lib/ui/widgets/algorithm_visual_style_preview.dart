import 'package:flutter/material.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

/// Draws the firmware 1.18 algorithm-overview decoration around [child].
///
/// The NT's 0-15 indent values are scaled to remain legible in the helper UI.
/// Bracket modes use the familiar group-outline shapes: opening corner,
/// vertical continuation, closing corner, or a complete bracket.
class AlgorithmVisualStylePreview extends StatelessWidget {
  static const double defaultIndentExtent = 3;

  const AlgorithmVisualStylePreview({
    super.key,
    required this.style,
    required this.child,
    this.color,
    this.indentExtent = defaultIndentExtent,
  });

  final AlgorithmVisualStyle style;
  final Widget child;
  final Color? color;
  final double indentExtent;

  @override
  Widget build(BuildContext context) {
    final decorationColor =
        (color ?? Theme.of(context).colorScheme.onSurfaceVariant).withValues(
          alpha: 1,
        );

    return Padding(
      key: const ValueKey('algorithm-style-indent'),
      padding: EdgeInsets.only(
        left: style.leftIndent * indentExtent,
        right: style.rightIndent * indentExtent,
      ),
      child: CustomPaint(
        foregroundPainter: AlgorithmVisualStylePainter(
          style: style,
          color: decorationColor,
        ),
        child: Padding(
          // Reserve the maximum rule/bracket frame so toggling decorations
          // only changes paint, never the preview's measured geometry.
          padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          child: child,
        ),
      ),
    );
  }
}

class AlgorithmVisualStylePainter extends CustomPainter {
  const AlgorithmVisualStylePainter({
    required this.style,
    required this.color,
    this.strokeWidth = 2,
  });

  final AlgorithmVisualStyle style;
  final Color color;
  final double strokeWidth;

  List<AlgorithmVisualStyleSegment> segmentsFor(Size size) {
    if (size.isEmpty) return const [];

    final inset = strokeWidth / 2;
    final top = inset;
    final bottom = size.height - inset;
    final left = inset;
    final hookEnd = 9.0.clamp(left, size.width).toDouble();
    final ruleStart = style.bracket == AlgorithmVisualBracket.none ? 0.0 : left;
    final segments = <AlgorithmVisualStyleSegment>[];

    if (style.lineAbove) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(ruleStart, top),
          Offset(size.width, top),
        ),
      );
    }
    if (style.lineBelow) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(ruleStart, bottom),
          Offset(size.width, bottom),
        ),
      );
    }

    if (style.bracket != AlgorithmVisualBracket.none) {
      segments.add(
        AlgorithmVisualStyleSegment(Offset(left, top), Offset(left, bottom)),
      );
    }
    if ((style.bracket == AlgorithmVisualBracket.open ||
            style.bracket == AlgorithmVisualBracket.openAndClose) &&
        !style.lineAbove) {
      segments.add(
        AlgorithmVisualStyleSegment(Offset(left, top), Offset(hookEnd, top)),
      );
    }
    if ((style.bracket == AlgorithmVisualBracket.close ||
            style.bracket == AlgorithmVisualBracket.openAndClose) &&
        !style.lineBelow) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(left, bottom),
          Offset(hookEnd, bottom),
        ),
      );
    }

    return segments;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final segment in segmentsFor(size)) {
      canvas.drawLine(segment.start, segment.end, paint);
    }
  }

  @override
  bool shouldRepaint(AlgorithmVisualStylePainter oldDelegate) =>
      style != oldDelegate.style ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth;
}

class AlgorithmVisualStyleSegment {
  const AlgorithmVisualStyleSegment(this.start, this.end);

  final Offset start;
  final Offset end;
}

String describeAlgorithmVisualStyle(AlgorithmVisualStyle style) {
  if (!style.isDecorated) return 'no decoration';

  final parts = <String>[];
  if (style.lineAbove) parts.add('line above');
  if (style.lineBelow) parts.add('line below');
  if (style.leftIndent > 0) parts.add('left indent ${style.leftIndent}');
  if (style.rightIndent > 0) parts.add('right indent ${style.rightIndent}');
  if (style.bracket != AlgorithmVisualBracket.none) {
    parts.add(switch (style.bracket) {
      AlgorithmVisualBracket.none => 'no bracket',
      AlgorithmVisualBracket.open => 'open bracket',
      AlgorithmVisualBracket.close => 'close bracket',
      AlgorithmVisualBracket.line => 'continuing bracket',
      AlgorithmVisualBracket.openAndClose => 'open and close bracket',
    });
  }
  return parts.join(', ');
}
