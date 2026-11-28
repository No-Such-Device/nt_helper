import 'package:lua_dardo_plus/lua.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/parameter_number_lookup.dart';

final class LuaAlgorithmControllerException implements Exception {
  const LuaAlgorithmControllerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Evaluates a controller as a pure function of an immutable [Slot] snapshot.
///
/// The Lua runtime receives data only. It cannot access the MIDI manager,
/// DistingCubit, Flutter widgets, the filesystem, or the network. The returned
/// table is validated into an [AlgorithmControllerDocument] before rendering.
final class LuaAlgorithmControllerEngine {
  const LuaAlgorithmControllerEngine();

  static const _runtimePrelude = r'''
ui = {}
nt = {}

local function element(kind, props)
  props = props or {}
  props.type = kind
  return props
end

function ui.column(props) return element("column", props) end
function ui.row(props) return element("row", props) end
function ui.section(props) return element("section", props) end
function ui.text(props) return element("text", props) end
function ui.slider(props) return element("slider", props) end
function ui.choice(props) return element("choice", props) end
function ui.toggle(props) return element("toggle", props) end
function ui.button(props) return element("button", props) end
function ui.divider(props) return element("divider", props) end
function ui.spacer(props) return element("spacer", props) end
function ui.canvas(props) return element("canvas", props) end
function ui.xy_pad(props) return element("xy_pad", props) end
function ui.note_mask(props) return element("note_mask", props) end
function ui.circle(props) return element("circle", props) end
function ui.line(props) return element("line", props) end
function ui.rect(props) return element("rect", props) end

function nt.parameter(name, occurrence)
  occurrence = occurrence or 1
  local seen = 0
  for _, parameter in ipairs(algorithm.parameters) do
    if parameter.name == name then
      seen = seen + 1
      if seen == occurrence then return parameter end
    end
  end
  return nil
end

function nt.parameter_by_number(number)
  for _, parameter in ipairs(algorithm.parameters) do
    if parameter.number == number then return parameter end
  end
  return nil
end

function nt.page(name, occurrence)
  occurrence = occurrence or 1
  local seen = 0
  for _, page in ipairs(algorithm.pages) do
    if page.name == name then
      seen = seen + 1
      if seen == occurrence then return page end
    end
  end
  return nil
end

-- The firmware prefixes a channel's parameters with the channel's name, so a
-- renamed channel reports "Grov:Gain" instead of "1:Gain". Channels are
-- identified by their "Channel N" pages, whose members keep their parameter
-- numbers across a rename.
local function channel_number_of_page(page_name)
  if string.sub(page_name, 1, 8) ~= "Channel " then return nil end
  local digits = string.sub(page_name, 9)
  if digits == "" then return nil end
  for index = 1, string.len(digits) do
    local byte = string.byte(digits, index)
    if byte < 48 or byte > 57 then return nil end
  end
  return tonumber(digits)
end

local function compute_channel_prefixes()
  local prefixes = {}
  local mapped = false
  for _, page in ipairs(algorithm.pages) do
    local number = channel_number_of_page(page.name)
    if number ~= nil then
      for _, member in ipairs(page.parameters) do
        local parameter = nt.parameter_by_number(member)
        if parameter ~= nil then
          local separator = string.find(parameter.name, ":", 1, true)
          if separator ~= nil and separator > 1 then
            prefixes[number] = string.sub(parameter.name, 1, separator - 1)
            mapped = true
            break
          end
        end
      end
    end
  end

  if mapped then return prefixes end

  -- Algorithms without channel pages: fall back to numeric prefixes, in the
  -- order the parameters appear.
  for _, parameter in ipairs(algorithm.parameters) do
    local separator = string.find(parameter.name, ":", 1, true)
    if separator ~= nil and separator > 1 then
      local prefix = string.sub(parameter.name, 1, separator - 1)
      local number = tonumber(prefix)
      if number ~= nil and prefixes[number] == nil then
        prefixes[number] = prefix
      end
    end
  end
  return prefixes
end

local prefixes_cache = nil

local function channel_prefixes()
  if prefixes_cache == nil then
    prefixes_cache = compute_channel_prefixes()
  end
  return prefixes_cache
end

function nt.channel_prefix(channel)
  return channel_prefixes()[channel]
end

function nt.channel_parameter(channel, name, occurrence)
  local prefix = channel_prefixes()[channel]
  if prefix == nil then return nil end
  return nt.parameter(prefix .. ":" .. name, occurrence)
end

function nt.channels()
  local numbers = {}
  for channel, _ in pairs(channel_prefixes()) do table.insert(numbers, channel) end
  table.sort(numbers)
  return numbers
end
''';

