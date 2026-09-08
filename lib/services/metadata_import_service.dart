import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';

class MetadataImportService {
  final AppDatabase database;

  MetadataImportService(this.database);

  /// Imports metadata from a bundled JSON asset file
  /// This is used to pre-populate the database on first launch
  Future<bool> importFromAsset(String assetPath) async {
    try {
      // Load the JSON file from assets
      final jsonString = await rootBundle.loadString(assetPath);
      return await importFromJson(jsonString);
    } catch (e) {
      return false;
    }
  }

  /// Imports metadata from a JSON string
  /// This is useful for tests where assets aren't available
  Future<bool> importFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> data = json.decode(jsonString);

      // Validate the export format
      if (data['exportType'] != 'full_metadata') {
        return false;
      }

      final exportVersion = (data['exportVersion'] as int?) ?? 1;
      if (exportVersion < 1 || exportVersion > 3) return false;

      final tables = data['tables'] as Map<String, dynamic>;
      if (tables.isEmpty) {
        return false;
      }

      // Validate every grammar before opening the transaction. This also makes
      // unknown grammar versions/tags a clean all-or-nothing import failure.
      final grammars = exportVersion >= 3
          ? _parseAlgorithmRepeatGrammars(
              tables['algorithmRepeatGrammars'] as List<dynamic>?,
            )
          : const <AlgorithmRepeatGrammarEntry>[];

      // Import in the correct order to respect foreign key constraints
      await database.transaction(() async {
        await _importUnits(tables['units'] as List<dynamic>?);
        await _importAlgorithms(tables['algorithms'] as List<dynamic>?);
        await _importSpecifications(tables['specifications'] as List<dynamic>?);
        await _importParameters(tables['parameters'] as List<dynamic>?);
        await _importParameterEnums(tables['parameterEnums'] as List<dynamic>?);
        await _importParameterPages(tables['parameterPages'] as List<dynamic>?);
        await _importParameterPageItems(
          tables['parameterPageItems'] as List<dynamic>?,
        );
        await _importParameterOutputModeUsage(
          tables['parameterOutputModeUsage'] as List<dynamic>?,
        );
        if (exportVersion >= 3 && grammars.isNotEmpty) {
          await database.batch((batch) {
            batch.insertAllOnConflictUpdate(
              database.algorithmRepeatGrammars,
              grammars,
            );
          });
        }
        await _importMetadataCache(tables['metadataCache'] as List<dynamic>?);
      });

