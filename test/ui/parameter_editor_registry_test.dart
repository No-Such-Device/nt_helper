import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/file_parameter_editor.dart';

void main() {
  Slot createTestSlot({
    required String guid,
    required String parameterName,
    required int unit,
    String algorithmName = 'Test Algorithm',
  }) {
    return Slot(
      algorithm: Algorithm(algorithmIndex: 0, guid: guid, name: algorithmName),
      routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
      pages: ParameterPages(algorithmIndex: 0, pages: []),
      parameters: [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: 0,
          max: 100,
          defaultValue: 0,
          unit: unit,
          name: parameterName,
          powerOfTen: 0,
        ),
      ],
      values: [ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0)],
      enums: [ParameterEnumStrings.filler()],
      mappings: [
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler(),
        ),
      ],
      valueStrings: [ParameterValueString.filler()],
    );
  }

  Slot createNtSampleCatalogueSlot() {
    final slot = createTestSlot(
      guid: 'ThCa',
      parameterName: 'Folder',
      unit: ParameterUnits.modernHasStrings,
    );
    return slot.copyWith(
      parameters: [
        slot.parameters.single,
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 1,
          min: 0,
          max: 100,
          defaultValue: 0,
          unit: ParameterUnits.modernConfirm,
          name: 'Sample',
          powerOfTen: 0,
        ),
      ],
      values: [
        slot.values.single,
        ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 0),
      ],
      enums: [slot.enums.single, ParameterEnumStrings.filler()],
      mappings: [
        slot.mappings.single,
        Mapping(
          algorithmIndex: 0,
          parameterNumber: 1,
          packedMappingData: PackedMappingData.filler(),
        ),
      ],
      valueStrings: [slot.valueStrings.single, ParameterValueString.filler()],
    );
  }

  Widget? findEditor(Slot slot) {
    return ParameterEditorRegistry.findEditorFor(
      slot: slot,
      parameterInfo: slot.parameters[0],
      parameterNumber: 0,
      currentValue: 0,
      onValueChanged: (_) {},
    );
  }

  group('ParameterEditorRegistry - Unified rules', () {
    test('Lua Script Program matches with both legacy and modern units', () {
      for (final unit in [
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'lua ',
          parameterName: 'Program',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        expect(editor, isA<FileParameterEditor>());
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.directFile));
        expect(
          fileEditor.rule.description.toLowerCase(),
          contains('lua script'),
        );
      }
    });

    test('Three Pot Program matches with both legacy and modern units', () {
      for (final unit in [
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'spin',
          parameterName: 'Program',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.directFile));
        expect(
          fileEditor.rule.description.toLowerCase(),
          contains('three pot'),
        );
      }
    });

    test('Sample Player Folder matches with both legacy and modern units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.modernHasStrings,
      ]) {
        final slot = createTestSlot(
          guid: 'splr',
          parameterName: 'Folder',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.folderOnly));
      }
    });

    test('Sample selector accepts legacy, string, and confirm units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'splr',
          parameterName: 'Sample',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.fileOnly));
      }
    });

    test('pymu Folder and Sample use Poly Multisample rules', () {
      for (final parameterName in ['Folder', 'Sample']) {
        final slot = createTestSlot(
          guid: 'pymu',
          parameterName: parameterName,
          unit: ParameterUnits.modernHasStrings,
          algorithmName: 'Poly Multisample',
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: parameterName);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, '/samples');
        expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
        expect(
          fileEditor.rule.zeroValueSentinelLabel,
          parameterName == 'Sample' ? 'Multisample' : isNull,
        );
      }
    });

    test('pyms Folder and Sample use Poly Multisample legacy rules', () {
      for (final parameterName in ['Folder', 'Sample']) {
        final slot = createTestSlot(
          guid: 'pyms',
          parameterName: parameterName,
          unit: ParameterUnits.modernHasStrings,
          algorithmName: 'Poly Multisample (legacy)',
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: parameterName);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, '/samples');
        expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
        expect(
          fileEditor.rule.zeroValueSentinelLabel,
          parameterName == 'Sample' ? 'Multisample' : isNull,
        );
      }
    });

    test('generic Folder and Sample rules remain non-recursive', () {
      for (final parameterName in ['Folder', 'Sample']) {
        final slot = createTestSlot(
          guid: 'splr',
          parameterName: parameterName,
          unit: ParameterUnits.modernHasStrings,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: parameterName);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, '/samples');
        expect(fileEditor.rule.ntSampleFolderEnumeration, isFalse);
        expect(fileEditor.rule.zeroValueSentinelLabel, isNull);
      }
    });

    test('generic confirm Sample uses the selected-folder file picker', () {
      final slot = createNtSampleCatalogueSlot();
      final editor = ParameterEditorRegistry.findEditorFor(
        slot: slot,
        parameterInfo: slot.parameters[1],
        parameterNumber: 1,
        currentValue: 0,
        onValueChanged: (_) {},
      );
      expect(editor, isA<FileParameterEditor>());
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.mode, FileSelectionMode.fileOnly);
      expect(fileEditor.rule.baseDirectory, '/samples');
      expect(fileEditor.rule.allowedExtensions, ['.wav', '.aif', '.aiff']);
      expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
    });

    test('generic Folder uses the recursive NT sample catalogue', () {
      final slot = createNtSampleCatalogueSlot();

      final editor = findEditor(slot);
      expect(editor, isA<FileParameterEditor>());
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.mode, FileSelectionMode.folderOnly);
      expect(fileEditor.rule.baseDirectory, '/samples');
      expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
    });

    test('Text input matches with both legacy and modern units', () {
      for (final unit in [
        ParameterUnits.legacyTextInput,
        ParameterUnits.modernTextInput,
      ]) {
        final slot = createTestSlot(
          guid: 'test',
          parameterName: 'Mix Name',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.textInput));
      }
    });

    test('factory mixer channel names remain editable text parameters', () {
      for (final guid in ['mix1', 'mix2', 'quad']) {
        final slot = createTestSlot(
          guid: guid,
          parameterName: '1:Name',
          unit: ParameterUnits.modernTextInput,
        );

        final editor = findEditor(slot);
        expect(editor, isA<FileParameterEditor>(), reason: guid);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, FileSelectionMode.textInput, reason: guid);
      }
    });

    test('factory unit-16 controls do not become file editors', () {
      final slot = createTestSlot(
        guid: 'quad',
        parameterName: '1:Spin rate',
        unit: ParameterUnits.modernHasStrings,
      );

      expect(findEditor(slot), isNull);
    });

    test('Wavetable matches with legacy, modern, and enum units', () {
      for (final unit in [
        ParameterUnits.legacyFilePath,
        ParameterUnits.legacyFileFolder,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
        ParameterUnits.enum_,
      ]) {
        final slot = createTestSlot(
          guid: 'vcot',
          parameterName: 'Wavetable',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, equals(FileSelectionMode.folderOnly));
        expect(fileEditor.rule.baseDirectory, equals('/wavetables'));
      }
    });

    test('"Sample rate" does NOT match generic Sample rule', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.modernHasStrings,
      ]) {
        final slot = createTestSlot(
          guid: 'revc',
          parameterName: 'Sample rate',
          unit: unit,
        );
        expect(findEditor(slot), isNull, reason: 'unit=$unit');
      }
    });

    test('Unit 14 (BPM) does NOT match any file editor rule', () {
      final slot = createTestSlot(
        guid: 'clck',
        parameterName: 'Tempo',
        unit: ParameterUnits.modernBPM,
      );
      expect(findEditor(slot), isNull);
    });

    test('Regular parameter (unit 0) returns null', () {
      final slot = createTestSlot(
        guid: 'test',
        parameterName: 'Level',
        unit: 0,
      );
      expect(findEditor(slot), isNull);
    });
  });

  group('ParameterEditorRegistry - Chimera', () {
    test('Chimera folder parameters use recursive NT sample enumeration', () {
      for (final parameterName in [
        'Lion folder',
        'Goat folder',
        'Beef folder',
      ]) {
        final slot = createTestSlot(
          guid: 'Chim',
          parameterName: parameterName,
          unit: ParameterUnits.modernHasStrings,
          algorithmName: 'Chimera',
        );
        final editor = findEditor(slot);
        expect(editor, isA<FileParameterEditor>(), reason: parameterName);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, FileSelectionMode.folderOnly);
        expect(fileEditor.rule.baseDirectory, '/samples');
        expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
        expect(fileEditor.rule.zeroValueSentinelLabel, isNull);
      }
    });

    test(
      'Chimera loop sample parameters use confirm units and their own folders',
      () {
        for (final parameterName in ['Lion sample', 'Goat sample']) {
          final slot = createTestSlot(
            guid: 'Chim',
            parameterName: parameterName,
            unit: ParameterUnits.modernConfirm,
            algorithmName: 'Chimera',
          );
          final editor = findEditor(slot);
          expect(editor, isA<FileParameterEditor>(), reason: parameterName);
          final fileEditor = editor as FileParameterEditor;
          expect(fileEditor.rule.mode, FileSelectionMode.fileOnly);
          expect(fileEditor.rule.baseDirectory, '/samples');
          expect(fileEditor.rule.allowedExtensions, ['.wav', '.aif', '.aiff']);
          expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
          expect(fileEditor.rule.zeroValueSentinelLabel, isNull);
        }
      },
    );

    test('Chimera Beef samples share Beef folder and use a None sentinel', () {
      for (final parameterName in [
        'Kick sample',
        'Snare sample',
        'Perc sample',
        'Hat sample',
        'Crash sample',
      ]) {
        final slot = createTestSlot(
          guid: 'Chim',
          parameterName: parameterName,
          unit: ParameterUnits.modernConfirm,
          algorithmName: 'Chimera',
        );
        final editor = findEditor(slot);
        expect(editor, isA<FileParameterEditor>(), reason: parameterName);
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.mode, FileSelectionMode.fileOnly);
        expect(fileEditor.rule.baseDirectory, '/samples');
        expect(fileEditor.rule.allowedExtensions, ['.wav', '.aif', '.aiff']);
        expect(fileEditor.rule.ntSampleFolderEnumeration, isTrue);
        expect(fileEditor.rule.zeroValueSentinelLabel, 'None');
      }
    });

    test('qualified sample contract is not scoped to an algorithm GUID', () {
      final slot = createTestSlot(
        guid: 'test',
        parameterName: 'Lion sample',
        unit: ParameterUnits.modernConfirm,
      );

      expect(findEditor(slot), isA<FileParameterEditor>());
    });

    test('qualified sample names require the confirm unit', () {
      final slot = createTestSlot(
        guid: 'Chim',
        parameterName: 'Lion sample',
        unit: ParameterUnits.modernHasStrings,
      );

      expect(findEditor(slot), isNull);
    });

    test('string and confirm units alone do not imply sample file pickers', () {
      final stringSlot = createTestSlot(
        guid: 'test',
        parameterName: 'Custom',
        unit: ParameterUnits.modernHasStrings,
      );
      final confirmSlot = createTestSlot(
        guid: 'test',
        parameterName: 'Reseed',
        unit: ParameterUnits.modernConfirm,
      );

      expect(findEditor(stringSlot), isNull);
      final confirmEditor = findEditor(confirmSlot) as FileParameterEditor;
      expect(confirmEditor.rule.mode, FileSelectionMode.textInput);
    });
  });

  group('ParameterEditorRegistry - Tuning file rules', () {
    test('.scl parameter matches for any algorithm with file units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'tuns',
          parameterName: 'Tuning .scl',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, equals('/scl'));
        expect(fileEditor.rule.allowedExtensions, contains('.scl'));
      }
    });

    test('.kbm parameter matches for any algorithm with file units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'quan',
          parameterName: 'Mapping .kbm',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, equals('/scl'));
        expect(fileEditor.rule.allowedExtensions, contains('.kbm'));
      }
    });

    test('.syx parameter matches for any algorithm with file units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'ssjw',
          parameterName: 'Tuning .syx',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, equals('/mts'));
        expect(fileEditor.rule.allowedExtensions, contains('.syx'));
      }
    });

    test('Quantizer "Scale" with enum unit does NOT match tuning rules', () {
      final slot = createTestSlot(
        guid: 'quan',
        parameterName: 'Scale',
        unit: 1,
      );
      expect(findEditor(slot), isNull);
    });
  });

  group('ParameterEditorRegistry - Community plugin rules', () {
    test('"Scl file" matches with all file units', () {
      for (final unit in [
        ParameterUnits.legacyFileFolder,
        ParameterUnits.legacyFilePath,
        ParameterUnits.modernHasStrings,
        ParameterUnits.modernConfirm,
      ]) {
        final slot = createTestSlot(
          guid: 'XYZW',
          parameterName: 'Scl file',
          unit: unit,
        );
        final editor = findEditor(slot);
        expect(editor, isNotNull, reason: 'unit=$unit');
        final fileEditor = editor as FileParameterEditor;
        expect(fileEditor.rule.baseDirectory, equals('/scl'));
        expect(fileEditor.rule.allowedExtensions, contains('.scl'));
      }
    });

    test('"Scale file" matches community plugin rule', () {
      final slot = createTestSlot(
        guid: 'XYZW',
        parameterName: 'Scale file',
        unit: ParameterUnits.modernHasStrings,
      );
      final editor = findEditor(slot);
      expect(editor, isNotNull);
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.baseDirectory, equals('/scl'));
      expect(fileEditor.rule.allowedExtensions, contains('.scl'));
    });

    test('"Scale File" (capital F) matches community plugin rule', () {
      final slot = createTestSlot(
        guid: 'ThMs',
        parameterName: 'Scale File',
        unit: ParameterUnits.modernConfirm,
      );
      final editor = findEditor(slot);
      expect(editor, isNotNull);
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.baseDirectory, equals('/scl'));
      expect(fileEditor.rule.allowedExtensions, contains('.scl'));
    });

    test('"Kbm file" matches community plugin rule', () {
      final slot = createTestSlot(
        guid: 'XYZW',
        parameterName: 'Kbm file',
        unit: ParameterUnits.modernHasStrings,
      );
      final editor = findEditor(slot);
      expect(editor, isNotNull);
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.baseDirectory, equals('/scl'));
      expect(fileEditor.rule.allowedExtensions, contains('.kbm'));
    });

    test('"Keyboard mapping file" matches community plugin rule', () {
      final slot = createTestSlot(
        guid: 'XYZW',
        parameterName: 'Keyboard mapping file',
        unit: ParameterUnits.modernHasStrings,
      );
      final editor = findEditor(slot);
      expect(editor, isNotNull);
      final fileEditor = editor as FileParameterEditor;
      expect(fileEditor.rule.baseDirectory, equals('/scl'));
      expect(fileEditor.rule.allowedExtensions, contains('.kbm'));
    });
  });

  group('ParameterEditorRegistry - isStringTypeUnit', () {
    setUp(() {
      ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.12.0'));
    });

    test('returns true for legacy string units', () {
      expect(
        ParameterEditorRegistry.isStringTypeUnit(ParameterUnits.legacyFilePath),
        isTrue,
      );
      expect(
        ParameterEditorRegistry.isStringTypeUnit(
          ParameterUnits.legacyFileFolder,
        ),
        isTrue,
      );
      expect(
        ParameterEditorRegistry.isStringTypeUnit(
          ParameterUnits.legacyTextInput,
        ),
        isTrue,
      );
      expect(ParameterEditorRegistry.isStringTypeUnit(0), isFalse);
      expect(ParameterEditorRegistry.isStringTypeUnit(1), isFalse);
    });

    test('returns true for modern string units', () {
      ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.13.0'));
      expect(
        ParameterEditorRegistry.isStringTypeUnit(
          ParameterUnits.modernHasStrings,
        ),
        isTrue,
      );
      expect(
        ParameterEditorRegistry.isStringTypeUnit(ParameterUnits.modernConfirm),
        isTrue,
      );
      expect(
        ParameterEditorRegistry.isStringTypeUnit(
          ParameterUnits.modernTextInput,
        ),
        isTrue,
      );
      expect(
        ParameterEditorRegistry.isStringTypeUnit(ParameterUnits.modernBPM),
        isFalse,
      );
      expect(ParameterEditorRegistry.isStringTypeUnit(0), isFalse);
      expect(ParameterEditorRegistry.isStringTypeUnit(1), isFalse);
    });
  });

  group('ParameterEditorRegistry - Firmware scheme detection', () {
    test('schemeFor correctly detects legacy firmware', () {
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.12.0')),
        equals(ParameterUnitScheme.legacy),
      );
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.11.5')),
        equals(ParameterUnitScheme.legacy),
      );
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.0.0')),
        equals(ParameterUnitScheme.legacy),
      );
    });

    test('schemeFor correctly detects modern firmware', () {
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.13.0')),
        equals(ParameterUnitScheme.modern),
      );
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.13.1')),
        equals(ParameterUnitScheme.modern),
      );
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('1.14.0')),
        equals(ParameterUnitScheme.modern),
      );
      expect(
        ParameterUnits.schemeFor(FirmwareVersion('2.0.0')),
        equals(ParameterUnitScheme.modern),
      );
    });

    test('schemeFor returns modern for null version', () {
      expect(
        ParameterUnits.schemeFor(null),
        equals(ParameterUnitScheme.modern),
      );
    });
  });

  group('ParameterEditorRegistry - Rule count', () {
    test('unified rules list is smaller than combined legacy + modern', () {
      // Verify we actually reduced duplication
      expect(ParameterEditorRegistry.rules.length, lessThan(40));
    });
  });
}
