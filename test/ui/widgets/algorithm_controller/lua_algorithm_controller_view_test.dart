import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/lua_algorithm_controller_view.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

const _sectionHeaderSource = r'''
return {
  version = 1,
  title = "Header treatment",
  root = ui.column {
    gap = 16,
    padding = 16,
    children = {
      ui.section {
        title = "Main section",
        subtitle = "Primary controls",
        children = {
          ui.toggle {
            label = "Voice enabled",
            parameter = nt.parameter("1:Enable").number
          },
          ui.section {
            title = "Nested section",
            subtitle = "Nested controls",
            children = {
              ui.text { text = "Nested content" }
            }
          }
        }
      },
      ui.section {
        title = "Second section",
        subtitle = "Secondary controls",
        children = {
          ui.text { text = "Second content" }
        }
      }
    }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDistingCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cubit = MockDistingCubit();
    when(() => cubit.state).thenReturn(const DistingState.initial());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(
      () => cubit.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
  });

  test('section state disposes its expansion controllers', () {
    final sectionState = AlgorithmControllerSectionController(
      initiallyCollapsed: false,
    );
    sectionState.synchronizeSections(const [
      (path: 'root/0', title: 'First section'),
    ]);
    final expansionController = sectionState.controllerFor('root/0');

    sectionState.dispose();

    expect(() => expansionController.addListener(() {}), throwsFlutterError);
  });

  testWidgets('section state disposes controllers removed by a new document', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final sectionState = AlgorithmControllerSectionController(
      initiallyCollapsed: false,
    );
    sectionState.synchronizeSections(const [
      (path: 'root/0', title: 'Removed section'),
    ]);
    final expansionController = sectionState.controllerFor('root/0');

    sectionState.synchronizeSections(const []);
    await tester.pump();

    expect(() => expansionController.addListener(() {}), throwsFlutterError);
    sectionState.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'shades only $brightness controller headers without changing geometry',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final theme = AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: brightness,
        );

        await tester.pumpWidget(
          _host(cubit, _slot(), _sectionHeaderSource, theme: theme),
        );
        await tester.pumpAndSettle();

        final expectedShade = theme.colorScheme.onSurface.withValues(
          alpha: 0.10,
        );
        for (final path in ['root/0', 'root/0/1', 'root/1']) {
          final tile = tester.widget<ExpansionTile>(_sectionTile(path));
          expect(tile.backgroundColor, isNull);
          expect(tile.collapsedBackgroundColor, isNull);
          expect(_sectionHeaderInkColor(tester, path), expectedShade);
        }

        final mainTile = tester.widget<ExpansionTile>(_sectionTile('root/0'));
        expect(
          mainTile.key,
          const ValueKey('algorithm-controller-section:root/0'),
        );
        expect(
          mainTile.tilePadding,
          const EdgeInsets.symmetric(horizontal: 16),
        );
        expect(
          mainTile.childrenPadding,
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
        );
        expect(
          mainTile.shape,
          const RoundedRectangleBorder(side: BorderSide.none),
        );
        expect(
          mainTile.collapsedShape,
          const RoundedRectangleBorder(side: BorderSide.none),
        );
        expect(
          tester
              .widget<Card>(
                find
                    .ancestor(
                      of: _sectionTile('root/0'),
                      matching: find.byType(Card),
                    )
                    .first,
              )
              .clipBehavior,
          Clip.antiAlias,
        );

        final mainHeaderRect = tester.getRect(_sectionHeader('root/0'));
        expect(mainHeaderRect.height, 72);
        final titleRect = tester.getRect(find.text('Main section'));
        final subtitleRect = tester.getRect(find.text('Primary controls'));
        expect(titleRect.left, mainHeaderRect.left + 16);
        expect(subtitleRect.left, mainHeaderRect.left + 16);
        expect(titleRect.top, lessThan(subtitleRect.top));

        final renderedTheme = Theme.of(
          tester.element(find.text('Main section')),
        );
        final title = tester.widget<Text>(find.text('Main section'));
        expect(
          title.style?.fontSize,
          renderedTheme.textTheme.titleLarge?.fontSize,
        );
        expect(
          title.style?.fontWeight,
          renderedTheme.textTheme.titleLarge?.fontWeight,
        );
        final subtitle = tester.widget<Text>(find.text('Primary controls'));
        expect(
          subtitle.style?.fontSize,
          renderedTheme.textTheme.bodySmall?.fontSize,
        );
        expect(
          subtitle.style?.fontWeight,
          renderedTheme.textTheme.bodySmall?.fontWeight,
        );
        expect(
          subtitle.style?.color,
          renderedTheme.colorScheme.onSurfaceVariant,
        );

        final toggle = find.byType(SwitchListTile);
        expect(toggle, findsOneWidget);
        expect(
          ListTileTheme.of(tester.element(toggle)).tileColor,
          isNull,
          reason: 'the controller header shade must not tint toggle rows',
        );
        expect(find.text('Voice enabled'), findsOneWidget);
        expect(find.text('Nested content'), findsOneWidget);
        expect(find.text('Second content'), findsOneWidget);

        await tester.tap(toggle);
        await tester.pump();
        verify(
          () => cubit.updateParameterValue(
            algorithmIndex: 2,
            parameterNumber: 1,
            value: 0,
            userIsChangingTheValue: false,
          ),
        ).called(1);

        final expandedHeaderSize = mainHeaderRect.size;
        await tester.tap(find.text('Main section'));
        await tester.pumpAndSettle();

        expect(tester.getSize(_sectionHeader('root/0')), expandedHeaderSize);
        expect(_sectionHeaderInkColor(tester, 'root/0'), expectedShade);
        expect(find.text('Main section'), findsOneWidget);
        expect(find.text('Primary controls'), findsOneWidget);
        expect(find.text('Voice enabled'), findsNothing);
        expect(find.text('Nested section'), findsNothing);
        expect(find.text('Second content'), findsOneWidget);
      },
    );
  }

  testWidgets('re-evaluates Lua when a new immutable Slot arrives', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "Reactive controller",
  root = ui.text {
    text = "Snapshot value " .. nt.parameter("1:Steps").value
  }
}
''';
    var sourceLoads = 0;
    Future<String> sourceLoader(String _) async {
      sourceLoads += 1;
      return source;
    }

    await tester.pumpWidget(
      _host(cubit, _slot(steps: 16), source, sourceLoader: sourceLoader),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snapshot value 16'), findsOneWidget);
    expect(sourceLoads, 1);

    await tester.pumpWidget(
      _host(cubit, _slot(steps: 9), source, sourceLoader: sourceLoader),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snapshot value 16'), findsNothing);
    expect(find.text('Snapshot value 9'), findsOneWidget);
    expect(sourceLoads, 1);
  });

  testWidgets('XY pad follows values from a new immutable Slot', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(steps: 16), source));
    await tester.pumpAndSettle();
    expect(find.text('X 16 · Y 4'), findsOneWidget);

    await tester.pumpWidget(_host(cubit, _slot(steps: 99), source));
    await tester.pumpAndSettle();
    expect(find.text('X 16 · Y 4'), findsNothing);
    expect(find.text('X 32 · Y 4'), findsOneWidget);
  });

  testWidgets('XY pad stays a fixed desktop width in a wide editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 1
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    expect(tester.getSize(pad), const Size.square(480));
  });

  testWidgets('XY pad shrinks without overflow in a narrow editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 1
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    expect(tester.getSize(pad), const Size.square(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'piano note mask is text-free and toggles exact pitch parameters',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      const source = r'''
return {
  version = 1,
  title = "Note mask",
  root = ui.note_mask {
    label = "Allowed notes",
    layout = "piano",
    notes = {
      { label = "C", parameter = 5, pitch_class = 0 },
      { label = "C sharp", parameter = 6, pitch_class = 1 },
      { label = "F sharp", parameter = 7, pitch_class = 6 }
    }
  }
}
''';

      await tester.pumpWidget(
        _host(cubit, _noteMaskSlot(c: 1, cSharp: 0, fSharp: 1), source),
      );
      await tester.pumpAndSettle();

      expect(find.text('C'), findsNothing);
      expect(find.text('C sharp'), findsNothing);
      expect(find.text('F sharp'), findsNothing);

      final c = find.byKey(
        const ValueKey('algorithm-controller-note-mask:Allowed notes:pitch-0'),
      );
      final cSharp = find.byKey(
        const ValueKey('algorithm-controller-note-mask:Allowed notes:pitch-1'),
      );
      final d = find.byKey(
        const ValueKey('algorithm-controller-note-mask:Allowed notes:pitch-2'),
      );
      final fSharp = find.byKey(
        const ValueKey('algorithm-controller-note-mask:Allowed notes:pitch-6'),
      );
      expect(c, findsOneWidget);
      expect(cSharp, findsOneWidget);
      expect(d, findsOneWidget);
      expect(fSharp, findsOneWidget);
      expect(tester.getCenter(cSharp).dy, lessThan(tester.getCenter(c).dy));
      expect(
        tester.getCenter(cSharp).dx,
        inInclusiveRange(tester.getCenter(c).dx, tester.getCenter(d).dx),
      );

      final cSemantics = tester
          .getSemantics(
            find.byWidgetPredicate(
              (widget) => widget is Semantics && widget.properties.label == 'C',
            ),
          )
          .getSemanticsData();
      expect(cSemantics.flagsCollection.isToggled, Tristate.isTrue);
      expect(cSemantics.value, 'Included');

      await tester.tap(cSharp);
      await tester.pump();

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 2,
          parameterNumber: 6,
          value: 1,
          userIsChangingTheValue: false,
        ),
      ).called(1);

      clearInteractions(cubit);
      await tester.tap(d);
      await tester.pump();
      verifyNever(
        () => cubit.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      );

      semanticsHandle.dispose();
    },
  );

  testWidgets('note mask follows a new immutable Slot snapshot', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "Note mask",
  root = ui.note_mask {
    label = "Allowed notes",
    layout = "piano",
    notes = {
      { label = "C", parameter = 5, pitch_class = 0 }
    }
  }
}
''';
    Future<String> sourceLoader(String _) async => source;
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(cubit, _noteMaskSlot(c: 0), source, sourceLoader: sourceLoader),
    );
    await tester.pumpAndSettle();
    ({Tristate toggled, String value}) cState() {
      final data = tester
          .getSemantics(
            find.byWidgetPredicate(
              (widget) => widget is Semantics && widget.properties.label == 'C',
            ),
          )
          .getSemanticsData();
      return (toggled: data.flagsCollection.isToggled, value: data.value);
    }

    expect(cState().toggled, Tristate.isFalse);
    expect(cState().value, 'Excluded');

    await tester.pumpWidget(
      _host(cubit, _noteMaskSlot(c: 1), source, sourceLoader: sourceLoader),
    );
    await tester.pumpAndSettle();
    expect(cState().toggled, Tristate.isTrue);
    expect(cState().value, 'Included');

    semanticsHandle.dispose();
  });

  testWidgets('slider and button actions write through DistingCubit', (
    tester,
  ) async {
    const source = r'''
