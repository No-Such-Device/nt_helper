import 'dart:convert';

import '../test_helpers/mapping_v8.dart' show mappingV8Fixture;

import 'package:drift/native.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/template_metadata.dart';
import 'package:nt_helper/services/template_share_service.dart';

FullPresetSlot _slot(int index, String guid, String name) {
  return _slotWithMapping(index, guid, name, _mapping());
}

FullPresetSlot _slotWithMapping(
  int index,
  String guid,
  String name,
  PackedMappingData mapping, {
  List<int> specificationValues = const [],
}) {
  return FullPresetSlot(
    slot: PresetSlotEntry(
      id: index + 1,
      presetId: 1,
      slotIndex: index,
      algorithmGuid: guid,
      customName: 'Slot $index',
    ),
    algorithm: AlgorithmEntry(
      guid: guid,
      name: name,
      numSpecifications: specificationValues.length,
    ),
    specificationValues: specificationValues,
    parameterValues: {0: index + 10},
    parameterStringValues: {1: 'Value $index'},
    mappings: {2: mapping},
    routing: PresetRoutingEntry(
      presetSlotId: index + 1,
      routingInfoJson: [index, index + 1, index + 2],
    ),
  );
}

PackedMappingData _mapping() {
  return PackedMappingData(
    source: 0,
    cvInput: 1,
    isUnipolar: true,
    isGate: false,
    volts: 5,
    delta: 12,
    midiChannel: 1,
    midiMappingType: MidiMappingType.cc,
    midiCC: 74,
    isMidiEnabled: true,
    isMidiSymmetric: false,
    isMidiRelative: false,
    midiMin: 0,
    midiMax: 127,
    i2cCC: 3,
    isI2cEnabled: false,
    isI2cSymmetric: false,
    i2cMin: 0,
    i2cMax: 127,
    perfPageIndex: 0,
    version: 6,
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('template JSON and SQLite retain v8 flags and opaque bits', () async {
    final mapping = PackedMappingData.fromBytes(8, mappingV8Fixture());
    final service = TemplateShareService(db);
    final source = FullPresetDetails(
      preset: PresetEntry(
        id: 1,
        name: 'V8',
        lastModified: DateTime(2026),
        isTemplate: true,
      ),
      slots: [_slotWithMapping(0, 'AAAA', 'Alpha', mapping)],
    );
    final id = await service.importTemplate(service.encodeTemplate(source));
    final restored = (await db.presetsDao.getFullPresetDetails(id))!
        .slots
        .single
        .mappings[2]!;
    expect(restored, mapping);
    expect(restored.toBytes(), mappingV8Fixture());
    expect(restored.version, 8);
    final offline = OfflineDistingMidiManager(db);
    addTearDown(offline.dispose);
    await offline.initializeFromDb(
      await db.presetsDao.getFullPresetDetails(id),
    );
    await offline.setPerformancePageMapping(0, 2, 4);
    final offlineMapping = (await offline.requestMappings(
      0,
      2,
    ))!.packedMappingData;
    expect(offlineMapping, mapping.copyWith(perfPageIndex: 4));
    expect(offlineMapping.toBytes(), mappingV8Fixture());
  });

  test('exports and imports a template JSON payload', () async {
    final service = TemplateShareService(db);
    final source = FullPresetDetails(
      preset: PresetEntry(
        id: 1,
        name: 'Shared Template',
        lastModified: DateTime(2026),
        isTemplate: true,
        category: 'Performance',
        templateMetadata: const TemplateMetadata(
          description: 'Shareable patch',
          tags: ['stage', 'poly'],
          author: 'Neal',
        ).toJsonString(),
      ),
      slots: [
        _slotWithMapping(
          0,
          'AAAA',
          'Alpha',
          _mapping(),
          specificationValues: const [4, 2],
        ),
        _slot(1, 'BBBB', 'Beta'),
      ],
    );

    final jsonText = service.encodeTemplate(source);
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    expect(decoded['exportType'], TemplateShareService.exportType);
    expect(decoded['exportVersion'], TemplateShareService.exportVersion);

    final importedId = await service.importTemplate(jsonText);
    final imported = (await db.presetsDao.getFullPresetDetails(importedId))!;

    expect(imported.preset.name, 'Shared Template');
    expect(imported.preset.category, 'Performance');
    expect(imported.slots.map((slot) => slot.slot.algorithmGuid), [
      'AAAA',
      'BBBB',
    ]);
    expect(imported.slots.first.parameterValues[0], 10);
    expect(imported.slots.first.specificationValues, const [4, 2]);
    expect(imported.slots.first.parameterStringValues[1], 'Value 0');
    expect(imported.slots.first.mappings[2], _mapping());
    expect(imported.slots.first.routing?.routingInfoJson, [0, 1, 2]);
  });

  test(
    'exports and imports canonical expressive MIDI mapping objects',
    () async {
      final service = TemplateShareService(db);
      final expressiveMapping = _mapping().copyWith(
        version: 7,
        midiMappingType: MidiMappingType.channelPressure,
        midiCC: 0,
        isMidiEnabled: true,
        isMidiRelative: false,
      );
      final source = FullPresetDetails(
        preset: PresetEntry(
          id: 1,
          name: 'Expressive Template',
          lastModified: DateTime(2026),
          isTemplate: true,
        ),
        slots: [_slotWithMapping(0, 'AAAA', 'Alpha', expressiveMapping)],
      );

      final jsonText = service.encodeTemplate(source);
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      final rawMapping =
          (((decoded['template'] as Map<String, dynamic>)['slots'] as List)
                  .single
              as Map<String, dynamic>)['mappings']['2'];
      expect(rawMapping, isA<Map<String, dynamic>>());
      expect(rawMapping['midi_type'], 'channel_pressure');
      expect(rawMapping['is_midi_enabled'], isTrue);

      final importedId = await service.importTemplate(jsonText);
      final imported = (await db.presetsDao.getFullPresetDetails(importedId))!;

      expect(imported.slots.single.mappings[2], expressiveMapping);
    },
  );

  test('imports version 1 templates without specification values', () async {
    final importedId = await TemplateShareService(db).importTemplate(
      jsonEncode({
        'exportType': TemplateShareService.exportType,
        'exportVersion': 1,
        'template': {
          'name': 'Legacy Template',
          'slots': [
            {
              'algorithm': {
                'guid': 'quan',
                'name': 'Quantizer',
                'numSpecifications': 1,
              },
              'parameterValues': <String, int>{},
              'parameterStringValues': <String, String>{},
              'mappings': <String, Object?>{},
            },
          ],
        },
      }),
    );

    final imported = await db.presetsDao.getFullPresetDetails(importedId);
    expect(imported!.slots.single.specificationValues, isEmpty);
  });

  test('rejects unrelated JSON payloads', () async {
    await expectLater(
      TemplateShareService(db).importTemplate('{"exportType":"other"}'),
      throwsFormatException,
    );
  });
}
