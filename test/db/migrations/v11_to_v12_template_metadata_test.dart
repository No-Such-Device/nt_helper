import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';

void main() {
  group('v11 to v12 template metadata migration', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('current schema includes the later v14 migration', () {
      expect(database.schemaVersion, 14);
    });

    test(
      'fresh v12 schema accepts null category and templateMetadata',
      () async {
        final id = await database
            .into(database.presets)
            .insert(
              PresetsCompanion.insert(
                name: 'My Template',
                isTemplate: const Value(true),
              ),
            );

        final preset = await (database.select(
          database.presets,
        )..where((p) => p.id.equals(id))).getSingle();

        expect(preset.name, 'My Template');
        expect(preset.isTemplate, isTrue);
        expect(preset.category, isNull);
        expect(preset.templateMetadata, isNull);
      },
    );

    test(
      'fresh v12 schema persists category and templateMetadata strings',
      () async {
        final id = await database
            .into(database.presets)
            .insert(
              PresetsCompanion.insert(
                name: 'Cathedral Reverb',
                isTemplate: const Value(true),
                category: const Value('Reverb'),
                templateMetadata: const Value(
                  '{"description":"Long hall","tags":["space","wet"],"author":"neal","schemaVersion":1}',
                ),
              ),
            );

        final preset = await (database.select(
          database.presets,
        )..where((p) => p.id.equals(id))).getSingle();

        expect(preset.category, 'Reverb');
        expect(preset.templateMetadata, contains('"description":"Long hall"'));
      },
    );

    test(
      'category and templateMetadata round-trip including UTF-8 codepoints',
      () async {
        const jsonText = '{"description":"Glöcken — 🔔","tags":["bells","✨"]}';
        final id = await database
            .into(database.presets)
            .insert(
              PresetsCompanion.insert(
                name: 'Bells',
                isTemplate: const Value(true),
                category: const Value('Перкуссия'),
                templateMetadata: const Value(jsonText),
              ),
            );

        final preset = await (database.select(
          database.presets,
        )..where((p) => p.id.equals(id))).getSingle();

        expect(preset.category, 'Перкуссия');
        expect(preset.templateMetadata, jsonText);
      },
    );

    test(
      'default values for existing rows are null (migration safety)',
      () async {
        // Insert a row without specifying the new columns.
        final id = await database
            .into(database.presets)
            .insert(PresetsCompanion.insert(name: 'Legacy preset'));

        final preset = await (database.select(
          database.presets,
        )..where((p) => p.id.equals(id))).getSingle();

        expect(preset.category, isNull);
        expect(preset.templateMetadata, isNull);
        expect(preset.isTemplate, isFalse);
      },
    , tags: ['regression']);
  });
}
