import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/midi_listener/midi_detector_widget.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/packed_mapping_data_editor.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  late MockDistingCubit mockCubit;

  setUp(() {
    mockCubit = MockDistingCubit();
    when(() => mockCubit.state).thenReturn(DistingStateInitial());
    when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
  });
  group('PackedMappingDataEditor - TextField Autosave', () {
    late PackedMappingData testData;
    late List<Slot> mockSlots;

    setUp(() {
      testData = PackedMappingData.filler();
      mockSlots = [];
    });

    Widget createTestWidget({
      required Future<void> Function(PackedMappingData) onSave,
      Future<void> Function(PackedMappingData)? onSaveImmediately,
      PackedMappingData? initialData,
    }) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: PackedMappingDataEditor(
              initialData: initialData ?? testData,
              onSave: onSave,
              onSaveImmediately: onSaveImmediately,
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

    testWidgets(
      'CV Voltage slider hands off the requested mapping immediately',
      (tester) async {
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

        await tester.tap(find.text('CV'));
        await tester.pumpAndSettle();

        // Find the CV Voltage Slider (not a RangeSlider)
        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);

        final slider = tester.widget<Slider>(sliderFinder);
        // Invoke onChanged to simulate dragging to 7V
        slider.onChanged!(7.0);
        await tester.pump();

        expect(saveCount, 1);
        expect(lastSavedData?.volts, equals(7));
      },
    );

    testWidgets('CV tab shows RangeSlider and Slider', (tester) async {
      await tester.pumpWidget(createTestWidget(onSave: (data) async {}));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // CV tab should have a RangeSlider for the CV range
      expect(find.byType(RangeSlider), findsOneWidget);

      // CV tab should have a Slider for CV Voltage
      expect(find.byType(Slider), findsOneWidget);

      // Old text fields should not be present
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Volts',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Delta',
        ),
        findsNothing,
      );
    });

    testWidgets('MIDI CC field hands off the requested mapping immediately', (
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

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'MIDI CC / Note (0-128)',
      );

      await tester.enterText(textFieldFinder, '64');
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.midiCC, equals(64));
    });

    testWidgets('MIDI detection bypasses the normal save debounce', (
      tester,
    ) async {
      var normalSaveCount = 0;
      var immediateSaveCount = 0;
      PackedMappingData? detectedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (_) async {
            normalSaveCount++;
          },
          onSaveImmediately: (data) async {
            immediateSaveCount++;
            detectedData = data;
          },
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final detector = tester.widget<MidiDetectorWidget>(
        find.byType(MidiDetectorWidget),
      );
      detector.onMidiEventFound!(
        type: MidiEventType.cc,
        channel: 2,
        number: 74,
      );
      await tester.pump();

      expect(normalSaveCount, 0);
      expect(immediateSaveCount, 1);
      expect(detectedData?.midiChannel, 2);
      expect(detectedData?.midiCC, 74);
      expect(detectedData?.isMidiEnabled, isTrue);
    });

    testWidgets('NRPN detection keeps the default 7-bit mapping type', (
      tester,
    ) async {
      PackedMappingData? detectedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (_) async {},
          onSaveImmediately: (data) async {
            detectedData = data;
          },
          initialData: testData.copyWith(midiMin: -25, midiMax: 75),
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final detector = tester.widget<MidiDetectorWidget>(
        find.byType(MidiDetectorWidget),
      );
      detector.onMidiEventFound!(
        type: MidiEventType.nrpn,
        channel: 4,
        number: 42,
      );
      await tester.pump();

      expect(detectedData?.midiMappingType, MidiMappingType.cc);
      expect(detectedData?.midiChannel, 4);
      expect(detectedData?.midiCC, 42);
      expect(detectedData?.midiMin, -25);
      expect(detectedData?.midiMax, 75);
      expect(detectedData?.isMidiEnabled, isTrue);
    });

    testWidgets('NRPN detection preserves a selected 14-bit mapping type', (
      tester,
    ) async {
      PackedMappingData? detectedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (_) async {},
          onSaveImmediately: (data) async {
            detectedData = data;
          },
          initialData: testData.copyWith(
            midiMappingType: MidiMappingType.cc14BitLow,
          ),
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final detector = tester.widget<MidiDetectorWidget>(
        find.byType(MidiDetectorWidget),
      );
      detector.onMidiEventFound!(
        type: MidiEventType.nrpn,
        channel: 4,
        number: 42,
      );
      await tester.pump();

      expect(detectedData?.midiMappingType, MidiMappingType.cc14BitLow);
      expect(detectedData?.midiChannel, 4);
      expect(detectedData?.midiCC, 42);
      expect(detectedData?.isMidiEnabled, isTrue);
    });

    testWidgets('NRPN detection preserves the high-first 14-bit type', (
      tester,
    ) async {
      PackedMappingData? detectedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (_) async {},
          onSaveImmediately: (data) async {
            detectedData = data;
          },
          initialData: testData.copyWith(
            midiMappingType: MidiMappingType.cc14BitHigh,
          ),
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final detector = tester.widget<MidiDetectorWidget>(
        find.byType(MidiDetectorWidget),
      );
      detector.onMidiEventFound!(
        type: MidiEventType.nrpn,
        channel: 4,
        number: 42,
      );
      await tester.pump();

      expect(detectedData?.midiMappingType, MidiMappingType.cc14BitHigh);
      expect(detectedData?.midiChannel, 4);
      expect(detectedData?.midiCC, 42);
      expect(detectedData?.isMidiEnabled, isTrue);
    });

    testWidgets('MIDI RangeSlider is present without editing', (tester) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // RangeSlider should be present
      expect(find.byType(RangeSlider), findsOneWidget);

      expect(saveCount, 0);
    });

    testWidgets('I2C CC field hands off the requested mapping immediately', (
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

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'I2C CC',
      );

      await tester.enterText(textFieldFinder, '32');
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.i2cCC, equals(32));
    });

    testWidgets('I2C RangeSlider is present', (tester) async {
      int saveCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            saveCount++;
          },
        ),
      );

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      // RangeSlider should be present
      expect(find.byType(RangeSlider), findsOneWidget);

      expect(saveCount, 0);
    });

    testWidgets(
      'Rapid slider edits hand off each intent with the latest data',
      (tester) async {
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

        await tester.tap(find.text('CV'));
        await tester.pumpAndSettle();

        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);

        // Rapid slider changes
        tester.widget<Slider>(sliderFinder).onChanged!(3.0);
        await tester.pump(const Duration(milliseconds: 200));
        tester.widget<Slider>(sliderFinder).onChanged!(6.0);
        await tester.pump(const Duration(milliseconds: 200));
        tester.widget<Slider>(sliderFinder).onChanged!(9.0);
        await tester.pump();

        expect(saveCount, 3);
        expect(lastSavedData?.volts, equals(9));
      },
    );
  });

  group('PackedMappingDataEditor - Dropdown and Switch Autosave', () {
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

    testWidgets('Source dropdown triggers immediate save', (tester) async {
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final dropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenu<int> &&
            widget.label.toString().contains('Source'),
      );
      final dropdown = tester.widget<DropdownMenu<int>>(dropdownFinder);

      dropdown.onSelected?.call(2);
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.source, equals(2));
    });

    testWidgets('Source dropdown includes all preset slots', (tester) async {
      final slot40Source = DistingLimits.maxPresetSlots + 1;
      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {},
          initialData: testData.copyWith(source: slot40Source),
        ),
      );

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final dropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenu<int> &&
            widget.label.toString().contains('Source'),
      );
      final dropdown = tester.widget<DropdownMenu<int>>(dropdownFinder);

      expect(
        dropdown.dropdownMenuEntries.length,
        DistingLimits.maxPresetSlots + 2,
      );
      expect(
        dropdown.dropdownMenuEntries.last.label,
        'Slot ${DistingLimits.maxPresetSlots}',
      );
      expect(dropdown.initialSelection, slot40Source);
    });

    testWidgets('CV Input picker triggers immediate save', (tester) async {
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final picker = tester.widget<BusSelectionField>(
        find.byType(BusSelectionField),
      );
      picker.onChanged(3);
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.cvInput, equals(3));
    });

    testWidgets('MIDI Channel dropdown triggers immediate save', (
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

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final dropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenu<int> &&
            widget.label.toString().contains('MIDI Channel'),
      );
      final dropdown = tester.widget<DropdownMenu<int>>(dropdownFinder);

      dropdown.onSelected?.call(5);
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.midiChannel, equals(5));
    });

    testWidgets('MIDI Type dropdown triggers immediate save', (tester) async {
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

      dropdown.onSelected?.call(MidiMappingType.noteMomentary);
      await tester.pump();

      expect(saveCount, 1);
      expect(
        lastSavedData?.midiMappingType,
        equals(MidiMappingType.noteMomentary),
      );
    });

    testWidgets('Unipolar switch triggers immediate save', (tester) async {
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isUnipolar, equals(true));
    });

    testWidgets('Gate switch triggers immediate save', (tester) async {
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Gate';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isGate, equals(true));
    });

    testWidgets('MIDI Enabled switch triggers immediate save', (tester) async {
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

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Enabled';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isMidiEnabled, equals(true));
    });

    testWidgets('MIDI Symmetric switch triggers immediate save', (
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

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Symmetric';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isMidiSymmetric, equals(true));
    });

    testWidgets('MIDI Relative switch triggers immediate save', (tester) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      final testDataCC = PackedMappingData.filler().copyWith(
        midiMappingType: MidiMappingType.cc,
      );

      await tester.pumpWidget(
        createTestWidget(
          initialData: testDataCC,
          onSave: (data) async {
            saveCount++;
            lastSavedData = data;
          },
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Relative';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isMidiRelative, equals(true));
    });

    testWidgets('I2C Enabled switch triggers immediate save', (tester) async {
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

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'I2C Enabled';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isI2cEnabled, equals(true));
    });

    testWidgets('I2C Symmetric switch triggers immediate save', (tester) async {
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

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'I2C Symmetric';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(saveCount, 1);
      expect(lastSavedData?.isI2cSymmetric, equals(true));
    });
  });

  group('PackedMappingDataEditor - Save on Dispose', () {
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

    testWidgets('Pending save remains handed off when widget is disposed', (
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Change CV Voltage slider to 9V
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(9.0);
      await tester.pump();

      expect(saveCount, 1);

      // Dispose the transient editor immediately.
      await tester.pumpWidget(Container());

      expect(saveCount, 1);
      expect(lastSavedData?.volts, equals(9));
    });

    testWidgets('No save triggered on dispose if no pending changes', (
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

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Don't make any changes
      await tester.pumpWidget(Container());

      expect(saveCount, 0);
    });

    testWidgets('Dialog dismissal does not duplicate the handed-off save', (
      tester,
    ) async {
      int saveCount = 0;
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => BlocProvider<DistingCubit>.value(
                        value: mockCubit,
                        child: PackedMappingDataEditor(
                          initialData: testData,
                          onSave: (data) async {
                            saveCount++;
                            lastSavedData = data;
                          },
                          slots: mockSlots,
                          algorithmIndex: 0,
                          parameterNumber: 0,
                          parameterMin: 0,
                          parameterMax: 100,
                          powerOfTen: 0,
                        ),
                      ),
                    );
                  },
                  child: const Text('Show Editor'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Editor'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'MIDI CC / Note (0-128)',
      );

      await tester.enterText(textFieldFinder, '100');
      await tester.pump();

      expect(saveCount, 1);

      // Dismiss dialog
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(saveCount, 1);
      expect(lastSavedData?.midiCC, equals(100));
    });
  });

  group('PackedMappingDataEditor - Dirty State Indicator', () {
    final testTheme = AppTheme.build(
      seedColor: AppTheme.defaultSeedColor,
      brightness: Brightness.light,
    );
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
        theme: testTheme,
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

    Completer<void> pendingSave() {
      final completer = Completer<void>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete();
      });
      return completer;
    }

    testWidgets('Indicator shows when slider is modified', (tester) async {
      final save = pendingSave();
      await tester.pumpWidget(createTestWidget(onSave: (_) => save.future));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // No indicator initially
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsNothing,
      );

      // Change CV Voltage slider
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(7.0);
      await tester.pump();

      // Indicator should appear (amber - dirty)
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Indicator shows when bus picker is changed', (tester) async {
      final save = pendingSave();
      await tester.pumpWidget(createTestWidget(onSave: (_) => save.future));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final picker = tester.widget<BusSelectionField>(
        find.byType(BusSelectionField),
      );
      picker.onChanged(1);
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Indicator shows when switch is toggled', (tester) async {
      final save = pendingSave();
      await tester.pumpWidget(createTestWidget(onSave: (_) => save.future));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'Unipolar';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Indicator advances to "saving" while the handoff is pending', (
      tester,
    ) async {
      var saveCompleted = false;
      final save = pendingSave();
      await tester.pumpWidget(
        createTestWidget(
          onSave: (_) async {
            await save.future;
            saveCompleted = true;
          },
        ),
      );

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Change CV Voltage slider
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(7.0);
      await tester.pump();

      // Dirty state (amber)
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );

      // The Cubit starts its hardware save after the same coalescing delay.
      await tester.pump(const Duration(seconds: 1));

      // Pump once more to render the _isSaving=true state before save completes
      await tester.pump();

      // Saving state (blue) - the save is in progress (not yet completed)
      expect(saveCompleted, false);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.info.color,
        ),
        findsOneWidget,
      );

      save.complete();
      await tester.pump();
      expect(saveCompleted, true);
    });

    testWidgets('Indicator clears when save completes', (tester) async {
      await tester.pumpWidget(createTestWidget(onSave: (data) async {}));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Change CV Voltage slider
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(7.0);
      await tester.pump();

      // Wait for save to complete
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Indicator should be cleared
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              ((widget.decoration as BoxDecoration).color ==
                      testTheme.appColors.warning.color ||
                  (widget.decoration as BoxDecoration).color ==
                      testTheme.appColors.info.color),
        ),
        findsNothing,
      );
    });

    testWidgets('Indicator persists across tab switches until save completes', (
      tester,
    ) async {
      final save = pendingSave();
      await tester.pumpWidget(createTestWidget(onSave: (_) => save.future));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Change CV Voltage slider
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(7.0);
      await tester.pump();

      // Switch tabs
      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Indicator should still be visible
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );

      save.complete();
      await tester.pump();
      await tester.pump();

      // Indicator should be cleared
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              ((widget.decoration as BoxDecoration).color ==
                      testTheme.appColors.warning.color ||
                  (widget.decoration as BoxDecoration).color ==
                      testTheme.appColors.info.color),
        ),
        findsNothing,
      );
    });

    testWidgets('Indicator tooltip displays correct message for dirty state', (
      tester,
    ) async {
      final save = pendingSave();
      await tester.pumpWidget(createTestWidget(onSave: (_) => save.future));

      await tester.tap(find.text('CV'));
      await tester.pumpAndSettle();

      // Change CV Voltage slider
      final sliderFinder = find.byType(Slider);
      tester.widget<Slider>(sliderFinder).onChanged!(7.0);
      await tester.pump();

      // Find tooltip with "Unsaved changes" message
      // The Tooltip widget wraps the Container, check both exist
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        findsOneWidget,
      );

      // Verify the indicator is wrapped in a Tooltip
      final tooltipFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  testTheme.appColors.warning.color,
        ),
        matching: find.byType(Tooltip),
      );
      expect(tooltipFinder, findsOneWidget);
    });
  });

  group('PackedMappingDataEditor - RangeSlider Min/Max', () {
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

    testWidgets('MIDI tab shows RangeSlider instead of text fields', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(onSave: (data) async {}));

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // RangeSlider should be present
      expect(find.byType(RangeSlider), findsOneWidget);

      // Old text fields should not be present
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'MIDI Min',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'MIDI Max',
        ),
        findsNothing,
      );
    });

    testWidgets('I2C tab shows RangeSlider instead of text fields', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(onSave: (data) async {}));

      await tester.tap(find.text('I2C'));
      await tester.pumpAndSettle();

      // RangeSlider should be present
      expect(find.byType(RangeSlider), findsOneWidget);

      // Old text fields should not be present
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'I2C Min',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'I2C Max',
        ),
        findsNothing,
      );
    });

    testWidgets('New mapping auto-defaults MIDI min/max to parameter range', (
      tester,
    ) async {
      PackedMappingData? lastSavedData;

      await tester.pumpWidget(
        createTestWidget(
          onSave: (data) async {
            lastSavedData = data;
          },
        ),
      );

      await tester.tap(find.text('MIDI'));
      await tester.pumpAndSettle();

      // Enable MIDI to trigger a save
      final switchFinder = find.byWidgetPredicate((widget) {
        if (widget is! SwitchListTile) return false;
        final title = widget.title;
        return title is Text && title.data == 'MIDI Enabled';
      });

      await tester.tap(
        find.descendant(of: switchFinder, matching: find.byType(Switch)),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // For new filler mapping, min/max should default to parameterMin/parameterMax (0, 100)
      expect(lastSavedData?.midiMin, equals(0));
      expect(lastSavedData?.midiMax, equals(100));
    });
  });
}
