import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/widgets/mapping_editor_bottom_sheet.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockMidiListenerCubit extends MockCubit<MidiListenerState>
    implements MidiListenerCubit {}

void main() {
  setUpAll(() {
    registerFallbackValue(PackedMappingData.filler());
  });

  group('MappingEditorBottomSheet', () {
    late _MockDistingCubit distingCubit;
    late _MockMidiListenerCubit midiCubit;

    setUp(() {
      distingCubit = _MockDistingCubit();
      midiCubit = _MockMidiListenerCubit();
      when(() => distingCubit.state).thenReturn(DistingStateInitial());
      when(() => distingCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => midiCubit.startDetecting()).thenReturn(null);
      when(() => midiCubit.stopDetecting()).thenReturn(null);
      whenListen(
        midiCubit,
        const Stream<MidiListenerState>.empty(),
        initialState: const MidiListenerState.data(),
      );
    });

    testWidgets('awaits hardware save and does not announce save success', (
      tester,
    ) async {
      final pendingSave = Completer<void>();
      when(
        () => distingCubit.saveMapping(any(), any(), any()),
      ).thenAnswer((_) => pendingSave.future);

      final accessibilityMessages = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            Object? message,
          ) async {
            accessibilityMessages.add(message);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MappingEditorBottomSheet(
              myMidiCubit: midiCubit,
              distingCubit: distingCubit,
              data: PackedMappingData.filler(),
              slots: const [],
              algorithmIndex: 0,
              parameterNumber: 0,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownMenu<MidiMappingType>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<MidiMappingType> &&
              widget.label.toString().contains('MIDI Type'),
        ),
      );
      dropdown.onSelected?.call(MidiMappingType.noteMomentary);
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(
        accessibilityMessages.any(
          (message) => message.toString().contains('Changes saved'),
        ),
        isFalse,
      );

      pendingSave.complete();
      await tester.pump();

      expect(
        accessibilityMessages.any(
          (message) => message.toString().contains('Changes saved'),
        ),
        isFalse,
      );
    }, tags: ['regression']);

    testWidgets('hands i2c edits to the cubit before the sheet is dismissed', (
      tester,
    ) async {
      var saveCalls = 0;
      PackedMappingData? handedOffData;
      when(() => distingCubit.saveMapping(any(), any(), any())).thenAnswer((
        invocation,
      ) async {
        saveCalls++;
        handedOffData = invocation.positionalArguments[2] as PackedMappingData;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MappingEditorBottomSheet(
              myMidiCubit: midiCubit,
              distingCubit: distingCubit,
              data: PackedMappingData.filler(),
              slots: const [],
              algorithmIndex: 2,
              parameterNumber: 7,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      final i2cCcField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'I2C CC',
      );
      await tester.enterText(i2cCcField, '32');
      await tester.pump();

      expect(saveCalls, 1);
      expect(handedOffData?.i2cCC, 32);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
    });
  });
}