  AlgorithmControllerDocument evaluate({
    required String source,
    required Slot slot,
    required int slotIndex,
    required List<String> units,
  }) {
    final state = LuaState.newState();
    state.openLibs();
    _removeUnsafeGlobals(state);
    _pushValue(state, _slotSnapshot(slot, slotIndex, units));
    state.setGlobal('algorithm');

    final loadStatus = state.loadString('$_runtimePrelude\n$source');
    if (loadStatus != ThreadStatus.luaOk) {
      throw LuaAlgorithmControllerException(
        'Lua controller could not be loaded: ${_takeError(state)}',
      );
    }

    final callStatus = state.pCall(0, 1, 0);
    if (callStatus != ThreadStatus.luaOk) {
      throw LuaAlgorithmControllerException(
        'Lua controller failed: ${_takeError(state)}',
      );
    }

    final result = _readValue(state, -1);
    state.pop(1);
    final document = _AlgorithmControllerDocumentParser().parse(result);
    _validateNoIoBindings(document.root, slot);
    return document;
  }

  /// Data-only companion API. Caller runs this in a disposable isolate with a
  /// deadline. Explicitly loaded SD code has no host APIs; it still requires
  /// a trusted source because the isolate has no hard memory quota.
  Object? evaluateCompanion({
    required String source,
    required String guid,
    required Map<String, Object?> snapshot,
    Map<String, Object?>? event,
    Map<String, Object?>? change,
  }) {
    final state = LuaState.newState();
    state.openLibs();
    _removeUnsafeGlobals(state);
    for (final name in ['io', 'debug', 'collectgarbage']) {
      state.pushNil();
      state.setGlobal(name);
    }
    _pushValue(state, snapshot);
    state.setGlobal('snapshot');
    _pushValue(state, event);
    state.setGlobal('event');
    _pushValue(state, change);
    state.setGlobal('change');
    _pushValue(state, guid);
    state.setGlobal('companion_guid');
    final status = state.loadString(
      'local companion = (function()\n$source\nend)()\n'
      'assert(companion.api_version == 1 and companion.guid == companion_guid, "Incompatible companion")\n'
      'if change ~= nil and companion.on_change ~= nil then return companion.on_change(snapshot, change) end\n'
      'if event == nil then return companion.render(snapshot) else return companion.handle(snapshot, event) end',
    );
    if (status != ThreadStatus.luaOk ||
        state.pCall(0, 1, 0) != ThreadStatus.luaOk) {
      throw LuaAlgorithmControllerException(
        'SD-card companion failed: ${_takeError(state)}',
      );
    }
    return _readValue(state, -1);
  }

  void _removeUnsafeGlobals(LuaState state) {
    const names = [
      'package',
      'os',
      'coroutine',
      'require',
      'dofile',
      'loadfile',
      'load',
      'print',
    ];
    for (final name in names) {
      state.pushNil();
      state.setGlobal(name);
    }
  }

