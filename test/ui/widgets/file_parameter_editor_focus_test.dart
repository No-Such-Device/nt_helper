import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/file_parameter_editor.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

Slot _textNameSlot() {
  return Slot(
    algorithm: Algorithm(algorithmIndex: 0, guid: 'mix2', name: 'Mixer Stereo'),
    routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(algorithmIndex: 0, pages: []),
    parameters: [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 127,
        defaultValue: 0,
        unit: ParameterUnits.modernTextInput,
        name: 'Name',
        powerOfTen: 0,
      ),
    ],
    values: [ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0)],
    enums: [
      ParameterEnumStrings(
        algorithmIndex: 0,
        parameterNumber: 0,
        values: const [],
      ),
    ],
    mappings: [
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler(),
      ),
    ],
    valueStrings: [
      ParameterValueString(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 'Kick',
      ),
    ],
  );
}

/// Mirrors the SynchronizedScreen's digit-key page-navigation trap:
/// an ancestor Focus with autofocus: true that consumes bare digit keys.
class _DigitTrapScreen extends StatelessWidget {
  const _DigitTrapScreen({required this.child, required this.onDigit});

  final Widget child;
  final ValueChanged<LogicalKeyboardKey> onDigit;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final digits = <LogicalKeyboardKey>{
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit9,
        };
        if (digits.contains(event.logicalKey)) {
          onDigit(event.logicalKey);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.13.0'));
  });

  group('FileParameterEditor text input focus', () {
    testWidgets(
      'tap to edit grabs focus even when ancestor Focus is autofocused',
      (tester) async {
        final slot = _textNameSlot();
        final cubit = _MockDistingCubit();
        when(() => cubit.state).thenReturn(DistingStateInitial());
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        final trapped = <LogicalKeyboardKey>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<DistingCubit>.value(
                value: cubit,
                child: _DigitTrapScreen(
                  onDigit: trapped.add,
                  child: SizedBox(
                    width: 400,
                    child: FileParameterEditor(
                      slot: slot,
                      parameterInfo: slot.parameters[0],
                      parameterNumber: 0,
                      currentValue: 0,
                      onValueChanged: (_) {},
                      rule: const ParameterEditorRule(
                        parameterNamePattern: r'.*[Nn]ame.*',
                        mode: FileSelectionMode.textInput,
                        description: 'Editable text parameter',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Before editing the TextField is not in the tree.
        expect(find.byType(TextField), findsNothing);

        // Tap the display to enter edit mode.
        await tester.tap(find.text('Kick'));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);

        // The TextField's focus node should now hold primary focus — not the
        // ancestor digit-trap Focus widget.
        final primaryFocus = FocusManager.instance.primaryFocus;
        expect(primaryFocus, isNotNull);
        expect(
          primaryFocus!.debugLabel,
          equals('FileParameterEditor.textInput'),
          reason:
              'FileParameterEditor must own primary focus after tap-to-edit, '
              'so bare digit key presses reach the TextField rather than '
              'bubbling up to the SynchronizedScreen page-navigation handler.',
        );

        // Simulate pressing a digit. Because the field owns focus and
        // DigitShortcutBlocker swallows bare digits inside the TextField,
        // the ancestor Focus must NOT receive the digit.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
        await tester.pumpAndSettle();

        expect(
          trapped,
          isEmpty,
          reason:
              'Digit keys must be consumed by the focused TextField, not the '
              'ancestor page-navigation Focus widget.',
        );
      },
    , tags: ['regression']);
  });
}
