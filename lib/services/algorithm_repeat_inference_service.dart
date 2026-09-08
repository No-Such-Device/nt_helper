import 'package:collection/collection.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show Specification;
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';

final class SpecificationVector {
  SpecificationVector(List<int> values) : values = List.unmodifiable(values);

  final List<int> values;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecificationVector &&
          const ListEquality<int>().equals(values, other.values);

  @override
  int get hashCode => const ListEquality<int>().hash(values);

  @override
  String toString() => 'SpecificationVector($values)';
}

final class AlgorithmRepeatProbePlan {
  AlgorithmRepeatProbePlan({
    required this.canonical,
    required Map<int, SpecificationVector> lowerWitnessByAxis,
  }) : lowerWitnessByAxis = Map.unmodifiable(lowerWitnessByAxis);

  final SpecificationVector canonical;
  final Map<int, SpecificationVector> lowerWitnessByAxis;
}

final class AdjacentRepeatAnalysis {
  AdjacentRepeatAnalysis._({
    required this.specifications,
    required this.plan,
    required this.snapshots,
    required this.sections,
    required this.interactionAxisGroups,
    this.failureReason,
  });

  final List<Specification> specifications;
  final AlgorithmRepeatProbePlan plan;
  final Map<SpecificationVector, AlgorithmShapeSnapshot> snapshots;
  final List<RepeatSection> sections;
  final List<Set<int>> interactionAxisGroups;
  final String? failureReason;
}

sealed class AlgorithmRepeatInferenceResult {
  const AlgorithmRepeatInferenceResult();
}

final class ProvenAlgorithmRepeatGrammar
    extends AlgorithmRepeatInferenceResult {
  const ProvenAlgorithmRepeatGrammar(this.grammar);
  final AlgorithmRepeatGrammar grammar;
}

final class NoAlgorithmRepeats extends AlgorithmRepeatInferenceResult {
  const NoAlgorithmRepeats();
}

final class UnprovenAlgorithmRepeats extends AlgorithmRepeatInferenceResult {
  const UnprovenAlgorithmRepeats(this.reason);
  final String reason;
}

/// Infers the deliberately small version-1 adjacent count-repeat grammar.
final class AlgorithmRepeatInferenceService {
  static final RegExp _countNamePattern = RegExp(
    r'\b(channels?|inputs?|outputs?|sends?|stereo|voices?)\b',
    caseSensitive: false,
  );

  static bool isRepeatCandidate(Specification specification) {
    if (specification.type != 0 && specification.type != 2) return false;
    return _countNamePattern.hasMatch(specification.name);
  }