  Map<String, Object?> _slotSnapshot(
    Slot slot,
    int slotIndex,
    List<String> units,
  ) {
    final parameters = <Map<String, Object?>>[];
    for (final info in slot.parameters) {
      final parameterNumber = info.parameterNumber;
      final value = slot.values.byParameterNumber(parameterNumber);
      final enums = slot.enums.byParameterNumber(parameterNumber);
      final valueString = slot.valueStrings.byParameterNumber(parameterNumber);
      parameters.add({
        'number': parameterNumber,
        'name': info.name,
        'minimum': info.min,
        'maximum': info.max,
        'default': info.defaultValue,
        'unit': info.getUnitString(units),
        'unit_index': info.unit,
        'power_of_ten': info.powerOfTen,
        'value': value?.value ?? info.defaultValue,
        'disabled': value?.isDisabled ?? false,
        'enum_values': [
          for (final enumValue in enums?.values ?? const <String>[])
            enumValue.trim(),
        ],
        'display_value': valueString?.value.trim() ?? '',
        'io_flags': info.ioFlags,
        'is_input': info.isInput,
        'is_output': info.isOutput,
      });
    }

    return {
      'slot_index': slotIndex,
      'guid': slot.algorithm.guid,
      'name': slot.algorithm.name,
      'specifications': slot.algorithm.specifications,
      'parameters': parameters,
      'pages': [
        for (final page in slot.pages.pages)
          {'name': page.name, 'parameters': page.parameters},
      ],
      'routing': slot.routing.routingInfo,
    };
  }

  void _validateNoIoBindings(AlgorithmControllerNode node, Slot slot) {
    final parameterNumbers = switch (node) {
      AlgorithmControllerSlider(:final parameterNumber) => [parameterNumber],
      AlgorithmControllerChoice(:final parameterNumber) => [parameterNumber],
      AlgorithmControllerToggle(:final parameterNumber) => [parameterNumber],
      AlgorithmControllerButton(:final action) => [action.parameterNumber],
      AlgorithmControllerXYPad(
        :final xParameterNumber,
        :final yParameterNumber,
      ) =>
        [xParameterNumber, yParameterNumber],
      AlgorithmControllerNoteMask(:final notes) => [
        for (final note in notes) note.parameterNumber,
      ],
      AlgorithmControllerCanvas(:final targets) => [
        for (final target in targets) ...[
          if (target.xAxis case final axis?) axis.parameterNumber,
          if (target.yAxis case final axis?) axis.parameterNumber,
          if (target.wheel case final wheel?) wheel.parameterNumber,
        ],
      ],
      _ => const <int>[],
    };
    for (final parameterNumber in parameterNumbers) {
      final info = slot.parameters.byParameterNumber(parameterNumber);
      if (info != null && info.ioFlags != 0) {
        throw LuaAlgorithmControllerException(
          'Controller controls cannot bind I/O parameter '
          '$parameterNumber (${info.name})',
        );
      }
    }

    final children = switch (node) {
      AlgorithmControllerColumn(:final children) => children,
      AlgorithmControllerRow(:final children) => children,
      AlgorithmControllerSection(:final children) => children,
      _ => const <AlgorithmControllerNode>[],
    };
    for (final child in children) {
      _validateNoIoBindings(child, slot);
    }
  }

  void _pushValue(LuaState state, Object? value) {
    switch (value) {
      case null:
        state.pushNil();
      case bool value:
        state.pushBoolean(value);
      case int value:
        state.pushInteger(value);
      case double value:
        state.pushNumber(value);
      case String value:
        state.pushString(value);
      case List<Object?> value:
        state.createTable(value.length, 0);
        for (var index = 0; index < value.length; index++) {
          _pushValue(state, value[index]);
          state.rawSetI(-2, index + 1);
        }
      case Map<String, Object?> value:
        state.createTable(0, value.length);
        for (final entry in value.entries) {
          _pushValue(state, entry.value);
          state.setField(-2, entry.key);
        }
      default:
        throw LuaAlgorithmControllerException(
          'Unsupported controller snapshot value: ${value.runtimeType}',
        );
    }
  }

  Object? _readValue(LuaState state, int index, {int depth = 0}) {
    if (depth > 32) {
      throw const LuaAlgorithmControllerException(
        'Lua controller returned a table deeper than 32 levels',
      );
    }

    return switch (state.type(index)) {
      LuaType.luaNil => null,
      LuaType.luaBoolean => state.toBoolean(index),
      LuaType.luaNumber =>
        state.isInteger(index) ? state.toInteger(index) : state.toNumber(index),
      LuaType.luaString => state.toStr(index),
      LuaType.luaTable => _readTable(state, index, depth),
      final type => throw LuaAlgorithmControllerException(
        'Lua controller returned unsupported ${state.typeName(type)} value',
      ),
    };
  }

