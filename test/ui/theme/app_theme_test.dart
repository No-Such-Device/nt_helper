import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/routing/accessibility_colors.dart';

void main() {
  group('AppTheme', () {
    const customSeed = Color(0xFF6750A4);

    test('builds every brightness and contrast variant from one seed', () {
      for (final brightness in Brightness.values) {
        for (final contrastLevel in <double>[0, 1]) {
          final theme = AppTheme.build(
            seedColor: customSeed,
            brightness: brightness,
            contrastLevel: contrastLevel,
          );
          final expected = ColorScheme.fromSeed(
            seedColor: customSeed,
            dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
            brightness: brightness,
            contrastLevel: contrastLevel,
          );
          expect(theme.useMaterial3, isTrue);
          expect(theme.colorScheme.brightness, brightness);
          expect(theme.colorScheme.primary, expected.primary);
          expect(theme.colorScheme.tertiary, expected.tertiary);
          expect(theme.colorScheme.onTertiary, expected.onTertiary);
          expect(
            theme.colorScheme.tertiaryContainer,
            expected.tertiaryContainer,
          );
          expect(theme.colorScheme.surface, expected.surface);
          expect(theme.extension<AppThemeColors>(), isNotNull);
        }
      }
    });

    test('normalizes a translucent seed to opaque', () {
      final theme = AppTheme.build(
        seedColor: const Color(0x336750A4),
        brightness: Brightness.light,
      );
      final expected = AppTheme.build(
        seedColor: customSeed,
        brightness: Brightness.light,
      );

      expect(theme.colorScheme.primary, expected.colorScheme.primary);
    });

    test('domain roles provide readable foreground colours', () {
      for (final brightness in Brightness.values) {
        final colors = AppTheme.build(
          seedColor: customSeed,
          brightness: brightness,
        ).appColors;
        final pairs = <AppColorPair>[
          colors.success,
          colors.warning,
          colors.info,
          ...colors.categorical,
          ...colors.sequencer,
          colors.audioPort,
          colors.cvPort,
          colors.gatePort,
          colors.clockPort,
        ];

        for (final pair in pairs) {
          expect(
            AccessibilityColors.getContrastRatio(pair.color, pair.onColor),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }, tags: ['regression']);

    test('appColors falls back safely for third-party ThemeData', () {
      expect(ThemeData.light().appColors, isA<AppThemeColors>());
      expect(ThemeData.dark().appColors, isA<AppThemeColors>());
    });
  });
}
