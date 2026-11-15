import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Geometry for the Bus Lanes view: buses are vertical rails (lanes / "tubes"),
/// algorithm blocks are stacked top→bottom in slot order. Within a block each
/// port gets its own row (inputs first, then outputs), with a bead sitting on
/// its bus lane. Column 0 is a "None" (disconnect) column.
class BusLanesMetrics {
  static const double gutterWidth = 172;
  static const double railWidth = 42;
  static const double headerHeight = 28;
  static const double footerHeight = 28;
  static const double titleHeight = 24;
  static const double portRowHeight = 26;
  static const double padV = 8;

  /// Total columns, including the None column at index 0.
  final int columnCount;
  final List<double> cardTops;
  final List<double> cardHeights;

  const BusLanesMetrics({
    required this.columnCount,
    required this.cardTops,
    required this.cardHeights,
  });

  /// X of a column center. Column 0 is "None"; 1..n are bus lanes; the last
  /// column is the "＋" (add another bus) target.
  double columnX(int column) =>
      gutterWidth + column * railWidth + railWidth / 2;
  double get noneX => columnX(0);
  double get addX => columnX(columnCount - 1);
  double get railsTop => headerHeight;
  double get railsBottom =>
      cardTops.isEmpty ? headerHeight : cardTops.last + cardHeights.last;
  double get contentWidth => gutterWidth + columnCount * railWidth;
  double get contentHeight => railsBottom + footerHeight;
  double cardCenter(int slot) => cardTops[slot] + cardHeights[slot] / 2;

  static double portRowY(int row) =>
      titleHeight + padV + row * portRowHeight + portRowHeight / 2;
  static double cardHeightFor(int portCount) =>
      titleHeight + padV * 2 + (portCount < 1 ? 1 : portCount) * portRowHeight;
}

/// How an output writes its bus.
enum BandWrite { none, add, replace }

/// A colored span of a bus lane between two y positions.
class LaneSegment {
  final double top;
  final double bottom;
  final Color color;
  final bool driven;

  /// When true, the segment fades to transparent toward its bottom — used just
  /// above a Replace so the old signal visibly trails off before it's capped.
  final bool fadeBottom;

  const LaneSegment(
    this.top,
    this.bottom,
    this.color,
    this.driven, {
    this.fadeBottom = false,
  });
}

/// A replace "cap" drawn across a lane at a y position.
class LaneCap {
  final double y;
  final Color color;
  const LaneCap(this.y, this.color);
}

/// Render description for one bus rail (lane): explicit colored segments (a tube
/// exists only where the bus actually carries signal — from its first writer
/// down to its last use) plus any replace caps.
class BusRailRender {
  final int bus;
  final double x;
  final String label;
  final Color labelColor;
  final List<LaneSegment> segments;
  final List<LaneCap> caps;

  const BusRailRender({
    required this.bus,
    required this.x,
    required this.label,
    required this.labelColor,
    required this.segments,
    required this.caps,
  });
}

/// Paints the bus lanes (tubes), the None column, replace caps, and the
/// header/footer labels.
class BusLanesPainter extends CustomPainter {
  final List<BusRailRender> rails;
  final BusLanesMetrics metrics;
  final Color noneColor;
  final Color separatorColor;

