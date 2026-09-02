import 'package:flutter/material.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

/// Lays out and draws the firmware 1.18 algorithm-overview style around [child].
///
/// Hardware screenshots establish the geometry used by both the dialog preview
/// and desktop sidebar: 5 pixels per indent unit inside a fixed style
/// frame, rules on the row boundaries, and a bracket rail 6 pixels beyond the
/// unindented algorithm box's right edge.
class AlgorithmVisualStyleContainer extends StatelessWidget {
  static const double defaultIndentExtent = 5;
  static const double verticalFrameExtent = 4;
  static const double bracketRailExtent = 8;

  const AlgorithmVisualStyleContainer({
    super.key,
    required this.style,
    required this.child,
    this.color,
    this.indentExtent = defaultIndentExtent,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.boxDecoration,
  });

  final AlgorithmVisualStyle style;
  final Widget child;
  final Color? color;
  final double indentExtent;
  final EdgeInsetsGeometry contentPadding;
  final Decoration? boxDecoration;

  @override
  Widget build(BuildContext context) {
    final decorationColor =
        (color ?? Theme.of(context).colorScheme.onSurfaceVariant).withValues(
          alpha: 1,
        );

    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        key: const ValueKey('algorithm-style-frame'),
        foregroundPainter: AlgorithmVisualStylePainter(
          style: style,
          color: decorationColor,
        ),
        child: Padding(
          // The NT keeps a four-pixel half-gap above and below each algorithm,
          // plus a fixed rail to the right. Adjacent rows therefore share an
          // exact boundary where rules and continuing brackets meet.
          padding: const EdgeInsets.fromLTRB(
            0,
            verticalFrameExtent,
            bracketRailExtent,
            verticalFrameExtent,
          ),
          child: Padding(
            key: const ValueKey('algorithm-style-indent'),
            // Indents only change the box. Rules and the bracket rail stay on
            // the unindented frame, matching the NT overview.
            padding: EdgeInsets.only(
              left: style.leftIndent * indentExtent,
              right: style.rightIndent * indentExtent,
            ),
            child: DecoratedBox(
              key: const ValueKey('algorithm-style-box'),
              decoration: boxDecoration ?? const BoxDecoration(),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(padding: contentPadding, child: child),
              ),
            ),
          ),
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

  static const double _verticalFrameExtent =
      AlgorithmVisualStyleContainer.verticalFrameExtent;
  static const double _bracketRailExtent =
      AlgorithmVisualStyleContainer.bracketRailExtent;
  static const double _bracketGap = 6;
  static const double _hookLength = 4;

  List<AlgorithmVisualStyleSegment> segmentsFor(Size size) {
    if (size.isEmpty) return const [];

    final boxRight = (size.width - _bracketRailExtent)
        .clamp(0.0, size.width)
        .toDouble();
    final boxTop = _verticalFrameExtent.clamp(0.0, size.height / 2).toDouble();
    final boxBottom = (size.height - _verticalFrameExtent)
        .clamp(boxTop, size.height)
        .toDouble();
    final bracketX = (boxRight + _bracketGap)
        .clamp(boxRight, size.width)
        .toDouble();
    final hookStart = (bracketX - _hookLength)
        .clamp(boxRight, bracketX)
        .toDouble();
    final segments = <AlgorithmVisualStyleSegment>[];

    if (style.lineAbove) {
      segments.add(
        AlgorithmVisualStyleSegment(Offset.zero, Offset(boxRight, 0)),
      );
    }
    if (style.lineBelow) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(0, size.height),
          Offset(boxRight, size.height),
        ),
      );
    }

    if (style.bracket != AlgorithmVisualBracket.none) {
      final bracketTop = switch (style.bracket) {
        AlgorithmVisualBracket.open ||
        AlgorithmVisualBracket.openAndClose => boxTop,
        AlgorithmVisualBracket.line || AlgorithmVisualBracket.close => 0.0,
        AlgorithmVisualBracket.none => boxTop,
      };
      final bracketBottom = switch (style.bracket) {
        AlgorithmVisualBracket.open ||
        AlgorithmVisualBracket.line => size.height,
        AlgorithmVisualBracket.close ||
        AlgorithmVisualBracket.openAndClose => boxBottom,
        AlgorithmVisualBracket.none => boxBottom,
      };
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(bracketX, bracketTop),
          Offset(bracketX, bracketBottom),
        ),
      );
    }
    if ((style.bracket == AlgorithmVisualBracket.open ||
        style.bracket == AlgorithmVisualBracket.openAndClose)) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(hookStart, boxTop),
          Offset(bracketX, boxTop),
        ),
      );
    }
    if ((style.bracket == AlgorithmVisualBracket.close ||
        style.bracket == AlgorithmVisualBracket.openAndClose)) {
      segments.add(
        AlgorithmVisualStyleSegment(
          Offset(hookStart, boxBottom),
          Offset(bracketX, boxBottom),
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
      ..strokeCap = StrokeCap.butt
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

  @override
  bool operator ==(Object other) =>
      other is AlgorithmVisualStyleSegment &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

String describeAlgorithmVisualStyle(AlgorithmVisualStyle style) {
  if (!style.hasCustomStyle) return 'default style';

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
