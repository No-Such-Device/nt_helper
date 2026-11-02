import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/patch_map_device.dart';
import 'patch_map_editor_test.dart' show settleCompanion;

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [1280.0, 430.0, 360.0]) {
      for (final scale in [1.0, 1.25]) {
        testWidgets(
          'AUX rows align and have equal section gaps: $brightness, $width, $scale',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            await SettingsService().init();
            await tester.binding.setSurfaceSize(Size(width, 820));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final device = PatchMapDevice();
            for (var bus = 9; bus <= 26; bus++) {
              device.map = device.map.addAux(bus);
            }
            final theme = AppTheme.build(
              seedColor: AppTheme.defaultSeedColor,
              brightness: brightness,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: PatchMapEditor(
                    transport: device,
                    slotIndex: 0,
                    watchInterval: null,
                    download: (_) async => File(
                      'test/fixtures/patch_map/patch_helper.lua',
                    ).readAsBytesSync(),
                  ),
                ),
              ),
            );
            await settleCompanion(tester);
            if (width < 1050) {
              await tester.tap(find.widgetWithText(TextButton, 'Sockets'));
              await tester.pumpAndSettle();
            }
            final compact = width < 1050;
            final markerWidth = compact ? 48.0 : 30.0;
            final markerHeight = compact ? 48.0 : 36.0;
            Finder aux(int bus) => find.byKey(ValueKey('aux-dot-$bus'));
            Rect auxRect(int bus) => tester.getRect(aux(bus));
            Rect socket(int id) =>
                tester.getRect(find.byKey(ValueKey('socket-dot-$id')));
            expect(auxRect(9).size, Size(markerWidth, markerHeight));
            expect(auxRect(16).top, auxRect(9).top);
            expect(auxRect(16).left, auxRect(9).left + 7 * markerWidth);
            expect(auxRect(17).left, auxRect(9).left);
            expect(auxRect(17).top, auxRect(9).top + markerHeight);
            expect(auxRect(25).left, auxRect(9).left);
            expect(auxRect(25).top, auxRect(9).top + markerHeight * 2);
            final inputOutputGap = socket(12).left - socket(3).right;
            final outputAuxGap = auxRect(9).left - socket(13).right;
            expect(inputOutputGap, 16);
            expect(outputAuxGap, inputOutputGap);
            final auxCircle = tester.widget<Container>(
              find.byKey(const ValueKey('aux-circle-9')),
            );
            final decoration = auxCircle.decoration! as BoxDecoration;
            expect(decoration.color, isNull);
            expect(decoration.shape, BoxShape.circle);
            expect(
              decoration.border,
              Border.all(color: theme.colorScheme.onSurfaceVariant),
            );
            expect(
              tester.getRect(find.byKey(const ValueKey('aux-circle-9'))).top,
              tester.getRect(find.byKey(const ValueKey('socket-colour-0'))).top,
            );
            final auxNumber = tester.widget<Text>(
              find.descendant(of: aux(9), matching: find.text('9')),
            );
            final socketNumber = tester.widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('socket-dot-0')),
                matching: find.text('1'),
              ),
            );
            expect(auxNumber.style, socketNumber.style);
            final horizontal = find
                .ancestor(
                  of: aux(9),
                  matching: find.byType(SingleChildScrollView),
                )
                .first;
            await tester.drag(horizontal, const Offset(-1000, 0));
            await tester.pumpAndSettle();
            expect(aux(16).hitTestable(), findsOneWidget);
            if (compact) {
              await tester.drag(horizontal, const Offset(80, 0));
              await tester.pumpAndSettle();
            } else {
              await tester.drag(horizontal, const Offset(200, 0));
              await tester.pumpAndSettle();
            }
            await tester.ensureVisible(aux(9));
            await tester.pumpAndSettle();
            await tester.tap(aux(9));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<CompanionRecordRow>(
                    find.byType(CompanionRecordRow),
                  )
                  .singleWhere((row) => row.selected)
                  .record['bus'],
              9,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
