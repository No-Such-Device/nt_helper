import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import '../../support/patch_map_device.dart';

Future<void> settleCompanion(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.text('Waiting for the NT…').evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'SD Lua table, minimap selection, pending edits and narrow layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final font = File('/System/Library/Fonts/SFNS.ttf');
      if (font.existsSync()) {
        final loader = FontLoader('Evidence');
        loader.addFont(
          Future.value(ByteData.sublistView(font.readAsBytesSync())),
        );
        await loader.load();
      }
      final device = PatchMapDevice();
      device.map = device.map
          .addExpander(0)
          .addExpander(1)
          .withConnection(
            PatchConnection(socket: 0, destination: 'Plaits out', colour: 4),
          );
      device.map = device.map
          .withConnection(
            PatchConnection(
              socket: 12,
              destination: 'Mimeophon L',
              colour: 8,
              tag: 1,
              group: 'Effects',
            ),
          )
          .withConnection(
            PatchConnection(
              socket: 20,
              destination: 'Plaits V/oct',
              colour: 9,
              tag: 2,
              group: 'Voice',
            ),
          )
          .withConnection(
            PatchConnection(
              socket: 28,
              destination: 'Plaits trig',
              colour: 6,
              tag: 3,
              group: 'Voice',
            ),
          );
      final iconFont = File(
        '/Users/nealsanche/fvm/default/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (iconFont.existsSync()) {
        final loader = FontLoader('MaterialIcons');
        loader.addFont(
          Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
        );
        await loader.load();
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme:
              AppTheme.build(
                seedColor: AppTheme.defaultSeedColor,
                brightness: Brightness.dark,
              ).copyWith(
                textTheme: ThemeData.dark().textTheme.apply(
                  fontFamily: 'Evidence',
                ),
              ),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: AppTheme.build(
                  seedColor: AppTheme.defaultSeedColor,
                  brightness: Brightness.dark,
                ).colorScheme.surface,
                child: PatchMapEditor(
                  transport: device,
                  slotIndex: 0,
                  download: (_) async => File(
                    'test/fixtures/patch_map/patch_helper.lua',
                  ).readAsBytesSync(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Load SD companion'), findsOneWidget);
      await tester.tap(find.text('Load SD companion'));
      await settleCompanion(tester);
      expect(find.text('Socket minimap'), findsOneWidget);
      final semantics = tester.ensureSemantics();

      await tester.tap(find.byKey(const ValueKey('socket-dot-35')));
      await tester.pumpAndSettle();
      final selected = tester
          .widgetList<PatchMapRow>(find.byType(PatchMapRow))
          .singleWhere((row) => row.selected);
      expect(selected.row.socket, 35);
      expect(tester.getRect(find.text('E2 Out 8').first).bottom, lessThan(820));
      expect(find.bySemanticsLabel('E2 Out 8, Unused, None'), findsOneWidget);
      semantics.dispose();
      if (Platform.environment['CAPTURE_PATCH_EDITOR'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/evidence/patch-helper/editor-desktop.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const ValueKey('socket-dot-0')));
      await tester.pumpAndSettle();
      final destination = find.widgetWithText(TextField, 'Plaits out');
      await tester.enterText(destination, 'Rings odd');
      await tester.pump();
      expect(find.text('1 rows with unsent edits'), findsOneWidget);
      expect(device.map.connections.first.destination, 'Plaits out');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleCompanion(tester);
      expect(device.map.connections.first.destination, 'Rings odd');
      expect(find.text('1 rows with unsent edits'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '13');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Tag must be an integer from 1 to 12, or blank.'),
        findsOneWidget,
      );
      expect(device.map.connections.first.tag, 0);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleCompanion(tester);
      expect(device.map.connections.first.tag, 7);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleCompanion(tester);
      expect(device.map.connections.first.tag, 0);

      await tester.binding.setSurfaceSize(const Size(1280, 420));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('desktop-minimap-scroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('socket-dot-35')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('socket-dot-35'))).bottom,
        lessThan(420),
      );

      await tester.binding.setSurfaceSize(const Size(707, 853));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Socket minimap'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('socket-dot-0'))),
        const Size(48, 48),
      );
      if (Platform.environment['CAPTURE_PATCH_EDITOR'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/evidence/patch-helper/editor-compact.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
