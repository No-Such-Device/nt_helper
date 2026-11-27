sealed class AlgorithmControllerNode {
  const AlgorithmControllerNode();
}

final class AlgorithmControllerColumn extends AlgorithmControllerNode {
  const AlgorithmControllerColumn({
    required this.children,
    this.gap = 12,
    this.padding = 0,
  });

  final List<AlgorithmControllerNode> children;
  final double gap;
  final double padding;
}

final class AlgorithmControllerRow extends AlgorithmControllerNode {
  const AlgorithmControllerRow({required this.children, this.gap = 8});

  final List<AlgorithmControllerNode> children;
  final double gap;
}

final class AlgorithmControllerSection extends AlgorithmControllerNode {
  const AlgorithmControllerSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<AlgorithmControllerNode> children;
}

final class AlgorithmControllerText extends AlgorithmControllerNode {
  const AlgorithmControllerText({
    required this.text,
    this.style = 'body',
    this.align = 'start',
  });

  final String text;
  final String style;
  final String align;
}

final class AlgorithmControllerSlider extends AlgorithmControllerNode {
  const AlgorithmControllerSlider({
    required this.label,
    required this.parameterNumber,
    this.minimum,
    this.maximum,
    this.enabled = true,
  });

  final String label;
  final int parameterNumber;
  final int? minimum;
  final int? maximum;
  final bool enabled;
}

final class AlgorithmControllerChoice extends AlgorithmControllerNode {
  const AlgorithmControllerChoice({
    required this.label,
    required this.parameterNumber,
    this.enabled = true,
  });

  final String label;
  final int parameterNumber;
  final bool enabled;
}

final class AlgorithmControllerToggle extends AlgorithmControllerNode {
  const AlgorithmControllerToggle({
    required this.label,
    required this.parameterNumber,
    this.onValue = 1,
    this.offValue = 0,
    this.enabled = true,
  });

  final String label;
  final int parameterNumber;
  final int onValue;
  final int offValue;
  final bool enabled;
}

enum AlgorithmControllerActionType {
  setParameter,
  adjustParameter,
  pulseParameter,
}

final class AlgorithmControllerAction {
  const AlgorithmControllerAction.setParameter({
    required this.parameterNumber,
    required int this.value,
  }) : type = AlgorithmControllerActionType.setParameter,
       delta = null,
       offValue = null,
       onValue = null,
       durationMs = null;

  const AlgorithmControllerAction.adjustParameter({
    required this.parameterNumber,
    required int this.delta,
  }) : type = AlgorithmControllerActionType.adjustParameter,
       value = null,
       offValue = null,
       onValue = null,
       durationMs = null;

  const AlgorithmControllerAction.pulseParameter({
    required this.parameterNumber,
    this.offValue = 0,
    this.onValue = 1,
    this.durationMs = 100,
  }) : type = AlgorithmControllerActionType.pulseParameter,
       value = null,
       delta = null;

  final AlgorithmControllerActionType type;
  final int parameterNumber;
  final int? value;
  final int? delta;
  final int? offValue;
  final int? onValue;
  final int? durationMs;
}

final class AlgorithmControllerButton extends AlgorithmControllerNode {
  const AlgorithmControllerButton({
    required this.label,
    required this.action,
    this.style = 'filled',
    this.enabled = true,
  });

  final String label;
  final AlgorithmControllerAction action;
  final String style;
  final bool enabled;
}

final class AlgorithmControllerDivider extends AlgorithmControllerNode {
  const AlgorithmControllerDivider();
}

final class AlgorithmControllerSpacer extends AlgorithmControllerNode {
  const AlgorithmControllerSpacer({this.size = 8});

  final double size;
}

sealed class AlgorithmControllerCanvasShape {
  const AlgorithmControllerCanvasShape();
}

final class AlgorithmControllerCircle extends AlgorithmControllerCanvasShape {
  const AlgorithmControllerCircle({
    required this.x,
    required this.y,
    required this.radius,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });

  final double x;
  final double y;
  final double radius;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
}

final class AlgorithmControllerLine extends AlgorithmControllerCanvasShape {
  const AlgorithmControllerLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.stroke = 'outline',
    this.strokeWidth = 1,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String stroke;
  final double strokeWidth;
}

