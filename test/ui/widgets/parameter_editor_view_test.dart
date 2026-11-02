import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/parameter_editor_view.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';

void main() {
  group('ParameterEditorView', () {
    setUp(() {
      // Set to modern firmware scheme for these tests
      ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.13.0'));
    });
    // Helper to create a minimal Slot for testing
    Slot createTestSlot({
      required int algorithmIndex,
      List<String>? enumValues,
      String? valueString,
      int? currentValue,
      int unit = 0,
    }) {
      return Slot(
        algorithm: Algorithm(
          algorithmIndex: algorithmIndex,
          guid: 'test-guid',
          name: 'Test Algorithm',
        ),
        routing: RoutingInfo(
          algorithmIndex: algorithmIndex,
          routingInfo: List.filled(6, 0),
        ),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: []),
        parameters: [
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: 0,
            min: 0,
            max: 6,
            defaultValue: 0,
            unit: unit,
            name: 'Test Parameter',
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: 0,
            value: currentValue ?? 0,
          ),
        ],
        enums: [
          ParameterEnumStrings(
            algorithmIndex: algorithmIndex,
            parameterNumber: 0,
            values: enumValues ?? [],
          ),
        ],
        mappings: [
          Mapping(
            algorithmIndex: algorithmIndex,
            parameterNumber: 0,
            packedMappingData: PackedMappingData.filler().copyWith(
              perfPageIndex: 0,
            ),
          ),
        ],
        valueStrings: [
          ParameterValueString(
            algorithmIndex: algorithmIndex,
            parameterNumber: 0,
            value: valueString ?? '',
          ),
        ],
      );
    }

    testWidgets(
      'ES-5 Expander (unit 16) shows "Off" for value 0 with valueString',
      (tester) async {
        final slot = createTestSlot(
          algorithmIndex: 0,
          unit: ParameterUnits.modernHasStrings, // Unit 16 in modern firmware
          currentValue: 0,
          valueString: 'Off',
          enumValues: [], // Empty enum strings (sparse array)
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterEditorView(
                slot: slot,
                parameterInfo: slot.parameters[0],
                value: slot.values[0],
                enumStrings: slot.enums[0],
                mapping: slot.mappings[0],
                valueString: slot.valueStrings[0],
                unit: null, // Should be null for unit 14
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should find a ParameterViewRow with displayString = "Off"
        final parameterViewRow = tester.widget<ParameterViewRow>(
          find.byType(ParameterViewRow),
        );
        expect(parameterViewRow.displayString, equals('Off'));
        expect(parameterViewRow.unit, isNull);
      },
    );

    testWidgets(
      'ES-5 Expander (unit 16) shows raw integer for value 1 with stale valueString',
      (tester) async {
        final slot = createTestSlot(
          algorithmIndex: 0,
          unit: ParameterUnits.modernHasStrings, // Unit 16 in modern firmware
          currentValue: 1,
          valueString: 'Off', // Stale valueString from previous value 0
          enumValues: [], // Empty enum strings
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterEditorView(
                slot: slot,
                parameterInfo: slot.parameters[0],
                value: slot.values[0],
                enumStrings: slot.enums[0],
                mapping: slot.mappings[0],
                valueString: slot.valueStrings[0],
                unit: null,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // displayString should be null, causing fallback to raw integer display
        final parameterViewRow = tester.widget<ParameterViewRow>(
          find.byType(ParameterViewRow),
        );
        expect(parameterViewRow.displayString, isNull);
        expect(parameterViewRow.unit, isNull);
      },
    , tags: ['regression']);

    testWidgets('ES-5 Expander (unit 16) shows raw integer for value 6', (
      tester,
    ) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: ParameterUnits.modernHasStrings, // Unit 16 in modern firmware
        currentValue: 6,
        valueString: 'Off', // Stale valueString
        enumValues: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.displayString, isNull);
    });

    testWidgets('Looper decay time keeps unit 16 firmware ms value string', (
      tester,
    ) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: ParameterUnits.modernHasStrings,
        currentValue: 500,
        valueString: '500 ms',
        enumValues: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.displayString, equals('500 ms'));
      expect(parameterViewRow.unit, isNull);
    });

    testWidgets('Complete enum strings are passed as dropdown items', (
      tester,
    ) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 0,
        currentValue: 1,
        enumValues: ['Off', 'On'],
        valueString: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: 'ms',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.dropdownItems, equals(['Off', 'On']));
      expect(parameterViewRow.isOnOff, isTrue);
    });

    testWidgets(
      'Partial enum strings (with empty values) are not passed as dropdown',
      (tester) async {
        final slot = createTestSlot(
          algorithmIndex: 0,
          unit: 0,
          currentValue: 0,
          enumValues: ['Off', '', '', ''], // Partial enum array
          valueString: '',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterEditorView(
                slot: slot,
                parameterInfo: slot.parameters[0],
                value: slot.values[0],
                enumStrings: slot.enums[0],
                mapping: slot.mappings[0],
                valueString: slot.valueStrings[0],
                unit: 'ms',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final parameterViewRow = tester.widget<ParameterViewRow>(
          find.byType(ParameterViewRow),
        );
        // Should not be treated as dropdown because not all values are filled
        expect(parameterViewRow.dropdownItems, isNull);
        expect(parameterViewRow.isOnOff, isFalse);
        // Should use the enum string for the current value (0 = "Off")
        expect(parameterViewRow.displayString, equals('Off'));
      },
    );

    testWidgets('Unit 13 parameters suppress unit display', (tester) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 13,
        currentValue: 5,
        valueString: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: null, // Should be null for unit 13
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.unit, isNull);
    });

    testWidgets('Unit 17 parameters suppress unit display', (tester) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 17,
        currentValue: 3,
        valueString: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: null, // Should be null for unit 17
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.unit, isNull);
    });

    testWidgets('Normal parameters show unit when provided', (tester) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 5, // Some normal unit
        currentValue: 50,
        valueString: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: 'Hz', // Normal unit should be passed through
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.unit, equals('Hz'));
    });

    testWidgets('valueString takes precedence for non-unit-14 parameters', (
      tester,
    ) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 0,
        currentValue: 5,
        valueString: 'Custom Display',
        enumValues: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: 'ms',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.displayString, equals('Custom Display'));
    });

    testWidgets(
      'Empty valueString and enum strings fallback to null displayString',
      (tester) async {
        final slot = createTestSlot(
          algorithmIndex: 0,
          unit: 0,
          currentValue: 42,
          valueString: '',
          enumValues: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterEditorView(
                slot: slot,
                parameterInfo: slot.parameters[0],
                value: slot.values[0],
                enumStrings: slot.enums[0],
                mapping: slot.mappings[0],
                valueString: slot.valueStrings[0],
                unit: 'dB',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final parameterViewRow = tester.widget<ParameterViewRow>(
          find.byType(ParameterViewRow),
        );
        // No displayString, should fall back to unit-based or raw value display
        expect(parameterViewRow.displayString, isNull);
        expect(parameterViewRow.unit, equals('dB'));
      },
    );

    testWidgets('Disabled parameters render with reduced opacity', (
      tester,
    ) async {
      // Create a slot with a disabled parameter
      final slot = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'test-guid',
          name: 'Test Algorithm',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            min: 0,
            max: 100,
            defaultValue: 50,
            unit: 0,
            name: 'Disabled Parameter',
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 50,
            isDisabled: true, // Mark as disabled
          ),
        ],
        enums: [
          ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 0,
            values: [],
          ),
        ],
        mappings: [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: PackedMappingData.filler().copyWith(
              perfPageIndex: 0,
            ),
          ),
        ],
        valueStrings: [
          ParameterValueString(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: '',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: 'Hz',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.isDisabled, isTrue);
    });

    testWidgets('Enabled parameters render with full opacity', (tester) async {
      final slot = createTestSlot(
        algorithmIndex: 0,
        unit: 0,
        currentValue: 50,
        valueString: '',
        enumValues: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters[0],
              value: slot.values[0],
              enumStrings: slot.enums[0],
              mapping: slot.mappings[0],
              valueString: slot.valueStrings[0],
              unit: 'Hz',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final parameterViewRow = tester.widget<ParameterViewRow>(
        find.byType(ParameterViewRow),
      );
      expect(parameterViewRow.isDisabled, isFalse);
    });
  });
}
