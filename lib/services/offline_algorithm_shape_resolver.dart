import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nt_helper/db/database.dart' show SpecificationEntry;
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';

final class ResolvedAlgorithmShape {
  const ResolvedAlgorithmShape({
    required this.snapshot,
    required this.usedGrammar,
  });

  final AlgorithmShapeSnapshot snapshot;
  final bool usedGrammar;
}

/// Resolves the immutable flat database rows into a specification-aware shape.
final class OfflineAlgorithmShapeResolver {
  OfflineAlgorithmShapeResolver(this.dao);

  final MetadataDao dao;

  Future<ResolvedAlgorithmShape> resolve(
    String algorithmGuid,
    List<int> specificationValues,
  ) async {
    final parameters =
        await (dao.select(dao.parameters)
              ..where((row) => row.algorithmGuid.equals(algorithmGuid))
              ..orderBy([(row) => OrderingTerm.asc(row.parameterNumber)]))
            .get();
    final enums =
        await (dao.select(dao.parameterEnums)
              ..where((row) => row.algorithmGuid.equals(algorithmGuid))
              ..orderBy([
                (row) => OrderingTerm.asc(row.parameterNumber),
                (row) => OrderingTerm.asc(row.enumIndex),
              ]))
            .get();
    final pages =
        await (dao.select(dao.parameterPages)
              ..where((row) => row.algorithmGuid.equals(algorithmGuid))
              ..orderBy([(row) => OrderingTerm.asc(row.pageIndex)]))
            .get();
    final pageItems = await (dao.select(
      dao.parameterPageItems,
    )..where((row) => row.algorithmGuid.equals(algorithmGuid))).get();
    final outputUsage =
        await (dao.select(dao.parameterOutputModeUsage)
              ..where((row) => row.algorithmGuid.equals(algorithmGuid))
              ..orderBy([(row) => OrderingTerm.asc(row.parameterNumber)]))
            .get();
    final specifications =
        await (dao.select(dao.specifications)
              ..where((row) => row.algorithmGuid.equals(algorithmGuid))
              ..orderBy([(row) => OrderingTerm.asc(row.specIndex)]))
            .get();

    final enumsByParameter = <int, List<String>>{};
    for (final entry in enums) {
      (enumsByParameter[entry.parameterNumber] ??= []).add(entry.enumString);
    }

    AlgorithmRepeatGrammar? grammar;
    try {
      final row = await dao.getAlgorithmRepeatGrammar(algorithmGuid);
      if (row != null &&
          AlgorithmRepeatGrammar.supportedVersions.contains(
            row.grammarVersion,
          )) {
        grammar = AlgorithmRepeatGrammar.fromCompactJson(
          jsonDecode(row.grammarJson),
        );
      }
    } catch (_) {
      grammar = null;
    }

    final fallbackSpecifications = [
      for (final specification in specifications)
        _safeDefault(
          specification.minValue,
          specification.maxValue,
          specification.defaultValue,
        ),
    ];
    final baseline = grammar?.baselineSpecifications ?? fallbackSpecifications;
    final canonical = AlgorithmShapeSnapshot(
      specificationValues: baseline,
      parameters: [
        for (final parameter in parameters)
          ShapeParameterAtom(
            name: parameter.name,
            min: parameter.minValue ?? 0,
            max: parameter.maxValue ?? 0,
            defaultValue: parameter.defaultValue ?? 0,
            rawUnitIndex: parameter.rawUnitIndex ?? 0,
            powerOfTen: parameter.powerOfTen ?? 0,
            ioFlags: parameter.ioFlags ?? 0,
            enumStrings:
                enumsByParameter[parameter.parameterNumber] ?? const [],
          ),
      ],
      pages: [for (final page in pages) ShapePageAtom(name: page.name)],
      pageMemberships: [
        for (final item in pageItems)
          ShapePageMembershipAtom(
            pageIndex: item.pageIndex,
            parameterNumber: item.parameterNumber,
          ),
      ],
      outputUsage: [
        for (final usage in outputUsage)
          for (final affected in usage.affectedOutputNumbers)
            ShapeOutputUsageAtom(
              parameterNumber: usage.parameterNumber,
              affectedParameterNumber: affected,
            ),
      ],
    );

    if (grammar == null ||
        specificationValues.length != specifications.length ||
        baseline.length != specifications.length ||
        !_inRange(specifications, specificationValues)) {
      return ResolvedAlgorithmShape(snapshot: canonical, usedGrammar: false);
    }
    try {
      return ResolvedAlgorithmShape(
        snapshot: grammar.expand(canonical, specificationValues),
        usedGrammar: true,
      );
    } catch (_) {
      return ResolvedAlgorithmShape(snapshot: canonical, usedGrammar: false);
    }
  }

  bool _inRange(List<SpecificationEntry> specifications, List<int> values) {
    for (var index = 0; index < values.length; index++) {
      final specification = specifications[index];
      if (values[index] < specification.minValue ||
          values[index] > specification.maxValue) {
        return false;
      }
    }
    return true;
  }

  int _safeDefault(int min, int max, int defaultValue) {
    if (defaultValue >= min && defaultValue <= max) return defaultValue;
    return ((min + max) ~/ 2).clamp(min, max);
  }
}
