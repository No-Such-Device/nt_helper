import 'dart:ui' show SemanticsAction;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/theme_seed_picker.dart';

void main() {
  test('formats seed colours as opaque RGB hex', () {
    expect(formatThemeColorHex(const Color(0x12345678)), '#345678');
  });

  testWidgets('exposes an accessible one-line picker and reset button', (
    tester,
  ) async {
    var selected = const Color(0xFF6750A4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeSeedPicker(
            value: selected,
            defaultValue: AppTheme.defaultSeedColor,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Theme Colour'), findsOneWidget);
    expect(find.text('#6750A4'), findsOneWidget);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('theme-seed-swatch')),
    );
    expect(semantics.label, 'Choose theme colour. Current colour #6750A4');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.byTooltip('Reset theme colour'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reset-theme-seed')));
    await tester.pump();
    expect(selected, AppTheme.defaultSeedColor);
  });

  testWidgets('selects a Material colour from the dialog', (tester) async {
    Color? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeSeedPicker(
            value: AppTheme.defaultSeedColor,
            defaultValue: AppTheme.defaultSeedColor,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose theme colour'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Theme Colour'), findsOneWidget);

    await tester.tap(find.byTooltip('Purple'));
    await tester.pump();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(selected, Colors.purple.shade500);
  });
}