  Object _readTable(LuaState state, int index, int depth) {
    final absoluteIndex = state.absIndex(index);
    final entries = <Object, Object?>{};
    state.pushNil();
    while (state.next(absoluteIndex)) {
      final key = _readValue(state, -2, depth: depth + 1);
      if (key == null) {
        throw const LuaAlgorithmControllerException(
          'Lua controller returned an invalid table key',
        );
      }
      entries[key] = _readValue(state, -1, depth: depth + 1);
      state.pop(1);
    }

    if (entries.isEmpty) return <Object?>[];
    final integerKeys = entries.keys.whereType<int>().toList()..sort();
    final isList =
        integerKeys.length == entries.length &&
        integerKeys.first == 1 &&
        integerKeys.last == integerKeys.length;
    if (isList) {
      return [
        for (var index = 1; index <= entries.length; index++) entries[index],
      ];
    }
    return entries;
  }

  String _takeError(LuaState state) {
    if (state.getTop() == 0) return 'Unknown Lua error';
    final message = state.toStr(-1) ?? state.typeName2(-1);
    state.pop(1);
    return message;
  }
}

final class _AlgorithmControllerDocumentParser {
  static const _maximumNodes = 512;
  static const _maximumShapes = 2048;
  static const _maximumCanvasTargets = 256;

  var _nodeCount = 0;
  var _shapeCount = 0;
  var _canvasTargetCount = 0;

  AlgorithmControllerDocument parse(Object? value) {
    final document = _map(value, 'document');
    final version = _integer(document['version'], 'document.version');
    if (version != 1) {
      throw LuaAlgorithmControllerException(
        'Unsupported controller document version $version',
      );
    }
    return AlgorithmControllerDocument(
      version: version,
      title: _string(document['title'], 'document.title'),
      root: _node(document['root'], 'document.root', 0),
    );
  }

  AlgorithmControllerNode _node(Object? value, String path, int depth) {
    if (depth > 32) {
      throw LuaAlgorithmControllerException('$path exceeds 32 levels');
    }
    _nodeCount++;
    if (_nodeCount > _maximumNodes) {
      throw const LuaAlgorithmControllerException(
        'Controller document exceeds 512 UI nodes',
      );
    }

    final node = _map(value, path);
    final type = _string(node['type'], '$path.type');
    return switch (type) {
      'column' => AlgorithmControllerColumn(
        children: _children(node['children'], '$path.children', depth),
        gap: _optionalNumber(node['gap'], '$path.gap') ?? 12,
        padding: _optionalNumber(node['padding'], '$path.padding') ?? 0,
      ),
      'row' => AlgorithmControllerRow(
        children: _children(node['children'], '$path.children', depth),
        gap: _optionalNumber(node['gap'], '$path.gap') ?? 8,
      ),
      'section' => AlgorithmControllerSection(
        title: _string(node['title'], '$path.title'),
        subtitle: _optionalString(node['subtitle'], '$path.subtitle'),
        children: _children(node['children'], '$path.children', depth),
      ),
      'text' => AlgorithmControllerText(
        text: _string(node['text'], '$path.text'),
        style: _optionalString(node['style'], '$path.style') ?? 'body',
        align: _optionalString(node['align'], '$path.align') ?? 'start',
      ),
      'slider' => AlgorithmControllerSlider(
        label: _string(node['label'], '$path.label'),
        parameterNumber: _integer(node['parameter'], '$path.parameter'),
        minimum: _optionalInteger(node['minimum'], '$path.minimum'),
        maximum: _optionalInteger(node['maximum'], '$path.maximum'),
        enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
      ),
      'choice' => AlgorithmControllerChoice(
        label: _string(node['label'], '$path.label'),
        parameterNumber: _integer(node['parameter'], '$path.parameter'),
        enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
      ),
      'toggle' => AlgorithmControllerToggle(
        label: _string(node['label'], '$path.label'),
        parameterNumber: _integer(node['parameter'], '$path.parameter'),
        onValue: _optionalInteger(node['on_value'], '$path.on_value') ?? 1,
        offValue: _optionalInteger(node['off_value'], '$path.off_value') ?? 0,
        enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
      ),
      'button' => AlgorithmControllerButton(
        label: _string(node['label'], '$path.label'),
        action: _action(node['action'], '$path.action'),
        style: _optionalString(node['style'], '$path.style') ?? 'filled',
        enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
      ),
      'divider' => const AlgorithmControllerDivider(),
      'spacer' => AlgorithmControllerSpacer(
        size: _optionalNumber(node['size'], '$path.size') ?? 8,
      ),
      'canvas' => _canvas(node, path),
      'xy_pad' => AlgorithmControllerXYPad(
        label: _string(node['label'], '$path.label'),
        xParameterNumber: _integer(node['x_parameter'], '$path.x_parameter'),
        yParameterNumber: _integer(node['y_parameter'], '$path.y_parameter'),
        xLabel: _optionalString(node['x_label'], '$path.x_label') ?? 'X',
        yLabel: _optionalString(node['y_label'], '$path.y_label') ?? 'Y',
        aspectRatio:
            _optionalNumber(node['aspect_ratio'], '$path.aspect_ratio') ?? 1,
        invertY: _optionalBoolean(node['invert_y'], '$path.invert_y') ?? true,
        enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
      ),
      'note_mask' => _noteMask(node, path),
      _ => throw LuaAlgorithmControllerException(
        '$path has unknown UI node type "$type"',
      ),
    };
  }

