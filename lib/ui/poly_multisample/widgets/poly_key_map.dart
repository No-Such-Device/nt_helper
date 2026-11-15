import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';
import 'package:nt_helper/ui/poly_multisample/poly_region_math.dart';

class PolyKeyMap extends StatefulWidget {
  const PolyKeyMap({
    super.key,
    required this.regions,
    required this.mappingResolution,
    required this.selectedPath,
    required this.onSelect,
    this.height = 180,
    this.onPreviewNote,
    this.onPreviewNoteStart,
    this.onPreviewNoteEnd,
    this.playedMidiNote,
  });

  final List<PolySampleRegion> regions;
  final PolySampleMappingResolution mappingResolution;
  final String? selectedPath;
  final ValueChanged<PolySampleRegion> onSelect;
  final double height;
  final ValueChanged<int>? onPreviewNote;
  final ValueChanged<int>? onPreviewNoteStart;
  final VoidCallback? onPreviewNoteEnd;
  final int? playedMidiNote;

  @override
  State<PolyKeyMap> createState() => _PolyKeyMapState();
}

class _PolyKeyMapState extends State<PolyKeyMap> {
  final ScrollController _scrollController = ScrollController();
  String? _pendingAutoScrollPath;
  String? _focusedRegionPath;

  @override
  void initState() {
    super.initState();
    _pendingAutoScrollPath = widget.selectedPath;
  }