      // Log import summary
      final summary = data['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        summary.forEach((key, value) {});
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if the database already has metadata
  Future<bool> hasExistingMetadata() async {
    return await database.metadataDao.hasCachedAlgorithms();
  }

  // --- Private import methods for each table ---

  List<AlgorithmRepeatGrammarEntry> _parseAlgorithmRepeatGrammars(
    List<dynamic>? rows,
  ) {
    if (rows == null) return const [];
    return rows.map((row) {
      final data = row as Map<String, dynamic>;
      final grammarVersion = data['grammarVersion'] as int;
      final compact = data['grammar'];
      if (!AlgorithmRepeatGrammar.supportedVersions.contains(grammarVersion)) {
        throw FormatException('Unsupported grammar version $grammarVersion');
      }
      final grammar = AlgorithmRepeatGrammar.fromCompactJson(compact);
      return AlgorithmRepeatGrammarEntry(
        algorithmGuid: data['algorithmGuid'] as String,
        grammarVersion: AlgorithmRepeatGrammar.currentVersion,
        grammarJson: jsonEncode(grammar.toCompactJson()),
      );
    }).toList();
  }

  Future<void> _importUnits(List<dynamic>? unitsList) async {
    if (unitsList == null || unitsList.isEmpty) {
      return;
    }

    final entries = <UnitsCompanion>[];

    for (final unitData in unitsList) {
      entries.add(
        UnitsCompanion.insert(
          id: Value(unitData['id'] as int),
          unitString: unitData['unitString'] as String,
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.units,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importAlgorithms(List<dynamic>? algorithmsList) async {
    if (algorithmsList == null || algorithmsList.isEmpty) {
      return;
    }

    final entries = <AlgorithmsCompanion>[];

    for (final algoData in algorithmsList) {
      entries.add(
        AlgorithmsCompanion(
          guid: Value(algoData['guid'] as String),
          name: Value(algoData['name'] as String),
          numSpecifications: Value(algoData['numSpecifications'] as int),
          pluginFilePath: Value(algoData['pluginFilePath'] as String?),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(database.algorithms, entries);
    });
  }

  Future<void> _importSpecifications(List<dynamic>? specsList) async {
    if (specsList == null || specsList.isEmpty) {
      return;
    }

    final entries = <SpecificationsCompanion>[];

    for (final specData in specsList) {
      entries.add(
        SpecificationsCompanion(
          algorithmGuid: Value(specData['algorithmGuid'] as String),
          specIndex: Value(specData['specIndex'] as int),
          name: Value(specData['name'] as String),
          minValue: Value(specData['minValue'] as int),
          maxValue: Value(specData['maxValue'] as int),
          defaultValue: Value(specData['defaultValue'] as int),
          type: Value(specData['type'] as int),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.specifications,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importParameters(List<dynamic>? paramsList) async {
    if (paramsList == null || paramsList.isEmpty) {
      return;
    }

    final entries = <ParametersCompanion>[];

    for (final paramData in paramsList) {
      // Read and validate ioFlags field (version 2+ export format)
      // null = no data available, 0-15 = valid flag combinations
      // Missing field (old v1 format) is treated as null
      int? ioFlags = paramData['ioFlags'] as int?;
      if (ioFlags != null && (ioFlags < 0 || ioFlags > 15)) {
        // Invalid flag value outside valid range - treat as null (no data)
        ioFlags = null;
      }

      entries.add(
        ParametersCompanion(
          algorithmGuid: Value(paramData['algorithmGuid'] as String),
          parameterNumber: Value(paramData['parameterNumber'] as int),
          name: Value(paramData['name'] as String),
          minValue: Value(paramData['minValue'] as int?),
          maxValue: Value(paramData['maxValue'] as int?),
          defaultValue: Value(paramData['defaultValue'] as int?),
          unitId: Value(paramData['unitId'] as int?),
          powerOfTen: Value(paramData['powerOfTen'] as int?),
          rawUnitIndex: Value(paramData['rawUnitIndex'] as int?),
          ioFlags: Value(ioFlags), // I/O flags from firmware (null or 0-15)
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.parameters,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importParameterEnums(List<dynamic>? enumsList) async {
    if (enumsList == null || enumsList.isEmpty) {
      return;
    }

    final entries = <ParameterEnumsCompanion>[];

    for (final enumData in enumsList) {
      entries.add(
        ParameterEnumsCompanion(
          algorithmGuid: Value(enumData['algorithmGuid'] as String),
          parameterNumber: Value(enumData['parameterNumber'] as int),
          enumIndex: Value(enumData['enumIndex'] as int),
          enumString: Value(enumData['enumString'] as String),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.parameterEnums,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importParameterPages(List<dynamic>? pagesList) async {
    if (pagesList == null || pagesList.isEmpty) {
      return;
    }

    final entries = <ParameterPagesCompanion>[];

    for (final pageData in pagesList) {
      entries.add(
        ParameterPagesCompanion(
          algorithmGuid: Value(pageData['algorithmGuid'] as String),
          pageIndex: Value(pageData['pageIndex'] as int),
          name: Value(pageData['name'] as String),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.parameterPages,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importParameterPageItems(List<dynamic>? itemsList) async {
    if (itemsList == null || itemsList.isEmpty) {
      return;
    }

    final entries = <ParameterPageItemsCompanion>[];

    for (final itemData in itemsList) {
      entries.add(
        ParameterPageItemsCompanion(
          algorithmGuid: Value(itemData['algorithmGuid'] as String),
          pageIndex: Value(itemData['pageIndex'] as int),
          parameterNumber: Value(itemData['parameterNumber'] as int),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.parameterPageItems,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importParameterOutputModeUsage(List<dynamic>? usageList) async {
    if (usageList == null || usageList.isEmpty) {
      return;
    }

    final entries = <ParameterOutputModeUsageCompanion>[];

    for (final usageData in usageList) {
      final affectedOutputNumbers = (usageData['affectedOutputNumbers'] as List)
          .map((value) => value as int)
          .toList();

      entries.add(
        ParameterOutputModeUsageCompanion(
          algorithmGuid: Value(usageData['algorithmGuid'] as String),
          parameterNumber: Value(usageData['parameterNumber'] as int),
          affectedOutputNumbers: Value(affectedOutputNumbers),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.parameterOutputModeUsage,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _importMetadataCache(List<dynamic>? cacheList) async {
    if (cacheList == null || cacheList.isEmpty) {
      return;
    }

    final entries = <MetadataCacheCompanion>[];

    for (final cacheData in cacheList) {
      entries.add(
        MetadataCacheCompanion(
          cacheKey: Value(cacheData['cacheKey'] as String),
          cacheValue: Value(cacheData['cacheValue'] as String),
        ),
      );
    }

    await database.batch((batch) {
      batch.insertAll(
        database.metadataCache,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}