  List<AlgorithmControllerNode> _children(
    Object? value,
    String path,
    int depth,
  ) {
    final children = _list(value, path);
    return [
      for (var index = 0; index < children.length; index++)
        _node(children[index], '$path[$index]', depth + 1),
    ];
  }

  AlgorithmControllerNoteMask _noteMask(
    Map<Object, Object?> node,
    String path,
  ) {
    final layoutName = _string(node['layout'], '$path.layout');
    final layout = switch (layoutName) {
      'piano' => AlgorithmControllerNoteMaskLayout.piano,
      'degrees' => AlgorithmControllerNoteMaskLayout.degrees,
      _ => throw LuaAlgorithmControllerException(
        '$path.layout must be "piano" or "degrees"',
      ),
    };
    final rawNotes = _list(node['notes'], '$path.notes');
    if (rawNotes.length > 128) {
      throw LuaAlgorithmControllerException(
        '$path.notes must contain at most 128 notes',
      );
    }

    final pitchClasses = <int>{};
    final parameterNumbers = <int>{};
    final notes = <AlgorithmControllerNoteMaskEntry>[];
    for (var index = 0; index < rawNotes.length; index++) {
      final notePath = '$path.notes[$index]';
      final note = _map(rawNotes[index], notePath);
      final label = _string(note['label'], '$notePath.label');
      final parameterNumber = _integer(
        note['parameter'],
        '$notePath.parameter',
      );
      if (!parameterNumbers.add(parameterNumber)) {
        throw LuaAlgorithmControllerException(
          '$notePath.parameter duplicates parameter $parameterNumber',
        );
      }
      int? pitchClass;
      switch (layout) {
        case AlgorithmControllerNoteMaskLayout.piano:
          pitchClass = _integer(note['pitch_class'], '$notePath.pitch_class');
          if (pitchClass < 0 || pitchClass > 11) {
            throw LuaAlgorithmControllerException(
              '$notePath.pitch_class must be between 0 and 11',
            );
          }
          if (!pitchClasses.add(pitchClass)) {
            throw LuaAlgorithmControllerException(
              '$notePath.pitch_class duplicates pitch class $pitchClass',
            );
          }
        case AlgorithmControllerNoteMaskLayout.degrees:
          if (note.containsKey('pitch_class')) {
            throw LuaAlgorithmControllerException(
              '$notePath.pitch_class must be omitted for degrees layout',
            );
          }
      }
      notes.add(
        AlgorithmControllerNoteMaskEntry(
          label: label,
          parameterNumber: parameterNumber,
          pitchClass: pitchClass,
        ),
      );
    }

    return AlgorithmControllerNoteMask(
      label: _string(node['label'], '$path.label'),
      layout: layout,
      notes: List.unmodifiable(notes),
      enabled: _optionalBoolean(node['enabled'], '$path.enabled') ?? true,
    );
  }