final class AlgorithmControllerRectangle
    extends AlgorithmControllerCanvasShape {
  const AlgorithmControllerRectangle({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.radius = 0,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double radius;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
}

sealed class AlgorithmControllerCanvasHitArea {
  const AlgorithmControllerCanvasHitArea();
}

final class AlgorithmControllerCanvasCircleHitArea
    extends AlgorithmControllerCanvasHitArea {
  const AlgorithmControllerCanvasCircleHitArea({
    required this.x,
    required this.y,
    required this.radius,
  });

  final double x;
  final double y;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is AlgorithmControllerCanvasCircleHitArea &&
      other.x == x &&
      other.y == y &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(x, y, radius);
}

final class AlgorithmControllerCanvasRectHitArea
    extends AlgorithmControllerCanvasHitArea {
  const AlgorithmControllerCanvasRectHitArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is AlgorithmControllerCanvasRectHitArea &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

final class AlgorithmControllerCanvasAxisBinding {
  const AlgorithmControllerCanvasAxisBinding({
    required this.parameterNumber,
    this.from = 0,
    this.to = 1,
    this.minimum,
    this.maximum,
    this.step = 1,
    this.invert = false,
    this.enabled = true,
  });

  final int parameterNumber;
  final double from;
  final double to;
  final int? minimum;
  final int? maximum;
  final int step;
  final bool invert;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is AlgorithmControllerCanvasAxisBinding &&
      other.parameterNumber == parameterNumber &&
      other.from == from &&
      other.to == to &&
      other.minimum == minimum &&
      other.maximum == maximum &&
      other.step == step &&
      other.invert == invert &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    parameterNumber,
    from,
    to,
    minimum,
    maximum,
    step,
    invert,
    enabled,
  );
}

final class AlgorithmControllerCanvasWheelBinding {
  const AlgorithmControllerCanvasWheelBinding({
    required this.parameterNumber,
    this.minimum,
    this.maximum,
    this.step = 1,
    this.invert = false,
    this.enabled = true,
  });

  final int parameterNumber;
  final int? minimum;
  final int? maximum;
  final int step;
  final bool invert;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is AlgorithmControllerCanvasWheelBinding &&
      other.parameterNumber == parameterNumber &&
      other.minimum == minimum &&
      other.maximum == maximum &&
      other.step == step &&
      other.invert == invert &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(parameterNumber, minimum, maximum, step, invert, enabled);
}

final class AlgorithmControllerCanvasTarget {
  const AlgorithmControllerCanvasTarget({
    required this.id,
    required this.label,
    required this.hitArea,
    this.selectable = false,
    this.order,
    this.enabled = true,
    this.xAxis,
    this.yAxis,
    this.wheel,
  });

  final String id;
  final String label;
  final AlgorithmControllerCanvasHitArea hitArea;
  final bool selectable;
  final int? order;
  final bool enabled;
  final AlgorithmControllerCanvasAxisBinding? xAxis;
  final AlgorithmControllerCanvasAxisBinding? yAxis;
  final AlgorithmControllerCanvasWheelBinding? wheel;
}

enum AlgorithmControllerCanvasInteractionEventType {
  selected,
  dragStart,
  dragUpdate,
  dragEnd,
  dragCancel,
  wheel,
}

enum AlgorithmControllerCanvasCancelReason {
  pointerCancel,
  escapeKey,
  slotChanged,
  bindingChanged,
  reconnect,
  disposed,
  gestureRejected,
}

final class AlgorithmControllerCanvasInteractionEvent {
  const AlgorithmControllerCanvasInteractionEvent({
    required this.type,
    required this.targetId,
    this.pointer,
    this.xValue,
    this.yValue,
    this.wheelValue,
    this.cancelReason,
  });

  final AlgorithmControllerCanvasInteractionEventType type;
  final String targetId;
  final int? pointer;
  final int? xValue;
  final int? yValue;
  final int? wheelValue;
  final AlgorithmControllerCanvasCancelReason? cancelReason;
}

final class AlgorithmControllerCanvas extends AlgorithmControllerNode {
  const AlgorithmControllerCanvas({
    required this.semanticsLabel,
    required this.shapes,
    this.aspectRatio = 4,
    this.targets = const [],
    this.dragThreshold = 4,
    this.cycleOverlappingSelection = false,
  });

  final String semanticsLabel;
  final double aspectRatio;
  final List<AlgorithmControllerCanvasShape> shapes;
  final List<AlgorithmControllerCanvasTarget> targets;
  final double dragThreshold;
  final bool cycleOverlappingSelection;

  bool get isInteractive => targets.isNotEmpty;
}

final class AlgorithmControllerXYPad extends AlgorithmControllerNode {
  const AlgorithmControllerXYPad({
    required this.label,
    required this.xParameterNumber,
    required this.yParameterNumber,
    this.xLabel = 'X',
    this.yLabel = 'Y',
    this.aspectRatio = 1,
    this.invertY = true,
    this.enabled = true,
  });

  final String label;
  final int xParameterNumber;
  final int yParameterNumber;
  final String xLabel;
  final String yLabel;
  final double aspectRatio;
  final bool invertY;
  final bool enabled;
}

enum AlgorithmControllerNoteMaskLayout { piano, degrees }

final class AlgorithmControllerNoteMaskEntry {
  const AlgorithmControllerNoteMaskEntry({
    required this.label,
    required this.parameterNumber,
    this.pitchClass,
  });

  final String label;
  final int parameterNumber;
  final int? pitchClass;
}

final class AlgorithmControllerNoteMask extends AlgorithmControllerNode {
  const AlgorithmControllerNoteMask({
    required this.label,
    required this.layout,
    required this.notes,
    this.enabled = true,
  });

  final String label;
  final AlgorithmControllerNoteMaskLayout layout;
  final List<AlgorithmControllerNoteMaskEntry> notes;
  final bool enabled;
}

final class AlgorithmControllerDocument {
  const AlgorithmControllerDocument({
    required this.version,
    required this.title,
    required this.root,
  });

  final int version;
  final String title;
  final AlgorithmControllerNode root;
}

final class AlgorithmControllerDefinition {
  const AlgorithmControllerDefinition({
    required this.id,
    required this.algorithmGuid,
    required this.name,
    required this.assetPath,
  });

  final String id;
  final String algorithmGuid;
  final String name;
  final String assetPath;
}

final class AlgorithmControllerRegistry {
  const AlgorithmControllerRegistry(this._definitions);

  static const bundled = AlgorithmControllerRegistry([
    AlgorithmControllerDefinition(
      id: 'builtin.euclidean-patterns',
      algorithmGuid: 'eucp',
      name: 'Euclidean controller',
      assetPath: 'assets/algorithm_controllers/euclidean_patterns.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.clock',
      algorithmGuid: 'clck',
      name: 'Clock controller',
      assetPath: 'assets/algorithm_controllers/clock.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.clock-divider',
      algorithmGuid: 'clkd',
      name: 'Clock divider controller',
      assetPath: 'assets/algorithm_controllers/clock_divider.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.attenuverter',
      algorithmGuid: 'attn',
      name: 'Attenuverter controller',
      assetPath: 'assets/algorithm_controllers/attenuverter.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.crossfader',
      algorithmGuid: 'xfad',
      name: 'Crossfader controller',
      assetPath: 'assets/algorithm_controllers/crossfader.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.dj-filter',
      algorithmGuid: 'djfi',
      name: 'DJ Filter controller',
      assetPath: 'assets/algorithm_controllers/dj_filter.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.lfo',
      algorithmGuid: 'lfo ',
      name: 'LFO controller',
      assetPath: 'assets/algorithm_controllers/lfo.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.envelope-dahdsr',
      algorithmGuid: 'envq',
      name: 'Envelope DAHDSR controller',
      assetPath: 'assets/algorithm_controllers/envelope_dahdsr.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.envelope-ar-ad',
      algorithmGuid: 'env2',
      name: 'Envelope AR/AD controller',
      assetPath: 'assets/algorithm_controllers/envelope_ar_ad.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.parametric-eq',
      algorithmGuid: 'eqpa',
      name: 'Parametric EQ controller',
      assetPath: 'assets/algorithm_controllers/parametric_eq.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.mixer-mono',
      algorithmGuid: 'mix1',
      name: 'Mono mixer controller',
      assetPath: 'assets/algorithm_controllers/mixer_mono.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.mixer-stereo',
      algorithmGuid: 'mix2',
      name: 'Stereo mixer controller',
      assetPath: 'assets/algorithm_controllers/mixer_stereo.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.dream-machine',
      algorithmGuid: 'drea',
      name: 'Dream Machine controller',
      assetPath: 'assets/algorithm_controllers/dream_machine.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.macro-oscillator-2',
      algorithmGuid: 'mac2',
      name: 'Macro Oscillator 2 controller',
      assetPath: 'assets/algorithm_controllers/macro_oscillator_2.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.poly-macro-oscillator-2',
      algorithmGuid: 'pym2',
      name: 'Poly Macro Oscillator 2 controller',
      assetPath: 'assets/algorithm_controllers/macro_oscillator_2.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.filter-bank',
      algorithmGuid: 'fbnk',
      name: 'Filter bank controller',
      assetPath: 'assets/algorithm_controllers/filter_bank.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.chaos',
      algorithmGuid: 'xaoc',
      name: 'Chaos controller',
      assetPath: 'assets/algorithm_controllers/chaos.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.quantizer',
      algorithmGuid: 'quan',
      name: 'Quantizer controller',
      assetPath: 'assets/algorithm_controllers/quantizer.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.envelope-sequencer',
      algorithmGuid: 'ensq',
      name: 'Envelope sequencer controller',
      assetPath: 'assets/algorithm_controllers/envelope_sequencer.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.quadraphonic-mixer',
      algorithmGuid: 'quad',
      name: 'Quadraphonic mixer controller',
      assetPath: 'assets/algorithm_controllers/quadraphonic_mixer.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.seaside-jawari',
      algorithmGuid: 'ssjw',
      name: 'Seaside Jawari controller',
      assetPath: 'assets/algorithm_controllers/seaside_jawari.lua',
    ),
    AlgorithmControllerDefinition(
      id: 'builtin.stopwatch',
      algorithmGuid: 'stpw',
      name: 'Stopwatch controller',
      assetPath: 'assets/algorithm_controllers/stopwatch.lua',
    ),
  ]);

  final List<AlgorithmControllerDefinition> _definitions;

  AlgorithmControllerDefinition? findForGuid(String guid) {
    for (final definition in _definitions) {
      if (definition.algorithmGuid == guid) return definition;
    }
    return null;
  }
}