  @override
  void didUpdateWidget(covariant PolyKeyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPath != widget.selectedPath ||
        oldWidget.mappingResolution != widget.mappingResolution) {
      _pendingAutoScrollPath = widget.selectedPath;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollHorizontally(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final next = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(next);
  }

  void _scheduleSelectedScroll(Size canvasSize, int minMidi, int maxMidi) {
    final selectedPath = _pendingAutoScrollPath;
    if (selectedPath == null) return;
    _pendingAutoScrollPath = null;
    final selected = widget.mappingResolution.mappingForPath(selectedPath);
    if (selected == null || !selected.isPlayable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final layout = _PolyKeyMapLayout(
        canvasSize,
        widget.mappingResolution.velocityLanes,
      );
      final span = math.max(1, maxMidi - minMidi + 1);
      final rootX =
          layout.left +
          ((selected.naturalMidi - minMidi) / span) * layout.width;
      final viewportWidth = _scrollController.position.viewportDimension;
      final current = _scrollController.offset;
      if (rootX >= current && rootX <= current + viewportWidth) return;
      final target = (rootX - viewportWidth / 2).clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
  }

  int? _midiAtKeyboardPosition(
    Offset position,
    Size size,
    int minMidi,
    int maxMidi,
  ) {
    final layout = _PolyKeyMapLayout(
      size,
      widget.mappingResolution.velocityLanes,
    );
    final keyboardRect = Rect.fromLTRB(
      layout.left,
      layout.keyboardTop,
      layout.right,
      layout.keyboardBottom,
    );
    return PolyKeyboardGeometry(
      keyboardRect: keyboardRect,
      minMidi: minMidi,
      maxMidi: maxMidi,
    ).hitTest(position);
  }

  List<Widget> _regionSemanticTargets(
    Size canvasSize,
    int minMidi,
    int maxMidi,
  ) {
    final layout = _PolyKeyMapLayout(
      canvasSize,
      widget.mappingResolution.velocityLanes,
    );
    final span = math.max(1, maxMidi - minMidi + 1);
    return [
      for (final mapping in widget.mappingResolution.playableMappings)
        Positioned.fromRect(
          rect: _regionRect(mapping, layout, span, minMidi),
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onSelect(mapping.region);
                  return null;
                },
              ),
            },
            onFocusChange: (focused) {
              setState(() {
                _focusedRegionPath = focused ? mapping.region.path : null;
              });
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(mapping.region),
              child: Semantics(
                button: true,
                selected: mapping.region.path == widget.selectedPath,
                label: _regionSemanticLabel(mapping, widget.regions),
                onTap: () => widget.onSelect(mapping.region),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _focusedRegionPath == mapping.region.path
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _noteSemanticTargets(Size canvasSize, int minMidi, int maxMidi) {
    final onPreviewNoteStart =
        widget.onPreviewNoteStart ?? widget.onPreviewNote;
    if (onPreviewNoteStart == null) return const [];
    final layout = _PolyKeyMapLayout(
      canvasSize,
      widget.mappingResolution.velocityLanes,
    );
    final keyboardRect = Rect.fromLTRB(
      layout.left,
      layout.keyboardTop,
      layout.right,
      layout.keyboardBottom,
    );
    final geometry = PolyKeyboardGeometry(
      keyboardRect: keyboardRect,
      minMidi: minMidi,
      maxMidi: maxMidi,
    );
    final keys = [...geometry.whiteKeys, ...geometry.blackKeys];
    return [
      for (final key in keys)
        Positioned.fromRect(
          rect: key.rect,
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  onPreviewNoteStart(key.midi);
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => onPreviewNoteStart(key.midi),
              onTapUp: (_) => widget.onPreviewNoteEnd?.call(),
              onTapCancel: () => widget.onPreviewNoteEnd?.call(),
              child: Semantics(
                button: true,
                label:
                    'Preview ${PolyMultisampleParser.midiToNoteName(key.midi)}',
                onTap: () => onPreviewNoteStart(key.midi),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mappedCount = widget.mappingResolution.mappedCount;
    final extents = widget.mappingResolution.midiExtents;
    final minMidi = extents == null ? 24 : math.max(0, extents.$1 - 6);
    final maxMidi = extents == null ? 96 : math.min(127, extents.$2 + 6);
    return Semantics(
      container: true,
      label: 'Keyboard map with $mappedCount mapped samples',
      hint: 'Tap sample ranges to select. Tap piano keys to preview notes.',
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasWidth = math.max(
              constraints.maxWidth,
              (maxMidi - minMidi + 1) * 6.0 + 32,
            );
            final canvasSize = Size(canvasWidth, constraints.maxHeight);
            _scheduleSelectedScroll(canvasSize, minMidi, maxMidi);
            return Listener(
              onPointerSignal: _scrollHorizontally,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasSize.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) {
                            final midi = _midiAtKeyboardPosition(
                              details.localPosition,
                              canvasSize,
                              minMidi,
                              maxMidi,
                            );
                            if (midi == null) return;
                            final onPreviewNoteStart =
                                widget.onPreviewNoteStart ??
                                widget.onPreviewNote;
                            onPreviewNoteStart?.call(midi);
                          },
                          onTapUp: (details) {
                            final region = _regionAtPosition(
                              details.localPosition,
                              canvasSize,
                              widget.mappingResolution,
                              minMidi,
                              maxMidi,
                            );
                            if (region != null) {
                              widget.onSelect(region);
                              return;
                            }
                            final midi = _midiAtKeyboardPosition(
                              details.localPosition,
                              canvasSize,
                              minMidi,
                              maxMidi,
                            );
                            if (midi != null) {
                              widget.onPreviewNoteEnd?.call();
                              return;
                            }
                          },
                          onTapCancel: () => widget.onPreviewNoteEnd?.call(),
                          child: CustomPaint(
                            painter: _PolyKeyMapPainter(
                              regions: widget.regions,
                              mappingResolution: widget.mappingResolution,
                              selectedPath: widget.selectedPath,
                              playedMidiNote: widget.playedMidiNote,
                              minMidi: minMidi,
                              maxMidi: maxMidi,
                              colorScheme: Theme.of(context).colorScheme,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      ..._regionSemanticTargets(canvasSize, minMidi, maxMidi),
                      ..._noteSemanticTargets(canvasSize, minMidi, maxMidi),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Rect _regionRect(
  PolySampleResolvedMapping mapping,
  _PolyKeyMapLayout layout,
  int span,
  int minMidi,
) {
  final region = mapping.region;
  final laneIndex = layout.lanes.indexOf(region.velocityLayer ?? 1);
  final lane = laneIndex < 0 ? 0 : laneIndex;
  final x0 = layout.left + ((mapping.lowMidi! - minMidi) / span) * layout.width;
  final x1 =
      layout.left + ((mapping.highMidi! + 1 - minMidi) / span) * layout.width;
  final y0 = layout.zoneTop + lane * layout.laneHeight;
  return Rect.fromLTWH(
    x0 + 1,
    y0 + 2,
    math.max(1, x1 - x0 - 2),
    math.max(1, layout.laneHeight - 4),
  );
}

String _regionSemanticLabel(
  PolySampleResolvedMapping mapping,
  List<PolySampleRegion> regions,
) {
  final region = mapping.region;
  final root = PolyMultisampleParser.midiToNoteName(mapping.naturalMidi);
  return [
    sampleDisplayLabel(region, regions),
    mapping.naturalIsAutomatic ? 'root $root, automatic' : 'root $root',
    'range ${PolyMultisampleParser.midiToNoteName(mapping.lowMidi!)} to ${PolyMultisampleParser.midiToNoteName(mapping.highMidi!)}',
    'velocity ${region.velocityLayer ?? 1}',
  ].join(', ');
}

PolySampleRegion? _regionAtPosition(
  Offset position,
  Size size,
  PolySampleMappingResolution mappingResolution,
  int minMidi,
  int maxMidi,
) {
  final layout = _PolyKeyMapLayout(size, mappingResolution.velocityLanes);
  if (!layout.zoneRect.contains(position)) return null;
  final span = math.max(1, maxMidi - minMidi + 1);
  final midi = (minMidi + ((position.dx - layout.left) / layout.width) * span)
      .floor()
      .clamp(minMidi, maxMidi);
  final laneIndex = ((position.dy - layout.zoneTop) / layout.laneHeight)
      .floor()
      .clamp(0, layout.lanes.length - 1);
  final velocity = layout.lanes[laneIndex];
  final matches = mappingResolution.playableMappings.where((mapping) {
    return (mapping.region.velocityLayer ?? 1) == velocity &&
        midi >= mapping.lowMidi! &&
        midi <= mapping.highMidi!;
  }).toList();
  if (matches.isEmpty) return null;
  matches.sort((a, b) {
    final rootCompare = a.naturalMidi.compareTo(b.naturalMidi);
    if (rootCompare != 0) return rootCompare;
    return (a.region.roundRobin ?? 1).compareTo(b.region.roundRobin ?? 1);
  });
  return matches.first.region;
}

class _PolyKeyMapLayout {
  _PolyKeyMapLayout(Size size, this.lanes)
    : left = lanes.length > 1 ? 52 : 16,
      right = size.width - 16,
      zoneTop = 24,
      keyboardTop = size.height - 42,
      keyboardBottom = size.height - 8 {
    width = math.max(1, right - left);
    zoneBottom = keyboardTop - 8;
    laneHeight = math.max(1, (zoneBottom - zoneTop) / lanes.length);
    zoneRect = Rect.fromLTRB(left, zoneTop, right, zoneBottom);
  }

  final List<int> lanes;
  final double left;
  final double right;
  final double zoneTop;
  final double keyboardTop;
  final double keyboardBottom;
  late final double width;
  late final double zoneBottom;
  late final double laneHeight;
  late final Rect zoneRect;
}

class PolyPianoKeyGeometry {
  const PolyPianoKeyGeometry({
    required this.midi,
    required this.pitchClass,
    required this.rect,
    required this.isBlack,
  });

  final int midi;
  final int pitchClass;
  final Rect rect;
  final bool isBlack;
}

class PolyPianoKeyBoundary {
  const PolyPianoKeyBoundary({required this.start, required this.end});

  final Offset start;
  final Offset end;
}

class PolyKeyboardGeometry {
  PolyKeyboardGeometry({
    required this.keyboardRect,
    required this.minMidi,
    required this.maxMidi,
    this.blackKeyWidthRatio = 0.62,
    this.blackKeyHeightRatio = 0.62,
  }) : assert(minMidi <= maxMidi),
       assert(blackKeyWidthRatio > 0 && blackKeyWidthRatio < 1),
       assert(blackKeyHeightRatio > 0 && blackKeyHeightRatio < 1);

  static const List<int> naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11];
  static const Set<int> blackPitchClasses = {1, 3, 6, 8, 10};

  final Rect keyboardRect;
  final int minMidi;
  final int maxMidi;
  final double blackKeyWidthRatio;
  final double blackKeyHeightRatio;

  late final _KeyboardUnitSpan _unitSpan = _keyboardUnitSpan();

  late final List<PolyPianoKeyGeometry> whiteKeys = [
    for (var midi = minMidi; midi <= maxMidi; midi++)
      if (!isBlackMidi(midi))
        PolyPianoKeyGeometry(
          midi: midi,
          pitchClass: pitchClassForMidi(midi),
          rect: _rectForUnitSpan(_noteUnitSpan(midi)),
          isBlack: false,
        ),
  ];

  late final List<PolyPianoKeyGeometry> blackKeys = [
    for (var midi = minMidi; midi <= maxMidi; midi++)
      if (isBlackMidi(midi))
        PolyPianoKeyGeometry(
          midi: midi,
          pitchClass: pitchClassForMidi(midi),
          rect: _blackRectForMidi(midi),
          isBlack: true,
        ),
  ];

  late final List<PolyPianoKeyBoundary> whiteBoundaries =
      _buildWhiteBoundaries();

  static int pitchClassForMidi(int midi) => midi.remainder(12);

  static bool isBlackMidi(int midi) =>
      blackPitchClasses.contains(pitchClassForMidi(midi));

  int? hitTest(Offset position) {
    if (!keyboardRect.contains(position)) return null;
    for (final key in blackKeys.reversed) {
      if (key.rect.contains(position)) return key.midi;
    }
    for (final key in whiteKeys) {
      if (key.rect.contains(position)) return key.midi;
    }
    return null;
  }

  Rect _blackRectForMidi(int midi) {
    final unitSpan = _noteUnitSpan(midi);
    return _rectForUnitSpan(
      unitSpan,
      bottom: keyboardRect.top + keyboardRect.height * blackKeyHeightRatio,
    );
  }

  List<PolyPianoKeyBoundary> _buildWhiteBoundaries() {
    final boundaries = <PolyPianoKeyBoundary>[];
    for (var i = 0; i < whiteKeys.length - 1; i++) {
      final left = whiteKeys[i];
      final right = whiteKeys[i + 1];
      final expectedNextNatural = _nextNaturalMidi(left.midi);
      if (right.midi != expectedNextNatural) continue;
      final x = right.rect.left;
      final blackBetween = _blackMidiBetween(left.midi, right.midi);
      final startY = blackBetween == null
          ? keyboardRect.top
          : keyboardRect.top + keyboardRect.height * blackKeyHeightRatio;
      boundaries.add(
        PolyPianoKeyBoundary(
          start: Offset(x, startY),
          end: Offset(x, keyboardRect.bottom),
        ),
      );
    }
    return boundaries;
  }

  int? _blackMidiBetween(int leftWhiteMidi, int rightWhiteMidi) {
    final candidate = leftWhiteMidi + 1;
    if (candidate < rightWhiteMidi &&
        candidate >= minMidi &&
        candidate <= maxMidi &&
        isBlackMidi(candidate)) {
      return candidate;
    }
    return null;
  }

  Rect _rectForUnitSpan(_KeyboardUnitSpan unitSpan, {double? bottom}) {
    final unitWidth = _unitSpan.end - _unitSpan.start;
    final left =
        keyboardRect.left +
        ((unitSpan.start - _unitSpan.start) / unitWidth) * keyboardRect.width;
    final right =
        keyboardRect.left +
        ((unitSpan.end - _unitSpan.start) / unitWidth) * keyboardRect.width;
    return Rect.fromLTRB(
      left.clamp(keyboardRect.left, keyboardRect.right).toDouble(),
      keyboardRect.top,
      right.clamp(keyboardRect.left, keyboardRect.right).toDouble(),
      bottom ?? keyboardRect.bottom,
    );
  }

  _KeyboardUnitSpan _keyboardUnitSpan() {
    var start = double.infinity;
    var end = double.negativeInfinity;
    for (var midi = minMidi; midi <= maxMidi; midi++) {
      final span = _noteUnitSpan(midi);
      start = math.min(start, span.start);
      end = math.max(end, span.end);
    }
    return _KeyboardUnitSpan(start, end);
  }

  _KeyboardUnitSpan _noteUnitSpan(int midi) {
    if (!isBlackMidi(midi)) {
      final index = _whiteIndexForNaturalMidi(midi);
      return _KeyboardUnitSpan(index.toDouble(), index + 1.0);
    }
    final boundary = _previousWhiteIndexForBlackMidi(midi) + 1.0;
    final halfWidth = blackKeyWidthRatio / 2;
    return _KeyboardUnitSpan(boundary - halfWidth, boundary + halfWidth);
  }

  static int _whiteIndexForNaturalMidi(int midi) {
    final octave = midi ~/ 12;
    final pitchClass = pitchClassForMidi(midi);
    final naturalIndex = naturalPitchClasses.indexOf(pitchClass);
    assert(naturalIndex >= 0);
    return octave * naturalPitchClasses.length + naturalIndex;
  }

  static int _previousWhiteIndexForBlackMidi(int midi) {
    final octave = midi ~/ 12;
    final pitchClass = pitchClassForMidi(midi);
    final naturalIndex = switch (pitchClass) {
      1 => 0,
      3 => 1,
      6 => 3,
      8 => 4,
      10 => 5,
      _ => throw ArgumentError.value(midi, 'midi', 'Expected a black key'),
    };
    return octave * naturalPitchClasses.length + naturalIndex;
  }

  static int _nextNaturalMidi(int midi) {
    var next = midi + 1;
    while (isBlackMidi(next)) {
      next++;
    }
    return next;
  }
}

class _KeyboardUnitSpan {
  const _KeyboardUnitSpan(this.start, this.end);

  final double start;
  final double end;
}

class _PolyKeyMapPainter extends CustomPainter {
  _PolyKeyMapPainter({
    required this.regions,
    required this.mappingResolution,
    required this.selectedPath,
    required this.playedMidiNote,
    required this.minMidi,
    required this.maxMidi,
    required this.colorScheme,
  });

  final List<PolySampleRegion> regions;
  final PolySampleMappingResolution mappingResolution;
  final String? selectedPath;
  final int? playedMidiNote;
  final int minMidi;
  final int maxMidi;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final lanes = mappingResolution.velocityLanes;
    final layout = _PolyKeyMapLayout(size, lanes);
    final span = math.max(1, maxMidi - minMidi + 1);
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    final fillPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.28);

    final title = TextPainter(
      text: TextSpan(
        text: 'Keyboard',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, const Offset(14, 6));

    for (var i = 0; i < lanes.length; i++) {
      final top = layout.zoneTop + i * layout.laneHeight;
      final bottom = top + layout.laneHeight;
      if (i.isOdd) {
        canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), fillPaint);
      }
      if (lanes.length > 1) {
        final laneLabel = TextPainter(
          text: TextSpan(
            text: 'V${lanes[i]}',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        laneLabel.paint(
          canvas,
          Offset(14, top + (layout.laneHeight - laneLabel.height) / 2),
        );
      }
      canvas.drawLine(
        Offset(layout.left, bottom),
        Offset(layout.right, bottom),
        gridPaint,
      );
    }

    for (var midi = minMidi; midi <= maxMidi; midi++) {
      final x = layout.left + ((midi - minMidi) / span) * layout.width;
      if (midi % 12 == 0) {
        canvas.drawLine(
          Offset(x, layout.zoneTop),
          Offset(x, layout.keyboardBottom),
          gridPaint,
        );
      }
    }

    for (final mapping in mappingResolution.playableMappings) {
      final region = mapping.region;
      final laneIndex = lanes.indexOf(region.velocityLayer ?? 1);
      final lane = laneIndex < 0 ? 0 : laneIndex;
      final x0 =
          layout.left + ((mapping.lowMidi! - minMidi) / span) * layout.width;
      final x1 =
          layout.left +
          ((mapping.highMidi! + 1 - minMidi) / span) * layout.width;
      final y0 = layout.zoneTop + lane * layout.laneHeight;
      final rect = Rect.fromLTRB(
        x0 + 1,
        y0 + 2,
        x1 - 1,
        y0 + layout.laneHeight - 2,
      );
      final selected = region.path == selectedPath;
      canvas.drawRect(
        rect,
        Paint()
          ..color = selected
              ? colorScheme.tertiary.withValues(alpha: 0.70)
              : colorScheme.primary.withValues(alpha: 0.36),
      );
      if (selected) {
        canvas.drawRect(
          rect.deflate(1),
          Paint()
            ..color = colorScheme.onSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (rect.width > 26) {
        final label = PolyMultisampleParser.midiToNoteName(mapping.naturalMidi);
        final text = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width - 6);
        text.paint(
          canvas,
          Offset(rect.left + 3, rect.center.dy - text.height / 2),
        );
      }
    }

    final keyboardRect = Rect.fromLTRB(
      layout.left,
      layout.keyboardTop,
      layout.right,
      layout.keyboardBottom,
    );
    final keyboardGeometry = PolyKeyboardGeometry(
      keyboardRect: keyboardRect,
      minMidi: minMidi,
      maxMidi: maxMidi,
    );
    final whiteFillPaint = Paint()..color = colorScheme.surface;
    final playedWhiteFillPaint = Paint()
      ..color = colorScheme.tertiary.withValues(alpha: 0.72);
    final keyStrokePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final whiteBoundaryPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 0.8;
    canvas.drawRect(
      keyboardRect,
      Paint()..color = colorScheme.surfaceContainerHighest,
    );
    for (final key in keyboardGeometry.whiteKeys) {
      canvas.drawRect(
        key.rect,
        key.midi == playedMidiNote ? playedWhiteFillPaint : whiteFillPaint,
      );
    }
    canvas.drawRect(keyboardRect, keyStrokePaint);
    for (final boundary in keyboardGeometry.whiteBoundaries) {
      canvas.drawLine(boundary.start, boundary.end, whiteBoundaryPaint);
    }
    for (final key in keyboardGeometry.blackKeys) {
      final radius = Radius.circular(math.min(2, key.rect.width * 0.15));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          key.rect,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        Paint()
          ..color = key.midi == playedMidiNote
              ? colorScheme.tertiary
              : colorScheme.onSurface,
      );
    }
    for (final key in keyboardGeometry.whiteKeys) {
      if (key.pitchClass == 0) {
        final octave = TextPainter(
          text: TextSpan(
            text: PolyMultisampleParser.midiToNoteName(key.midi),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        octave.paint(
          canvas,
          Offset(key.rect.left + 3, layout.keyboardBottom - 15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PolyKeyMapPainter oldDelegate) {
    return oldDelegate.regions != regions ||
        oldDelegate.mappingResolution != mappingResolution ||
        oldDelegate.selectedPath != selectedPath ||
        oldDelegate.playedMidiNote != playedMidiNote ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi ||
        oldDelegate.colorScheme != colorScheme;
  }
}