  AlgorithmControllerAction _action(Object? value, String path) {
    final action = _map(value, path);
    final type = _string(action['type'], '$path.type');
    final parameter = _integer(action['parameter'], '$path.parameter');
    return switch (type) {
      'set_parameter' => AlgorithmControllerAction.setParameter(
        parameterNumber: parameter,
        value: _integer(action['value'], '$path.value'),
      ),
      'adjust_parameter' => AlgorithmControllerAction.adjustParameter(
        parameterNumber: parameter,
        delta: _integer(action['delta'], '$path.delta'),
      ),
      'pulse_parameter' => AlgorithmControllerAction.pulseParameter(
        parameterNumber: parameter,
        offValue: _optionalInteger(action['off_value'], '$path.off_value') ?? 0,
        onValue: _optionalInteger(action['on_value'], '$path.on_value') ?? 1,
        durationMs:
            (_optionalInteger(action['duration_ms'], '$path.duration_ms') ??
                    100)
                .clamp(0, 1000),
      ),
      _ => throw LuaAlgorithmControllerException(
        '$path has unknown action type "$type"',
      ),
    };
  }

  AlgorithmControllerCanvas _canvas(Map<Object, Object?> node, String path) {
    final dragThreshold =
        _optionalNumber(node['drag_threshold'], '$path.drag_threshold') ?? 4;
    if (dragThreshold < 0) {
      throw LuaAlgorithmControllerException(
        '$path.drag_threshold must be non-negative',
      );
    }
    final rawTargets = node['targets'];
    final targets = rawTargets == null
        ? const <AlgorithmControllerCanvasTarget>[]
        : _canvasTargets(rawTargets, '$path.targets');
    return AlgorithmControllerCanvas(
      semanticsLabel: _string(node['semantics_label'], '$path.semantics_label'),
      aspectRatio:
          _optionalNumber(node['aspect_ratio'], '$path.aspect_ratio') ?? 4,
      shapes: _shapes(node['shapes'], '$path.shapes'),
      targets: targets,
      dragThreshold: dragThreshold,
      cycleOverlappingSelection:
          _optionalBoolean(
            node['cycle_overlapping_selection'],
            '$path.cycle_overlapping_selection',
          ) ??
          false,
    );
  }

  List<AlgorithmControllerCanvasTarget> _canvasTargets(
    Object? value,
    String path,
  ) {
    final rawTargets = _list(value, path);
    _canvasTargetCount += rawTargets.length;
    if (_canvasTargetCount > _maximumCanvasTargets) {
      throw const LuaAlgorithmControllerException(
        'Controller document exceeds 256 canvas targets',
      );
    }
    final seenIds = <String>{};
    final targets = <AlgorithmControllerCanvasTarget>[];
    for (var index = 0; index < rawTargets.length; index++) {
      final targetPath = '$path[$index]';
      final target = _canvasTarget(rawTargets[index], targetPath);
      if (!seenIds.add(target.id)) {
        throw LuaAlgorithmControllerException(
          '$targetPath.id duplicates target "${target.id}"',
        );
      }
      targets.add(target);
    }
    return List.unmodifiable(targets);
  }