local steps = nt.parameter("1:Steps")
return {
  version = 1,
  title = "Controls",
  root = ui.column {
    children = {
      ui.slider { label = "Steps", parameter = steps.number },
      ui.button {
        label = "Set twelve",
        action = {
          type = "set_parameter",
          parameter = steps.number,
          value = 12
        }
      }
    }
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(steps: 16), source));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 1);
    expect(slider.max, 32);
    slider.onChanged!(18);
    slider.onChangeEnd!(18);
    await tester.tap(find.text('Set twelve'));

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 18,
        userIsChangingTheValue: true,
      ),
    ).called(1);
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 18,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 12,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  testWidgets('pulse button writes high then clears in order', (tester) async {
    const source = r'''
return {
  version = 1,
  title = "Pulse",
  root = ui.button {
    label = "Trigger",
    action = {
      type = "pulse_parameter",
      parameter = nt.parameter("1:Enable").number
    }
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trigger'));
    await tester.pump();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 1,
        value: 1,
        userIsChangingTheValue: true,
      ),
    ).called(1);
    verifyNever(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 1,
        value: 0,
        userIsChangingTheValue: true,
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 1,
        value: 0,
        userIsChangingTheValue: true,
      ),
    ).called(1);
  });

  testWidgets(
    'controller ranges and writes stay inside live parameter limits',
    (tester) async {
      const source = r'''
local steps = nt.parameter("1:Steps")
return {
  version = 1,
  title = "Clamped controls",
  root = ui.slider {
    label = "Steps",
    parameter = steps.number,
    minimum = -100,
    maximum = 100
  }
}
''';

      await tester.pumpWidget(_host(cubit, _slot(steps: 16), source));
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 1);
      expect(slider.max, 32);
      slider.onChanged!(100);

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 2,
          parameterNumber: 2,
          value: 32,
          userIsChangingTheValue: true,
        ),
      ).called(1);
    },
  );

  testWidgets('canvas supplies a semantic description', (tester) async {
    const source = r'''
return {
  version = 1,
  title = "Drawing",
  root = ui.canvas {
    semantics_label = "Four pulses across sixteen steps",
    shapes = {
      ui.circle { x = 0.5, y = 0.5, radius = 0.1, fill = "primary" }
    }
  }
}
''';

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Four pulses across sixteen steps'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('canvas stays bounded in a wide editor', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const source = r'''
return {
  version = 1,
  title = "Drawing",
  root = ui.canvas {
    semantics_label = "Bounded drawing",
    aspect_ratio = 4,
    shapes = {
      ui.circle { x = 0.5, y = 0.5, radius = 0.1, fill = "primary" }
    }
  }
}
''';

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.bySemanticsLabel('Bounded drawing')),
      const Size(720, 180),
    );
    semantics.dispose();
  });

  testWidgets('canvas shrinks without overflow in a narrow editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const source = r'''
return {
  version = 1,
  title = "Drawing",
  root = ui.canvas {
    semantics_label = "Narrow drawing",
    aspect_ratio = 4,
    shapes = {
      ui.circle { x = 0.5, y = 0.5, radius = 0.1, fill = "primary" }
    }
  }
}
''';

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.bySemanticsLabel('Narrow drawing')),
      const Size(320, 80),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('XY pad supports pointer and keyboard parameter writes', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 2
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    final rect = tester.getRect(pad);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(
      Offset(rect.left + rect.width * 0.75, rect.top + rect.height * 0.25),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 24,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 3,
        value: 24,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    expect(find.text('X 24 · Y 24'), findsOneWidget);

    clearInteractions(cubit);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 25,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 3,
        value: 25,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  testWidgets('XY pad exposes accessible axes and resets on double tap', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 2
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    final xySemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Position' &&
          widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == 'Increase X',
              ) ==
              true &&
          widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == 'Increase Y',
              ) ==
              true &&
          widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == 'Reset Position to default',
              ) ==
              true,
    );
    expect(xySemantics, findsOneWidget);
    expect(find.bySemanticsLabel('Position'), findsOneWidget);
    expect(
      tester.getSemantics(xySemantics).getSemanticsData().value,
      'X 16, Y 4',
    );

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    final rect = tester.getRect(pad);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(
      Offset(rect.left + rect.width * 0.75, rect.top + rect.height * 0.25),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    clearInteractions(cubit);

    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 16,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 3,
        value: 4,
        userIsChangingTheValue: false,
      ),
    ).called(1);

    semanticsHandle.dispose();
  });

  testWidgets('XY pad keyboard follows visual Y direction', (tester) async {
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 2,
    invert_y = false
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    final rect = tester.getRect(pad);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(
      Offset(rect.left + rect.width * 0.75, rect.top + rect.height * 0.75),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('X 24 · Y 24'), findsOneWidget);
    clearInteractions(cubit);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 3,
        value: 23,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  testWidgets('XY pad safely paints a constant parameter range', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "XY controller",
  root = ui.xy_pad {
    label = "Position",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number
  }
}
''';

    await tester.pumpWidget(
      _host(cubit, _slot(pulsesMinimum: 4, pulsesMaximum: 4), source),
    );
    await tester.pumpAndSettle();

    final pad = find.byKey(
      const ValueKey('algorithm-controller-xy-pad:Position'),
    );
    expect(pad, findsOneWidget);
    expect(
      tester
          .widget<FocusableActionDetector>(
            find.ancestor(
              of: pad,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('choice renders NT strings and writes their raw value', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "Choice",
  root = ui.choice {
    label = "Channel state",
    parameter = nt.parameter("1:Enable").number
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(), source));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Off'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'On'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Off'));
    await tester.pump();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 1,
        value: 0,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  testWidgets('choice falls back to a slider for incomplete NT strings', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "Choice fallback",
  root = ui.choice {
    label = "Channel state",
    parameter = nt.parameter("1:Enable").number
  }
}
''';
    final slot = _slot();
    final incompleteEnums = [
      for (final enumStrings in slot.enums)
        enumStrings.parameterNumber == 1
            ? ParameterEnumStrings(
                algorithmIndex: 2,
                parameterNumber: 1,
                values: const ['Off', ''],
              )
            : enumStrings,
    ];

    await tester.pumpWidget(
      _host(cubit, slot.copyWith(enums: incompleteEnums), source),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('slider shows the NT-formatted current value', (tester) async {
    const source = r'''
return {
  version = 1,
  title = "Formatted",
  root = ui.slider {
    label = "Steps",
    parameter = nt.parameter("1:Steps").number
  }
}
''';

    await tester.pumpWidget(
      _host(cubit, _slot(stepsDisplay: 'sixteen steps'), source),
    );
    await tester.pumpAndSettle();

    expect(find.text('sixteen steps'), findsOneWidget);
  });

  testWidgets('slider formats raw values like the parameter editor', (
    tester,
  ) async {
    const source = r'''
return {
  version = 1,
  title = "Scaled",
  root = ui.slider {
    label = "Steps",
    parameter = nt.parameter("1:Steps").number
  }
}
''';

    await tester.pumpWidget(
      _host(
        cubit,
        _slot(steps: 16, stepsPowerOfTen: -1, stepsUnit: 1),
        source,
        units: const ['V'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.6 V'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.semanticFormatterCallback!(16), 'Steps 1.6 V');
  });

  testWidgets('double-tapping a slider resets its parameter to default', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    const source = r'''
return {
  version = 1,
  title = "Resettable",
  root = ui.slider {
    label = "Steps",
    parameter = nt.parameter("1:Steps").number
  }
}
''';

    await tester.pumpWidget(_host(cubit, _slot(steps: 9), source));
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider);
    final resetSemanticsFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == 'Reset Steps to default',
              ) ==
              true,
    );
    expect(resetSemanticsFinder, findsOneWidget);
    final semantics = tester
        .getSemantics(resetSemanticsFinder)
        .getSemanticsData();
    expect(semantics.customSemanticsActionIds, isNotEmpty);
    clearInteractions(cubit);

    final sliderRect = tester.getRect(sliderFinder);
    final doubleTapPoint = Offset(sliderRect.right - 12, sliderRect.center.dy);
    await tester.tapAt(doubleTapPoint);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(doubleTapPoint);
    await tester.pumpAndSettle();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 2,
        value: 16,
        userIsChangingTheValue: false,
      ),
    ).called(1);

    semanticsHandle.dispose();
  });

  testWidgets('pinned Bypass uses NT strings and parameter zero', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    Widget app(Slot slot) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: slot,
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      app(
        _slot(
          bypassEnums: const ['Processing', 'Skipped'],
          bypassDisplay: 'Processing',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bypass: Processing'), findsOneWidget);
    expect(find.text('Algorithm'), findsNothing);
    expect(find.text('Patterns'), findsOneWidget);
    final bypassSemantics = tester
        .getSemantics(find.byKey(const ValueKey('slot-bypass-toggle')))
        .getSemanticsData();
    expect(bypassSemantics.label, 'Bypass');
    expect(bypassSemantics.value, 'Processing');
    expect(bypassSemantics.flagsCollection.isToggled, Tristate.isFalse);
    final bypassSize = tester.getSize(
      find.byKey(const ValueKey('slot-bypass-toggle')),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slot-bypass-toggle')),
        matching: find.byIcon(Icons.power_settings_new_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('slot-bypass-toggle')));
    await tester.pump();

    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 0,
        value: 1,
        userIsChangingTheValue: false,
      ),
    ).called(1);

    await tester.pumpWidget(
      app(
        _slot(
          bypassed: true,
          bypassEnums: const ['Processing', 'Skipped'],
          bypassDisplay: 'Skipped',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bypass: Skipped'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('slot-bypass-toggle'))),
      bypassSize,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slot-bypass-toggle')),
        matching: find.byIcon(Icons.power_off_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('slot-bypass-toggle')))
          .showCheckmark,
      isFalse,
    );

    semanticsHandle.dispose();
  });

  testWidgets('slot action bar is right aligned', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: _slot(),
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screenRight = tester.getRect(find.byType(Scaffold)).right;
    final moreOptionsRight = tester
        .getRect(find.byKey(const ValueKey('slot-editor-more-options')))
        .right;
    expect(moreOptionsRight, closeTo(screenRight - 24, 0.1));
  });

  testWidgets('pinned Bypass remains usable on a narrow layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: _slot(),
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-bypass-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned Bypass reports write failures', (tester) async {
    when(
      () => cubit.updateParameterValue(
        algorithmIndex: 2,
        parameterNumber: 0,
        value: 1,
        userIsChangingTheValue: false,
      ),
    ).thenThrow(StateError('offline'));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: _slot(),
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slot-bypass-toggle')));
    await tester.pump();

    expect(find.textContaining('Could not change Bypass'), findsOneWidget);
  });

  testWidgets('Algorithm page navigation focuses the pinned Bypass control', (
    tester,
  ) async {
    final pageController = SectionParameterController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: _slot(),
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
              pageController: pageController,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    pageController.goToPage(2, 1);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SlotDetailView.bypass',
    );
  });

  testWidgets('Euclidean controller is default-off and survives Slot updates', (
    tester,
  ) async {
    Widget app(Slot slot) {
      return MaterialApp(
        theme: AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: Brightness.light,
        ),
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: _SlotDetailHarness(
              slot: slot,
              slotIndex: 2,
              units: const [],
              firmwareVersion: FirmwareVersion('1.17.0'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(app(_slot(steps: 16, emptyPages: true)));
    await tester.pumpAndSettle();

    IconButton controllerButton() => tester.widget<IconButton>(
      find.byKey(const ValueKey('slot-editor-mode-controller')),
    );

    expect(find.byType(LuaAlgorithmControllerView), findsNothing);
    expect(controllerButton().isSelected, isFalse);
    expect(find.text('Bypass: Off'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-editor-mode-controller')));
    await tester.pumpAndSettle();

    expect(find.byType(LuaAlgorithmControllerView), findsOneWidget);
    expect(controllerButton().isSelected, isTrue);
    expect(find.text('Bypass: Off'), findsOneWidget);
    expect(find.text('16 steps · 4 pulses · rotation 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('slot-editor-collapse-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('slot-editor-more-options')),
      findsOneWidget,
    );
    expect(find.byTooltip('Collapse all'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-editor-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand all'), findsOneWidget);
    expect(find.text('Steps'), findsNothing);

    await tester.pumpWidget(app(_slot(steps: 9, emptyPages: true)));
    await tester.pumpAndSettle();

    expect(find.byType(LuaAlgorithmControllerView), findsOneWidget);
    expect(controllerButton().isSelected, isTrue);
    expect(find.text('9 steps · 4 pulses · rotation 0'), findsOneWidget);
    expect(find.byTooltip('Expand all'), findsOneWidget);
    expect(find.text('Steps'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('slot-editor-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse all'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);

    await tester.tap(find.text('Channel 1'));
    await tester.pumpAndSettle();
    expect(find.text('Steps'), findsNothing);
    await tester.tap(find.text('Channel 1'));
    await tester.pumpAndSettle();
    expect(find.text('Steps'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-editor-mode-standard')));
    await tester.pumpAndSettle();
    expect(find.byType(LuaAlgorithmControllerView), findsNothing);
  });
}

class _SlotDetailHarness extends StatefulWidget {
  const _SlotDetailHarness({
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.firmwareVersion,
    this.pageController,
  });

  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final FirmwareVersion firmwareVersion;
  final SectionParameterController? pageController;

  @override
  State<_SlotDetailHarness> createState() => _SlotDetailHarnessState();
}

class _SlotDetailHarnessState extends State<_SlotDetailHarness> {
  SlotEditorMode _mode = SlotEditorMode.standard;
  late final AlgorithmControllerSectionController _sectionController =
      AlgorithmControllerSectionController(initiallyCollapsed: false);

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlotDetailView(
      slot: widget.slot,
      slotIndex: widget.slotIndex,
      units: widget.units,
      firmwareVersion: widget.firmwareVersion,
      sectionController: widget.pageController,
      algorithmControllerSections: _sectionController,
      editorMode: _mode,
      onEditorModeChanged: (mode) => setState(() => _mode = mode),
    );
  }
}

Widget _host(
  MockDistingCubit cubit,
  Slot slot,
  String source, {
  AlgorithmControllerSourceLoader? sourceLoader,
  List<String> units = const [],
  ThemeData? theme,
}) {
  return _LuaAlgorithmControllerHarness(
    cubit: cubit,
    slot: slot,
    source: source,
    sourceLoader: sourceLoader,
    units: units,
    theme: theme,
  );
}

class _LuaAlgorithmControllerHarness extends StatefulWidget {
  const _LuaAlgorithmControllerHarness({
    required this.cubit,
    required this.slot,
    required this.source,
    this.sourceLoader,
    this.units = const [],
    this.theme,
  });

  final MockDistingCubit cubit;
  final Slot slot;
  final String source;
  final AlgorithmControllerSourceLoader? sourceLoader;
  final List<String> units;
  final ThemeData? theme;

  @override
  State<_LuaAlgorithmControllerHarness> createState() =>
      _LuaAlgorithmControllerHarnessState();
}

class _LuaAlgorithmControllerHarnessState
    extends State<_LuaAlgorithmControllerHarness> {
  late final AlgorithmControllerSectionController _sectionController =
      AlgorithmControllerSectionController(initiallyCollapsed: false);

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: widget.theme,
      home: BlocProvider<DistingCubit>.value(
        value: widget.cubit,
        child: Scaffold(
          body: LuaAlgorithmControllerView(
            definition: const AlgorithmControllerDefinition(
              id: 'test.controller',
              algorithmGuid: 'eucp',
              name: 'Test controller',
              assetPath: 'memory.lua',
            ),
            slot: widget.slot,
            slotIndex: 2,
            units: widget.units,
            sectionController: _sectionController,
            sourceLoader: widget.sourceLoader ?? (_) async => widget.source,
          ),
        ),
      ),
    );
  }
}

Finder _sectionTile(String path) =>
    find.byKey(ValueKey('algorithm-controller-section:$path'));

Finder _sectionHeader(String path) => find
    .descendant(of: _sectionTile(path), matching: find.byType(ListTile))
    .first;

Color? _sectionHeaderInkColor(WidgetTester tester, String path) {
  final inkFinder = find
      .descendant(of: _sectionHeader(path), matching: find.byType(Ink))
      .first;
  final decoration = tester.widget<Ink>(inkFinder).decoration;
  expect(decoration, isA<ShapeDecoration>());
  return (decoration! as ShapeDecoration).color;
}

Slot _slot({
  int steps = 16,
  int pulsesMinimum = 1,
  int pulsesMaximum = 32,
  bool emptyPages = false,
  bool bypassed = false,
  List<String> bypassEnums = const ['Off', 'On'],
  String bypassDisplay = 'Off',
  String stepsDisplay = '',
  int stepsPowerOfTen = 0,
  int stepsUnit = 0,
}) {
  final fixtures = [
    (name: 'Bypass', min: 0, max: 1, defaultValue: 0),
    (name: '1:Enable', min: 0, max: 1, defaultValue: 0),
    (name: '1:Steps', min: 1, max: 32, defaultValue: 16),
    (name: '1:Pulses', min: pulsesMinimum, max: pulsesMaximum, defaultValue: 4),
    (name: '1:Rotation', min: 0, max: 32, defaultValue: 0),
  ];
  final values = [bypassed ? 1 : 0, 1, steps, 4, 0];
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: 2,
      guid: 'eucp',
      name: 'Euclidean Patterns',
      specifications: const [1],
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: 2,
      pages: emptyPages
          ? const []
          : [
              ParameterPage(
                name: 'Patterns',
                parameters: [
                  for (var index = 1; index < fixtures.length; index++) index,
                ],
              ),
              ParameterPage(name: 'Algorithm', parameters: const [0]),
            ],
    ),
    parameters: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterInfo(
          algorithmIndex: 2,
          parameterNumber: index,
          min: fixtures[index].min,
          max: fixtures[index].max,
          defaultValue: fixtures[index].defaultValue,
          unit: index == 2 ? stepsUnit : 0,
          name: fixtures[index].name,
          powerOfTen: index == 2 ? stepsPowerOfTen : 0,
        ),
    ],
    values: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValue(
          algorithmIndex: 2,
          parameterNumber: index,
          value: values[index],
        ),
    ],
    enums: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterEnumStrings(
          algorithmIndex: 2,
          parameterNumber: index,
          values: switch (index) {
            0 => bypassEnums,
            1 => const ['Off', 'On'],
            _ => const [],
          },
        ),
    ],
    mappings: [for (final _ in fixtures) Mapping.filler()],
    valueStrings: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValueString(
          algorithmIndex: 2,
          parameterNumber: index,
          value: switch (index) {
            0 => bypassDisplay,
            2 => stepsDisplay,
            _ => '',
          },
        ),
    ],
  );
}

Slot _noteMaskSlot({int c = 0, int cSharp = 0, int fSharp = 0}) {
  final slot = _slot();
  const names = ['C mask', 'C sharp mask', 'F sharp mask'];
  final values = [c, cSharp, fSharp];
  return slot.copyWith(
    parameters: [
      ...slot.parameters,
      for (var index = 0; index < names.length; index++)
        ParameterInfo(
          algorithmIndex: 2,
          parameterNumber: 5 + index,
          min: 0,
          max: 1,
          defaultValue: 1,
          unit: 0,
          name: names[index],
          powerOfTen: 0,
        ),
    ],
    values: [
      ...slot.values,
      for (var index = 0; index < values.length; index++)
        ParameterValue(
          algorithmIndex: 2,
          parameterNumber: 5 + index,
          value: values[index],
        ),
    ],
    enums: [
      ...slot.enums,
      for (var index = 0; index < names.length; index++)
        ParameterEnumStrings(
          algorithmIndex: 2,
          parameterNumber: 5 + index,
          values: const ['Off', 'On'],
        ),
    ],
    mappings: [...slot.mappings, for (final _ in names) Mapping.filler()],
    valueStrings: [
      ...slot.valueStrings,
      for (var index = 0; index < names.length; index++)
        ParameterValueString(
          algorithmIndex: 2,
          parameterNumber: 5 + index,
          value: values[index] == 1 ? 'On' : 'Off',
        ),
    ],
  );
}