  AlgorithmRepeatProbePlan buildInitialPlan(List<Specification> specs) {
    final canonical = <int>[];
    final selectedAxes = <int>[];
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      if (isRepeatCandidate(spec) && spec.min < spec.max) {
        canonical.add(spec.min + 1);
        selectedAxes.add(index);
      } else {
        canonical.add(spec.safeDefaultValue);
      }
    }
    return AlgorithmRepeatProbePlan(
      canonical: SpecificationVector(canonical),
      lowerWitnessByAxis: {
        for (final axis in selectedAxes)
          axis: SpecificationVector([
            for (var index = 0; index < canonical.length; index++)
              index == axis ? specs[index].min : canonical[index],
          ]),
      },
    );
  }

  AdjacentRepeatAnalysis analyzeInitial({
    required List<Specification> specifications,
    required AlgorithmRepeatProbePlan plan,
    required Map<SpecificationVector, AlgorithmShapeSnapshot> snapshots,
  }) {
    final canonical = snapshots[plan.canonical];
    if (canonical == null ||
        !const ListEquality<int>().equals(
          canonical.specificationValues,
          plan.canonical.values,
        )) {
      return _failed(
        specifications,
        plan,
        snapshots,
        'Missing or mismatched canonical witness',
      );
    }

    final sections = <RepeatSection>[];
    for (final entry in plan.lowerWitnessByAxis.entries) {
      final lower = snapshots[entry.value];
      if (lower == null ||
          !const ListEquality<int>().equals(
            lower.specificationValues,
            entry.value.values,
          )) {
        return _failed(
          specifications,
          plan,
          snapshots,
          'Missing or mismatched lower witness for axis ${entry.key}',
        );
      }
      try {
        sections.addAll(
          _inferAxisSections(
            entry.key,
            specifications[entry.key],
            canonical,
            lower,
          ),
        );
      } on FormatException catch (error) {
        return _failed(
          specifications,
          plan,
          snapshots,
          'Axis ${entry.key} is ambiguous: ${error.message}',
        );
      }
    }

    final groups = _interactionGroups(sections, plan.canonical.values);
    return AdjacentRepeatAnalysis._(
      specifications: List.unmodifiable(specifications),
      plan: plan,
      snapshots: Map.unmodifiable(snapshots),
      sections: List.unmodifiable(sections),
      interactionAxisGroups: List.unmodifiable(groups),
    );
  }

  List<SpecificationVector> interactionWitnesses(
    AdjacentRepeatAnalysis analysis,
  ) {
    if (analysis.failureReason != null) return const [];
    return analysis.interactionAxisGroups
        .where((group) => group.length >= 2)
        .map((group) {
          final values = [...analysis.plan.canonical.values];
          for (final axis in group) {
            values[axis] = analysis.specifications[axis].min;
          }
          return SpecificationVector(values);
        })
        .toSet()
        .toList();
  }

  AlgorithmRepeatInferenceResult compile({
    required AdjacentRepeatAnalysis analysis,
    required Map<SpecificationVector, AlgorithmShapeSnapshot> snapshots,
  }) {
    if (analysis.failureReason case final reason?) {
      return UnprovenAlgorithmRepeats(reason);
    }
    if (analysis.sections.isEmpty) return const NoAlgorithmRepeats();
    if (analysis.interactionAxisGroups.any((group) => group.length > 2)) {
      return const UnprovenAlgorithmRepeats(
        'Version 1 cannot prove three interacting count axes',
      );
    }
    for (final witness in interactionWitnesses(analysis)) {
      final snapshot = snapshots[witness];
      if (snapshot == null ||
          !const ListEquality<int>().equals(
            snapshot.specificationValues,
            witness.values,
          )) {
        return const UnprovenAlgorithmRepeats(
          'Missing or mismatched interaction witness',
        );
      }
    }

    List<RepeatSection> compiledSections;
    try {
      compiledSections = _nestInteractions(
        analysis.sections,
        analysis.plan.canonical.values,
        snapshots[analysis.plan.canonical]!,
      );
    } on FormatException catch (error) {
      return UnprovenAlgorithmRepeats(
        'Interaction could not be proven: ${error.message}',
      );
    }
    final grammar = AlgorithmRepeatGrammar(
      baselineSpecifications: analysis.plan.canonical.values,
      sections: compiledSections,
    );
    try {
      final witnesses = <SpecificationVector>{
        analysis.plan.canonical,
        ...analysis.plan.lowerWitnessByAxis.values,
        ...interactionWitnesses(analysis),
      };
      for (final vector in witnesses) {
        final expected = snapshots[vector];
        if (expected == null ||
            grammar.expand(
                  snapshots[analysis.plan.canonical]!,
                  vector.values,
                ) !=
                expected) {
          return UnprovenAlgorithmRepeats(
            'Grammar does not reconstruct witness $vector',
          );
        }
      }
    } on FormatException catch (error) {
      return UnprovenAlgorithmRepeats(
        'Grammar expansion failed: ${error.message}',
      );
    }
    return ProvenAlgorithmRepeatGrammar(grammar);
  }

  AdjacentRepeatAnalysis _failed(
    List<Specification> specifications,
    AlgorithmRepeatProbePlan plan,
    Map<SpecificationVector, AlgorithmShapeSnapshot> snapshots,
    String reason,
  ) => AdjacentRepeatAnalysis._(
    specifications: List.unmodifiable(specifications),
    plan: plan,
    snapshots: Map.unmodifiable(snapshots),
    sections: const [],
    interactionAxisGroups: const [],
    failureReason: reason,
  );

  List<RepeatSection> _inferAxisSections(
    int axis,
    Specification specification,
    AlgorithmShapeSnapshot canonical,
    AlgorithmShapeSnapshot lower,
  ) {
    final parameterAlignment = _align<ShapeParameterAtom>(
      canonical.parameters,
      lower.parameters,
      _parameterMatch,
    );
    final pageAlignment = _align<ShapePageAtom>(
      canonical.pages,
      lower.pages,
      _pageMatch,
    );
    if (parameterAlignment.ambiguous || pageAlignment.ambiguous) {
      throw const FormatException('tied metadata alignment');
    }

    final sections = <RepeatSection>[];
    sections.addAll(
      _sectionsForUnmatched<ShapeParameterAtom>(
        axis: axis,
        specification: specification,
        stream: ShapeStream.parameters,
        canonical: canonical.parameters,
        unmatched: parameterAlignment.unmatchedCanonical,
        compatible: (a, b) => _parameterMatch(a, b) > 0,
        substitutions: _parameterSubstitutions,
      ),
    );
    sections.addAll(
      _sectionsForUnmatched<ShapePageAtom>(
        axis: axis,
        specification: specification,
        stream: ShapeStream.pages,
        canonical: canonical.pages,
        unmatched: pageAlignment.unmatchedCanonical,
        compatible: (a, b) => _pageMatch(a, b) > 0,
        substitutions: _pageSubstitutions,
      ),
    );

    final remappedLowerMemberships = lower.pageMemberships
        .map(
          (edge) => ShapePageMembershipAtom(
            pageIndex: pageAlignment.lowerToCanonical[edge.pageIndex] ?? -1,
            parameterNumber:
                parameterAlignment.lowerToCanonical[edge.parameterNumber] ?? -1,
          ),
        )
        .toList();
    final membershipAlignment = _align<ShapePageMembershipAtom>(
      canonical.pageMemberships,
      remappedLowerMemberships,
      (a, b) => a == b ? 2 : 0,
    );
    final remappedLowerUsage = lower.outputUsage
        .map(
          (edge) => ShapeOutputUsageAtom(
            parameterNumber:
                parameterAlignment.lowerToCanonical[edge.parameterNumber] ?? -1,
            affectedParameterNumber:
                parameterAlignment.lowerToCanonical[edge
                    .affectedParameterNumber] ??
                -1,
          ),
        )
        .toList();
    final usageAlignment = _align<ShapeOutputUsageAtom>(
      canonical.outputUsage,
      remappedLowerUsage,
      (a, b) => a == b ? 2 : 0,
    );
    if (membershipAlignment.ambiguous || usageAlignment.ambiguous) {
      throw const FormatException('ambiguous relationship ownership');
    }
    sections.addAll(
      _relationshipSections<ShapePageMembershipAtom>(
        axis: axis,
        specification: specification,
        stream: ShapeStream.memberships,
        canonical: canonical.pageMemberships,
        unmatched: membershipAlignment.unmatchedCanonical,
        structuralSections: sections,
        parameterReferences: (edge) => [edge.parameterNumber],
        pageReferences: (edge) => [edge.pageIndex],
      ),
    );
    sections.addAll(
      _relationshipSections<ShapeOutputUsageAtom>(
        axis: axis,
        specification: specification,
        stream: ShapeStream.outputUsage,
        canonical: canonical.outputUsage,
        unmatched: usageAlignment.unmatchedCanonical,
        structuralSections: sections,
        parameterReferences: (edge) => [
          edge.parameterNumber,
          edge.affectedParameterNumber,
        ],
        pageReferences: (_) => const [],
      ),
    );

    final topologyChanged =
        canonical.parameters.length != lower.parameters.length ||
        canonical.pages.length != lower.pages.length ||
        canonical.pageMemberships.length != lower.pageMemberships.length ||
        canonical.outputUsage.length != lower.outputUsage.length;
    if (topologyChanged && sections.isEmpty) {
      throw const FormatException('unsupported topology change');
    }
    return sections;
  }

  List<RepeatSection> _sectionsForUnmatched<T>({
    required int axis,
    required Specification specification,
    required ShapeStream stream,
    required List<T> canonical,
    required List<int> unmatched,
    required bool Function(T a, T b) compatible,
    required List<OrdinalSubstitution> Function(
      List<List<T>> occurrences,
      ShapeStream stream,
      int axis,
      int sourceOrdinal,
    )
    substitutions,
  }) {
    final sections = <RepeatSection>[];
    for (final range in _contiguousRanges(unmatched)) {
      final itemCount = range.end - range.start;
      if (itemCount <= 0) continue;
      bool blocksCompatible(int first, int second) {
        if (first < 0 ||
            second < 0 ||
            first + itemCount > canonical.length ||
            second + itemCount > canonical.length) {
          return false;
        }
        for (var offset = 0; offset < itemCount; offset++) {
          if (!compatible(
            canonical[first + offset],
            canonical[second + offset],
          )) {
            return false;
          }
        }
        return true;
      }

      var firstStart = range.start;
      while (blocksCompatible(firstStart - itemCount, firstStart)) {
        firstStart -= itemCount;
      }
      var end = range.end;
      while (blocksCompatible(range.start, end)) {
        end += itemCount;
      }
      final occurrenceCount = (end - firstStart) ~/ itemCount;
      final sourceOrdinal = (range.start - firstStart) ~/ itemCount;
      final countBias =
          occurrenceCount - canonicalSpecificationValue(specification);
      if (specification.min + countBias < 0) {
        throw const FormatException('negative repeat count in declared range');
      }
      final occurrences = <List<T>>[
        for (var ordinal = 0; ordinal < occurrenceCount; ordinal++)
          canonical.sublist(
            firstStart + ordinal * itemCount,
            firstStart + (ordinal + 1) * itemCount,
          ),
      ];
      sections.add(
        RepeatSection(
          specificationIndex: axis,
          countBias: countBias,
          sourceOrdinal: sourceOrdinal,
          runs: [
            ShapeStreamRun(
              stream: stream,
              firstStart: firstStart,
              itemCount: itemCount,
            ),
          ],
          substitutions: substitutions(
            occurrences,
            stream,
            axis,
            sourceOrdinal,
          ),
          children: const [],
        ),
      );
    }
    return sections;
  }

  int canonicalSpecificationValue(Specification specification) =>
      specification.min + 1;

  List<RepeatSection> _relationshipSections<T>({
    required int axis,
    required Specification specification,
    required ShapeStream stream,
    required List<T> canonical,
    required List<int> unmatched,
    required List<RepeatSection> structuralSections,
    required Iterable<int> Function(T row) parameterReferences,
    required Iterable<int> Function(T row) pageReferences,
  }) {
    if (unmatched.isEmpty) return const [];
    final canonicalSpecification = canonicalSpecificationValue(specification);

    ({int countBias, int ordinal})? ownerFor(T row) {
      ({int countBias, int ordinal})? owner;
      void includeReference(int reference, ShapeStream referenceStream) {
        for (final section in structuralSections) {
          if (section.specificationIndex != axis) continue;
          final run = section.runFor(referenceStream);
          if (run == null) continue;
          final occurrenceCount = canonicalSpecification + section.countBias;
          final end = run.firstStart + occurrenceCount * run.itemCount;
          if (reference < run.firstStart || reference >= end) continue;
          final next = (
            countBias: section.countBias,
            ordinal: (reference - run.firstStart) ~/ run.itemCount,
          );
          if (owner != null && owner != next) {
            throw const FormatException(
              'relationship endpoints have different repeat owners',
            );
          }
          owner = next;
        }
      }

      for (final reference in parameterReferences(row)) {
        includeReference(reference, ShapeStream.parameters);
      }
      for (final reference in pageReferences(row)) {
        includeReference(reference, ShapeStream.pages);
      }
      return owner;
    }

    final owners = canonical.map(ownerFor).toList();
    final unmatchedSet = unmatched.toSet();
    final consumed = <int>{};
    final sections = <RepeatSection>[];
    var cursor = 0;
    while (cursor < owners.length) {
      final first = owners[cursor];
      if (first == null || first.ordinal != 0) {
        cursor++;
        continue;
      }
      var itemCount = 0;
      while (cursor + itemCount < owners.length &&
          owners[cursor + itemCount] == first) {
        itemCount++;
      }
      final occurrenceCount = canonicalSpecification + first.countBias;
      if (occurrenceCount <= 0) {
        throw const FormatException('invalid relationship repeat count');
      }
      final runEnd = cursor + occurrenceCount * itemCount;
      var complete = runEnd <= owners.length;
      if (complete) {
        for (var ordinal = 0; ordinal < occurrenceCount; ordinal++) {
          for (var offset = 0; offset < itemCount; offset++) {
            if (owners[cursor + ordinal * itemCount + offset] !=
                (countBias: first.countBias, ordinal: ordinal)) {
              complete = false;
              break;
            }
          }
          if (!complete) break;
        }
      }
      if (!complete) {
        cursor++;
        continue;
      }

      final removedOrdinals = <int>[];
      for (var ordinal = 0; ordinal < occurrenceCount; ordinal++) {
        final indexes = [
          for (var offset = 0; offset < itemCount; offset++)
            cursor + ordinal * itemCount + offset,
        ];
        final removed = indexes.where(unmatchedSet.contains).length;
        if (removed == indexes.length) {
          removedOrdinals.add(ordinal);
        } else if (removed != 0) {
          throw const FormatException(
            'relationship occurrence is only partially inserted',
          );
        }
      }
      if (removedOrdinals.length == 1) {
        sections.add(
          RepeatSection(
            specificationIndex: axis,
            countBias: first.countBias,
            sourceOrdinal: removedOrdinals.single,
            runs: [
              ShapeStreamRun(
                stream: stream,
                firstStart: cursor,
                itemCount: itemCount,
              ),
            ],
            substitutions: const [],
            children: const [],
          ),
        );
        consumed.addAll([
          for (var offset = 0; offset < itemCount; offset++)
            cursor + removedOrdinals.single * itemCount + offset,
        ]);
      }
      cursor = runEnd;
    }
    if (!consumed.containsAll(unmatchedSet)) {
      throw const FormatException('unresolved relationship ownership');
    }
    return sections;
  }

  int _parameterMatch(ShapeParameterAtom a, ShapeParameterAtom b) {
    if (a.rawUnitIndex != b.rawUnitIndex ||
        a.powerOfTen != b.powerOfTen ||
        a.ioFlags != b.ioFlags ||
        a.enumStrings.length != b.enumStrings.length) {
      return 0;
    }
    final exactText =
        a.name == b.name &&
        const ListEquality<String>().equals(a.enumStrings, b.enumStrings);
    if (exactText) return 2;
    if (!_ordinalCompatibleText(a.name, b.name)) return 0;
    for (var index = 0; index < a.enumStrings.length; index++) {
      final aValue = a.enumStrings[index];
      final bValue = b.enumStrings[index];
      if (aValue != bValue && !_ordinalCompatibleText(aValue, bValue)) {
        return 0;
      }
    }
    return 1;
  }

  int _pageMatch(ShapePageAtom a, ShapePageAtom b) {
    if (a.name == b.name) return 2;
    return _ordinalCompatibleText(a.name, b.name) ? 1 : 0;
  }

  bool _ordinalCompatibleText(String a, String b) {
    final aParts = _splitDigits(a);
    final bParts = _splitDigits(b);
    if (aParts.length != bParts.length) return false;
    int? delta;
    var changed = false;
    for (var index = 0; index < aParts.length; index++) {
      final aPart = aParts[index];
      final bPart = bParts[index];
      if (aPart is String || bPart is String) {
        if (aPart != bPart) return false;
        continue;
      }
      final nextDelta = (aPart as int) - (bPart as int);
      if (nextDelta == 0) continue;
      changed = true;
      if (delta != null && delta != nextDelta) return false;
      delta = nextDelta;
    }
    return changed;
  }

  List<Object> _splitDigits(String value) {
    final result = <Object>[];
    var cursor = 0;
    for (final match in RegExp(r'\d+').allMatches(value)) {
      result.add(value.substring(cursor, match.start));
      result.add(int.parse(match.group(0)!));
      cursor = match.end;
    }
    result.add(value.substring(cursor));
    return result;
  }

  List<OrdinalSubstitution> _parameterSubstitutions(
    List<List<ShapeParameterAtom>> occurrences,
    ShapeStream stream,
    int axis,
    int sourceOrdinal,
  ) {
    final substitutions = <OrdinalSubstitution>[];
    final itemCount = occurrences.first.length;
    for (var offset = 0; offset < itemCount; offset++) {
      final rows = occurrences.map((occurrence) => occurrence[offset]).toList();
      if (rows.any(
        (row) =>
            row.rawUnitIndex != rows.first.rawUnitIndex ||
            row.powerOfTen != rows.first.powerOfTen ||
            row.ioFlags != rows.first.ioFlags ||
            row.enumStrings.length != rows.first.enumStrings.length,
      )) {
        throw const FormatException('non-isomorphic parameter occurrence');
      }
      final nameParts = _inferTextParts(
        rows.map((row) => row.name).toList(),
        axis,
        sourceOrdinal,
      );
      if (nameParts != null) {
        substitutions.add(
          OrdinalTextSubstitution(
            stream: stream,
            rowOffset: offset,
            field: OrdinalField.parameterName,
            parts: nameParts,
          ),
        );
      }
      for (
        var enumIndex = 0;
        enumIndex < rows.first.enumStrings.length;
        enumIndex++
      ) {
        final enumParts = _inferTextParts(
          rows.map((row) => row.enumStrings[enumIndex]).toList(),
          axis,
          sourceOrdinal,
        );
        if (enumParts != null) {
          substitutions.add(
            OrdinalTextSubstitution(
              stream: stream,
              rowOffset: offset,
              field: OrdinalField.parameterEnumString,
              elementIndex: enumIndex,
              parts: enumParts,
            ),
          );
        }
      }
      substitutions.addAll(_integerSubstitutions(rows, stream, offset, axis));
    }
    return substitutions;
  }

  List<OrdinalSubstitution> _pageSubstitutions(
    List<List<ShapePageAtom>> occurrences,
    ShapeStream stream,
    int axis,
    int sourceOrdinal,
  ) {
    final substitutions = <OrdinalSubstitution>[];
    for (var offset = 0; offset < occurrences.first.length; offset++) {
      final parts = _inferTextParts(
        occurrences.map((occurrence) => occurrence[offset].name).toList(),
        axis,
        sourceOrdinal,
      );
      if (parts != null) {
        substitutions.add(
          OrdinalTextSubstitution(
            stream: stream,
            rowOffset: offset,
            field: OrdinalField.pageName,
            parts: parts,
          ),
        );
      }
    }
    return substitutions;
  }

  List<OrdinalTextPart>? _inferTextParts(
    List<String> values,
    int axis,
    int sourceOrdinal,
  ) {
    if (values.toSet().length == 1 && !RegExp(r'\d').hasMatch(values.first)) {
      return null;
    }
    final split = values.map(_splitDigits).toList();
    if (split.any((parts) => parts.length != split.first.length)) {
      throw const FormatException('unsupported ordinal text change');
    }
    final result = <OrdinalTextPart>[];
    var usedPlaceholder = false;
    for (var partIndex = 0; partIndex < split.first.length; partIndex++) {
      final parts = split.map((value) => value[partIndex]).toList();
      if (parts.first is String) {
        if (parts.toSet().length != 1) {
          throw const FormatException('unsupported text substitution');
        }
        result.add(LiteralTextPart(parts.first as String));
        continue;
      }
      final digits = parts.cast<int>();
      final bias = digits.first;
      final advances = [
        for (var ordinal = 0; ordinal < digits.length; ordinal++)
          digits[ordinal] == ordinal + bias,
      ].every((value) => value);
      final singleSourceHint =
          digits.length == 1 && digits.single == sourceOrdinal + 1;
      if (advances || singleSourceHint) {
        result.add(
          OrdinalTextPlaceholder(
            specificationIndex: axis,
            displayBias: advances ? bias : 1,
          ),
        );
        usedPlaceholder = true;
      } else if (digits.toSet().length == 1) {
        result.add(LiteralTextPart('${digits.first}'));
      } else {
        throw const FormatException('non-affine ordinal text');
      }
    }
    return usedPlaceholder ? result : null;
  }

  List<OrdinalSubstitution> _integerSubstitutions(
    List<ShapeParameterAtom> rows,
    ShapeStream stream,
    int rowOffset,
    int axis,
  ) {
    final result = <OrdinalSubstitution>[];
    for (final field in const [
      OrdinalField.parameterMin,
      OrdinalField.parameterMax,
      OrdinalField.parameterDefault,
    ]) {
      final values = rows
          .map(
            (row) => switch (field) {
              OrdinalField.parameterMin => row.min,
              OrdinalField.parameterMax => row.max,
              OrdinalField.parameterDefault => row.defaultValue,
              _ => throw StateError('unreachable'),
            },
          )
          .toList();
      if (values.toSet().length == 1) continue;
      final coefficient = values[1] - values[0];
      for (var ordinal = 0; ordinal < values.length; ordinal++) {
        if (values[ordinal] != values[0] + coefficient * ordinal) {
          throw const FormatException('non-affine integer occurrence');
        }
      }
      result.add(
        AffineIntegerSubstitution(
          stream: stream,
          rowOffset: rowOffset,
          field: field,
          constant: values[0],
          coefficients: [
            AffineCoefficient(
              specificationIndex: axis,
              coefficient: coefficient,
            ),
          ],
        ),
      );
    }
    return result;
  }

  _Alignment _align<T>(
    List<T> canonical,
    List<T> lower,
    int Function(T canonical, T lower) matchScore,
  ) {
    final scores = List.generate(
      canonical.length + 1,
      (_) => List.filled(lower.length + 1, 0),
    );
    final ways = List.generate(
      canonical.length + 1,
      (_) => List.filled(lower.length + 1, 1),
    );
    for (var i = canonical.length - 1; i >= 0; i--) {
      for (var j = lower.length - 1; j >= 0; j--) {
        final options = <(int score, int ways, int kind)>[
          (scores[i + 1][j], ways[i + 1][j], 0),
          (scores[i][j + 1], ways[i][j + 1], 1),
        ];
        final match = matchScore(canonical[i], lower[j]);
        if (match > 0) {
          options.add((match + scores[i + 1][j + 1], ways[i + 1][j + 1], 2));
        }
        final best = options
            .map((option) => option.$1)
            .reduce((a, b) => a > b ? a : b);
        scores[i][j] = best;
        ways[i][j] = options
            .where((option) => option.$1 == best)
            .fold<int>(0, (sum, option) => (sum + option.$2).clamp(0, 2));
      }
    }

    final canonicalToLower = <int, int>{};
    final lowerToCanonical = <int, int>{};
    final unmatched = <int>[];
    var i = 0;
    var j = 0;
    var ambiguous = false;
    while (i < canonical.length || j < lower.length) {
      if (i == canonical.length) {
        j++;
        continue;
      }
      if (j == lower.length) {
        unmatched.add(i++);
        continue;
      }
      final choices = <int>[];
      final best = scores[i][j];
      final match = matchScore(canonical[i], lower[j]);
      if (match > 0 && match + scores[i + 1][j + 1] == best) choices.add(2);
      if (scores[i + 1][j] == best) choices.add(0);
      if (scores[i][j + 1] == best) choices.add(1);
      if (choices.length > 1) {
        final exactMatch = match == 2 && choices.contains(2);
        if (exactMatch) {
          choices
            ..clear()
            ..add(2);
        } else {
          ambiguous = true;
          break;
        }
      }
      switch (choices.single) {
        case 2:
          canonicalToLower[i] = j;
          lowerToCanonical[j] = i;
          i++;
          j++;
        case 0:
          unmatched.add(i++);
        case 1:
          j++;
      }
    }
    return _Alignment(
      canonicalToLower: canonicalToLower,
      lowerToCanonical: lowerToCanonical,
      unmatchedCanonical: unmatched,
      ambiguous:
          ambiguous ||
          ways[0][0] > 1 && canonical.isNotEmpty && lower.isNotEmpty,
    );
  }

  List<Set<int>> _interactionGroups(
    List<RepeatSection> sections,
    List<int> baseline,
  ) {
    final adjacency = <int, Set<int>>{};
    for (var i = 0; i < sections.length; i++) {
      for (var j = i + 1; j < sections.length; j++) {
        final a = sections[i];
        final b = sections[j];
        if (a.specificationIndex == b.specificationIndex) continue;
        if (_sectionsOverlap(a, b, baseline)) {
          (adjacency[a.specificationIndex] ??= {}).add(b.specificationIndex);
          (adjacency[b.specificationIndex] ??= {}).add(a.specificationIndex);
        }
      }
    }
    final groups = <Set<int>>[];
    final visited = <int>{};
    for (final axis in adjacency.keys) {
      if (!visited.add(axis)) continue;
      final group = <int>{axis};
      final pending = <int>[axis];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        for (final next in adjacency[current] ?? const <int>{}) {
          if (visited.add(next)) pending.add(next);
          group.add(next);
        }
      }
      groups.add(group);
    }
    return groups;
  }

  bool _sectionsOverlap(RepeatSection a, RepeatSection b, List<int> baseline) {
    for (final aRun in a.runs) {
      for (final bRun in b.runs.where((run) => run.stream == aRun.stream)) {
        final aEnd =
            aRun.firstStart +
            (baseline[a.specificationIndex] + a.countBias) * aRun.itemCount;
        final bEnd =
            bRun.firstStart +
            (baseline[b.specificationIndex] + b.countBias) * bRun.itemCount;
        if (aRun.firstStart < bEnd && bRun.firstStart < aEnd) return true;
      }
    }
    return false;
  }

  List<RepeatSection> _nestInteractions(
    List<RepeatSection> original,
    List<int> baseline,
    AlgorithmShapeSnapshot canonical,
  ) {
    var sections = [...original];
    var changed = true;
    while (changed) {
      changed = false;
      for (final outer in [...sections]) {
        final outerCount = baseline[outer.specificationIndex] + outer.countBias;
        final candidates = <_NestedCandidate>[];
        for (final inner in sections) {
          if (inner == outer ||
              inner.specificationIndex == outer.specificationIndex ||
              inner.runs.length != 1) {
            continue;
          }
          final innerRun = inner.runs.single;
          final outerRun = outer.runFor(innerRun.stream);
          if (outerRun == null) continue;
          final innerCount =
              baseline[inner.specificationIndex] + inner.countBias;
          final relativeStart = innerRun.firstStart - outerRun.firstStart;
          if (relativeStart < 0) continue;
          final outerOrdinal = relativeStart ~/ outerRun.itemCount;
          if (outerOrdinal >= outerCount) continue;
          final relativeOffset = relativeStart % outerRun.itemCount;
          if (relativeOffset + innerCount * innerRun.itemCount >
              outerRun.itemCount) {
            continue;
          }
          candidates.add(
            _NestedCandidate(
              section: inner,
              run: innerRun,
              outerOrdinal: outerOrdinal,
              relativeOffset: relativeOffset,
            ),
          );
        }
        if (candidates.isEmpty) continue;
        _NestedCandidate? seed;
        List<_NestedCandidate> group = const [];
        for (final candidate in candidates) {
          final matches = candidates.where((other) {
            return other.section.specificationIndex ==
                    candidate.section.specificationIndex &&
                other.section.countBias == candidate.section.countBias &&
                other.section.sourceOrdinal ==
                    candidate.section.sourceOrdinal &&
                other.run.stream == candidate.run.stream &&
                other.run.itemCount == candidate.run.itemCount &&
                other.relativeOffset == candidate.relativeOffset;
          }).toList();
          if (matches.length == outerCount &&
              matches.map((entry) => entry.outerOrdinal).toSet().length ==
                  outerCount) {
            seed = candidate;
            group = matches;
            break;
          }
        }
        if (seed == null) continue;
        final innerAxis = seed.section.specificationIndex;
        final innerCount = baseline[innerAxis] + seed.section.countBias;
        final outerRun = outer.runFor(seed.run.stream)!;
        final child = RepeatSection(
          specificationIndex: innerAxis,
          countBias: seed.section.countBias,
          sourceOrdinal: seed.section.sourceOrdinal,
          runs: [
            ShapeStreamRun(
              stream: seed.run.stream,
              firstStart: seed.relativeOffset,
              itemCount: seed.run.itemCount,
            ),
          ],
          substitutions: _nestedSubstitutions(
            canonical: canonical,
            stream: seed.run.stream,
            outerRun: outerRun,
            outerAxis: outer.specificationIndex,
            outerCount: outerCount,
            relativeOffset: seed.relativeOffset,
            itemCount: seed.run.itemCount,
            innerAxis: innerAxis,
            innerCount: innerCount,
            innerSourceOrdinal: seed.section.sourceOrdinal,
          ),
          children: const [],
        );
        final replacement = RepeatSection(
          specificationIndex: outer.specificationIndex,
          countBias: outer.countBias,
          sourceOrdinal: outer.sourceOrdinal,
          runs: outer.runs,
          substitutions: outer.substitutions,
          children: [...outer.children, child],
        );
        sections = [
          for (final section in sections)
            if (section == outer)
              replacement
            else if (!group.any((entry) => entry.section == section))
              section,
        ];
        changed = true;
        break;
      }
    }
    if (_interactionGroups(sections, baseline).isNotEmpty) {
      throw const FormatException('overlapping sections remain');
    }
    return sections;
  }

  List<OrdinalSubstitution> _nestedSubstitutions({
    required AlgorithmShapeSnapshot canonical,
    required ShapeStream stream,
    required ShapeStreamRun outerRun,
    required int outerAxis,
    required int outerCount,
    required int relativeOffset,
    required int itemCount,
    required int innerAxis,
    required int innerCount,
    required int innerSourceOrdinal,
  }) {
    if (stream != ShapeStream.parameters && stream != ShapeStream.pages) {
      return const [];
    }
    final rows = switch (stream) {
      ShapeStream.parameters => canonical.parameters.cast<Object>(),
      ShapeStream.pages => canonical.pages.cast<Object>(),
      _ => const <Object>[],
    };
    final result = <OrdinalSubstitution>[];
    for (var offset = 0; offset < itemCount; offset++) {
      final samples = <_NestedAtomSample>[
        for (var outerOrdinal = 0; outerOrdinal < outerCount; outerOrdinal++)
          for (var innerOrdinal = 0; innerOrdinal < innerCount; innerOrdinal++)
            _NestedAtomSample(
              value:
                  rows[outerRun.firstStart +
                      outerOrdinal * outerRun.itemCount +
                      relativeOffset +
                      innerOrdinal * itemCount +
                      offset],
              outerOrdinal: outerOrdinal,
              innerOrdinal: innerOrdinal,
            ),
      ];
      if (stream == ShapeStream.pages) {
        final parts = _inferNestedTextParts(
          samples
              .map(
                (sample) => _NestedTextSample(
                  value: (sample.value as ShapePageAtom).name,
                  outerOrdinal: sample.outerOrdinal,
                  innerOrdinal: sample.innerOrdinal,
                ),
              )
              .toList(),
          outerAxis: outerAxis,
          innerAxis: innerAxis,
          innerSourceOrdinal: innerSourceOrdinal,
        );
        if (parts != null) {
          result.add(
            OrdinalTextSubstitution(
              stream: stream,
              rowOffset: offset,
              field: OrdinalField.pageName,
              parts: parts,
            ),
          );
        }
        continue;
      }

      final parameters = samples
          .map(
            (sample) => _NestedParameterSample(
              value: sample.value as ShapeParameterAtom,
              outerOrdinal: sample.outerOrdinal,
              innerOrdinal: sample.innerOrdinal,
            ),
          )
          .toList();
      final first = parameters.first.value;
      if (parameters.any(
        (sample) =>
            sample.value.rawUnitIndex != first.rawUnitIndex ||
            sample.value.powerOfTen != first.powerOfTen ||
            sample.value.ioFlags != first.ioFlags ||
            sample.value.enumStrings.length != first.enumStrings.length,
      )) {
        throw const FormatException('non-isomorphic nested parameter');
      }
      final nameParts = _inferNestedTextParts(
        parameters
            .map(
              (sample) => _NestedTextSample(
                value: sample.value.name,
                outerOrdinal: sample.outerOrdinal,
                innerOrdinal: sample.innerOrdinal,
              ),
            )
            .toList(),
        outerAxis: outerAxis,
        innerAxis: innerAxis,
        innerSourceOrdinal: innerSourceOrdinal,
      );
      if (nameParts != null) {
        result.add(
          OrdinalTextSubstitution(
            stream: stream,
            rowOffset: offset,
            field: OrdinalField.parameterName,
            parts: nameParts,
          ),
        );
      }
      for (
        var enumIndex = 0;
        enumIndex < first.enumStrings.length;
        enumIndex++
      ) {
        final enumParts = _inferNestedTextParts(
          parameters
              .map(
                (sample) => _NestedTextSample(
                  value: sample.value.enumStrings[enumIndex],
                  outerOrdinal: sample.outerOrdinal,
                  innerOrdinal: sample.innerOrdinal,
                ),
              )
              .toList(),
          outerAxis: outerAxis,
          innerAxis: innerAxis,
          innerSourceOrdinal: innerSourceOrdinal,
        );
        if (enumParts != null) {
          result.add(
            OrdinalTextSubstitution(
              stream: ShapeStream.parameters,
              rowOffset: offset,
              field: OrdinalField.parameterEnumString,
              elementIndex: enumIndex,
              parts: enumParts,
            ),
          );
        }
      }
      for (final field in const [
        OrdinalField.parameterMin,
        OrdinalField.parameterMax,
        OrdinalField.parameterDefault,
      ]) {
        int valueOf(ShapeParameterAtom parameter) => switch (field) {
          OrdinalField.parameterMin => parameter.min,
          OrdinalField.parameterMax => parameter.max,
          OrdinalField.parameterDefault => parameter.defaultValue,
          _ => throw StateError('unreachable'),
        };
        final base = parameters
            .singleWhere(
              (sample) => sample.outerOrdinal == 0 && sample.innerOrdinal == 0,
            )
            .value;
        final constant = valueOf(base);
        final outerCoefficient = outerCount > 1
            ? valueOf(
                    parameters
                        .singleWhere(
                          (sample) =>
                              sample.outerOrdinal == 1 &&
                              sample.innerOrdinal == 0,
                        )
                        .value,
                  ) -
                  constant
            : 0;
        final innerCoefficient = innerCount > 1
            ? valueOf(
                    parameters
                        .singleWhere(
                          (sample) =>
                              sample.outerOrdinal == 0 &&
                              sample.innerOrdinal == 1,
                        )
                        .value,
                  ) -
                  constant
            : 0;
        if (parameters.any(
          (sample) =>
              valueOf(sample.value) !=
              constant +
                  outerCoefficient * sample.outerOrdinal +
                  innerCoefficient * sample.innerOrdinal,
        )) {
          throw const FormatException('non-affine nested integer occurrence');
        }
        if (outerCoefficient == 0 && innerCoefficient == 0) continue;
        result.add(
          AffineIntegerSubstitution(
            stream: stream,
            rowOffset: offset,
            field: field,
            constant: constant,
            coefficients: [
              if (outerCoefficient != 0)
                AffineCoefficient(
                  specificationIndex: outerAxis,
                  coefficient: outerCoefficient,
                ),
              if (innerCoefficient != 0)
                AffineCoefficient(
                  specificationIndex: innerAxis,
                  coefficient: innerCoefficient,
                ),
            ],
          ),
        );
      }
    }
    return result;
  }

  List<OrdinalTextPart>? _inferNestedTextParts(
    List<_NestedTextSample> samples, {
    required int outerAxis,
    required int innerAxis,
    required int innerSourceOrdinal,
  }) {
    final split = samples.map((sample) => _splitDigits(sample.value)).toList();
    if (split.any((parts) => parts.length != split.first.length)) {
      throw const FormatException('unsupported nested text');
    }
    final result = <OrdinalTextPart>[];
    var usedPlaceholder = false;
    for (var partIndex = 0; partIndex < split.first.length; partIndex++) {
      final parts = split.map((value) => value[partIndex]).toList();
      if (parts.first is String) {
        if (parts.toSet().length != 1) {
          throw const FormatException('unsupported nested literal');
        }
        result.add(LiteralTextPart(parts.first as String));
        continue;
      }
      final digits = parts.cast<int>();
      final outerBias = digits.first - samples.first.outerOrdinal;
      final innerBias = digits.first - samples.first.innerOrdinal;
      final followsOuter = [
        for (var index = 0; index < digits.length; index++)
          digits[index] == samples[index].outerOrdinal + outerBias,
      ].every((value) => value);
      final followsInner = [
        for (var index = 0; index < digits.length; index++)
          digits[index] == samples[index].innerOrdinal + innerBias,
      ].every((value) => value);
      final outerVaries =
          samples.map((sample) => sample.outerOrdinal).toSet().length > 1;
      final innerVaries =
          samples.map((sample) => sample.innerOrdinal).toSet().length > 1;
      if (outerVaries && followsOuter && !(innerVaries && followsInner)) {
        result.add(
          OrdinalTextPlaceholder(
            specificationIndex: outerAxis,
            displayBias: outerBias,
          ),
        );
        usedPlaceholder = true;
      } else if (innerVaries &&
          followsInner &&
          !(outerVaries && followsOuter)) {
        result.add(
          OrdinalTextPlaceholder(
            specificationIndex: innerAxis,
            displayBias: innerBias,
          ),
        );
        usedPlaceholder = true;
      } else if (!innerVaries &&
          digits.toSet().length == 1 &&
          digits.first == innerSourceOrdinal + 1) {
        result.add(
          OrdinalTextPlaceholder(specificationIndex: innerAxis, displayBias: 1),
        );
        usedPlaceholder = true;
      } else if (digits.toSet().length == 1) {
        result.add(LiteralTextPart('${digits.first}'));
      } else {
        throw const FormatException('unsupported nested ordinal');
      }
    }
    return usedPlaceholder ? result : null;
  }

  List<({int start, int end})> _contiguousRanges(List<int> indexes) {
    if (indexes.isEmpty) return const [];
    final sorted = [...indexes]..sort();
    final ranges = <({int start, int end})>[];
    var start = sorted.first;
    var previous = start;
    for (final index in sorted.skip(1)) {
      if (index != previous + 1) {
        ranges.add((start: start, end: previous + 1));
        start = index;
      }
      previous = index;
    }
    ranges.add((start: start, end: previous + 1));
    return ranges;
  }
}

