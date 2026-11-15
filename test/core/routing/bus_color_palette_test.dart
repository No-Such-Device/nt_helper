import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/bus_color_palette.dart';

void main() {
  group('BusColorPalette', () {
    test('base color is deterministic per bus', () {
      expect(BusColorPalette.baseColor(21), BusColorPalette.baseColor(21));
      expect(
        BusColorPalette.baseColor(21) == BusColorPalette.baseColor(22),
        isFalse,
        reason: 'adjacent buses should differ',
      );
    });

    test('empty wire is paler than the driven base (light mode)', () {
      final base = HSLColor.fromColor(BusColorPalette.baseColor(21));
      final neutral = ThemeData.light().colorScheme.outlineVariant;
      final empty = HSLColor.fromColor(
        BusColorPalette.empty(21, neutralColor: neutral),
      );
      expect(empty.lightness, greaterThan(base.lightness));
      expect(empty.saturation, lessThan(base.saturation));
    });

    test('session 0 equals the base color; later sessions differ', () {
      expect(
        BusColorPalette.sessionColor(21, 0),
        BusColorPalette.baseColor(21),
      );
      expect(
        BusColorPalette.sessionColor(21, 1) ==
            BusColorPalette.sessionColor(21, 0),
        isFalse,
        reason: 'a Replace must visibly change the tone',
      );
    });

    test('withAddDepth(0) is a no-op and deeper adds darken (denser)', () {
      final session = BusColorPalette.sessionColor(21, 0);
      expect(BusColorPalette.withAddDepth(session, 0), session);

      final d1 = HSLColor.fromColor(BusColorPalette.withAddDepth(session, 1));
      final d3 = HSLColor.fromColor(BusColorPalette.withAddDepth(session, 3));
      final base = HSLColor.fromColor(session);
      // More signal -> denser: darker and more saturated.
      expect(d1.lightness, lessThan(base.lightness));
      expect(d3.lightness, lessThan(d1.lightness));
      expect(d3.saturation, greaterThanOrEqualTo(d1.saturation));
    });
  });
}
