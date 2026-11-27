import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/algorithm_controller/lua_algorithm_controller_engine.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = LuaAlgorithmControllerEngine();

  test('evaluates generic UI primitives from the latest slot snapshot', () {
    const source = r'''
return {
  version = 1,
  title = algorithm.name,
  root = ui.column {
    children = {
      ui.text { text = "Steps " .. nt.parameter("1:Steps").value },
      ui.slider {
        label = "Steps",
        parameter = nt.parameter("1:Steps").number
      }
    }
  }
}
''';

    final firstDocument = engine.evaluate(
      source: source,
      slot: _euclideanSlot(steps: 16),
      slotIndex: 2,
      units: const [],
    );
    final secondDocument = engine.evaluate(
      source: source,
      slot: _euclideanSlot(steps: 11),
      slotIndex: 2,
      units: const [],
    );

    expect(firstDocument.title, 'Euclidean Patterns');
    final firstRoot = firstDocument.root as AlgorithmControllerColumn;
    final secondRoot = secondDocument.root as AlgorithmControllerColumn;
    expect(
      (firstRoot.children.first as AlgorithmControllerText).text,
      'Steps 16',
    );
    expect(
      (secondRoot.children.first as AlgorithmControllerText).text,
      'Steps 11',
    );
    expect(
      (firstRoot.children.last as AlgorithmControllerSlider).parameterNumber,
      2,
    );
  });

  test('parses an enum-backed choice control', () {
    const source = r'''
return {
  version = 1,
  title = "Choice",
  root = ui.choice {
    label = "Mode",
    parameter = nt.parameter("1:Enable").number
  }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 2,
      units: const [],
    );

    final choice = document.root as AlgorithmControllerChoice;
    expect(choice.label, 'Mode');
    expect(choice.parameterNumber, 1);
  });

  test('looks up live parameters by number from a named page', () {
    const source = r'''
local page = nt.page("Patterns")
local first = nt.parameter_by_number(page.parameters[1])
local second = nt.parameter_by_number(page.parameters[2])
return {
  version = 1,
  title = "Page",
  root = ui.text {
    text = first.name .. "|" .. second.name .. "=" .. second.value
  }
}
''';

    final firstDocument = engine.evaluate(
      source: source,
      slot: _euclideanSlot(steps: 16),
      slotIndex: 2,
      units: const [],
    );
    final secondDocument = engine.evaluate(
      source: source,
      slot: _euclideanSlot(steps: 11),
      slotIndex: 2,
      units: const [],
    );

    expect(
      (firstDocument.root as AlgorithmControllerText).text,
      '1:Enable|1:Steps=16',
    );
    expect(
      (secondDocument.root as AlgorithmControllerText).text,
      '1:Enable|1:Steps=11',
    );
  });

  test('exposes I/O flags for read-only previews', () {
    const source = r'''
local steps = nt.parameter("1:Steps")
return {
  version = 1,
  title = "I/O metadata",
  root = ui.text { text = tostring(steps.io_flags) }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _slotWithIoParameter(),
      slotIndex: 2,
      units: const [],
    );

    expect((document.root as AlgorithmControllerText).text, '5');
  });

  test('rejects controls bound to any I/O parameter', () {
    const source = r'''
return {
  version = 1,
  title = "I/O control",
  root = ui.slider {
    label = "Forbidden routing",
    parameter = nt.parameter("1:Steps").number
  }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _slotWithIoParameter(),
        slotIndex: 2,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('cannot bind I/O parameter 2 (1:Steps)'),
        ),
      ),
    );
  });

  test('selects repeated named pages by occurrence', () {
    const source = r'''
local page = nt.page("Patterns", 2)
return {
  version = 1,
  title = "Page occurrence",
  root = ui.text {
    text = nt.parameter_by_number(page.parameters[1]).name
  }
}
''';
    final slot = _euclideanSlot();
    final repeatedPagesSlot = slot.copyWith(
      pages: ParameterPages(
        algorithmIndex: slot.algorithm.algorithmIndex,
        pages: [
          ...slot.pages.pages,
          ParameterPage(name: 'Patterns', parameters: const [2]),
        ],
      ),
    );

    final document = engine.evaluate(
      source: source,
      slot: repeatedPagesSlot,
      slotIndex: 2,
      units: const [],
    );

    expect((document.root as AlgorithmControllerText).text, '1:Steps');
  });

  test('parses a parameter-bound XY pad', () {
    const source = r'''
return {
  version = 1,
  title = "XY",
  root = ui.xy_pad {
    label = "Position",
    x_label = "Horizontal",
    y_label = "Vertical",
    x_parameter = nt.parameter("1:Steps").number,
    y_parameter = nt.parameter("1:Pulses").number,
    aspect_ratio = 1.5,
    invert_y = false,
    enabled = false
  }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 2,
      units: const [],
    );

    final pad = document.root as AlgorithmControllerXYPad;
    expect(pad.label, 'Position');
    expect(pad.xLabel, 'Horizontal');
    expect(pad.yLabel, 'Vertical');
    expect(pad.xParameterNumber, 2);
    expect(pad.yParameterNumber, 3);
    expect(pad.aspectRatio, 1.5);
    expect(pad.invertY, isFalse);
    expect(pad.enabled, isFalse);
  });

  test('parses a piano note mask with unique pitch classes', () {
    const source = r'''
return {
  version = 1,
  title = "Notes",
  root = ui.note_mask {
    label = "Allowed notes",
    layout = "piano",
    enabled = false,
    notes = {
      { label = "C", parameter = 10, pitch_class = 0 },
      { label = "F sharp", parameter = 16, pitch_class = 6 },
      { label = "B", parameter = 21, pitch_class = 11 }
    }
  }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 2,
      units: const [],
    );

    final noteMask = document.root as AlgorithmControllerNoteMask;
    expect(noteMask.label, 'Allowed notes');
    expect(noteMask.layout, AlgorithmControllerNoteMaskLayout.piano);
    expect(noteMask.enabled, isFalse);
    expect(noteMask.notes, hasLength(3));
    expect(noteMask.notes.map((note) => note.label), ['C', 'F sharp', 'B']);
    expect(noteMask.notes.map((note) => note.parameterNumber), [10, 16, 21]);
    expect(noteMask.notes.map((note) => note.pitchClass), [0, 6, 11]);
  });

  test('parses a degree note mask without pitch classes', () {
    const source = r'''
return {
  version = 1,
  title = "Degrees",
  root = ui.note_mask {
    label = "Scale degrees",
    layout = "degrees",
    notes = {
      { label = "1", parameter = 10 },
      { label = "2", parameter = 11 }
    }
  }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 2,
      units: const [],
    );

    final noteMask = document.root as AlgorithmControllerNoteMask;
    expect(noteMask.layout, AlgorithmControllerNoteMaskLayout.degrees);
    expect(noteMask.enabled, isTrue);
    expect(noteMask.notes.map((note) => note.pitchClass), [null, null]);
  });

  test('rejects invalid piano note-mask pitch classes', () {
    for (final invalidNotes in [
      '{ label = "Missing", parameter = 1 }',
      '{ label = "Low", parameter = 1, pitch_class = -1 }',
      '{ label = "High", parameter = 1, pitch_class = 12 }',
      '{ label = "C", parameter = 1, pitch_class = 0 }, '
          '{ label = "C again", parameter = 2, pitch_class = 0 }',
    ]) {
      final source =
          '''
return {
  version = 1,
  title = "Invalid",
  root = ui.note_mask {
    label = "Notes",
    layout = "piano",
    notes = { $invalidNotes }
  }
}
''';

      expect(
        () => engine.evaluate(
          source: source,
          slot: _euclideanSlot(),
          slotIndex: 2,
          units: const [],
        ),
        throwsA(isA<LuaAlgorithmControllerException>()),
      );
    }
  });

  test('rejects unsupported note-mask layouts', () {
    const source = r'''
return {
  version = 1,
  title = "Invalid",
  root = ui.note_mask {
    label = "Notes",
    layout = "chromatic",
    notes = {}
  }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 2,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('must be "piano" or "degrees"'),
        ),
      ),
    );
  });

  test('rejects pitch classes in a degree note mask', () {
    const source = r'''
return {
  version = 1,
  title = "Invalid",
  root = ui.note_mask {
    label = "Degrees",
    layout = "degrees",
    notes = {
      { label = "1", parameter = 1, pitch_class = 0 }
    }
  }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 2,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('must be omitted'),
        ),
      ),
    );
  });

  test('rejects duplicate parameter bindings in a note mask', () {
    const source = r'''
return {
  version = 1,
  title = "Invalid",
  root = ui.note_mask {
    label = "Degrees",
    layout = "degrees",
    notes = {
      { label = "1", parameter = 7 },
      { label = "2", parameter = 7 }
    }
  }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 2,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('duplicates parameter 7'),
        ),
      ),
    );
  });

  test('rejects note masks with more than 128 notes', () {
    final notes = List.generate(
      129,
      (index) => '{ label = "$index", parameter = $index }',
    ).join(',');
    final source =
        '''
return {
  version = 1,
  title = "Too many",
  root = ui.note_mask {
    label = "Degrees",
    layout = "degrees",
    notes = { $notes }
  }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 2,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('at most 128 notes'),
        ),
      ),
    );
  });

  test('parses a repeatable parameter pulse action', () {
    const source = r'''
return {
  version = 1,
  title = "Pulse",
  root = ui.button {
    label = "Trigger",
    action = {
      type = "pulse_parameter",
      parameter = nt.parameter("1:Enable").number,
      off_value = 2,
      on_value = 7,
      duration_ms = 75
    }
  }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 2,
      units: const [],
    );

    final action = (document.root as AlgorithmControllerButton).action;
    expect(action.type, AlgorithmControllerActionType.pulseParameter);
    expect(action.parameterNumber, 1);
    expect(action.offValue, 2);
    expect(action.onValue, 7);
    expect(action.durationMs, 75);
  });

  test('matches snapshot values and strings by hardware parameter number', () {
    const source = r'''
local steps = nt.parameter("1:Steps")
return {
  version = 1,
  title = "Numbered snapshot",
  root = ui.text {
    text = steps.value .. "|" .. steps.display_value
  }
}
''';
    final slot = _euclideanSlot(steps: 11);
    final shuffled = slot.copyWith(
      values: slot.values.reversed.toList(),
      enums: slot.enums.reversed.toList(),
      valueStrings: [
        for (final valueString in slot.valueStrings.reversed)
          valueString.parameterNumber == 2
              ? ParameterValueString(
                  algorithmIndex: 2,
                  parameterNumber: 2,
                  value: 'eleven steps',
                )
              : valueString,
      ],
    );

    final document = engine.evaluate(
      source: source,
      slot: shuffled,
      slotIndex: 2,
      units: const [],
    );

    expect((document.root as AlgorithmControllerText).text, '11|eleven steps');
  });

  test('does not expose filesystem and process libraries to controllers', () {
    const source = r'''
return {
  version = 1,
  title = "Unsafe",
  root = ui.text { text = tostring(os) }
}
''';

    final document = engine.evaluate(
      source: source,
      slot: _euclideanSlot(),
      slotIndex: 0,
      units: const [],
    );
    expect((document.root as AlgorithmControllerText).text, 'nil');
  }, tags: ['regression']);

  test('rejects unknown UI primitives', () {
    const source = r'''
return {
  version = 1,
  title = "Unknown",
  root = { type = "native_flutter_widget" }
}
''';

    expect(
      () => engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 0,
        units: const [],
      ),
      throwsA(
        isA<LuaAlgorithmControllerException>().having(
          (error) => error.message,
          'message',
          contains('unknown UI node type'),
        ),
      ),
    );
  });

  test(
    'bundled Euclidean controller builds controls and canvas shapes',
    () async {
      final source = await rootBundle.loadString(
        'assets/algorithm_controllers/euclidean_patterns.lua',
      );

      final document = engine.evaluate(
        source: source,
        slot: _euclideanSlot(channelCount: 2),
        slotIndex: 2,
        units: const [],
      );

      final root = document.root as AlgorithmControllerColumn;
      final channelColumn = root.children.last as AlgorithmControllerColumn;
      expect(document.title, 'Euclidean Patterns');
      expect(channelColumn.children, hasLength(2));

      final firstChannel =
          channelColumn.children.first as AlgorithmControllerSection;
      expect(firstChannel.title, 'Channel 1');
      expect(
        firstChannel.children.whereType<AlgorithmControllerSlider>(),
        hasLength(3),
      );
      final canvas = firstChannel.children
          .whereType<AlgorithmControllerCanvas>()
          .single;
      expect(
        canvas.shapes.whereType<AlgorithmControllerCircle>(),
        hasLength(16),
      );
      expect(canvas.targets, isEmpty);
      expect(canvas.isInteractive, isFalse);
    },
  );

  group('canvas opt-in input targets', () {
    test('parses circle and rect targets with axes, wheel, and options', () {
      const source = r'''
return {
  version = 1,
  title = "Interactive canvas",
  root = ui.canvas {
    semantics_label = "Synthetic interactive surface",
    aspect_ratio = 3,
    drag_threshold = 6.5,
    cycle_overlapping_selection = true,
    shapes = {
      ui.circle { x = 0.5, y = 0.5, radius = 0.05, fill = "primary" }
    },
    targets = {
      {
        id = "handle-1",
        label = "Handle 1",
        shape = "circle",
        x = 0.5,
        y = 0.5,
        radius = 0.06,
        selectable = true,
        order = 2,
        x_axis = {
          parameter = nt.parameter("1:Steps").number,
          from = 0.1,
          to = 0.9,
          minimum = 2,
          maximum = 24,
          step = 2
        },
        y_axis = {
          parameter = nt.parameter("1:Pulses").number,
          from = 0.15,
          to = 0.85,
          invert = false
        },
        wheel = {
          parameter = nt.parameter("1:Rotation").number,
          minimum = 0,
          maximum = 16,
          step = 2,
          invert = true
        }
      },
      {
        id = "fader-1",
        label = "Fader 1",
        shape = "rect",
        x = 0.1,
        y = 0.2,
        width = 0.12,
        height = 0.6,
        enabled = false,
        y_axis = {
          parameter = nt.parameter("1:Pulses").number
        }
      }
    }
  }
}
''';

      final document = engine.evaluate(
        source: source,
        slot: _euclideanSlot(),
        slotIndex: 2,
        units: const [],
      );

      final canvas = document.root as AlgorithmControllerCanvas;
      expect(canvas.isInteractive, isTrue);
      expect(canvas.dragThreshold, 6.5);
      expect(canvas.cycleOverlappingSelection, isTrue);
      expect(canvas.targets, hasLength(2));

      final circleTarget = canvas.targets[0];
      expect(circleTarget.id, 'handle-1');
      expect(circleTarget.label, 'Handle 1');
      expect(
        circleTarget.hitArea,
        const AlgorithmControllerCanvasCircleHitArea(
          x: 0.5,
          y: 0.5,
          radius: 0.06,
        ),
      );
      expect(circleTarget.selectable, isTrue);
      expect(circleTarget.order, 2);
      expect(circleTarget.enabled, isTrue);
      expect(
        circleTarget.xAxis,
        const AlgorithmControllerCanvasAxisBinding(
          parameterNumber: 2,
          from: 0.1,
          to: 0.9,
          minimum: 2,
          maximum: 24,
          step: 2,
          invert: false,
          enabled: true,
        ),
      );
      expect(
        circleTarget.yAxis,
        const AlgorithmControllerCanvasAxisBinding(
          parameterNumber: 3,
          from: 0.15,
          to: 0.85,
          invert: false,
          enabled: true,
        ),
      );
      expect(
        circleTarget.wheel,
        const AlgorithmControllerCanvasWheelBinding(
          parameterNumber: 4,
          minimum: 0,
          maximum: 16,
          step: 2,
          invert: true,
          enabled: true,
        ),
      );

      final rectTarget = canvas.targets[1];
      expect(rectTarget.id, 'fader-1');
      expect(
        rectTarget.hitArea,
        const AlgorithmControllerCanvasRectHitArea(
          x: 0.1,
          y: 0.2,
          width: 0.12,
          height: 0.6,
        ),
      );
      expect(rectTarget.enabled, isFalse);
      expect(rectTarget.selectable, isFalse);
      expect(rectTarget.yAxis?.invert, isTrue);
      expect(rectTarget.xAxis, isNull);
      expect(rectTarget.wheel, isNull);
    });

    test(
      'legacy canvas without targets stays non-interactive with defaults',
      () {
        const source = r'''
return {
  version = 1,
  title = "Legacy canvas",
  root = ui.canvas {
    semantics_label = "Paint only",
    shapes = {
      ui.rect { x = 0, y = 0, width = 1, height = 1, fill = "surface" }
    }
  }
}
''';

        final document = engine.evaluate(
          source: source,
          slot: _euclideanSlot(),
          slotIndex: 2,
          units: const [],
        );

        final canvas = document.root as AlgorithmControllerCanvas;
        expect(canvas.targets, isEmpty);
        expect(canvas.isInteractive, isFalse);
        expect(canvas.dragThreshold, 4);
        expect(canvas.cycleOverlappingSelection, isFalse);
      },
    );

    test('rejects invalid canvas target descriptors', () {
      final invalidCases = <({String name, String canvasBody, String error})>[
        (
          name: 'negative drag threshold',
          canvasBody: 'drag_threshold = -1, targets = {}',
          error: 'drag_threshold must be non-negative',
        ),
        (
          name: 'non-array targets',
          canvasBody: 'targets = { id = "not-a-list" }',
          error: 'must be an array table',
        ),
        (
          name: 'empty target id',
          canvasBody: 'targets = { { id = "  ", label = "A", shape = "circle", x = 0.5, y = 0.5, radius = 0.1 } }',
          error: 'must be a non-empty string',
        ),
        (
          name: 'duplicate target id',
          canvasBody:
              'targets = { '
              '{ id = "dup", label = "A", shape = "circle", x = 0.2, y = 0.5, radius = 0.1 }, '
              '{ id = "dup", label = "B", shape = "circle", x = 0.8, y = 0.5, radius = 0.1 } '
              '}',
          error: 'duplicates target "dup"',
        ),
        (
          name: 'missing label',
          canvasBody: 'targets = { { id = "a", shape = "circle", x = 0.5, y = 0.5, radius = 0.1 } }',
          error: '.label must be a string',
        ),
        (
          name: 'unknown shape',
          canvasBody: 'targets = { { id = "a", label = "A", shape = "triangle", x = 0.5, y = 0.5 } }',
          error: 'must be "circle" or "rect"',
        ),
        (
          name: 'non-positive circle radius',
          canvasBody: 'targets = { { id = "a", label = "A", shape = "circle", x = 0.5, y = 0.5, radius = 0 } }',
          error: 'radius must be positive',
        ),
        (
          name: 'non-positive rect width',
          canvasBody: 'targets = { { id = "a", label = "A", shape = "rect", x = 0.1, y = 0.1, width = 0, height = 0.5 } }',
          error: 'width must be positive',
        ),
        (
          name: 'non-positive rect height',
          canvasBody: 'targets = { { id = "a", label = "A", shape = "rect", x = 0.1, y = 0.1, width = 0.2, height = -0.1 } }',
          error: 'height must be positive',
        ),
        (
          name: 'inverted from/to bounds on axis',
          canvasBody:
              'targets = { { id = "a", label = "A", shape = "circle", x = 0.5, y = 0.5, radius = 0.1, '
              'x_axis = { parameter = 2, from = 0.8, to = 0.2 } } }',
          error: 'from must be less than to',
        ),
        (
          name: 'non-positive axis step',
          canvasBody:
              'targets = { { id = "a", label = "A", shape = "circle", x = 0.5, y = 0.5, radius = 0.1, '
              'x_axis = { parameter = 2, step = 0 } } }',
          error: 'step must be at least 1',
        ),
        (
          name: 'non-positive wheel step',
          canvasBody:
              'targets = { { id = "a", label = "A", shape = "circle", x = 0.5, y = 0.5, radius = 0.1, '
              'wheel = { parameter = 2, step = 0 } } }',
          error: 'step must be at least 1',
        ),
      ];

      for (final testCase in invalidCases) {
        final source =
            '''
return {
  version = 1,
  title = "Invalid canvas",
  root = ui.canvas {
    semantics_label = "Invalid",
    shapes = {},
    ${testCase.canvasBody}
  }
}
''';
        expect(
          () => engine.evaluate(
            source: source,
            slot: _euclideanSlot(),
            slotIndex: 2,
            units: const [],
          ),
          throwsA(
            isA<LuaAlgorithmControllerException>().having(
              (error) => error.message,
              'message',
              contains(testCase.error),
            ),
          ),
          reason: testCase.name,
        );
      }
    });

    test('rejects canvas targets bound to I/O parameters', () {
      for (final binding in [
        'x_axis = { parameter = 2 }',
        'y_axis = { parameter = 2 }',
        'wheel = { parameter = 2 }',
      ]) {
        final source =
            '''
return {
  version = 1,
  title = "I/O canvas",
  root = ui.canvas {
    semantics_label = "Forbidden",
    shapes = {},
    targets = {
      {
        id = "io",
        label = "I/O target",
        shape = "circle",
        x = 0.5,
        y = 0.5,
        radius = 0.1,
        $binding
      }
    }
  }
}
''';

        expect(
          () => engine.evaluate(
            source: source,
            slot: _slotWithIoParameter(),
            slotIndex: 2,
            units: const [],
          ),
          throwsA(
            isA<LuaAlgorithmControllerException>().having(
              (error) => error.message,
              'message',
              contains('cannot bind I/O parameter 2 (1:Steps)'),
            ),
          ),
          reason: binding,
        );
      }
    });
  });
}

Slot _euclideanSlot({int steps = 16, int channelCount = 1}) {
  final fixtures = <({String name, int value, int min, int max})>[
    (name: 'Bypass', value: 0, min: 0, max: 1),
  ];
  for (var channel = 1; channel <= channelCount; channel++) {
    fixtures.addAll([
      (name: '$channel:Enable', value: channel == 1 ? 1 : 0, min: 0, max: 1),
      (name: '$channel:Steps', value: steps, min: 1, max: 32),
      (name: '$channel:Pulses', value: 4, min: 1, max: 32),
      (name: '$channel:Rotation', value: 0, min: 0, max: 32),
    ]);
  }

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: 2,
      guid: 'eucp',
      name: 'Euclidean Patterns',
      specifications: [channelCount],
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: 2,
      pages: [
        ParameterPage(
          name: 'Patterns',
          parameters: [
            for (var index = 1; index < fixtures.length; index++) index,
          ],
        ),
        ParameterPage(name: 'Algorithm', parameters: const [0]),
      ],
    ),
    parameters: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterInfo(
          algorithmIndex: 2,
          parameterNumber: index,
          min: fixtures[index].min,
          max: fixtures[index].max,
          defaultValue: fixtures[index].min,
          unit: 0,
          name: fixtures[index].name,
          powerOfTen: 0,
        ),
    ],
    values: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValue(
          algorithmIndex: 2,
          parameterNumber: index,
          value: fixtures[index].value,
        ),
    ],
    enums: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterEnumStrings(
          algorithmIndex: 2,
          parameterNumber: index,
          values:
              fixtures[index].name.endsWith(':Enable') ||
                  fixtures[index].name == 'Bypass'
              ? const ['Off', 'On']
              : const [],
        ),
    ],
    mappings: [for (final _ in fixtures) Mapping.filler()],
    valueStrings: [
      for (var index = 0; index < fixtures.length; index++)
        ParameterValueString(
          algorithmIndex: 2,
          parameterNumber: index,
          value: '',
        ),
    ],
  );
}

Slot _slotWithIoParameter() {
  final slot = _euclideanSlot();
  return slot.copyWith(
    parameters: [
      for (final parameter in slot.parameters)
        parameter.parameterNumber == 2
            ? ParameterInfo(
                algorithmIndex: parameter.algorithmIndex,
                parameterNumber: parameter.parameterNumber,
                min: parameter.min,
                max: parameter.max,
                defaultValue: parameter.defaultValue,
                unit: parameter.unit,
                name: parameter.name,
                powerOfTen: parameter.powerOfTen,
                ioFlags: 5,
              )
            : parameter,
    ],
  );
}
