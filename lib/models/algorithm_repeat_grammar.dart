import 'package:collection/collection.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';

enum ShapeStream {
  parameters(0),
  pages(1),
  memberships(2),
  outputUsage(3);

  const ShapeStream(this.code);
  final int code;

  static ShapeStream fromCode(Object? code) => switch (code) {
    0 => ShapeStream.parameters,
    1 => ShapeStream.pages,
    2 => ShapeStream.memberships,
    3 => ShapeStream.outputUsage,
    _ => throw FormatException('Unknown shape stream code: $code'),
  };
}

enum OrdinalField {
  parameterName(0),
  parameterEnumString(1),
  pageName(2),
  parameterMin(3),
  parameterMax(4),
  parameterDefault(5);

  const OrdinalField(this.code);
  final int code;

  static OrdinalField fromCode(Object? code) => switch (code) {
    0 => OrdinalField.parameterName,
    1 => OrdinalField.parameterEnumString,
    2 => OrdinalField.pageName,
    3 => OrdinalField.parameterMin,
    4 => OrdinalField.parameterMax,
    5 => OrdinalField.parameterDefault,
    _ => throw FormatException('Unknown ordinal field code: $code'),
  };
}

final class ShapeStreamRun {
  const ShapeStreamRun({
    required this.stream,
    required this.firstStart,
    required this.itemCount,
  });

  final ShapeStream stream;
  final int firstStart;
  final int itemCount;

  List<Object> toCompactJson() => [stream.code, firstStart, itemCount];

