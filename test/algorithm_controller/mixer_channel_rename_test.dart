import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/algorithm_controller/lua_algorithm_controller_engine.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/services/offline_algorithm_shape_resolver.dart';

/// Renaming a mixer channel rewrites the channel's parameter-name prefixes on
/// the device ("1:Gain" becomes "Grov:Gain"). Controllers address channels by
/// their position, so a renamed channel must not disappear from the UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = LuaAlgorithmControllerEngine();
  late AppDatabase database;
  late OfflineAlgorithmShapeResolver resolver;
  late Map<String, dynamic> tables;
  late String mixerStereoSource;
  late String parametricEqSource;

  setUpAll(() async {
    final source = await File('assets/metadata/full_metadata.json')
        .readAsString();
    final bundle = jsonDecode(source) as Map<String, dynamic>;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    expect(
      await MetadataImportService(database).importFromJson(source),
      isTrue,
    );
    tables = Map<String, dynamic>.from(bundle['tables'] as Map);
    resolver = OfflineAlgorithmShapeResolver(database.metadataDao);
    mixerStereoSource = await File(
      'assets/algorithm_controllers/mixer_stereo.lua',
    ).readAsString();
    parametricEqSource = await File(
      'assets/algorithm_controllers/parametric_eq.lua',
    ).readAsString();
  });

  tearDownAll(() async {
    await database.close();
  });

  test('mixer stereo controller keeps renamed channels', () async {
    final slot = await _slotFromMetadata(
      tables,
      resolver,
      guid: 'mix2',
      name: 'Mixer Stereo',
      specificationOverrides: const [6, 2],
    );

    final baseline = _sections(
      engine
          .evaluate(
            source: mixerStereoSource,
            slot: slot,
            slotIndex: 0,
            units: const [],
          )
          .root,
    );
    expect(
      baseline.map((section) => section.title).where(_isChannelSection),
      hasLength(6),
    );

    final renamed = slot.copyWith(
      parameters: _renameChannels(slot, const {1: 'Grov', 2: 'CH2'}),
    );

    final document = engine.evaluate(
      source: mixerStereoSource,
      slot: renamed,
      slotIndex: 0,
      units: const [],
    );
    final sections = _sections(document.root);

    expect(
      sections.map((section) => section.title).where(_isChannelSection),
      hasLength(6),
      reason: 'renamed channels must not be dropped from the mixer controller',
    );
    final channelOne = sections.firstWhere(
      (section) => section.title == 'Channel 1',
    );
    final gainSlider = channelOne.children
        .whereType<AlgorithmControllerSlider>()
        .firstWhere((slider) => slider.label == 'Gain');
    expect(
      renamed.parameters[gainSlider.parameterNumber].name,
      'Grov:Gain',
      reason: 'channel 1 controls must address the renamed prefix',
    );

    final sendSlider = sections
        .firstWhere((section) => section.title.startsWith('Channel 1'))
        .children
        .whereType<AlgorithmControllerSlider>()
        .firstWhere((slider) => slider.label.startsWith('Send '));
    expect(
      renamed.parameters[sendSlider.parameterNumber].name,
      startsWith('Grov:'),
      reason: 'channel 1 sends must resolve through the renamed prefix',
    );
  });

  test('parametric EQ controller keeps renamed channels and bands', () async {
    final slot = await _slotFromMetadata(
      tables,
      resolver,
      guid: 'eqpa',
      name: 'EQ Parametric',
    );
    final renamed = slot.copyWith(
      parameters: _renameChannels(slot, const {1: 'Grov'}),
    );

    final document = engine.evaluate(
      source: parametricEqSource,
      slot: renamed,
      slotIndex: 0,
      units: const [],
    );

    final sliders = _flatten(document.root)
        .whereType<AlgorithmControllerSlider>();
    expect(sliders, isNotEmpty);
    expect(
      sliders.map((slider) => renamed.parameters[slider.parameterNumber].name),
      everyElement(startsWith('Grov:')),
      reason: 'renamed channel controls must still address their parameters',
    );
  });
}

bool _isChannelSection(String title) => title.startsWith('Channel ');

