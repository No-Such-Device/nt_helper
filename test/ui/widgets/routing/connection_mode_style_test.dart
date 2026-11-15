import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/routing/accessibility_colors.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart';
import 'package:nt_helper/ui/widgets/routing/connection_theme.dart';

ConnectionData _connectionData(
  OutputMode mode, {
  bool isSelected = false,
  bool isHighlighted = false,
}) {
  return ConnectionData(
    connection: const Connection(
      id: 'connection',
      sourcePortId: 'audio_output',
      destinationPortId: 'audio_input',
      connectionType: ConnectionType.algorithmToAlgorithm,
    ),
    sourcePosition: Offset.zero,
    destinationPosition: const Offset(100, 0),
    outputMode: mode,
    isSelected: isSelected,
    isHighlighted: isHighlighted,
  );
}

ConnectionPainter _painterFor(ConnectionData connection, ThemeData theme) {
  return ConnectionPainter(
    connections: [connection],
    theme: theme,
    showLabels: false,
  );
}

void main() {
  group('routing connection mode theme', () {
    for (final brightness in Brightness.values) {
      for (final contrastLevel in <double>[0, 1]) {
        test(
          '$brightness contrast $contrastLevel uses distinct accessible modes',
          () {
            final theme = AppTheme.build(
              seedColor: AppTheme.defaultSeedColor,
              brightness: brightness,
              contrastLevel: contrastLevel,
            );
            final routingTheme = ConnectionVisualTheme.fromColorScheme(
              theme.colorScheme,
            );

            expect(
              routingTheme.addModeConnection.color.toARGB32(),
              isNot(routingTheme.replaceModeConnection.color.toARGB32()),
            );
            expect(
              routingTheme.replaceModeConnection.strokeWidth,
              greaterThan(routingTheme.addModeConnection.strokeWidth),
            );
            expect(
              AccessibilityColors.getContrastRatio(
                routingTheme.addModeConnection.color,
                theme.colorScheme.surface,
              ),
              greaterThanOrEqualTo(AccessibilityColors.wcagAANormal),
            );
            expect(
              AccessibilityColors.getContrastRatio(
                routingTheme.replaceModeConnection.color,
                theme.colorScheme.surface,
              ),
              greaterThanOrEqualTo(AccessibilityColors.wcagAANormal),
            );
          },
        );
      }
    }

    test('painter applies mode colours and redundant stroke widths', () {
      final theme = AppTheme.build(
        seedColor: AppTheme.defaultSeedColor,
        brightness: Brightness.light,
      );
      final routingTheme = ConnectionVisualTheme.fromColorScheme(
        theme.colorScheme,
      );
      final add = _connectionData(OutputMode.add);
      final replace = _connectionData(OutputMode.replace);
      final addPainter = _painterFor(add, theme);
      final replacePainter = _painterFor(replace, theme);

      expect(
        addPainter.debugResolveStyleColor(add).toARGB32(),
        routingTheme.addModeConnection.color.toARGB32(),
      );
      expect(
        replacePainter.debugResolveStyleColor(replace).toARGB32(),
        routingTheme.replaceModeConnection.color.toARGB32(),
      );
      expect(
        addPainter.debugResolveStyleStrokeWidth(add),
        routingTheme.addModeConnection.strokeWidth,
      );
      expect(
        replacePainter.debugResolveStyleStrokeWidth(replace),
        routingTheme.replaceModeConnection.strokeWidth,
      );
    });

    test('selection styling takes precedence over output mode styling', () {
      final theme = AppTheme.build(
        seedColor: AppTheme.defaultSeedColor,
        brightness: Brightness.light,
      );
      final add = _connectionData(OutputMode.add, isSelected: true);
      final replace = _connectionData(OutputMode.replace, isSelected: true);

      expect(
        _painterFor(add, theme).debugResolveStyleColor(add).toARGB32(),
        _painterFor(replace, theme).debugResolveStyleColor(replace).toARGB32(),
      );
      expect(
        _painterFor(add, theme).debugResolveStyleStrokeWidth(add),
        _painterFor(replace, theme).debugResolveStyleStrokeWidth(replace),
      );
    });
  });
}