  AlgorithmControllerCanvasTarget _canvasTarget(Object? value, String path) {
    final target = _map(value, path);
    final id = _nonEmptyString(target['id'], '$path.id');
    final label = _nonEmptyString(target['label'], '$path.label');
    final hitArea = _canvasHitArea(target, path);
    return AlgorithmControllerCanvasTarget(
      id: id,
      label: label,
      hitArea: hitArea,
      selectable:
          _optionalBoolean(target['selectable'], '$path.selectable') ?? false,
      order: _optionalInteger(target['order'], '$path.order'),
      enabled: _optionalBoolean(target['enabled'], '$path.enabled') ?? true,
      xAxis: target['x_axis'] == null
          ? null
          : _canvasAxisBinding(
              target['x_axis'],
              '$path.x_axis',
              defaultInvert: false,
            ),
      yAxis: target['y_axis'] == null
          ? null
          : _canvasAxisBinding(
              target['y_axis'],
              '$path.y_axis',
              defaultInvert: true,
            ),
      wheel: target['wheel'] == null
          ? null
          : _canvasWheelBinding(target['wheel'], '$path.wheel'),
    );
  }

  AlgorithmControllerCanvasHitArea _canvasHitArea(
    Map<Object, Object?> target,
    String path,
  ) {
    final shape = _string(target['shape'], '$path.shape');
    return switch (shape) {
      'circle' => _circleHitArea(target, path),
      'rect' => _rectHitArea(target, path),
      _ => throw LuaAlgorithmControllerException(
        '$path.shape must be "circle" or "rect"',
      ),
    };
  }

  AlgorithmControllerCanvasCircleHitArea _circleHitArea(
    Map<Object, Object?> target,
    String path,
  ) {
    final x = _number(target['x'], '$path.x');
    final y = _number(target['y'], '$path.y');
    final radius = _number(target['radius'], '$path.radius');
    if (radius <= 0) {
      throw LuaAlgorithmControllerException('$path.radius must be positive');
    }
    return AlgorithmControllerCanvasCircleHitArea(x: x, y: y, radius: radius);
  }