/// Renames a channel the way the firmware does: every parameter on the
/// channel's "Channel N" page gets its prefix replaced, while unrelated pages
/// (sends, common) keep theirs.
List<ParameterInfo> _renameChannels(
  Slot slot,
  Map<int, String> renamesByChannel,
) {
  final pageByParameter = <int, String>{
    for (final page in slot.pages.pages)
      for (final number in page.parameters) number: page.name,
  };

  String renameName(ParameterInfo parameter) {
    final pageName = pageByParameter[parameter.parameterNumber] ?? '';
    final channel = _channelPageNumber(pageName);
    final renamed = channel == null ? null : renamesByChannel[channel];
    if (renamed == null) return parameter.name;
    final separator = parameter.name.indexOf(':');
    if (separator < 0) return parameter.name;
    return '$renamed:${parameter.name.substring(separator + 1)}';
  }

  return [
    for (final parameter in slot.parameters)
      ParameterInfo(
        algorithmIndex: parameter.algorithmIndex,
        parameterNumber: parameter.parameterNumber,
        name: renameName(parameter),
        min: parameter.min,
        max: parameter.max,
        defaultValue: parameter.defaultValue,
        unit: parameter.unit,
        powerOfTen: parameter.powerOfTen,
        ioFlags: parameter.ioFlags,
      ),
  ];
}

int? _channelPageNumber(String pageName) {
  const prefix = 'Channel ';
  if (!pageName.startsWith(prefix)) return null;
  return int.tryParse(pageName.substring(prefix.length));
}

Iterable<AlgorithmControllerNode> _flatten(AlgorithmControllerNode node) sync* {
  yield node;
  switch (node) {
    case AlgorithmControllerColumn(:final children):
    case AlgorithmControllerRow(:final children):
    case AlgorithmControllerSection(:final children):
      for (final child in children) {
        yield* _flatten(child);
      }
    default:
      break;
  }
}

Iterable<AlgorithmControllerSection> _sections(AlgorithmControllerNode root) =>
    _flatten(root).whereType<AlgorithmControllerSection>();

Future<Slot> _slotFromMetadata(
  Map<String, dynamic> tables,
  OfflineAlgorithmShapeResolver resolver, {
  required String guid,
  required String name,
  List<int>? specificationOverrides,
}) async {
  const algorithmIndex = 7;
  final specificationRows =
      _rows(
        tables,
        'specifications',
      ).where((row) => row['algorithmGuid'] == guid).toList()..sort(
        (left, right) =>
            _int(left['specIndex']).compareTo(_int(right['specIndex'])),
      );
  final specifications =
      specificationOverrides ??
      [for (final row in specificationRows) _int(row['defaultValue'])];
  final snapshot = (await resolver.resolve(guid, specifications)).snapshot;
  final parameters = snapshot.parameters;

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: algorithmIndex,
      guid: guid,
      name: name,
      specifications: specifications,
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: [
        for (var pageIndex = 0; pageIndex < snapshot.pages.length; pageIndex++)
          ParameterPage(
            name: snapshot.pages[pageIndex].name,
            parameters: [
              for (final membership in snapshot.pageMemberships)
                if (membership.pageIndex == pageIndex)
                  membership.parameterNumber,
            ]..sort(),
          ),
      ],
    ),
    parameters: [
      for (var number = 0; number < parameters.length; number++)
        ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          min: parameters[number].min,
          max: parameters[number].max,
          defaultValue: parameters[number].defaultValue,
          unit: parameters[number].rawUnitIndex,
          name: parameters[number].name,
          powerOfTen: parameters[number].powerOfTen,
          ioFlags: parameters[number].ioFlags,
        ),
    ],
    values: [
      for (var number = 0; number < parameters.length; number++)
        ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          value: parameters[number].defaultValue,
        ),
    ],
    enums: [
      for (var number = 0; number < parameters.length; number++)
        ParameterEnumStrings(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          values: parameters[number].enumStrings,
        ),
    ],
    mappings: [for (final _ in parameters) Mapping.filler()],
    valueStrings: [
      for (var number = 0; number < parameters.length; number++)
        ParameterValueString(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          value: '',
        ),
    ],
  );
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> tables, String name) => [
  for (final row in tables[name] as List) Map<String, dynamic>.from(row as Map),
];

int _int(Object? value) => (value as num).toInt();
