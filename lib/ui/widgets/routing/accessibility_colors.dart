import 'package:material_ui/material_ui.dart';

import 'dart:math' as math;

/// Helper class for ensuring WCAG-compliant contrast ratios in the routing editor.
///
/// This class provides methods to calculate contrast ratios and suggest
/// alternative colors that meet WCAG AA (4.5:1) or AAA (7:1) standards.
class AccessibilityColors {
  /// WCAG AA standard contrast ratio for normal text
  static const double wcagAANormal = 4.5;

  /// WCAG AAA standard contrast ratio for normal text
  static const double wcagAAANormal = 7.0;

  /// WCAG AA standard contrast ratio for large text
  static const double wcagAALarge = 3.0;

  /// WCAG AAA standard contrast ratio for large text
  static const double wcagAAALarge = 4.5;

  /// Calculates the relative luminance of a color
  /// Based on WCAG 2.1 specification
  static double _getRelativeLuminance(Color color) {
    final r = _getRGBComponent((color.r * 255.0).round() / 255.0);
    final g = _getRGBComponent((color.g * 255.0).round() / 255.0);
    final b = _getRGBComponent((color.b * 255.0).round() / 255.0);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Converts RGB component to linear color space
  static double _getRGBComponent(double component) {
    if (component <= 0.03928) {
      return component / 12.92;
    } else {
      return math.pow((component + 0.055) / 1.055, 2.4).toDouble();
    }
  }

  /// Calculates the contrast ratio between two colors
  /// Returns a value between 1.0 (no contrast) and 21.0 (maximum contrast)
  static double getContrastRatio(Color color1, Color color2) {
    final luminance1 = _getRelativeLuminance(color1);
    final luminance2 = _getRelativeLuminance(color2);

    final lighter = math.max(luminance1, luminance2);
    final darker = math.min(luminance1, luminance2);

    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Checks if the contrast ratio meets WCAG AA standards
  static bool meetsWCAGAA(
    Color foreground,
    Color background, {
    bool isLargeText = false,
  }) {
    final ratio = getContrastRatio(foreground, background);
    return ratio >= (isLargeText ? wcagAALarge : wcagAANormal);
  }

  /// Checks if the contrast ratio meets WCAG AAA standards
  static bool meetsWCAGAAA(
    Color foreground,
    Color background, {
    bool isLargeText = false,
  }) {
    final ratio = getContrastRatio(foreground, background);
    return ratio >= (isLargeText ? wcagAAALarge : wcagAAANormal);
  }

  /// Adjusts a color's lightness to meet minimum contrast requirements
  /// Returns a color that meets the specified contrast ratio against the background
  static Color ensureContrast(
    Color foreground,
    Color background, {
    double minRatio = wcagAANormal,
  }) {
    final currentRatio = getContrastRatio(foreground, background);

    if (currentRatio >= minRatio) {
      return foreground; // Already meets requirements
    }

    // Convert to HSL for easier manipulation
    final HSLColor hsl = HSLColor.fromColor(foreground);
    // Precompute once to keep logic explicit and avoid unused warnings
    final _ = _getRelativeLuminance(background);

    // Try making it darker first, then lighter
    for (final makeDarker in [true, false]) {
      double lightness = hsl.lightness;

      // Binary search for the right lightness value
      double min = makeDarker ? 0.0 : lightness;
      double max = makeDarker ? lightness : 1.0;

      for (int i = 0; i < 20; i++) {
        // 20 iterations should be enough precision
        lightness = (min + max) / 2.0;

        final testColor = hsl.withLightness(lightness).toColor();
        final testRatio = getContrastRatio(testColor, background);

        if (testRatio >= minRatio) {
          if (makeDarker) {
            min = lightness;
          } else {
            max = lightness;
          }

          // Found a good value
          if ((testRatio - minRatio).abs() < 0.1) {
            return testColor;
          }
        } else {
          if (makeDarker) {
            max = lightness;
          } else {
            min = lightness;
          }
        }
      }
    }

    // Fallback: return high contrast black or white
    final whiteRatio = getContrastRatio(Colors.white, background);
    final blackRatio = getContrastRatio(Colors.black, background);

    return whiteRatio > blackRatio ? Colors.white : Colors.black;
  }

  /// Creates accessible colors for the routing editor based on Material theme
  static AccessibleRoutingColors fromColorScheme(ColorScheme colorScheme) {
    return AccessibleRoutingColors(
      // Connection colors with proper contrast
      primaryConnection: ensureContrast(
        colorScheme.primary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      secondaryConnection: ensureContrast(
        colorScheme.secondary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      tertiaryConnection: ensureContrast(
        colorScheme.tertiary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      errorConnection: ensureContrast(
        colorScheme.error,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      // Port type colors with high contrast
      audioPortColor: ensureContrast(
        colorScheme.primary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      cvPortColor: ensureContrast(
        colorScheme.tertiary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      gatePortColor: ensureContrast(
        colorScheme.secondary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      clockPortColor: ensureContrast(
        colorScheme.error,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      // UI element colors
      focusIndicator: ensureContrast(
        colorScheme.primary,
        colorScheme.surface,
        minRatio: wcagAANormal,
      ),

      selectionIndicator: ensureContrast(
        colorScheme.primary,
        colorScheme.surface,
        minRatio: wcagAAANormal, // Higher contrast for selection
      ),

      hoverIndicator: ensureContrast(
        colorScheme.primary.withValues(alpha: 0.7),
        colorScheme.surface,
        minRatio: wcagAALarge,
      ),
    );
  }
}

/// Container for accessible color values used in the routing editor
class AccessibleRoutingColors {
  final Color primaryConnection;
  final Color secondaryConnection;
  final Color tertiaryConnection;
  final Color errorConnection;

  final Color audioPortColor;
  final Color cvPortColor;
  final Color gatePortColor;
  final Color clockPortColor;

  final Color focusIndicator;
  final Color selectionIndicator;
  final Color hoverIndicator;

  const AccessibleRoutingColors({
    required this.primaryConnection,
    required this.secondaryConnection,
    required this.tertiaryConnection,
    required this.errorConnection,
    required this.audioPortColor,
    required this.cvPortColor,
    required this.gatePortColor,
    required this.clockPortColor,
    required this.focusIndicator,
    required this.selectionIndicator,
    required this.hoverIndicator,
  });
}
