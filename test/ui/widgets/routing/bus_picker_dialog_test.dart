import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/bus_picker_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';
import 'package:nt_helper/models/device_io_profile.dart';

const _stoppedSelectionAnimation = AlwaysStoppedAnimation<double>(1);

Widget _testApp({required Widget home, bool disableAnimations = true}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: home,
  );
}

void main() {
  testWidgets(
    'bus picker displays all supplied buses and marks current bus selected',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _testApp(
          home: Scaffold(
            body: BusPickerDialog(
              portLabel: 'Output',
              selectionAnimation: _stoppedSelectionAnimation,
              model: BusSelectionModel.fromProfile(
                deviceIoProfile: DeviceIoProfile.distingLegacy,
                currentValue: 13,
                minimum: 11,
                maximum: 14,
                allowNone: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('I11'), findsOneWidget);
      expect(find.text('I12'), findsOneWidget);
      expect(find.text('O1'), findsOneWidget);
      expect(find.text('O2'), findsOneWidget);
      expect(find.bySemanticsLabel('Current bus O1'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Current bus O1'));
      // ignore: deprecated_member_use
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(find.bySemanticsLabel('Route to O2'), findsOneWidget);
      expect(find.textContaining('Currently:'), findsNothing);

      semantics.dispose();
    },
  );

  testWidgets('bus picker lays out bus groups in rows of eight', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 700));

    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: BusPickerDialog(
            portLabel: 'Input',
            selectionAnimation: _stoppedSelectionAnimation,
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: DeviceIoProfile.distingLegacy,
              currentValue: 1,
              minimum: 1,
              maximum: 12,
              allowNone: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstRowY = tester.getCenter(find.text('I1')).dy;
    expect(tester.getCenter(find.text('I8')).dy, firstRowY);
    expect(tester.getCenter(find.text('I9')).dy, greaterThan(firstRowY));

    final dialogRect = tester.getRect(
      find.byKey(const Key('bus-picker-dialog-surface')),
    );
    final firstTileRect = tester.getRect(
      find.ancestor(of: find.text('I1'), matching: find.byType(InkWell)),
    );
    final lastTileRect = tester.getRect(
      find.ancestor(of: find.text('I8'), matching: find.byType(InkWell)),
    );
    final leadingSpace = firstTileRect.left - dialogRect.left;
    final trailingSpace = dialogRect.right - lastTileRect.right;
    expect(trailingSpace, greaterThan(leadingSpace));
  });

  testWidgets('bus picker reflows to rows of four on a narrow screen', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 640));

    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: BusPickerDialog(
            portLabel: 'Input',
            selectionAnimation: _stoppedSelectionAnimation,
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: DeviceIoProfile.distingLegacy,
              currentValue: 1,
              minimum: 1,
              maximum: 12,
              allowNone: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstRowY = tester.getCenter(find.text('I1')).dy;
    expect(tester.getCenter(find.text('I4')).dy, firstRowY);
    expect(tester.getCenter(find.text('I5')).dy, greaterThan(firstRowY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrollbar stays in a gutter beside the eighth column', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: BusPickerDialog(
            portLabel: 'Input',
            selectionAnimation: _stoppedSelectionAnimation,
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: DeviceIoProfile.distingExtended,
              currentValue: 1,
              minimum: 1,
              maximum: 64,
              allowNone: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(
      find.byKey(const Key('bus-picker-dialog-surface')),
    );
    final scrollbarFinder = find.byType(Scrollbar);
    expect(scrollbarFinder, findsOneWidget);
    final scrollbarRect = tester.getRect(scrollbarFinder);
    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    final eighthTileRect = tester.getRect(
      find.ancestor(of: find.text('I8'), matching: find.byType(InkWell)),
    );

    expect(dialogRect.right - scrollbarRect.right, closeTo(4, 0.01));
    expect(scrollbar.thickness, 6);
    expect(
      scrollbarRect.right - eighthTileRect.right,
      greaterThanOrEqualTo(20),
    );
  });

  testWidgets('selected bus outline keeps fading from transparent to bright', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selectionController = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 1400),
      value: 1,
    )..repeat(reverse: true);
    try {
      await tester.pumpWidget(
        _testApp(
          disableAnimations: true,
          home: Scaffold(
            body: BusPickerDialog(
              portLabel: 'Output',
              selectionAnimation: selectionController,
              model: BusSelectionModel.fromProfile(
                deviceIoProfile: DeviceIoProfile.distingLegacy,
                currentValue: 13,
                minimum: 13,
                maximum: 14,
                allowNone: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Color borderColor(String semanticsLabel) {
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.bySemanticsLabel(semanticsLabel),
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.shape! as RoundedRectangleBorder).side.color;
      }

      Color selectionOutlineColor() {
        final outline = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.bySemanticsLabel('Current bus O1'),
            matching: find.byKey(const Key('selected-bus-outline')),
          ),
        );
        return (outline.decoration as BoxDecoration).border!.top.color;
      }

      final selectedBaseOutline = borderColor('Current bus O1');
      final unselectedBefore = borderColor('Route to O2');
      await tester.pump(const Duration(milliseconds: 1400));

      expect(selectionOutlineColor().a, 0);
      expect(borderColor('Current bus O1'), selectedBaseOutline);
      expect(borderColor('Route to O2'), unselectedBefore);

      await tester.pump(const Duration(milliseconds: 1400));

      expect(selectionOutlineColor().a, closeTo(1, 0.00001));

      await tester.pump(const Duration(milliseconds: 6300));

      expect(selectionOutlineColor().a, isNot(1));
    } finally {
      selectionController.dispose();
      semantics.dispose();
    }
  });

  testWidgets('bus picker scrolls current bus near vertical center', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(440, 360));

    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: BusPickerDialog(
            portLabel: 'Output',
            selectionAnimation: _stoppedSelectionAnimation,
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: DeviceIoProfile.distingExtended,
              currentValue: 50,
              minimum: 1,
              maximum: 64,
              allowNone: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    final selectedY = tester.getCenter(find.text('A30')).dy;
    expect(selectedY, greaterThan(dialogRect.top + dialogRect.height * 0.30));
    expect(selectedY, lessThan(dialogRect.top + dialogRect.height * 0.80));
  });

  testWidgets('bus choices can be selected with Tab and Enter', (tester) async {
    int? selected;
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: DeviceIoProfile.distingLegacy,
      currentValue: 13,
      minimum: 13,
      maximum: 14,
      allowNone: false,
    );

    await tester.pumpWidget(
      _testApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showDialog<int>(
                context: context,
                builder: (context) => BusPickerDialog(
                  portLabel: 'Output',
                  model: model,
                  selectionAnimation: _stoppedSelectionAnimation,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 14);
  });

  testWidgets('keyboard traversal starts at the current bus', (tester) async {
    int? selected;
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: DeviceIoProfile.distingExtended,
      currentValue: 50,
      minimum: 1,
      maximum: 64,
      allowNone: false,
    );

    await tester.pumpWidget(
      _testApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showDialog<int>(
                context: context,
                builder: (context) => BusPickerDialog(
                  portLabel: 'Output',
                  model: model,
                  selectionAnimation: _stoppedSelectionAnimation,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 51);
  });
}
