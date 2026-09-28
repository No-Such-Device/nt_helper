import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import '../../support/patch_map_device.dart';

Future<void> settleCompanion(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (i >= 3 &&
        find.byTooltip('Up to date').evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Lua action dialog adds each model, cancels without writes and keeps layout stable',
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
      final device = PatchMapDevice();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child!),
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
            body: PatchMapEditor(
              transport: device,
              slotIndex: 0,
              download: (_) async => File(
                'test/fixtures/patch_map/patch_helper.lua',
              ).readAsBytesSync(),
            ),
          ),
        ),
      );
      await settleCompanion(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Add expander'), findsOneWidget);
      final action = find.byTooltip('Add expander');
      final header = tester.getRect(find.text('Socket'));
      expect(tester.getRect(action).right, greaterThan(1200));
      expect(tester.getRect(find.byTooltip('Up to date')).left, lessThan(60));
      for (final model in PatchMap.expanderTypes) {
        expect(find.text(model), findsNothing);
      }
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Socket')), header);
      expect(
        tester.getSemantics(find.text('Add expander')).flagsCollection.isHeader,
        isTrue,
      );
      for (final model in PatchMap.expanderTypes) {
        expect(find.widgetWithText(TextButton, model), findsOneWidget);
      }
      if (Platform.environment['CAPTURE_PATCH_EDITOR'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/evidence/patch-helper/expander-dialog.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(device.map.expanders, isEmpty);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(device.map.expanders, isEmpty);
      for (var model = 0; model < PatchMap.expanderTypes.length; model++) {
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(TextButton, PatchMap.expanderTypes[model]),
        );
        await settleCompanion(tester);
        expect(device.map.expanders.length, model + 1);
        expect(device.map.expanders.last.type, model);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.getRect(find.text('Socket')), header);
      }
      while (device.map.expanders.length < PatchMap.maxNewExpanders) {
        device.map = device.map.addExpander(0);
      }
      device.revision++;
      await tester.pump(const Duration(seconds: 1));
      await settleCompanion(tester);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: action, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unnamed socket dots follow automatic edits and NT colour changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final device = PatchMapDevice();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatchMapEditor(
              transport: device,
              slotIndex: 0,
              download: (_) async => File(
                'test/fixtures/patch_map/patch_helper.lua',
              ).readAsBytesSync(),
            ),
          ),
        ),
      );
      await settleCompanion(tester);
      final header = tester.getRect(find.text('Socket'));
      Color? dotColour() =>
          (tester
                      .widget<Container>(
                        find.byKey(const ValueKey('socket-colour-0')),
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(dotColour(), isNull);
      final selector = find.descendant(
        of: find.byType(PatchMapRow).first,
        matching: find.byType(DropdownButton<int>),
      );
      tester.widget<DropdownButton<int>>(selector).onChanged!(8);
      await tester.pump();
      await tester.pump();
      expect(dotColour(), patchCableColours[8]);
      expect(tester.getRect(find.text('Socket')), header);
      await settleCompanion(tester);
      expect(device.map.connections[0].colour, 8);
      expect(device.map.connections[0].destination, isEmpty);
      device.changeProperty(1, 4);
      await tester.pump(const Duration(seconds: 1));
      await settleCompanion(tester);
      expect(dotColour(), patchCableColours[4]);
      expect(tester.getRect(find.text('Socket')), header);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
      final rootBoundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              RepaintBoundary(key: rootBoundary, child: child!),
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
                  watchInterval: const Duration(seconds: 1),
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
      expect(find.text('Load SD companion'), findsNothing);
      await settleCompanion(tester);
      expect(find.text('Sockets'), findsOneWidget);
      expect(find.text('Patch title'), findsNothing);
      expect(find.text('Reload companion & map'), findsNothing);
      expect(find.textContaining('Save the preset'), findsNothing);
      expect(find.byTooltip('Up to date'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Up to date'), findsOneWidget);

      device.changeProperty(0, 36);
      await tester.pump(const Duration(seconds: 1));
      await settleCompanion(tester);
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
      final stableHeader = tester.getRect(find.text('Socket'));
      final destination = find.widgetWithText(TextField, 'Plaits out');
      await tester.tap(destination);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(modifier);
      final destinationField = tester.widget<TextField>(destination);
      expect(
        destinationField.controller!.selection,
        TextSelection(baseOffset: 0, extentOffset: 'Plaits out'.length),
      );
      await tester.enterText(destination, 'Rings odd');
      await tester.pump();
      expect(find.byTooltip('Syncing'), findsOneWidget);
      expect(tester.getRect(find.text('Socket')), stableHeader);
      expect(device.map.connections.first.destination, 'Plaits out');
      await settleCompanion(tester);
      expect(device.map.connections.first.destination, 'Rings odd');
      expect(find.byTooltip('Syncing'), findsNothing);
      final nextRow = find.byType(PatchMapRow).at(1);
      final stableRow = tester.getRect(nextRow);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '13');
      await tester.pumpAndSettle();
      expect(
        find.text('Tag must be an integer from 1 to 12, or blank.'),
        findsOneWidget,
      );
      expect(tester.getRect(nextRow), stableRow);
      expect(device.map.connections.first.tag, 0);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '7');
      await settleCompanion(tester);
      expect(device.map.connections.first.tag, 7);
      await tester.enterText(find.byKey(const ValueKey('tag-0')), '');
      await settleCompanion(tester);
      expect(device.map.connections.first.tag, 0);

      // Pausing the app stops periodic reads; resuming receives later changes.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final pausedFrames = device.frames.length;
      await tester.pump(const Duration(seconds: 3));
      expect(device.frames.length, pausedFrames);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

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
      await tester.tap(find.text('Sockets'));
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
      await tester.tap(find.byKey(const ValueKey('socket-dot-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Rings odd'),
        'Updated destination',
      );
      await tester.pump();
      final compactHeader = tester.getRect(find.text('Socket'));
      device.changeProperty(2, 5);
      await tester.pump(const Duration(seconds: 1));
      await settleCompanion(tester);
      expect(
        find.widgetWithText(TextField, 'Updated destination'),
        findsOneWidget,
      );
      expect(
        device.map.connections[0].destination,
        'Updated destination',
        reason: tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((t) => t.message)
            .join('; '),
      );
      expect(find.text('Apply row'), findsNothing);
      expect(find.text('Discard edits'), findsNothing);
      expect(device.map.connections[35].tag, 5);
      expect(tester.getRect(find.text('Socket')), compactHeader);
      await settleCompanion(tester);
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      await tester.pumpAndSettle();
      final rename = find.byTooltip('Rename Expander 1 · NTX-8CV');
      await tester.ensureVisible(rename);
      await tester.tap(rename);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Expander 1'),
        'Draft expander',
      );
      device.changeProperty(2, 6);
      await tester.pump(const Duration(seconds: 1));
      await settleCompanion(tester);
      expect(find.widgetWithText(TextField, 'Draft expander'), findsOneWidget);
      expect(device.map.expanders.first.name, 'Draft expander');
      expect(find.text('Apply'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      final closedFrames = device.frames.length;
      await tester.pump(const Duration(seconds: 3));
      expect(device.frames.length, closedFrames);
    },
  );
}
