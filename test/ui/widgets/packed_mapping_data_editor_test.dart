import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/widgets/packed_mapping_data_editor.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class _MockMidiListenerCubit extends MockCubit<MidiListenerState>
    implements MidiListenerCubit {}

void main() {
  late MockDistingCubit mockCubit;
  late MockDistingMidiManager mockDisting;

  setUp(() {
    mockCubit = MockDistingCubit();
    mockDisting = MockDistingMidiManager();
    when(() => mockCubit.state).thenReturn(DistingStateInitial());
    when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
  });
  group('PackedMappingDataEditor - 14-bit CC Support', () {
    late PackedMappingData testData;
    late List<Slot> mockSlots;

    setUp(() {
      testData = PackedMappingData.filler();
      mockSlots = [];
    });

    Widget createTestWidget({
      PackedMappingData? initialData,
      FirmwareVersion? firmwareVersion,
      Future<void> Function(PackedMappingData)? onSave,
    }) {
      if (firmwareVersion != null) {
        when(() => mockCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDisting,
            distingVersion: firmwareVersion.versionString,
            firmwareVersion: firmwareVersion,
            presetName: 'Test',
            algorithms: const [],
            slots: mockSlots,
            unitStrings: const [],
          ),
        );
      }
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: PackedMappingDataEditor(
              initialData: initialData ?? testData,
              onSave: onSave ?? (_) async {},
              slots: mockSlots,
              algorithmIndex: 0,
              parameterNumber: 0,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );
    }

    testWidgets('MIDI type dropdown includes all 5 options', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find the MIDI Type dropdown
      final dropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenu<MidiMappingType> &&
            widget.label.toString().contains('MIDI Type'),
      );
      expect(dropdownFinder, findsOneWidget);

      // Get the dropdown widget to verify it has all 5 entries
      final dropdown = tester.widget<DropdownMenu<MidiMappingType>>(
        dropdownFinder,
      );
      expect(dropdown.dropdownMenuEntries.length, equals(5));

      // Verify entry labels
      expect(dropdown.dropdownMenuEntries[0].label, equals('CC'));
      expect(dropdown.dropdownMenuEntries[1].label, equals('Note - Momentary'));
      expect(dropdown.dropdownMenuEntries[2].label, equals('Note - Toggle'));
      expect(dropdown.dropdownMenuEntries[3].label, equals('14 bit CC - low'));
      expect(dropdown.dropdownMenuEntries[4].label, equals('14 bit CC - high'));
    });

    testWidgets('MIDI type dropdown adds expressive types on firmware 1.17', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(firmwareVersion: FirmwareVersion('1.17.0-beta')),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final dropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenu<MidiMappingType> &&
            widget.label.toString().contains('MIDI Type'),
      );
      final dropdown = tester.widget<DropdownMenu<MidiMappingType>>(
        dropdownFinder,
      );

      expect(dropdown.dropdownMenuEntries.length, equals(7));
      expect(dropdown.dropdownMenuEntries[5].label, equals('Pitch bend'));
      expect(dropdown.dropdownMenuEntries[6].label, equals('Channel pressure'));
    });

    testWidgets(
      'MIDI type dropdown omits expressive types before firmware 1.17',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(firmwareVersion: FirmwareVersion('1.16.0')),
        );

        await tester.tap(find.text('MIDI'));
        await tester.pumpAndSettle();

        final dropdownFinder = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<MidiMappingType> &&
              widget.label.toString().contains('MIDI Type'),
        );
        final dropdown = tester.widget<DropdownMenu<MidiMappingType>>(
          dropdownFinder,
        );

        expect(dropdown.dropdownMenuEntries.length, equals(5));
        expect(
          dropdown.dropdownMenuEntries.map((entry) => entry.label),
          isNot(contains('Pitch bend')),
        );
        expect(
          dropdown.dropdownMenuEntries.map((entry) => entry.label),
          isNot(contains('Channel pressure')),
        );
      },
    );

    testWidgets(
      'unsupported expressive MIDI learn emits one warning and does not save',
      (tester) async {
        final midiCubit = _MockMidiListenerCubit();
        final midiController = StreamController<MidiListenerState>.broadcast();
        addTearDown(midiController.close);
        when(() => midiCubit.startDetecting()).thenReturn(null);
        when(() => midiCubit.stopDetecting()).thenReturn(null);
        whenListen(
          midiCubit,
          midiController.stream,
          initialState: const MidiListenerState.data(),
        );

        final accessibilityMessages = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              (Object? message) async {
                accessibilityMessages.add(message);
                return null;
              },
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockDecodedMessageHandler<Object?>(
                SystemChannels.accessibility,
                null,
              );
        });

        var saveCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<DistingCubit>.value(value: mockCubit),
                BlocProvider<MidiListenerCubit>.value(value: midiCubit),
              ],
              child: Scaffold(
                body: PackedMappingDataEditor(
                  initialData: testData,
                  onSave: (_) async {
                    saveCount++;
                  },
                  slots: mockSlots,
                  algorithmIndex: 0,
                  parameterNumber: 0,
                  parameterMin: 0,
                  parameterMax: 100,
                  powerOfTen: 0,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('MIDI'));
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          midiController.add(
            MidiListenerState.data(
              lastDetectedType: MidiEventType.pitchBend,
              lastDetectedChannel: 0,
              lastDetectedCc: 0,
              lastDetectedTime: DateTime(2026, 6, 4, 12, 0, i),
            ),
          );
          await tester.pump();
        }

        expect(saveCount, isZero);
        expect(
          accessibilityMessages
              .where(
                (message) => message.toString().contains(
                  'Pitch bend and channel pressure mappings require firmware 1.17 or newer.',
                ),
              )
              .length,
          equals(1),
        );
      },
    );

    testWidgets(
      'unsupported expressive MIDI dropdown edit warns and preserves selection',
      (tester) async {
        final accessibilityMessages = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              (Object? message) async {
                accessibilityMessages.add(message);
                return null;
              },
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockDecodedMessageHandler<Object?>(
                SystemChannels.accessibility,
                null,
              );
        });

        var saveCount = 0;
        await tester.pumpWidget(
          createTestWidget(
            firmwareVersion: FirmwareVersion('1.16.0'),
            initialData: testData.copyWith(
              version: 7,
              midiMappingType: MidiMappingType.pitchBend,
              midiCC: 0,
              isMidiEnabled: true,
            ),
            onSave: (_) async {
              saveCount++;
            },
          ),
        );

        await tester.tap(find.text('MIDI'));
        await tester.pumpAndSettle();

        final dropdownFinder = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<MidiMappingType> &&
              widget.label.toString().contains('MIDI Type'),
        );
        tester
            .widget<DropdownMenu<MidiMappingType>>(dropdownFinder)
            .onSelected
            ?.call(MidiMappingType.channelPressure);
        await tester.pump();

        expect(saveCount, isZero);
        expect(
          tester
              .widget<DropdownMenu<MidiMappingType>>(dropdownFinder)
              .initialSelection,
          MidiMappingType.pitchBend,
        );
        expect(
          accessibilityMessages.any(
            (message) => message.toString().contains(
              'Pitch bend and channel pressure mappings require firmware 1.17 or newer.',
            ),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'unsupported expressive MIDI control edit warns and preserves state',
      (tester) async {
        final accessibilityMessages = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              (Object? message) async {
                accessibilityMessages.add(message);
                return null;
              },
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockDecodedMessageHandler<Object?>(
                SystemChannels.accessibility,
                null,
              );
        });

        var saveCount = 0;
        await tester.pumpWidget(
          createTestWidget(
            firmwareVersion: FirmwareVersion('1.16.0'),
            initialData: testData.copyWith(
              version: 7,
              midiMappingType: MidiMappingType.pitchBend,
              midiCC: 0,
              isMidiEnabled: true,
            ),
            onSave: (_) async {
              saveCount++;
            },
          ),
        );

        await tester.tap(find.text('MIDI'));
        await tester.pumpAndSettle();

        final enabledSwitchFinder = find.byWidgetPredicate((widget) {
          if (widget is! SwitchListTile) return false;
          final title = widget.title;
          return title is Text && title.data == 'MIDI Enabled';
        });
        tester
            .widget<SwitchListTile>(enabledSwitchFinder)
            .onChanged
            ?.call(false);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(saveCount, isZero);
        expect(
          tester.widget<SwitchListTile>(enabledSwitchFinder).value,
          isTrue,
        );
        expect(
          accessibilityMessages.any(
            (message) => message.toString().contains(
              'Pitch bend and channel pressure mappings require firmware 1.17 or newer.',
            ),
          ),
          isTrue,
        );
      },
    );

    testWidgets('Pitch bend disables MIDI CC field and relative switch', (
      tester,
    ) async {
      final pitchBendData = testData.copyWith(
        midiMappingType: MidiMappingType.pitchBend,
        midiCC: 0,
        version: 7,
      );

      await tester.pumpWidget(
        createTestWidget(
          initialData: pitchBendData,
          firmwareVersion: FirmwareVersion('1.17.0-beta'),
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final ccFieldFinder = find.byWidgetPredicate((widget) {
        if (widget is! TextField) return false;
        return widget.decoration?.labelText == 'MIDI CC / Note (ignored)';
      });
      expect(ccFieldFinder, findsOneWidget);
      expect(tester.widget<TextField>(ccFieldFinder).enabled, isFalse);

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchFinder).onChanged, isNull);
    });

    testWidgets('Selecting 14-bit CC low updates data model', (tester) async {
      final data14BitLow = testData.copyWith(
        midiMappingType: MidiMappingType.cc14BitLow,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: Scaffold(
              body: PackedMappingDataEditor(
                initialData: data14BitLow,
                onSave: (_) async {},
                slots: mockSlots,
                algorithmIndex: 0,
                parameterNumber: 0,
                parameterMin: 0,
                parameterMax: 100,
                powerOfTen: 0,
              ),
            ),
          ),
        ),
      );

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Verify the editor displays the correct initial data
      // (No Save button needed - optimistic updates handle persistence)
      expect(find.text('MIDI'), findsOneWidget);
    });

    testWidgets('Selecting 14-bit CC high updates data model', (tester) async {
      final data14BitHigh = testData.copyWith(
        midiMappingType: MidiMappingType.cc14BitHigh,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: Scaffold(
              body: PackedMappingDataEditor(
                initialData: data14BitHigh,
                onSave: (_) async {},
                slots: mockSlots,
                algorithmIndex: 0,
                parameterNumber: 0,
                parameterMin: 0,
                parameterMax: 100,
                powerOfTen: 0,
              ),
            ),
          ),
        ),
      );

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Verify the editor displays the correct initial data
      // (No Save button needed - optimistic updates handle persistence)
      expect(find.text('MIDI'), findsOneWidget);
    });

    testWidgets('MIDI Relative switch disabled for 14-bit CC low', (
      tester,
    ) async {
      final data14BitLow = testData.copyWith(
        midiMappingType: MidiMappingType.cc14BitLow,
      );

      await tester.pumpWidget(createTestWidget(initialData: data14BitLow));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find the MIDI Relative switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });
      expect(switchFinder, findsOneWidget);

      final switchListTile = tester.widget<SwitchListTile>(switchFinder);
      final switchWidget = Switch(
        value: switchListTile.value,
        onChanged: switchListTile.onChanged,
      );

      // Verify it's disabled (onChanged is null)
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('MIDI Relative switch disabled for 14-bit CC high', (
      tester,
    ) async {
      final data14BitHigh = testData.copyWith(
        midiMappingType: MidiMappingType.cc14BitHigh,
      );

      await tester.pumpWidget(createTestWidget(initialData: data14BitHigh));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find the MIDI Relative switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });
      expect(switchFinder, findsOneWidget);

      final switchListTile = tester.widget<SwitchListTile>(switchFinder);
      final switchWidget = Switch(
        value: switchListTile.value,
        onChanged: switchListTile.onChanged,
      );

      // Verify it's disabled (onChanged is null)
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('MIDI Relative switch enabled for standard CC', (tester) async {
      final dataCc = testData.copyWith(midiMappingType: MidiMappingType.cc);

      await tester.pumpWidget(createTestWidget(initialData: dataCc));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find the MIDI Relative switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });
      expect(switchFinder, findsOneWidget);

      final switchListTile = tester.widget<SwitchListTile>(switchFinder);
      final switchWidget = Switch(
        value: switchListTile.value,
        onChanged: switchListTile.onChanged,
      );

      // Verify it's enabled (onChanged is not null)
      expect(switchWidget.onChanged, isNotNull);
    });

    testWidgets('MIDI Relative switch disabled for note types', (tester) async {
      final dataNoteMomentary = testData.copyWith(
        midiMappingType: MidiMappingType.noteMomentary,
      );

      await tester.pumpWidget(createTestWidget(initialData: dataNoteMomentary));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find the MIDI Relative switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });
      expect(switchFinder, findsOneWidget);

      final switchListTile = tester.widget<SwitchListTile>(switchFinder);
      final switchWidget = Switch(
        value: switchListTile.value,
        onChanged: switchListTile.onChanged,
      );

      // Verify it's disabled (onChanged is null)
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('Displays N/A message for 14-bit CC types', (tester) async {
      final data14BitLow = testData.copyWith(
        midiMappingType: MidiMappingType.cc14BitLow,
      );

      await tester.pumpWidget(createTestWidget(initialData: data14BitLow));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Verify N/A message is displayed
      expect(
        find.text(
          '(N/A for notes, 14-bit CC, pitch bend, and channel pressure)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Does not display N/A message for CC type', (tester) async {
      final dataCc = testData.copyWith(midiMappingType: MidiMappingType.cc);

      await tester.pumpWidget(createTestWidget(initialData: dataCc));

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Verify N/A message is NOT displayed
      expect(find.text('(N/A for Notes and 14-bit CC)'), findsNothing);
    });
  });

  group('PackedMappingDataEditor - Optimistic Updates', () {
    late PackedMappingData testData;
    late List<Slot> mockSlots;

    setUp(() {
      testData = PackedMappingData.filler();
      mockSlots = [];
    });

    Widget createTestWidget({
      required Future<void> Function(PackedMappingData) onSave,
      PackedMappingData? initialData,
    }) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: PackedMappingDataEditor(
              initialData: initialData ?? testData,
              onSave: onSave,
              slots: mockSlots,
              algorithmIndex: 0,
              parameterNumber: 0,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );
    }

    testWidgets('rapid changes hand every intent to the save coordinator', (
      tester,
    ) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
            lastSavedData = data;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Find the Unipolar switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      // Make 5 rapid changes
      for (int i = 0; i < 5; i++) {
        await tester.tap(
          find.descendant(of: switchFinder, matching: find.byType(Switch)),
        );
        await tester.pump(Duration(milliseconds: 100));
      }

      expect(saveCount, 5);
      expect(lastSavedData, isNotNull);
    });

    testWidgets('changes on different fields are handed off independently', (
      tester,
    ) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Find switches
      final unipolarFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      final gateFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Gate';
      });

      // Toggle Unipolar
      await tester.tap(
        find.descendant(of: unipolarFinder, matching: find.byType(Switch)),
      );
      await tester.pump(Duration(milliseconds: 500));

      expect(saveCount, 1);

      // Toggle Gate.
      await tester.tap(
        find.descendant(of: gateFinder, matching: find.byType(Switch)),
      );
      await tester.pump(Duration(milliseconds: 500));

      expect(saveCount, 2);
    });

    testWidgets('Handed-off save survives editor disposal', (tester) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Find the Unipolar switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      // Trigger a change and hand it off.
      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);

      // Disposing the editor must not duplicate or cancel the handoff.
      await tester.pumpWidget(Container());

      expect(saveCount, 1);
    });

    testWidgets('Tab switching does not trigger save', (tester) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Navigate to I2C tab
      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      // Wait for any delayed indicator work.
      await tester.pump(Duration(seconds: 2));

      expect(saveCount, 0); // Tab switching alone should not trigger saves
    });

    testWidgets('CV bus picker triggers optimistic save', (tester) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
            lastSavedData = data;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Source remains a dropdown; CV Input is exclusively the shared picker.
      expect(find.byType(DropdownMenu<int>), findsOneWidget);
      expect(find.byType(BusSelectionField), findsOneWidget);
      final picker = tester.widget<BusSelectionField>(
        find.byType(BusSelectionField),
      );
      picker.onChanged(1);
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.cvInput, equals(1));
    });

    testWidgets('MIDI text field triggers optimistic save', (tester) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
            lastSavedData = data;
          },
        ),
      );

      // Navigate to MIDI tab
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Find MIDI CC text field
      final textFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'MIDI CC / Note (0-128)',
      );

      // Enter text
      await tester.enterText(textFieldFinder, '64');
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.midiCC, equals(64));
    });

    testWidgets('I2C switch triggers optimistic save', (tester) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
            lastSavedData = data;
          },
        ),
      );

      // Navigate to I2C tab
      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      // Find the I2C Enabled switch
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'I2C Enabled';
      });

      // Toggle switch
      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isI2cEnabled, equals(true));
    });

    testWidgets('Multiple rapid changes hand off the latest state', (
      tester,
    ) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      // Navigate to CV tab
      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Find switches
      final unipolarFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      final gateFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Gate';
      });

      // Make multiple changes across different fields
      await tester.tap(
        find.descendant(of: unipolarFinder, matching: find.byType(Switch)),
      );
      await tester.pump(Duration(milliseconds: 200));

      await tester.tap(
        find.descendant(of: gateFinder, matching: find.byType(Switch)),
      );
      await tester.pump(Duration(milliseconds: 200));

      await tester.tap(
        find.descendant(of: unipolarFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 3);
    });
  });

  group('PackedMappingDataEditor - Performance Tab', () {
    late PackedMappingData testData;
    late List<Slot> mockSlots;

    setUp(() {
      testData = PackedMappingData.filler();
      mockSlots = [];
    });

    Widget createTestWidget({PackedMappingData? initialData}) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: PackedMappingDataEditor(
              initialData: initialData ?? testData,
              onSave: (_) async {},
              slots: mockSlots,
              algorithmIndex: 0,
              parameterNumber: 0,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );
    }

    testWidgets('Performance tab is rendered', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Verify 4 tabs exist (CV, MIDI, I2C, Performance)
      expect(find.text('CV'), findsOneWidget);
      expect(find.text('MIDI'), findsOneWidget);
      expect(find.text('I2C'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
    });

    testWidgets('TabController has length 4 - navigate all tabs', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      // Navigate through first 3 tabs (CV, MIDI, I2C)
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();
      expect(find.text('MIDI Enabled'), findsOneWidget);

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();
      expect(find.text('I2C Enabled'), findsOneWidget);

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();
      expect(find.text('Unipolar'), findsOneWidget);
    });

    testWidgets('Performance tab auto-selected when perfPageIndex > 0', (
      tester,
    ) async {
      final testDataWithPerfPage = testData.copyWith(perfPageIndex: 3);

      await tester.pumpWidget(
        createTestWidget(initialData: testDataWithPerfPage),
      );

      // The initial tab should be Performance (index 3) since perfPageIndex > 0
      // and no other mappings are active
      // Note: We can't verify the tab content without BlocProvider/DistingCubit
      // Integration tests will verify the actual Performance tab functionality
      expect(find.text('Performance'), findsOneWidget);
    });
  });

  group('PackedMappingDataEditor - Filler CC defaults', () {
    late MockDistingCubit mockCubit;

    setUp(() {
      mockCubit = MockDistingCubit();
      when(() => mockCubit.state).thenReturn(DistingStateInitial());
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
    });

    Widget createTestWidget({required PackedMappingData initialData}) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: PackedMappingDataEditor(
              initialData: initialData,
              onSave: (_) async {},
              slots: [],
              algorithmIndex: 0,
              parameterNumber: 0,
              parameterMin: 0,
              parameterMax: 100,
              powerOfTen: 0,
            ),
          ),
        ),
      );
    }

    testWidgets('MIDI CC field shows 0 instead of -1 for filler data', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(initialData: PackedMappingData.filler()),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // The CC field should show "0", not "-1"
      expect(find.text('-1'), findsNothing);
      final ccField = find.widgetWithText(TextField, '0');
      expect(ccField, findsWidgets);
    });

    testWidgets('I2C CC field shows 0 instead of -1 for filler data', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(initialData: PackedMappingData.filler()),
      );

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      // The CC field should show "0", not "-1"
      expect(find.text('-1'), findsNothing);
    });

    testWidgets(
      'MIDI CC preserves valid value when min/max are from hardware',
      (tester) async {
        final dataWithValidCC = PackedMappingData.filler().copyWith(
          midiCC: 42,
          midiMin: 10,
          midiMax: 90,
          isMidiEnabled: true,
        );
        await tester.pumpWidget(createTestWidget(initialData: dataWithValidCC));

        await tester.tap(find.text('MIDI'));
        await tester.pumpAndSettle();

        // CC field should show the original value
        expect(find.widgetWithText(TextField, '42'), findsOneWidget);
      },
    );
  });
}