  static ShapeStreamRun fromCompactJson(Object? json) {
    final values = _array(json, length: 3, label: 'stream run');
    return ShapeStreamRun(
      stream: ShapeStream.fromCode(values[0]),
      firstStart: _integer(values[1], 'run start'),
      itemCount: _integer(values[2], 'run item count'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeStreamRun &&
          stream == other.stream &&
          firstStart == other.firstStart &&
          itemCount == other.itemCount;

  @override
  int get hashCode => Object.hash(stream, firstStart, itemCount);
}

sealed class OrdinalTextPart {
  const OrdinalTextPart();
  Object toCompactJson();
}

final class LiteralTextPart extends OrdinalTextPart {
  const LiteralTextPart(this.value);
  final String value;

  @override
  Object toCompactJson() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiteralTextPart && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

final class OrdinalTextPlaceholder extends OrdinalTextPart {
  const OrdinalTextPlaceholder({
    required this.specificationIndex,
    required this.displayBias,
  });

  final int specificationIndex;
  final int displayBias;

  @override
  Object toCompactJson() => [specificationIndex, displayBias];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrdinalTextPlaceholder &&
          specificationIndex == other.specificationIndex &&
          displayBias == other.displayBias;

  @override
  int get hashCode => Object.hash(specificationIndex, displayBias);
}

sealed class OrdinalSubstitution {
  const OrdinalSubstitution({
    required this.stream,
    required this.rowOffset,
    required this.field,
    this.elementIndex = -1,
  });

  final ShapeStream stream;
  final int rowOffset;
  final OrdinalField field;
  final int elementIndex;

  Object toCompactJson();

  static OrdinalSubstitution fromCompactJson(Object? json) {
    final values = _array(json, label: 'ordinal substitution');
    if (values.isEmpty) {
      throw const FormatException('Empty ordinal substitution');
    }
    return switch (values.first) {
      't' => OrdinalTextSubstitution.fromCompactJson(values),
      'i' => AffineIntegerSubstitution.fromCompactJson(values),
      'c' => CountDeltaSubstitution.fromCompactJson(values),
      'e' => EnumRepeatSubstitution.fromCompactJson(values),
      _ => throw FormatException(
        'Unknown ordinal substitution tag: ${values.first}',
      ),
    };
  }
}

final class OrdinalTextSubstitution extends OrdinalSubstitution {
  OrdinalTextSubstitution({
    required super.stream,
    required super.rowOffset,
    required super.field,
    super.elementIndex,
    required List<OrdinalTextPart> parts,
  }) : parts = List.unmodifiable(parts);

  final List<OrdinalTextPart> parts;

  @override
  Object toCompactJson() => [
    't',
    stream.code,
    rowOffset,
    field.code,
    elementIndex,
    parts.map((part) => part.toCompactJson()).toList(),
  ];

  static OrdinalTextSubstitution fromCompactJson(List<Object?> values) {
    if (values.length != 6) {
      throw const FormatException('Text substitution must have 6 values');
    }
    final parts = _textParts(values[5], 'text parts');
    return OrdinalTextSubstitution(
      stream: ShapeStream.fromCode(values[1]),
      rowOffset: _integer(values[2], 'text row offset'),
      field: OrdinalField.fromCode(values[3]),
      elementIndex: _integer(values[4], 'text element index'),
      parts: parts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrdinalTextSubstitution &&
          stream == other.stream &&
          rowOffset == other.rowOffset &&
          field == other.field &&
          elementIndex == other.elementIndex &&
          const ListEquality<OrdinalTextPart>().equals(parts, other.parts);

  @override
  int get hashCode => Object.hash(
    stream,
    rowOffset,
    field,
    elementIndex,
    const ListEquality<OrdinalTextPart>().hash(parts),
  );
}

final class AffineCoefficient {
  const AffineCoefficient({
    required this.specificationIndex,
    required this.coefficient,
  });

  final int specificationIndex;
  final int coefficient;

  Object toCompactJson() => [specificationIndex, coefficient];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AffineCoefficient &&
          specificationIndex == other.specificationIndex &&
          coefficient == other.coefficient;

  @override
  int get hashCode => Object.hash(specificationIndex, coefficient);
}

final class AffineIntegerSubstitution extends OrdinalSubstitution {
  AffineIntegerSubstitution({
    required super.stream,
    required super.rowOffset,
    required super.field,
    super.elementIndex,
    required this.constant,
    required List<AffineCoefficient> coefficients,
  }) : coefficients = List.unmodifiable(coefficients);

  final int constant;
  final List<AffineCoefficient> coefficients;

  @override
  Object toCompactJson() => [
    'i',
    stream.code,
    rowOffset,
    field.code,
    elementIndex,
    constant,
    coefficients.map((coefficient) => coefficient.toCompactJson()).toList(),
  ];

  static AffineIntegerSubstitution fromCompactJson(List<Object?> values) {
    if (values.length != 7) {
      throw const FormatException('Integer substitution must have 7 values');
    }
    final coefficients = _affineCoefficients(values[6]);
    return AffineIntegerSubstitution(
      stream: ShapeStream.fromCode(values[1]),
      rowOffset: _integer(values[2], 'integer row offset'),
      field: OrdinalField.fromCode(values[3]),
      elementIndex: _integer(values[4], 'integer element index'),
      constant: _integer(values[5], 'integer constant'),
      coefficients: coefficients,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AffineIntegerSubstitution &&
          stream == other.stream &&
          rowOffset == other.rowOffset &&
          field == other.field &&
          elementIndex == other.elementIndex &&
          constant == other.constant &&
          const ListEquality<AffineCoefficient>().equals(
            coefficients,
            other.coefficients,
          );

  @override
  int get hashCode => Object.hash(
    stream,
    rowOffset,
    field,
    elementIndex,
    constant,
    const ListEquality<AffineCoefficient>().hash(coefficients),
  );
}

/// Adds `coefficient * (requested - baseline)` per specification to an
/// integer field, so the value at the baseline is always the canonical one.
final class CountDeltaSubstitution extends OrdinalSubstitution {
  CountDeltaSubstitution({
    required super.stream,
    required super.rowOffset,
    required super.field,
    super.elementIndex,
    required List<AffineCoefficient> coefficients,
  }) : coefficients = List.unmodifiable(coefficients);

  final List<AffineCoefficient> coefficients;

  @override
  Object toCompactJson() => [
    'c',
    stream.code,
    rowOffset,
    field.code,
    elementIndex,
    coefficients.map((coefficient) => coefficient.toCompactJson()).toList(),
  ];

  static CountDeltaSubstitution fromCompactJson(List<Object?> values) {
    if (values.length != 6) {
      throw const FormatException(
        'Count delta substitution must have 6 values',
      );
    }
    return CountDeltaSubstitution(
      stream: ShapeStream.fromCode(values[1]),
      rowOffset: _integer(values[2], 'count delta row offset'),
      field: OrdinalField.fromCode(values[3]),
      elementIndex: _integer(values[4], 'count delta element index'),
      coefficients: _affineCoefficients(values[5]),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountDeltaSubstitution &&
          stream == other.stream &&
          rowOffset == other.rowOffset &&
          field == other.field &&
          elementIndex == other.elementIndex &&
          const ListEquality<AffineCoefficient>().equals(
            coefficients,
            other.coefficients,
          );

  @override
  int get hashCode => Object.hash(
    stream,
    rowOffset,
    field,
    elementIndex,
    const ListEquality<AffineCoefficient>().hash(coefficients),
  );
}

/// Replaces a run of enum strings that repeats once per counted item.
///
/// The canonical run starts at [elementIndex] and holds
/// `(baseline + countBias) * items.length` strings; expansion renders
/// [items] once per requested ordinal and keeps the strings around the run.
final class EnumRepeatSubstitution extends OrdinalSubstitution {
  EnumRepeatSubstitution({
    required super.stream,
    required super.rowOffset,
    required super.field,
    required super.elementIndex,
    required this.specificationIndex,
    required this.countBias,
    required this.sourceOrdinal,
    required List<List<OrdinalTextPart>> items,
  }) : items = List.unmodifiable(
         items.map((item) => List<OrdinalTextPart>.unmodifiable(item)),
       );

  final int specificationIndex;
  final int countBias;
  final int sourceOrdinal;
  final List<List<OrdinalTextPart>> items;

  @override
  Object toCompactJson() => [
    'e',
    stream.code,
    rowOffset,
    field.code,
    elementIndex,
    specificationIndex,
    countBias,
    sourceOrdinal,
    items
        .map((item) => item.map((part) => part.toCompactJson()).toList())
        .toList(),
  ];

  static EnumRepeatSubstitution fromCompactJson(List<Object?> values) {
    if (values.length != 9) {
      throw const FormatException(
        'Enum repeat substitution must have 9 values',
      );
    }
    return EnumRepeatSubstitution(
      stream: ShapeStream.fromCode(values[1]),
      rowOffset: _integer(values[2], 'enum repeat row offset'),
      field: OrdinalField.fromCode(values[3]),
      elementIndex: _integer(values[4], 'enum repeat element index'),
      specificationIndex: _integer(values[5], 'enum repeat spec index'),
      countBias: _integer(values[6], 'enum repeat count bias'),
      sourceOrdinal: _integer(values[7], 'enum repeat source ordinal'),
      items: _array(
        values[8],
        label: 'enum repeat items',
      ).map((item) => _textParts(item, 'enum repeat item')).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnumRepeatSubstitution &&
          stream == other.stream &&
          rowOffset == other.rowOffset &&
          field == other.field &&
          elementIndex == other.elementIndex &&
          specificationIndex == other.specificationIndex &&
          countBias == other.countBias &&
          sourceOrdinal == other.sourceOrdinal &&
          const DeepCollectionEquality().equals(items, other.items);

  @override
  int get hashCode => Object.hash(
    stream,
    rowOffset,
    field,
    elementIndex,
    specificationIndex,
    countBias,
    sourceOrdinal,
    const DeepCollectionEquality().hash(items),
  );
}

List<AffineCoefficient> _affineCoefficients(Object? json) =>
    _array(json, label: 'affine coefficients').map((coefficient) {
      final pair = _array(coefficient, length: 2, label: 'affine coefficient');
      return AffineCoefficient(
        specificationIndex: _integer(pair[0], 'coefficient spec index'),
        coefficient: _integer(pair[1], 'coefficient'),
      );
    }).toList();

List<OrdinalTextPart> _textParts(Object? json, String label) =>
    _array(json, label: label).map<OrdinalTextPart>((part) {
      if (part is String) return LiteralTextPart(part);
      final placeholder = _array(part, length: 2, label: 'text placeholder');
      return OrdinalTextPlaceholder(
        specificationIndex: _integer(placeholder[0], 'placeholder spec index'),
        displayBias: _integer(placeholder[1], 'placeholder display bias'),
      );
    }).toList();

final class RepeatSection {
  RepeatSection({
    required this.specificationIndex,
    required this.countBias,
    required this.sourceOrdinal,
    required List<ShapeStreamRun> runs,
    required List<OrdinalSubstitution> substitutions,
    required List<RepeatSection> children,
  }) : runs = List.unmodifiable(runs),
       substitutions = List.unmodifiable(substitutions),
       children = List.unmodifiable(children);

  final int specificationIndex;
  final int countBias;
  final int sourceOrdinal;
  final List<ShapeStreamRun> runs;
  final List<OrdinalSubstitution> substitutions;
  final List<RepeatSection> children;

  ShapeStreamRun? runFor(ShapeStream stream) =>
      runs.where((run) => run.stream == stream).firstOrNull;

  Object toCompactJson() => [
    'r',
    specificationIndex,
    countBias,
    sourceOrdinal,
    runs.map((run) => run.toCompactJson()).toList(),
    substitutions.map((substitution) => substitution.toCompactJson()).toList(),
    children.map((child) => child.toCompactJson()).toList(),
  ];

  static RepeatSection fromCompactJson(Object? json) {
    final values = _array(json, length: 7, label: 'repeat section');
    if (values[0] != 'r') {
      throw FormatException('Unknown repeat section tag: ${values[0]}');
    }
    return RepeatSection(
      specificationIndex: _integer(values[1], 'section spec index'),
      countBias: _integer(values[2], 'section count bias'),
      sourceOrdinal: _integer(values[3], 'section source ordinal'),
      runs: _array(
        values[4],
        label: 'section runs',
      ).map(ShapeStreamRun.fromCompactJson).toList(),
      substitutions: _array(
        values[5],
        label: 'section substitutions',
      ).map(OrdinalSubstitution.fromCompactJson).toList(),
      children: _array(
        values[6],
        label: 'section children',
      ).map(RepeatSection.fromCompactJson).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepeatSection &&
          specificationIndex == other.specificationIndex &&
          countBias == other.countBias &&
          sourceOrdinal == other.sourceOrdinal &&
          const ListEquality<ShapeStreamRun>().equals(runs, other.runs) &&
          const ListEquality<OrdinalSubstitution>().equals(
            substitutions,
            other.substitutions,
          ) &&
          const ListEquality<RepeatSection>().equals(children, other.children);

  @override
  int get hashCode => Object.hash(
    specificationIndex,
    countBias,
    sourceOrdinal,
    const ListEquality<ShapeStreamRun>().hash(runs),
    const ListEquality<OrdinalSubstitution>().hash(substitutions),
    const ListEquality<RepeatSection>().hash(children),
  );
}

final class AlgorithmRepeatGrammar {
  AlgorithmRepeatGrammar({
    required List<int> baselineSpecifications,
    required List<RepeatSection> sections,
    List<OrdinalSubstitution> fixedSubstitutions = const [],
  }) : baselineSpecifications = List.unmodifiable(baselineSpecifications),
       sections = List.unmodifiable(sections),
       fixedSubstitutions = List.unmodifiable(fixedSubstitutions);

  /// Version 2 adds count-delta and enum-repeat substitutions plus
  /// [fixedSubstitutions]; version 1 JSON is still readable.
  static const currentVersion = 2;
  static const supportedVersions = {1, currentVersion};

  final List<int> baselineSpecifications;
  final List<RepeatSection> sections;

  /// Substitutions keyed by absolute canonical row that apply to every
  /// generated copy of that row, inside or outside repeat sections.
  final List<OrdinalSubstitution> fixedSubstitutions;

  AlgorithmShapeSnapshot expand(
    AlgorithmShapeSnapshot canonical,
    List<int> specificationValues,
  ) {
    if (canonical.specificationValues.length != baselineSpecifications.length ||
        specificationValues.length != baselineSpecifications.length) {
      throw const FormatException('Specification vector length mismatch');
    }
    if (!const ListEquality<int>().equals(
      canonical.specificationValues,
      baselineSpecifications,
    )) {
      throw const FormatException(
        'Canonical shape does not match grammar baseline',
      );
    }
    _validateSections(canonical, specificationValues);

    final parameters = _expandStream<ShapeParameterAtom>(
      ShapeStream.parameters,
      canonical.parameters,
      specificationValues,
    );
    final pages = _expandStream<ShapePageAtom>(
      ShapeStream.pages,
      canonical.pages,
      specificationValues,
    );
    final memberships = _expandStream<ShapePageMembershipAtom>(
      ShapeStream.memberships,
      canonical.pageMemberships,
      specificationValues,
    );
    final outputUsage = _expandStream<ShapeOutputUsageAtom>(
      ShapeStream.outputUsage,
      canonical.outputUsage,
      specificationValues,
    );

    final parameterAddresses = _addressMap(parameters, 'parameter');
    final pageAddresses = _addressMap(pages, 'page');
    final remappedMemberships = memberships.map((generated) {
      final atom = generated.value;
      return ShapePageMembershipAtom(
        pageIndex: _resolveReference(
          pageAddresses,
          atom.pageIndex,
          generated.ordinals,
          'membership page',
        ),
        parameterNumber: _resolveReference(
          parameterAddresses,
          atom.parameterNumber,
          generated.ordinals,
          'membership parameter',
        ),
      );
    }).toList();
    final remappedOutputUsage = outputUsage.map((generated) {
      final atom = generated.value;
      return ShapeOutputUsageAtom(
        parameterNumber: _resolveReference(
          parameterAddresses,
          atom.parameterNumber,
          generated.ordinals,
          'output usage source',
        ),
        affectedParameterNumber: _resolveReference(
          parameterAddresses,
          atom.affectedParameterNumber,
          generated.ordinals,
          'output usage affected parameter',
        ),
      );
    }).toList();
    if (remappedMemberships.toSet().length != remappedMemberships.length ||
        remappedOutputUsage.toSet().length != remappedOutputUsage.length) {
      throw const FormatException(
        'Expansion generated duplicate relationships',
      );
    }

    return AlgorithmShapeSnapshot(
      specificationValues: specificationValues,
      parameters: parameters.map((generated) => generated.value).toList(),
      pages: pages.map((generated) => generated.value).toList(),
      pageMemberships: remappedMemberships,
      outputUsage: remappedOutputUsage,
    );
  }

  Object toCompactJson() => [
    currentVersion,
    baselineSpecifications,
    sections.map((section) => section.toCompactJson()).toList(),
    fixedSubstitutions
        .map((substitution) => substitution.toCompactJson())
        .toList(),
  ];

  static AlgorithmRepeatGrammar fromCompactJson(Object? json) {
    final values = _array(json, label: 'repeat grammar');
    if (values.isEmpty || !supportedVersions.contains(values[0])) {
      throw FormatException(
        'Unknown repeat grammar version: ${values.firstOrNull}',
      );
    }
    final expectedLength = values[0] == 1 ? 3 : 4;
    if (values.length != expectedLength) {
      throw FormatException(
        'Repeat grammar version ${values[0]} must have $expectedLength values',
      );
    }
    return AlgorithmRepeatGrammar(
      baselineSpecifications: _array(
        values[1],
        label: 'baseline specifications',
      ).map((value) => _integer(value, 'baseline specification')).toList(),
      sections: _array(
        values[2],
        label: 'grammar sections',
      ).map(RepeatSection.fromCompactJson).toList(),
      fixedSubstitutions: values.length == 4
          ? _array(
              values[3],
              label: 'fixed substitutions',
            ).map(OrdinalSubstitution.fromCompactJson).toList()
          : const [],
    );
  }

  List<_Generated<T>> _expandStream<T>(
    ShapeStream stream,
    List<T> rows,
    List<int> requestedSpecifications,
  ) => _expandScope<T>(
    stream: stream,
    rows: rows,
    scopeStart: 0,
    scopeEnd: rows.length,
    scopeSections: sections,
    requestedSpecifications: requestedSpecifications,
    activeOrdinals: const {},
    activeSections: const [],
  );

  List<_Generated<T>> _expandScope<T>({
    required ShapeStream stream,
    required List<T> rows,
    required int scopeStart,
    required int scopeEnd,
    required List<RepeatSection> scopeSections,
    required List<int> requestedSpecifications,
    required Map<int, int> activeOrdinals,
    required List<_ActiveSection> activeSections,
  }) {
    final sectionsWithRuns =
        scopeSections
            .map((section) => (section: section, run: section.runFor(stream)))
            .where((entry) => entry.run != null)
            .map((entry) => (section: entry.section, run: entry.run!))
            .toList()
          ..sort((a, b) => a.run.firstStart.compareTo(b.run.firstStart));
    final output = <_Generated<T>>[];
    var cursor = scopeStart;
    for (final entry in sectionsWithRuns) {
      final section = entry.section;
      final run = entry.run;
      final runStart = scopeStart + run.firstStart;
      final canonicalCount =
          baselineSpecifications[section.specificationIndex] +
          section.countBias;
      final runEnd = runStart + canonicalCount * run.itemCount;
      if (runStart < cursor || runEnd > scopeEnd) {
        throw FormatException('Overlapping or out-of-scope ${stream.name} run');
      }
      for (var row = cursor; row < runStart; row++) {
        output.add(
          _generateRow(
            stream,
            rows[row],
            row,
            activeOrdinals,
            activeSections,
            requestedSpecifications,
          ),
        );
      }

      final requestedCount =
          requestedSpecifications[section.specificationIndex] +
          section.countBias;
      final sourceStart = runStart + section.sourceOrdinal * run.itemCount;
      for (var ordinal = 0; ordinal < requestedCount; ordinal++) {
        final nextOrdinals = {...activeOrdinals};
        final previous = nextOrdinals[section.specificationIndex];
        if (previous != null && previous != ordinal) {
          throw const FormatException(
            'Same-axis self-nesting is not supported',
          );
        }
        nextOrdinals[section.specificationIndex] = ordinal;
        output.addAll(
          _expandScope<T>(
            stream: stream,
            rows: rows,
            scopeStart: sourceStart,
            scopeEnd: sourceStart + run.itemCount,
            scopeSections: section.children,
            requestedSpecifications: requestedSpecifications,
            activeOrdinals: nextOrdinals,
            activeSections: [
              ...activeSections,
              _ActiveSection(section, sourceStart),
            ],
          ),
        );
      }
      cursor = runEnd;
    }
    for (var row = cursor; row < scopeEnd; row++) {
      output.add(
        _generateRow(
          stream,
          rows[row],
          row,
          activeOrdinals,
          activeSections,
          requestedSpecifications,
        ),
      );
    }
    return output;
  }

  _Generated<T> _generateRow<T>(
    ShapeStream stream,
    T original,
    int sourceRow,
    Map<int, int> ordinals,
    List<_ActiveSection> activeSections,
    List<int> requestedSpecifications,
  ) {
    Object value = original as Object;
    var ordinalDefault = false;
    void apply(OrdinalSubstitution substitution) {
      value = _applySubstitution(
        value,
        substitution,
        ordinals,
        requestedSpecifications,
      );
      ordinalDefault |=
          substitution is AffineIntegerSubstitution &&
          substitution.field == OrdinalField.parameterDefault;
    }

    for (final substitution in fixedSubstitutions) {
      if (substitution.stream == stream &&
          substitution.rowOffset == sourceRow) {
        apply(substitution);
      }
    }
    for (final context in activeSections) {
      final offset = sourceRow - context.sourceStart;
      for (final substitution in context.section.substitutions) {
        if (substitution.stream == stream && substitution.rowOffset == offset) {
          apply(substitution);
        }
      }
    }
    // An ordinal-driven default fitted from two witnesses cannot tell
    // "1, 0, 0, ..." from "1, 0, -1, ...", so it stays inside the range.
    final parameter = value;
    if (ordinalDefault &&
        parameter is ShapeParameterAtom &&
        parameter.min <= parameter.max) {
      value = parameter.copyWith(
        defaultValue: parameter.defaultValue.clamp(
          parameter.min,
          parameter.max,
        ),
      );
    }
    return _Generated<T>(
      sourceRow: sourceRow,
      ordinals: Map.unmodifiable(ordinals),
      value: value as T,
    );
  }

  Object _applySubstitution(
    Object value,
    OrdinalSubstitution substitution,
    Map<int, int> ordinals,
    List<int> requestedSpecifications,
  ) {
    if (substitution is EnumRepeatSubstitution) {
      if (value is! ShapeParameterAtom) {
        throw const FormatException('Enum repeat requires a parameter');
      }
      final itemCount = substitution.items.length;
      final canonicalCount =
          baselineSpecifications[substitution.specificationIndex] +
          substitution.countBias;
      final requestedCount =
          requestedSpecifications[substitution.specificationIndex] +
          substitution.countBias;
      final runEnd = substitution.elementIndex + canonicalCount * itemCount;
      if (substitution.elementIndex < 0 ||
          runEnd > value.enumStrings.length ||
          requestedCount < 0) {
        throw const FormatException('Enum repeat is outside its parameter');
      }
      final enums = <String>[
        ...value.enumStrings.sublist(0, substitution.elementIndex),
        for (var ordinal = 0; ordinal < requestedCount; ordinal++)
          for (final item in substitution.items)
            _renderText(item, {
              ...ordinals,
              substitution.specificationIndex: ordinal,
            }),
        ...value.enumStrings.sublist(runEnd),
      ];
      return value.copyWith(enumStrings: enums);
    }
    if (substitution is CountDeltaSubstitution) {
      if (value is! ShapeParameterAtom) {
        throw const FormatException('Count delta requires a parameter');
      }
      final delta = substitution.coefficients.fold<int>(0, (sum, coefficient) {
        final axis = coefficient.specificationIndex;
        return sum +
            coefficient.coefficient *
                (requestedSpecifications[axis] - baselineSpecifications[axis]);
      });
      return switch (substitution.field) {
        OrdinalField.parameterMin => value.copyWith(min: value.min + delta),
        OrdinalField.parameterMax => value.copyWith(max: value.max + delta),
        OrdinalField.parameterDefault => value.copyWith(
          defaultValue: value.defaultValue + delta,
        ),
        _ => throw const FormatException(
          'Count delta targets an invalid field',
        ),
      };
    }
    if (substitution is OrdinalTextSubstitution) {
      final text = _renderText(substitution.parts, ordinals);
      if (value is ShapeParameterAtom &&
          substitution.field == OrdinalField.parameterName) {
        return value.copyWith(name: text);
      }
      if (value is ShapeParameterAtom &&
          substitution.field == OrdinalField.parameterEnumString &&
          substitution.elementIndex >= 0 &&
          substitution.elementIndex < value.enumStrings.length) {
        final enums = [...value.enumStrings];
        enums[substitution.elementIndex] = text;
        return value.copyWith(enumStrings: enums);
      }
      if (value is ShapePageAtom &&
          substitution.field == OrdinalField.pageName) {
        return value.copyWith(name: text);
      }
      throw const FormatException('Text substitution targets an invalid field');
    }

    final integerSubstitution = substitution as AffineIntegerSubstitution;
    if (value is! ShapeParameterAtom) {
      throw const FormatException('Integer substitution requires a parameter');
    }
    final integerValue =
        integerSubstitution.constant +
        integerSubstitution.coefficients.fold<int>(0, (sum, coefficient) {
          return sum +
              coefficient.coefficient *
                  _ordinal(ordinals, coefficient.specificationIndex);
        });
    return switch (integerSubstitution.field) {
      OrdinalField.parameterMin => value.copyWith(min: integerValue),
      OrdinalField.parameterMax => value.copyWith(max: integerValue),
      OrdinalField.parameterDefault => value.copyWith(
        defaultValue: integerValue,
      ),
      _ => throw const FormatException(
        'Integer substitution targets an invalid field',
      ),
    };
  }

  String _renderText(List<OrdinalTextPart> parts, Map<int, int> ordinals) =>
      parts.map((part) {
        return switch (part) {
          LiteralTextPart() => part.value,
          OrdinalTextPlaceholder() =>
            '${_ordinal(ordinals, part.specificationIndex) + part.displayBias}',
        };
      }).join();

  int _ordinal(Map<int, int> ordinals, int specificationIndex) {
    final ordinal = ordinals[specificationIndex];
    if (ordinal == null) {
      throw FormatException(
        'Substitution references inactive specification $specificationIndex',
      );
    }
    return ordinal;
  }

  void _validateSections(
    AlgorithmShapeSnapshot canonical,
    List<int> requestedSpecifications,
  ) {
    final streamLengths = {
      ShapeStream.parameters: canonical.parameters.length,
      ShapeStream.pages: canonical.pages.length,
      ShapeStream.memberships: canonical.pageMemberships.length,
      ShapeStream.outputUsage: canonical.outputUsage.length,
    };
    void validateLevel(
      List<RepeatSection> level,
      Map<ShapeStream, int> scopeLengths,
      Set<int> ancestorAxes,
    ) {
      for (final stream in ShapeStream.values) {
        final runs = <({RepeatSection section, ShapeStreamRun run})>[];
        for (final section in level) {
          final run = section.runFor(stream);
          if (run != null) runs.add((section: section, run: run));
        }
        runs.sort((a, b) => a.run.firstStart.compareTo(b.run.firstStart));
        var cursor = 0;
        for (final entry in runs) {
          final canonicalCount =
              baselineSpecifications[entry.section.specificationIndex] +
              entry.section.countBias;
          final end =
              entry.run.firstStart + canonicalCount * entry.run.itemCount;
          if (entry.run.itemCount <= 0 ||
              entry.run.firstStart < cursor ||
              end > scopeLengths[stream]!) {
            throw const FormatException('Invalid or overlapping stream run');
          }
          cursor = end;
        }
      }

      for (final section in level) {
        final axis = section.specificationIndex;
        if (axis < 0 || axis >= baselineSpecifications.length) {
          throw const FormatException('Section specification index is invalid');
        }
        if (ancestorAxes.contains(axis)) {
          throw const FormatException('Same-axis self-nesting is invalid');
        }
        final canonicalCount = baselineSpecifications[axis] + section.countBias;
        final requestedCount =
            requestedSpecifications[axis] + section.countBias;
        if (canonicalCount <= 0 ||
            requestedCount < 0 ||
            section.sourceOrdinal < 0 ||
            section.sourceOrdinal >= canonicalCount ||
            section.runs.isEmpty ||
            section.runs.map((run) => run.stream).toSet().length !=
                section.runs.length) {
          throw const FormatException('Invalid repeat section');
        }
        final childScopeLengths = <ShapeStream, int>{};
        for (final stream in ShapeStream.values) {
          childScopeLengths[stream] = section.runFor(stream)?.itemCount ?? 0;
        }
        for (final child in section.children) {
          for (final childRun in child.runs) {
            if (section.runFor(childRun.stream) == null) {
              throw const FormatException('Child run is outside its parent');
            }
          }
        }
        for (final substitution in section.substitutions) {
          final run = section.runFor(substitution.stream);
          if (run == null ||
              substitution.rowOffset < 0 ||
              substitution.rowOffset >= run.itemCount) {
            throw const FormatException('Substitution is outside its section');
          }
          _validateSubstitution(substitution);
        }
        validateLevel(section.children, childScopeLengths, {
          ...ancestorAxes,
          axis,
        });
      }
    }

    validateLevel(sections, streamLengths, const {});
    for (final substitution in fixedSubstitutions) {
      if (substitution.rowOffset < 0 ||
          substitution.rowOffset >= streamLengths[substitution.stream]!) {
        throw const FormatException('Fixed substitution is outside the shape');
      }
      _validateSubstitution(substitution);
    }
  }

  void _validateSubstitution(OrdinalSubstitution substitution) {
    if (substitution is OrdinalTextSubstitution) {
      final validTarget =
          substitution.stream == ShapeStream.parameters &&
              substitution.field == OrdinalField.parameterName &&
              substitution.elementIndex == -1 ||
          substitution.stream == ShapeStream.parameters &&
              substitution.field == OrdinalField.parameterEnumString &&
              substitution.elementIndex >= 0 ||
          substitution.stream == ShapeStream.pages &&
              substitution.field == OrdinalField.pageName &&
              substitution.elementIndex == -1;
      if (!validTarget || substitution.parts.isEmpty) {
        throw const FormatException('Invalid text substitution');
      }
      for (final part in substitution.parts) {
        if (part is OrdinalTextPlaceholder &&
            (part.specificationIndex < 0 ||
                part.specificationIndex >= baselineSpecifications.length)) {
          throw const FormatException('Invalid text placeholder axis');
        }
      }
      return;
    }
    if (substitution is EnumRepeatSubstitution) {
      if (substitution.stream != ShapeStream.parameters ||
          substitution.field != OrdinalField.parameterEnumString ||
          substitution.elementIndex < 0 ||
          substitution.specificationIndex < 0 ||
          substitution.specificationIndex >= baselineSpecifications.length ||
          substitution.items.isEmpty ||
          substitution.items.any((item) => item.isEmpty) ||
          baselineSpecifications[substitution.specificationIndex] +
                  substitution.countBias <=
              0 ||
          substitution.sourceOrdinal < 0 ||
          substitution.sourceOrdinal >=
              baselineSpecifications[substitution.specificationIndex] +
                  substitution.countBias) {
        throw const FormatException('Invalid enum repeat substitution');
      }
      for (final part in substitution.items.expand((item) => item)) {
        if (part is OrdinalTextPlaceholder &&
            (part.specificationIndex < 0 ||
                part.specificationIndex >= baselineSpecifications.length)) {
          throw const FormatException('Invalid enum repeat placeholder axis');
        }
      }
      return;
    }
    final coefficients = switch (substitution) {
      AffineIntegerSubstitution() => substitution.coefficients,
      CountDeltaSubstitution() => substitution.coefficients,
      _ => throw const FormatException('Unknown substitution'),
    };
    if (substitution.stream != ShapeStream.parameters ||
        substitution.elementIndex != -1 ||
        !{
          OrdinalField.parameterMin,
          OrdinalField.parameterMax,
          OrdinalField.parameterDefault,
        }.contains(substitution.field) ||
        coefficients.isEmpty ||
        coefficients.map((e) => e.specificationIndex).toSet().length !=
            coefficients.length ||
        coefficients.any(
          (coefficient) =>
              coefficient.specificationIndex < 0 ||
              coefficient.specificationIndex >= baselineSpecifications.length,
        )) {
      throw const FormatException('Invalid integer substitution');
    }
  }

  Map<int, List<({Map<int, int> ordinals, int generatedIndex})>> _addressMap<T>(
    List<_Generated<T>> rows,
    String label,
  ) {
    final result =
        <int, List<({Map<int, int> ordinals, int generatedIndex})>>{};
    final keys = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final key = '${row.sourceRow}:${_ordinalKey(row.ordinals)}';
      if (!keys.add(key)) {
        throw FormatException('Duplicate $label logical address');
      }
      (result[row.sourceRow] ??= []).add((
        ordinals: row.ordinals,
        generatedIndex: index,
      ));
    }
    return result;
  }

  int _resolveReference(
    Map<int, List<({Map<int, int> ordinals, int generatedIndex})>> addresses,
    int sourceRow,
    Map<int, int> relationshipOrdinals,
    String label,
  ) {
    final candidates = (addresses[sourceRow] ?? []).where((candidate) {
      return candidate.ordinals.entries.every(
        (entry) => relationshipOrdinals[entry.key] == entry.value,
      );
    }).toList();
    if (candidates.length != 1) {
      throw FormatException(
        '$label reference is ${candidates.isEmpty ? 'dangling' : 'ambiguous'}',
      );
    }
    return candidates.single.generatedIndex;
  }

  String _ordinalKey(Map<int, int> ordinals) {
    final entries = ordinals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join(',');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlgorithmRepeatGrammar &&
          const ListEquality<int>().equals(
            baselineSpecifications,
            other.baselineSpecifications,
          ) &&
          const ListEquality<RepeatSection>().equals(
            sections,
            other.sections,
          ) &&
          const ListEquality<OrdinalSubstitution>().equals(
            fixedSubstitutions,
            other.fixedSubstitutions,
          );

  @override
  int get hashCode => Object.hash(
    const ListEquality<int>().hash(baselineSpecifications),
    const ListEquality<RepeatSection>().hash(sections),
    const ListEquality<OrdinalSubstitution>().hash(fixedSubstitutions),
  );
}

final class _Generated<T> {
  const _Generated({
    required this.sourceRow,
    required this.ordinals,
    required this.value,
  });

  final int sourceRow;
  final Map<int, int> ordinals;
  final T value;
}

final class _ActiveSection {
  const _ActiveSection(this.section, this.sourceStart);
  final RepeatSection section;
  final int sourceStart;
}

List<Object?> _array(Object? value, {int? length, required String label}) {
  if (value is! List<Object?> || (length != null && value.length != length)) {
    throw FormatException(
      '$label must be an array${length == null ? '' : ' of length $length'}',
    );
  }
  return value;
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer');
  return value;
}