  BusLanesPainter({
    required this.rails,
    required this.metrics,
    required this.noneColor,
    required this.separatorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dotted separators between algorithm rows.
    for (var i = 1; i < metrics.cardTops.length; i++) {
      _dottedLine(canvas, 0, size.width, metrics.cardTops[i], separatorColor);
    }

    // None column: a faint guide line + "—" labels.
    final noneX = metrics.noneX;
    canvas.drawLine(
      Offset(noneX, metrics.railsTop),
      Offset(noneX, metrics.railsBottom),
      Paint()
        ..color = noneColor
        ..strokeWidth = 1.5,
    );
    _label(
      canvas,
      '—',
      noneX,
      metrics.railsBottom + BusLanesMetrics.footerHeight / 2,
      noneColor,
    );

    // Add-a-bus column ("＋").
    final addX = metrics.addX;
    canvas.drawLine(
      Offset(addX, metrics.railsTop),
      Offset(addX, metrics.railsBottom),
      Paint()
        ..color = noneColor
        ..strokeWidth = 1.5,
    );
    _label(
      canvas,
      '＋',
      addX,
      metrics.railsBottom + BusLanesMetrics.footerHeight / 2,
      noneColor,
    );

    for (final rail in rails) {
      for (final seg in rail.segments) {
        final paint = Paint()
          ..strokeWidth = seg.driven ? 6.0 : 2.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        if (seg.fadeBottom && seg.bottom > seg.top) {
          // Fade the old signal out and reach full transparency about halfway
          // through, so the signal visibly stops before the junction below.
          final len = seg.bottom - seg.top;
          const fadeLen = 34.0;
          final solidEnd = len > fadeLen ? (len - fadeLen) / len : 0.0;
          final clearAt = len > fadeLen ? (len - fadeLen * 0.5) / len : 0.5;
          final clear = seg.color.withValues(alpha: 0);
          paint.shader = ui.Gradient.linear(
            Offset(rail.x, seg.top),
            Offset(rail.x, seg.bottom),
            [seg.color, seg.color, clear, clear],
            [0.0, solidEnd, clearAt, 1.0],
          );
        } else {
          paint.color = seg.color;
        }
        canvas.drawLine(
          Offset(rail.x, seg.top),
          Offset(rail.x, seg.bottom),
          paint,
        );
      }
      for (final cap in rail.caps) {
        canvas.drawLine(
          Offset(rail.x - 11, cap.y),
          Offset(rail.x + 11, cap.y),
          Paint()
            ..color = cap.color
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
      _label(
        canvas,
        rail.label,
        rail.x,
        metrics.railsBottom + BusLanesMetrics.footerHeight / 2,
        rail.labelColor,
      );
    }
  }

  void _label(Canvas canvas, String text, double cx, double cy, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _dottedLine(Canvas canvas, double x1, double x2, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 4.0;
    var x = x1;
    while (x < x2) {
      final endX = x + dash > x2 ? x2 : x + dash;
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant BusLanesPainter old) =>
      old.rails != rails ||
      old.noneColor != noneColor ||
      old.separatorColor != separatorColor;
}

/// One port row inside an algorithm block.
class PortRowRender {
  final String label;
  final bool isOutput;
  final int row; // overall row index (inputs first, then outputs)
  final double beadX; // column center the bead rests on (None or a lane)
  final bool connected;
  final Color color;
  final BandWrite write;
  final bool unprovided;

  const PortRowRender({
    required this.label,
    required this.isOutput,
    required this.row,
    required this.beadX,
    required this.connected,
    required this.color,
    required this.write,
    required this.unprovided,
  });
}

/// Paints one algorithm block: translucent body, title, per-port labels in the
/// gutter, a horizontal "shunt" guide from each label to its bead, and the
/// add/replace marker on outputs. The draggable beads are widgets on top.
class BusBlockPainter extends CustomPainter {
  final String title;
  final List<PortRowRender> ports;
  final Color cardColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final Color errorColor;
  final bool selected;

  BusBlockPainter({
    required this.title,
    required this.ports,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    required this.errorColor,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Only the gutter gets a card background, so the bus lanes to the right are
    // never dimmed by the algorithm block.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 4, BusLanesMetrics.gutterWidth - 8, size.height - 8),
      const Radius.circular(10),
    );
    canvas.drawRRect(body, Paint()..color = cardColor);
    canvas.drawRRect(
      body,
      Paint()
        ..color = selected ? textColor : borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1,
    );

    _text(
      canvas,
      title,
      14,
      BusLanesMetrics.titleHeight / 2 + 4,
      textColor,
      bold: true,
      maxWidth: BusLanesMetrics.gutterWidth - 54,
    );

    for (final port in ports) {
      final y = BusLanesMetrics.portRowY(port.row);
      final color = port.unprovided ? errorColor : port.color;

      // Shunt guide from the gutter label to the bead.
      if (port.connected) {
        canvas.drawLine(
          Offset(BusLanesMetrics.gutterWidth - 6, y),
          Offset(port.beadX, y),
          Paint()
            ..color = color
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        if (port.isOutput && port.write != BandWrite.none) {
          _text(
            canvas,
            port.write == BandWrite.replace ? '┳' : '+',
            port.beadX + 9,
            y,
            port.color,
            bold: port.write == BandWrite.replace,
          );
        }
      }

      // Direction marker + port label in the gutter. Larger arrow so the
      // read/write direction is obvious at a glance.
      final arrow = port.isOutput ? '▶' : '◀';
      _text(
        canvas,
        arrow,
        10,
        y,
        port.connected ? color : mutedColor,
        bold: true,
        fontSize: 17,
      );
      _text(
        canvas,
        port.label,
        32,
        y,
        port.connected ? textColor : mutedColor,
        maxWidth: BusLanesMetrics.gutterWidth - 46,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    double x,
    double cy,
    Color color, {
    bool bold = false,
    double? maxWidth,
    double fontSize = 12,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, Offset(x, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant BusBlockPainter old) =>
      old.title != title ||
      old.ports != ports ||
      old.selected != selected ||
      old.cardColor != cardColor;
}