  AlgorithmControllerCanvasRectHitArea _rectHitArea(
    Map<Object, Object?> target,
    String path,
  ) {
    final x = _number(target['x'], '$path.x');
    final y = _number(target['y'], '$path.y');
    final width = _number(target['width'], '$path.width');
    final height = _number(target['height'], '$path.height');
    if (width <= 0) {
      throw LuaAlgorithmControllerException('$path.width must be positive');
    }
    if (height <= 0) {
      throw LuaAlgorithmControllerException('$path.height must be positive');
    }
    return AlgorithmControllerCanvasRectHitArea(
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  AlgorithmControllerCanvasAxisBinding _canvasAxisBinding(
    Object? value,
    String path, {
    required bool defaultInvert,
  }) {
    final axis = _map(value, path);
    final from = _optionalNumber(axis['from'], '$path.from') ?? 0;
    final to = _optionalNumber(axis['to'], '$path.to') ?? 1;
    if (from >= to) {
      throw LuaAlgorithmControllerException('$path.from must be less than to');
    }
    final step = _optionalInteger(axis['step'], '$path.step') ?? 1;
    if (step < 1) {
      throw LuaAlgorithmControllerException('$path.step must be at least 1');
    }
    return AlgorithmControllerCanvasAxisBinding(
      parameterNumber: _integer(axis['parameter'], '$path.parameter'),
      from: from,
      to: to,
      minimum: _optionalInteger(axis['minimum'], '$path.minimum'),
      maximum: _optionalInteger(axis['maximum'], '$path.maximum'),
      step: step,
      invert: _optionalBoolean(axis['invert'], '$path.invert') ?? defaultInvert,
      enabled: _optionalBoolean(axis['enabled'], '$path.enabled') ?? true,
    );
  }

  AlgorithmControllerCanvasWheelBinding _canvasWheelBinding(
    Object? value,
    String path,
  ) {
    final wheel = _map(value, path);
    final step = _optionalInteger(wheel['step'], '$path.step') ?? 1;
    if (step < 1) {
      throw LuaAlgorithmControllerException('$path.step must be at least 1');
    }
    return AlgorithmControllerCanvasWheelBinding(
      parameterNumber: _integer(wheel['parameter'], '$path.parameter'),
      minimum: _optionalInteger(wheel['minimum'], '$path.minimum'),
      maximum: _optionalInteger(wheel['maximum'], '$path.maximum'),
      step: step,
      invert: _optionalBoolean(wheel['invert'], '$path.invert') ?? false,
      enabled: _optionalBoolean(wheel['enabled'], '$path.enabled') ?? true,
    );
  }

  List<AlgorithmControllerCanvasShape> _shapes(Object? value, String path) {
    final shapes = _list(value, path);
    _shapeCount += shapes.length;
    if (_shapeCount > _maximumShapes) {
      throw const LuaAlgorithmControllerException(
        'Controller document exceeds 2048 canvas shapes',
      );
    }
    return [
      for (var index = 0; index < shapes.length; index++)
        _shape(shapes[index], '$path[$index]'),
    ];
  }

  AlgorithmControllerCanvasShape _shape(Object? value, String path) {
    final shape = _map(value, path);
    final type = _string(shape['type'], '$path.type');
    return switch (type) {
      'circle' => AlgorithmControllerCircle(
        x: _number(shape['x'], '$path.x'),
        y: _number(shape['y'], '$path.y'),
        radius: _number(shape['radius'], '$path.radius'),
        fill: _optionalString(shape['fill'], '$path.fill'),
        stroke: _optionalString(shape['stroke'], '$path.stroke'),
        strokeWidth:
            _optionalNumber(shape['stroke_width'], '$path.stroke_width') ?? 1,
      ),
      'line' => AlgorithmControllerLine(
        x1: _number(shape['x1'], '$path.x1'),
        y1: _number(shape['y1'], '$path.y1'),
        x2: _number(shape['x2'], '$path.x2'),
        y2: _number(shape['y2'], '$path.y2'),
        stroke: _optionalString(shape['stroke'], '$path.stroke') ?? 'outline',
        strokeWidth:
            _optionalNumber(shape['stroke_width'], '$path.stroke_width') ?? 1,
      ),
      'rect' => AlgorithmControllerRectangle(
        x: _number(shape['x'], '$path.x'),
        y: _number(shape['y'], '$path.y'),
        width: _number(shape['width'], '$path.width'),
        height: _number(shape['height'], '$path.height'),
        radius: _optionalNumber(shape['radius'], '$path.radius') ?? 0,
        fill: _optionalString(shape['fill'], '$path.fill'),
        stroke: _optionalString(shape['stroke'], '$path.stroke'),
        strokeWidth:
            _optionalNumber(shape['stroke_width'], '$path.stroke_width') ?? 1,
      ),
      _ => throw LuaAlgorithmControllerException(
        '$path has unknown canvas shape type "$type"',
      ),
    };
  }

  Map<Object, Object?> _map(Object? value, String path) {
    if (value case Map<Object, Object?> map) return map;
    throw LuaAlgorithmControllerException('$path must be a table');
  }

  List<Object?> _list(Object? value, String path) {
    if (value case List<Object?> list) return list;
    throw LuaAlgorithmControllerException('$path must be an array table');
  }

  String _string(Object? value, String path) {
    if (value case String string) return string;
    throw LuaAlgorithmControllerException('$path must be a string');
  }

  String _nonEmptyString(Object? value, String path) {
    final string = _string(value, path);
    if (string.trim().isEmpty) {
      throw LuaAlgorithmControllerException('$path must be a non-empty string');
    }
    return string;
  }

  String? _optionalString(Object? value, String path) {
    if (value == null) return null;
    return _string(value, path);
  }

  int _integer(Object? value, String path) {
    if (value case int integer) return integer;
    throw LuaAlgorithmControllerException('$path must be an integer');
  }

  int? _optionalInteger(Object? value, String path) {
    if (value == null) return null;
    return _integer(value, path);
  }

  double _number(Object? value, String path) {
    if (value case num number when number.isFinite) return number.toDouble();
    throw LuaAlgorithmControllerException('$path must be a finite number');
  }

  double? _optionalNumber(Object? value, String path) {
    if (value == null) return null;
    return _number(value, path);
  }

  bool? _optionalBoolean(Object? value, String path) {
    if (value == null) return null;
    if (value case bool boolean) return boolean;
    throw LuaAlgorithmControllerException('$path must be a boolean');
  }
}
