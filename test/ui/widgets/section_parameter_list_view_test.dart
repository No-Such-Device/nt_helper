import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/ui/widgets/section_parameter_list_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

const _paintBoundaryKey = ValueKey('section-parameter-list-paint-boundary');
const _performanceHeader = 'Performance Parameters (1)';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.15.0'));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'paints only light/dark $brightness section headers without geometry changes',
      (tester) async {
        await _setTestSurfaceSize(tester);
        final theme = AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: brightness,
        );
        final slot = _sectionedSlot();
        final cubit = _cubitFor(slot);

        await tester.pumpWidget(_host(theme: theme, cubit: cubit, slot: slot));
        await tester.pumpAndSettle();

        final expectedShade = theme.colorScheme.onSurface.withValues(
          alpha: 0.10,
        );
        final boundaryRect = tester.getRect(find.byKey(_paintBoundaryKey));
        final performanceRect = tester.getRect(
          _headerListTile(_performanceHeader),
        );
        final mainRect = tester.getRect(_headerListTile('Main'));

        for (final label in [_performanceHeader, 'Main', 'Advanced']) {
          final tile = tester.widget<ExpansionTile>(_expansionTile(label));
          expect(tile.backgroundColor, isNull);
          expect(tile.collapsedBackgroundColor, isNull);
          expect(_headerInkColor(tester, label), expectedShade);

          final rect = tester.getRect(_headerListTile(label));
          expect(rect.left, boundaryRect.left + 8);
          expect(rect.right, boundaryRect.right - 8);
          expect(rect.height, 56);

          final titleRect = tester.getRect(find.text(label));
          expect(titleRect.left, rect.left + 16);
          expect(titleRect.center.dy, closeTo(rect.center.dy, 0.01));
        }

        final mainContext = tester.element(find.text('Main'));
        final renderedTheme = Theme.of(mainContext);
        final mainStyle = DefaultTextStyle.of(mainContext).style;
        expect(
          mainStyle.fontSize,
          renderedTheme.textTheme.titleLarge?.fontSize,
        );
        expect(
          mainStyle.fontWeight,
          renderedTheme.textTheme.titleLarge?.fontWeight,
        );

        final performanceText = tester.widget<Text>(
          find.text(_performanceHeader),
        );
        expect(
          performanceText.style?.fontSize,
          renderedTheme.textTheme.titleMedium?.fontSize,
        );
        expect(performanceText.style?.fontWeight, FontWeight.bold);

        final captured = await _captureSurface(tester);
        addTearDown(captured.image.dispose);
        final expectedPaintAlpha = (0.10 * 255).round();

        for (final rect in [performanceRect, mainRect]) {
          expect(
            captured.alphaAt(Offset(rect.left + 2, rect.center.dy)),
            expectedPaintAlpha,
          );
          expect(
            captured.alphaAt(Offset(rect.right - 2, rect.center.dy)),
            expectedPaintAlpha,
          );
          expect(captured.alphaAt(Offset(rect.left - 2, rect.center.dy)), 0);
        }

        // The expanded body remains transparent immediately below each header;
        // the header shade must not become a parameter-row background.
        expect(
          captured.alphaAt(
            Offset(performanceRect.left + 2, performanceRect.bottom + 8),
          ),
          0,
        );
        expect(
          captured.alphaAt(Offset(mainRect.left + 2, mainRect.bottom + 8)),
          0,
        );

        final mainSize = mainRect.size;
        await tester.tap(find.text('Main'));
        await tester.pumpAndSettle();
        expect(tester.getSize(_headerListTile('Main')), mainSize);
        expect(_headerInkColor(tester, 'Main'), expectedShade);
        expect(find.text('Main level'), findsNothing);

        await tester.tap(find.text(_performanceHeader));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(_headerListTile(_performanceHeader)),
          performanceRect.size,
        );
        expect(_headerInkColor(tester, _performanceHeader), expectedShade);
      },
    );
  }

  testWidgets('preserves individual and expand-all section behavior', (
    tester,
  ) async {
    await _setTestSurfaceSize(tester);
    final slot = _sectionedSlot();
    final cubit = _cubitFor(slot);

    await tester.pumpWidget(
      _host(
        theme: AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: Brightness.light,
        ),
        cubit: cubit,
        slot: slot,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rate'), findsNWidgets(2));
    expect(find.text('Main level'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);
    expect(find.byTooltip('Collapse all'), findsOneWidget);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Main level'), findsNothing);
    expect(find.text('Shape'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Shape'), findsNothing);

    await tester.tap(find.text('Main'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Main level'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);

    await tester.tap(find.text(_performanceHeader));
    await tester.pumpAndSettle();
    expect(find.text('Rate'), findsOneWidget);
    await tester.tap(find.text(_performanceHeader));
    await tester.pumpAndSettle();
    expect(find.text('Rate'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('slot-editor-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Main level'), findsNothing);
    expect(find.text('Shape'), findsNothing);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.byTooltip('Expand all'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-editor-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Main level'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);
    expect(find.text('Rate'), findsNWidgets(2));
    expect(find.byTooltip('Collapse all'), findsOneWidget);
  });

  testWidgets('controller navigation retains bypass-only page behavior', (
    tester,
  ) async {
    await _setTestSurfaceSize(tester);
    await SettingsService().setStartPagesCollapsed(true);
    final slot = _sectionedSlot();
    final cubit = _cubitFor(slot);
    final controller = SectionParameterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        theme: AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: Brightness.dark,
        ),
        cubit: cubit,
        slot: slot,
        sectionController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Algorithm'), findsNothing);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Main level'), findsNothing);
    expect(find.text('Shape'), findsNothing);
    expect(find.byTooltip('Expand all'), findsOneWidget);

    controller.goToPage(7, 1);
    await tester.pumpAndSettle();
    expect(find.text('Main level'), findsNothing);
    expect(find.text('Shape'), findsOneWidget);
    expect(find.byTooltip('Collapse all'), findsOneWidget);

    // Page 2 contains only the host-owned Bypass parameter. It remains absent,
    // and navigating to it does not disturb the currently expanded section.
    controller.goToPage(7, 2);
    await tester.pumpAndSettle();
    expect(find.text('Algorithm'), findsNothing);
    expect(find.text('Main level'), findsNothing);
    expect(find.text('Shape'), findsOneWidget);

    controller.goToPage(7, 0);
    await tester.pumpAndSettle();
    expect(find.text('Rate'), findsNWidgets(2));
    expect(find.text('Main level'), findsOneWidget);
    expect(find.text('Shape'), findsNothing);
  });
}

Widget _host({
  required ThemeData theme,
  required DistingCubit cubit,
  required Slot slot,
  SectionParameterController? sectionController,
}) {
  return MaterialApp(
    theme: theme,
    home: BlocProvider<DistingCubit>.value(
      value: cubit,
      child: Scaffold(
        body: RepaintBoundary(
          key: _paintBoundaryKey,
          child: SectionParameterListView(
            slot: slot,
            slotIndex: 7,
            units: const [],
            pages: slot.pages,
            sectionController: sectionController,
          ),
        ),
      ),
    ),
  );
}

Future<void> _setTestSurfaceSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Finder _expansionTile(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(ExpansionTile))
    .first;

Finder _headerListTile(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first;

Color? _headerInkColor(WidgetTester tester, String label) {
  final inkFinder = find
      .descendant(of: _headerListTile(label), matching: find.byType(Ink))
      .first;
  final decoration = tester.widget<Ink>(inkFinder).decoration;
  expect(decoration, isA<ShapeDecoration>());
  return (decoration! as ShapeDecoration).color;
}

Future<_CapturedSurface> _captureSurface(WidgetTester tester) async {
  final finder = find.byKey(_paintBoundaryKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final origin = tester.getTopLeft(finder);
  final captured = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not capture widget pixels');
    return _CapturedSurface(image: image, bytes: data, origin: origin);
  });
  if (captured == null) throw StateError('Could not capture widget surface');
  return captured;
}

class _CapturedSurface {
  const _CapturedSurface({
    required this.image,
    required this.bytes,
    required this.origin,
  });

  final ui.Image image;
  final ByteData bytes;
  final Offset origin;

  int alphaAt(Offset globalOffset) {
    final x = (globalOffset.dx - origin.dx).floor();
    final y = (globalOffset.dy - origin.dy).floor();
    final byteOffset = (y * image.width + x) * 4;
    return bytes.getUint8(byteOffset + 3);
  }
}

DistingCubit _cubitFor(Slot slot) {
  final cubit = _MockDistingCubit();
  final manager = _MockDistingMidiManager();
  final state = DistingState.synchronized(
    disting: manager,
    distingVersion: '1.15.0',
    firmwareVersion: FirmwareVersion('1.15.0'),
    presetName: 'Header shade test',
    algorithms: const [],
    slots: [slot],
    unitStrings: const [],
  );
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  return cubit;
}

Slot _sectionedSlot() {
  const fixtures = [
    (name: 'Bypass', min: 0, max: 1, value: 0, perfPage: 0),
    (name: 'Rate', min: 0, max: 100, value: 50, perfPage: 1),
    (name: 'Main level', min: 0, max: 100, value: 75, perfPage: 0),
    (name: 'Shape', min: 0, max: 10, value: 4, perfPage: 0),
  ];

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: 3,
      guid: 'header-test',
      name: 'Header Test',
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: 3,
      pages: [
        ParameterPage(name: 'Main', parameters: const [1, 2]),
        ParameterPage(name: 'Advanced', parameters: const [3]),
        ParameterPage(name: 'Algorithm', parameters: const [0]),
      ],
    ),
    parameters: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterInfo(
          algorithmIndex: 3,
          parameterNumber: index,
          min: fixtures[index].min,
          max: fixtures[index].max,
          defaultValue: fixtures[index].value,
          unit: 0,
          name: fixtures[index].name,
          powerOfTen: 0,
        ),
    ],
    values: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValue(
          algorithmIndex: 3,
          parameterNumber: index,
          value: fixtures[index].value,
        ),
    ],
    enums: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterEnumStrings(
          algorithmIndex: 3,
          parameterNumber: index,
          values: index == 0 ? const ['Off', 'On'] : const [],
        ),
    ],
    mappings: [
      for (var index = 0; index < fixtures.length; index++)
        Mapping(
          algorithmIndex: 3,
          parameterNumber: index,
          packedMappingData: PackedMappingData.filler().copyWith(
            perfPageIndex: fixtures[index].perfPage,
          ),
        ),
    ],
    valueStrings: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValueString(
          algorithmIndex: 3,
          parameterNumber: index,
          value: index == 0 ? 'Off' : '',
        ),
    ],
  );
}
