import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'UI colour literals stay centralized or objectively contrast-driven',
    () {
      const centralPaletteFiles = <String>{
        'lib/ui/theme/app_theme.dart',
        'lib/ui/widgets/theme_seed_picker.dart',
      };
      const objectiveContrastFiles = <String>{
        'lib/ui/widgets/routing/accessibility_colors.dart',
        'lib/ui/video_popup_app.dart',
        'lib/ui/widgets/draggable_resizable_overlay.dart',
        'lib/ui/widgets/floating_screenshot_overlay.dart',
        'lib/ui/widgets/floating_video_overlay.dart',
      };
      final materialColorPattern = RegExp(r'\bColors\.([A-Za-z0-9_]+)');
      final literalColorPattern = RegExp(
        r'\b(?:const\s+)?Color\(0x[0-9A-Fa-f]+',
      );
      final violations = <String>[];

      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final path = file.path.replaceAll('\\', '/');
        final lines = file.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          for (final match in materialColorPattern.allMatches(line)) {
            final name = match.group(1)!;
            final allowed =
                name == 'transparent' ||
                centralPaletteFiles.contains(path) ||
                (objectiveContrastFiles.contains(path) &&
                    (name == 'black' || name == 'white'));
            if (!allowed) {
              violations.add('$path:${index + 1}: Colors.$name');
            }
          }
          if (literalColorPattern.hasMatch(line) &&
              !centralPaletteFiles.contains(path)) {
            violations.add('$path:${index + 1}: literal Color');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Use ColorScheme/AppThemeColors, or document a narrowly scoped '
            'objective contrast exception:\n${violations.join('\n')}',
      );
    },
  tags: ['regression']);
}
