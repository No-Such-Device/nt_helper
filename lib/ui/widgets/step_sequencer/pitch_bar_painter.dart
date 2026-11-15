import 'package:material_ui/material_ui.dart';

enum BarDisplayMode {
  continuous, // Default vertical gradient bar
  division, // Discrete division display
}

/// CustomPainter for efficient parameter bar rendering
///
/// Supports multiple display modes:
/// - Continuous: Vertical gradient bar (pitch, velocity, mod)
/// - Division: Discrete block display for division parameter
///
/// Note: Bit pattern editing (Pattern/Ties) now uses BitPatternEditor widget
class PitchBarPainter extends CustomPainter {
  final int pitchValue; // Current value
  final Color barColor; // Color for the bar
  final BarDisplayMode displayMode; // Which rendering mode to use
  final int minValue; // Minimum value for range
  final int maxValue; // Maximum value for range

  const PitchBarPainter({
    required this.pitchValue,
    required this.barColor,
    this.displayMode = BarDisplayMode.continuous,
    this.minValue = 0,
    this.maxValue = 127,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (displayMode) {
      case BarDisplayMode.division:
        _paintDivisionBar(canvas, size);
      case BarDisplayMode.continuous:
        _paintContinuousBar(canvas, size);
    }
  }

  /// Paint continuous vertical gradient bar (default mode)
  void _paintContinuousBar(Canvas canvas, Size size) {
    // Create darker versions of the bar color for gradient background
    final alpha = (barColor.a * 255.0).round().clamp(0, 255);
    final red = (barColor.r * 255.0).round().clamp(0, 255);
    final green = (barColor.g * 255.0).round().clamp(0, 255);
    final blue = (barColor.b * 255.0).round().clamp(0, 255);

    final darkColor = Color.fromARGB(
      alpha,
      (red * 0.3).round(),
      (green * 0.3).round(),
      (blue * 0.3).round(),
    );
    final darkerColor = Color.fromARGB(
      alpha,
      (red * 0.2).round(),
      (green * 0.2).round(),
      (blue * 0.2).round(),
    );

    // Draw dark gradient background
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [darkColor, darkerColor],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw bright fill from bottom to parameter value level
    // Normalize value to 0.0-1.0 range based on min/max
    final normalizedValue = (pitchValue - minValue) / (maxValue - minValue);
    final fillHeight = normalizedValue * size.height;
    final fillPaint = Paint()..color = barColor;

    canvas.drawRect(
      Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
      fillPaint,
    );
  }

  /// Paint discrete division display (for Division parameter)
  void _paintDivisionBar(Canvas canvas, Size size) {
    // For now, use continuous bar for division
    // Could be extended to show discrete blocks
    _paintContinuousBar(canvas, size);
  }

  @override
  bool shouldRepaint(covariant PitchBarPainter oldDelegate) {
    // Repaint if value, color, or display mode changes
    return pitchValue != oldDelegate.pitchValue ||
        barColor != oldDelegate.barColor ||
        displayMode != oldDelegate.displayMode;
  }
}