final class _Alignment {
  const _Alignment({
    required this.canonicalToLower,
    required this.lowerToCanonical,
    required this.unmatchedCanonical,
    required this.ambiguous,
  });

  final Map<int, int> canonicalToLower;
  final Map<int, int> lowerToCanonical;
  final List<int> unmatchedCanonical;
  final bool ambiguous;
}

final class _NestedCandidate {
  const _NestedCandidate({
    required this.section,
    required this.run,
    required this.outerOrdinal,
    required this.relativeOffset,
  });

  final RepeatSection section;
  final ShapeStreamRun run;
  final int outerOrdinal;
  final int relativeOffset;
}

final class _NestedAtomSample {
  const _NestedAtomSample({
    required this.value,
    required this.outerOrdinal,
    required this.innerOrdinal,
  });

  final Object value;
  final int outerOrdinal;
  final int innerOrdinal;
}

final class _NestedParameterSample {
  const _NestedParameterSample({
    required this.value,
    required this.outerOrdinal,
    required this.innerOrdinal,
  });

  final ShapeParameterAtom value;
  final int outerOrdinal;
  final int innerOrdinal;
}

final class _NestedTextSample {
  const _NestedTextSample({
    required this.value,
    required this.outerOrdinal,
    required this.innerOrdinal,
  });

  final String value;
  final int outerOrdinal;
  final int innerOrdinal;
}
