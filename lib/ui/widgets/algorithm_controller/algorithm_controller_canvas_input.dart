import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/parameter_number_lookup.dart';

typedef AlgorithmControllerCanvasWriteCallback = void Function(
  int parameterNumber,
  int value, {
  required bool changing,
});

/// Identifies a live slot schema so value updates preserve capture while slot
/// or descriptor replacements invalidate it immediately.
final class AlgorithmControllerCanvasSlotIdentity {
  AlgorithmControllerCanvasSlotIdentity({
    required this.slotIndex,
    required this.instanceIdentity,
    required this.guid,
    required List<int> specifications,
    required List<ParameterInfo> parameters,
  }) : specifications = List.unmodifiable(specifications),
       parameters = List.unmodifiable(parameters);

  factory AlgorithmControllerCanvasSlotIdentity.fromSlot(
    int slotIndex,
    Slot slot,
  ) {
    return AlgorithmControllerCanvasSlotIdentity(
      slotIndex: slotIndex,
      instanceIdentity: slot.algorithm.instanceIdentity,
      guid: slot.algorithm.guid,
      specifications: slot.algorithm.specifications,
      parameters: slot.parameters,
    );
  }

  final int slotIndex;
  final Object instanceIdentity;
  final String guid;
  final List<int> specifications;
  final List<ParameterInfo> parameters;

  @override
  bool operator ==(Object other) =>
      other is AlgorithmControllerCanvasSlotIdentity &&
      other.slotIndex == slotIndex &&
      identical(other.instanceIdentity, instanceIdentity) &&
      other.guid == guid &&
      const ListEquality<int>().equals(other.specifications, specifications) &&
      const ListEquality<ParameterInfo>().equals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
    slotIndex,
    instanceIdentity,
    guid,
    Object.hashAll(specifications),
    Object.hashAll(parameters),
  );
}

typedef ResolvedCanvasParameterRange = ({
  int minimum,
  int maximum,
  int value,
  int step,
});

typedef ResolvedCanvasWheelEdit = ({
  int currentValue,
  int nextValue,
  bool changed,
});

bool isCanvasHitAreaValid(AlgorithmControllerCanvasHitArea hitArea) {
  return switch (hitArea) {
    AlgorithmControllerCanvasCircleHitArea(:final x, :final y, :final radius) =>
      x.isFinite && y.isFinite && radius.isFinite && radius > 0,
    AlgorithmControllerCanvasRectHitArea(
      :final x,
      :final y,
      :final width,
      :final height,
    ) =>
      x.isFinite &&
          y.isFinite &&
          width.isFinite &&
          height.isFinite &&
          width > 0 &&
          height > 0,
  };
}

bool isCanvasTargetValid(AlgorithmControllerCanvasTarget target) {
  return target.id.trim().isNotEmpty &&
      target.label.trim().isNotEmpty &&
      isCanvasHitAreaValid(target.hitArea);
}

bool canvasHitAreaContains(
  AlgorithmControllerCanvasHitArea hitArea,
  Offset localPosition,
  Size canvasSize,
) {
  if (!isCanvasHitAreaValid(hitArea) ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return false;
  }
  if (!localPosition.dx.isFinite ||
      !localPosition.dy.isFinite ||
      localPosition.dx < 0 ||
      localPosition.dx > canvasSize.width ||
      localPosition.dy < 0 ||
      localPosition.dy > canvasSize.height) {
    return false;
  }

  return switch (hitArea) {
    AlgorithmControllerCanvasCircleHitArea(:final x, :final y, :final radius) =>
      () {
        final scale = math.min(canvasSize.width, canvasSize.height);
        final center = Offset(x * canvasSize.width, y * canvasSize.height);
        final radiusPx = radius * scale;
        return (localPosition - center).distanceSquared <= radiusPx * radiusPx;
      }(),
    AlgorithmControllerCanvasRectHitArea(
      :final x,
      :final y,
      :final width,
      :final height,
    ) =>
      () {
        final rect = Rect.fromLTWH(
          x * canvasSize.width,
          y * canvasSize.height,
          width * canvasSize.width,
          height * canvasSize.height,
        );
        return localPosition.dx >= rect.left &&
            localPosition.dx <= rect.right &&
            localPosition.dy >= rect.top &&
            localPosition.dy <= rect.bottom;
      }(),
  };
}

Rect canvasHitAreaBounds(
  AlgorithmControllerCanvasHitArea hitArea,
  Size canvasSize,
) {
  if (!isCanvasHitAreaValid(hitArea) ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return Rect.zero;
  }
  final raw = switch (hitArea) {
    AlgorithmControllerCanvasCircleHitArea(:final x, :final y, :final radius) =>
      Rect.fromCircle(
        center: Offset(x * canvasSize.width, y * canvasSize.height),
        radius: radius * math.min(canvasSize.width, canvasSize.height),
      ),
    AlgorithmControllerCanvasRectHitArea(
      :final x,
      :final y,
      :final width,
      :final height,
    ) =>
      Rect.fromLTWH(
        x * canvasSize.width,
        y * canvasSize.height,
        width * canvasSize.width,
        height * canvasSize.height,
      ),
  };
  final bounds = Offset.zero & canvasSize;
  final intersected = raw.intersect(bounds);
  return intersected.isEmpty ? Rect.zero : intersected;
}

List<AlgorithmControllerCanvasTarget> orderCanvasTargets(
  List<AlgorithmControllerCanvasTarget> targets,
) {
  final indexed = [
    for (var index = 0; index < targets.length; index++)
      (target: targets[index], index: index),
  ];
  indexed.sort((a, b) {
    final orderA = a.target.order;
    final orderB = b.target.order;
    if (orderA != null && orderB != null && orderA != orderB) {
      return orderA.compareTo(orderB);
    }
    if (orderA != null && orderB == null) return -1;
    if (orderA == null && orderB != null) return 1;
    return a.index.compareTo(b.index);
  });
  return [for (final entry in indexed) entry.target];
}

List<AlgorithmControllerCanvasTarget> hitTestCanvasTargets(
  List<AlgorithmControllerCanvasTarget> targets,
  Offset localPosition,
  Size canvasSize,
) {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) {
    return const [];
  }
  final ordered = orderCanvasTargets(targets);
  return [
    for (final target in ordered)
      if (target.enabled &&
          isCanvasTargetValid(target) &&
          canvasHitAreaContains(target.hitArea, localPosition, canvasSize))
        target,
  ];
}

ResolvedCanvasParameterRange? resolveWritableParameterRange({
  required Slot slot,
  required int parameterNumber,
  required int? minimumOverride,
  required int? maximumOverride,
  required int step,
  required bool bindingEnabled,
}) {
  if (!bindingEnabled || step < 1) return null;
  final info = slot.parameters.byParameterNumber(parameterNumber);
  if (info == null || info.ioFlags != 0) return null;
  final value = slot.values.byParameterNumber(parameterNumber);
  if (value?.isDisabled ?? false) return null;

  final minimum = (minimumOverride ?? info.min).clamp(info.min, info.max);
  final maximum = (maximumOverride ?? info.max).clamp(info.min, info.max);
  if (minimum >= maximum) return null;

  final currentValue = (value?.value ?? info.defaultValue)
      .clamp(minimum, maximum)
      .toInt();
  return (minimum: minimum, maximum: maximum, value: currentValue, step: step);
}

int quantizeAndClampCanvasValue(
  double rawValue, {
  required int minimum,
  required int maximum,
  required int step,
}) {
  if (step <= 1) {
    return rawValue.round().clamp(minimum, maximum).toInt();
  }
  final stepsFromMin = ((rawValue - minimum) / step).round();
  return (minimum + stepsFromMin * step).clamp(minimum, maximum).toInt();
}

int? resolveCanvasAxisValue({
  required Slot slot,
  required AlgorithmControllerCanvasAxisBinding axis,
  required double normalizedCoordinate,
}) {
  if (!axis.from.isFinite ||
      !axis.to.isFinite ||
      axis.from >= axis.to ||
      !normalizedCoordinate.isFinite) {
    return null;
  }
  final range = resolveWritableParameterRange(
    slot: slot,
    parameterNumber: axis.parameterNumber,
    minimumOverride: axis.minimum,
    maximumOverride: axis.maximum,
    step: axis.step,
    bindingEnabled: axis.enabled,
  );
  if (range == null) return null;

  final rawFraction =
      ((normalizedCoordinate - axis.from) / (axis.to - axis.from)).clamp(
        0.0,
        1.0,
      );
  final fraction = axis.invert ? 1.0 - rawFraction : rawFraction;
  final rawValue = range.minimum + fraction * (range.maximum - range.minimum);
  return quantizeAndClampCanvasValue(
    rawValue,
    minimum: range.minimum,
    maximum: range.maximum,
    step: range.step,
  );
}

ResolvedCanvasWheelEdit? resolveCanvasWheelValue({
  required Slot slot,
  required AlgorithmControllerCanvasWheelBinding wheel,
  required Offset scrollDelta,
}) {
  if (!scrollDelta.dy.isFinite || scrollDelta.dy == 0) return null;
  final range = resolveWritableParameterRange(
    slot: slot,
    parameterNumber: wheel.parameterNumber,
    minimumOverride: wheel.minimum,
    maximumOverride: wheel.maximum,
    step: wheel.step,
    bindingEnabled: wheel.enabled,
  );
  if (range == null) return null;

  final rawDirection = scrollDelta.dy < 0 ? 1 : -1;
  final direction = wheel.invert ? -rawDirection : rawDirection;
  final rawNext = range.value + direction * range.step;
  final nextValue = quantizeAndClampCanvasValue(
    rawNext.toDouble(),
    minimum: range.minimum,
    maximum: range.maximum,
    step: range.step,
  );
  return (
    currentValue: range.value,
    nextValue: nextValue,
    changed: nextValue != range.value,
  );
}

final class InteractiveAlgorithmControllerCanvas extends StatefulWidget {
  const InteractiveAlgorithmControllerCanvas({
    super.key,
    required this.node,
    required this.slot,
    required this.slotIndex,
    required this.documentGeneration,
    required this.painter,
    required this.onWriteParameter,
    this.onInteraction,
  });

  final AlgorithmControllerCanvas node;
  final Slot slot;
  final int slotIndex;
  final int documentGeneration;
  final CustomPainter painter;
  final AlgorithmControllerCanvasWriteCallback onWriteParameter;
  final ValueChanged<AlgorithmControllerCanvasInteractionEvent>? onInteraction;

  @override
  State<InteractiveAlgorithmControllerCanvas> createState() =>
      _InteractiveAlgorithmControllerCanvasState();
}

final class _ActiveCanvasInteraction {
  _ActiveCanvasInteraction({
    required this.pointer,
    required this.generation,
    required this.downPosition,
    required this.downHitTargets,
    required this.capturedTarget,
    required this.capturedSlotIdentity,
    required this.wasSynchronized,
    required this.distingManager,
    required this.initialX,
    required this.initialY,
  }) : lastX = initialX,
       lastY = initialY;

  final int pointer;
  final int generation;
  final Offset downPosition;
  final List<AlgorithmControllerCanvasTarget> downHitTargets;
  final AlgorithmControllerCanvasTarget capturedTarget;
  final AlgorithmControllerCanvasSlotIdentity capturedSlotIdentity;
  final bool wasSynchronized;
  final Object? distingManager;
  final int? initialX;
  final int? initialY;

  bool dragging = false;
  int? lastX;
  int? lastY;
  bool dirtyX = false;
  bool dirtyY = false;
}

final class _InteractiveAlgorithmControllerCanvasState
    extends State<InteractiveAlgorithmControllerCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  final Map<String, FocusNode> _focusNodes = {};
  late final FocusNode _canvasFocusNode = FocusNode(
    debugLabel: 'algorithm-controller-canvas:root',
  );

  DistingCubit? _cubit;
  StreamSubscription<DistingState>? _cubitSubscription;
  bool _everSynchronized = false;
  Object? _lastSynchronizedDisting;
  bool _connectionInvalidated = false;

  int _sessionGeneration = 0;
  String? _selectedTargetId;
  String? _activeDragTargetId;
  _ActiveCanvasInteraction? _activeInteraction;
  _CanvasTargetGestureRecognizer? _recognizer;
  bool _disposed = false;

  late AlgorithmControllerCanvasSlotIdentity _slotIdentity =
      AlgorithmControllerCanvasSlotIdentity.fromSlot(
        widget.slotIndex,
        widget.slot,
      );

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<DistingCubit>();
    if (!identical(cubit, _cubit)) {
      if (_activeInteraction != null) {
        _cancelActiveInteraction(
          AlgorithmControllerCanvasCancelReason.reconnect,
        );
      }
      unawaited(_cubitSubscription?.cancel());
      _cubit = cubit;
      _everSynchronized = false;
      _lastSynchronizedDisting = null;
      _connectionInvalidated = false;
      _observeCubitState(cubit.state, isStreamEvent: false);
      _cubitSubscription = cubit.stream.listen(
        (state) => _observeCubitState(state, isStreamEvent: true),
        onDone: () {
          _connectionInvalidated = true;
          _sessionGeneration++;
          _cancelActiveInteraction(
            AlgorithmControllerCanvasCancelReason.reconnect,
          );
        },
      );
    } else {
      _observeCubitState(cubit.state, isStreamEvent: false);
    }
  }

  @override
  void didUpdateWidget(
    covariant InteractiveAlgorithmControllerCanvas oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    final nextSlotIdentity = AlgorithmControllerCanvasSlotIdentity.fromSlot(
      widget.slotIndex,
      widget.slot,
    );
    final slotReplaced =
        nextSlotIdentity != _slotIdentity ||
        widget.documentGeneration != oldWidget.documentGeneration;
    _slotIdentity = nextSlotIdentity;

    if (slotReplaced) {
      _sessionGeneration++;
      _cancelActiveInteraction(
        AlgorithmControllerCanvasCancelReason.slotChanged,
      );
      _selectedTargetId = null;
    } else if (_activeInteraction case final active?) {
      if (!_isCapturedTargetStillConsistent(active)) {
        _sessionGeneration++;
        _cancelActiveInteraction(
          AlgorithmControllerCanvasCancelReason.bindingChanged,
        );
      }
    }

    _syncFocusNodes();

    if (_selectedTargetId != null) {
      final selected = _findTargetById(_selectedTargetId!);
      if (selected == null || !selected.enabled || !selected.selectable) {
        _selectedTargetId = null;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _cancelActiveInteraction(
      AlgorithmControllerCanvasCancelReason.disposed,
      notifyRebuild: false,
    );
    unawaited(_cubitSubscription?.cancel());
    _cubitSubscription = null;
    _canvasFocusNode.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    super.dispose();
  }

  void _observeCubitState(DistingState state, {required bool isStreamEvent}) {
    if (_disposed) return;

    switch (state) {
      case DistingStateSynchronized(
        :final disting,
        :final loading,
        :final slots,
      ):
        final reconnectDetected =
            loading ||
            (_everSynchronized &&
                !identical(disting, _lastSynchronizedDisting));
        final slotMismatch =
            widget.slotIndex < 0 ||
            widget.slotIndex >= slots.length ||
            AlgorithmControllerCanvasSlotIdentity.fromSlot(
                  widget.slotIndex,
                  slots[widget.slotIndex],
                ) !=
                _slotIdentity;

        if (!_everSynchronized && !loading) {
          _everSynchronized = true;
          _lastSynchronizedDisting = disting;
          _connectionInvalidated = false;
          if (isStreamEvent && _activeInteraction != null) {
            _sessionGeneration++;
            _cancelActiveInteraction(
              AlgorithmControllerCanvasCancelReason.reconnect,
            );
          }
          return;
        }

        if (reconnectDetected) {
          _connectionInvalidated = loading;
          if (!loading) {
            _lastSynchronizedDisting = disting;
          }
          _sessionGeneration++;
          _cancelActiveInteraction(
            AlgorithmControllerCanvasCancelReason.reconnect,
          );
          return;
        }

        _connectionInvalidated = false;
        if (slotMismatch && _activeInteraction != null) {
          _sessionGeneration++;
          _cancelActiveInteraction(
            AlgorithmControllerCanvasCancelReason.slotChanged,
          );
        }
      case DistingStateInitial():
        if (_everSynchronized || isStreamEvent) {
          _connectionInvalidated = true;
          _sessionGeneration++;
          _cancelActiveInteraction(
            AlgorithmControllerCanvasCancelReason.reconnect,
          );
        }
      case DistingStateSelectDevice():
      case DistingStateConnected():
        _connectionInvalidated = true;
        _sessionGeneration++;
        _cancelActiveInteraction(
          AlgorithmControllerCanvasCancelReason.reconnect,
        );
    }
  }

  bool _isSessionLive() {
    if (_disposed || !mounted) return false;
    final cubit = _cubit;
    if (cubit == null || cubit.isClosed) return false;

    final state = cubit.state;
    switch (state) {
      case DistingStateSynchronized(
        :final disting,
        :final loading,
        :final slots,
      ):
        if (loading) return false;
        if (_everSynchronized &&
            !identical(disting, _lastSynchronizedDisting)) {
          return false;
        }
        if (widget.slotIndex < 0 || widget.slotIndex >= slots.length) {
          return false;
        }
        final liveSlotIdentity = AlgorithmControllerCanvasSlotIdentity.fromSlot(
          widget.slotIndex,
          slots[widget.slotIndex],
        );
        if (liveSlotIdentity != _slotIdentity) return false;
        return true;
      case DistingStateInitial():
        return !_everSynchronized && !_connectionInvalidated;
      case DistingStateSelectDevice():
      case DistingStateConnected():
        return false;
    }
  }

  AlgorithmControllerCanvasCancelReason? _invalidationReasonFor(
    _ActiveCanvasInteraction active,
  ) {
    if (_disposed || !mounted) {
      return AlgorithmControllerCanvasCancelReason.disposed;
    }
    final cubit = _cubit;
    if (cubit == null || cubit.isClosed) {
      return AlgorithmControllerCanvasCancelReason.reconnect;
    }
    final state = cubit.state;
    if (active.wasSynchronized) {
      if (state is! DistingStateSynchronized ||
          state.loading ||
          !identical(state.disting, active.distingManager)) {
        return AlgorithmControllerCanvasCancelReason.reconnect;
      }
      if (widget.slotIndex < 0 ||
          widget.slotIndex >= state.slots.length ||
          AlgorithmControllerCanvasSlotIdentity.fromSlot(
                widget.slotIndex,
                state.slots[widget.slotIndex],
              ) !=
              active.capturedSlotIdentity) {
        return AlgorithmControllerCanvasCancelReason.slotChanged;
      }
    } else if (state is! DistingStateInitial || _connectionInvalidated) {
      return AlgorithmControllerCanvasCancelReason.reconnect;
    }

    if (active.capturedSlotIdentity != _slotIdentity) {
      return AlgorithmControllerCanvasCancelReason.slotChanged;
    }
    if (active.generation != _sessionGeneration ||
        !_isCapturedTargetStillConsistent(active)) {
      return AlgorithmControllerCanvasCancelReason.bindingChanged;
    }
    return null;
  }

  bool _isCapturedTargetStillConsistent(_ActiveCanvasInteraction active) {
    final current = _findTargetById(active.capturedTarget.id);
    if (current == null || !current.enabled || !isCanvasTargetValid(current)) {
      return false;
    }
    if (current.xAxis != active.capturedTarget.xAxis ||
        current.yAxis != active.capturedTarget.yAxis) {
      return false;
    }
    if (active.initialX != null && current.xAxis != null) {
      final range = resolveWritableParameterRange(
        slot: widget.slot,
        parameterNumber: current.xAxis!.parameterNumber,
        minimumOverride: current.xAxis!.minimum,
        maximumOverride: current.xAxis!.maximum,
        step: current.xAxis!.step,
        bindingEnabled: current.xAxis!.enabled,
      );
      if (range == null) return false;
    }
    if (active.initialY != null && current.yAxis != null) {
      final range = resolveWritableParameterRange(
        slot: widget.slot,
        parameterNumber: current.yAxis!.parameterNumber,
        minimumOverride: current.yAxis!.minimum,
        maximumOverride: current.yAxis!.maximum,
        step: current.yAxis!.step,
        bindingEnabled: current.yAxis!.enabled,
      );
      if (range == null) return false;
    }
    return true;
  }

  AlgorithmControllerCanvasTarget? _findTargetById(String id) {
    for (final target in widget.node.targets) {
      if (target.id == id) return target;
    }
    return null;
  }

  void _syncFocusNodes() {
    final activeIds = {
      for (final target in widget.node.targets)
        if (isCanvasTargetValid(target)) target.id,
    };
    final removedIds = _focusNodes.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in removedIds) {
      _focusNodes.remove(id)?.dispose();
    }
    for (final target in widget.node.targets) {
      if (!isCanvasTargetValid(target)) continue;
      _focusNodes.putIfAbsent(
        target.id,
        () => FocusNode(
          debugLabel: 'algorithm-controller-canvas-target:${target.id}',
        ),
      );
    }
  }

  RenderBox? _canvasRenderBox() {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject;
    }
    return null;
  }

  Offset? _localPositionFromGlobal(Offset globalPosition) {
    final box = _canvasRenderBox();
    if (box == null) return null;
    return box.globalToLocal(globalPosition);
  }

  bool _canAcceptPointerDown(PointerDownEvent event) {
    if (_activeInteraction != null || !_isSessionLive()) return false;
    final box = _canvasRenderBox();
    if (box == null) return false;
    final localPosition = box.globalToLocal(event.position);
    final hits = hitTestCanvasTargets(
      widget.node.targets,
      localPosition,
      box.size,
    );
    return hits.isNotEmpty;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activeInteraction != null || !_isSessionLive()) return;
    final box = _canvasRenderBox();
    if (box == null) return;
    final localPosition = box.globalToLocal(event.position);
    final hits = hitTestCanvasTargets(
      widget.node.targets,
      localPosition,
      box.size,
    );
    if (hits.isEmpty) return;

    final selectedHit = _selectedTargetId == null
        ? null
        : hits.firstWhereOrNull((target) => target.id == _selectedTargetId);
    final capturedTarget = selectedHit ?? hits.first;

    final xRange = capturedTarget.xAxis == null
        ? null
        : resolveWritableParameterRange(
            slot: widget.slot,
            parameterNumber: capturedTarget.xAxis!.parameterNumber,
            minimumOverride: capturedTarget.xAxis!.minimum,
            maximumOverride: capturedTarget.xAxis!.maximum,
            step: capturedTarget.xAxis!.step,
            bindingEnabled: capturedTarget.xAxis!.enabled,
          );
    final yRange = capturedTarget.yAxis == null
        ? null
        : resolveWritableParameterRange(
            slot: widget.slot,
            parameterNumber: capturedTarget.yAxis!.parameterNumber,
            minimumOverride: capturedTarget.yAxis!.minimum,
            maximumOverride: capturedTarget.yAxis!.maximum,
            step: capturedTarget.yAxis!.step,
            bindingEnabled: capturedTarget.yAxis!.enabled,
          );

    final state = _cubit?.state;
    final wasSynchronized = state is DistingStateSynchronized;
    final distingManager = state is DistingStateSynchronized
        ? state.disting
        : null;

    _activeInteraction = _ActiveCanvasInteraction(
      pointer: event.pointer,
      generation: _sessionGeneration,
      downPosition: localPosition,
      downHitTargets: hits,
      capturedTarget: capturedTarget,
      capturedSlotIdentity: _slotIdentity,
      wasSynchronized: wasSynchronized,
      distingManager: distingManager,
      initialX: xRange?.value,
      initialY: yRange?.value,
    );
  }

  /// Returns `true` when drag capture is active, `false` when still below
  /// threshold, and `null` when the interaction was cancelled/rejected.
  bool? _handlePointerMove(PointerMoveEvent event) {
    final active = _activeInteraction;
    if (active == null || active.pointer != event.pointer) return null;
    final invalidReason = _invalidationReasonFor(active);
    if (invalidReason != null) {
      _cancelActiveInteraction(invalidReason);
      return null;
    }

    final box = _canvasRenderBox();
    if (box == null || box.size.width <= 0 || box.size.height <= 0) {
      _cancelActiveInteraction(
        AlgorithmControllerCanvasCancelReason.bindingChanged,
      );
      return null;
    }
    final localPosition = box.globalToLocal(event.position);
    final target = active.capturedTarget;

    if (!active.dragging) {
      final threshold =
          widget.node.dragThreshold.isFinite && widget.node.dragThreshold >= 0
          ? widget.node.dragThreshold
          : 4.0;
      if ((localPosition - active.downPosition).distance < threshold) {
        return false;
      }

      final hasWritableAxis =
          (target.xAxis != null && active.initialX != null) ||
          (target.yAxis != null && active.initialY != null);
      if (!hasWritableAxis) {
        _activeInteraction = null;
        return null;
      }

      active.dragging = true;
      setState(() {
        _activeDragTargetId = target.id;
        if (target.selectable) {
          _selectedTargetId = target.id;
        }
      });
      _focusTarget(target);
      widget.onInteraction?.call(
        AlgorithmControllerCanvasInteractionEvent(
          type: AlgorithmControllerCanvasInteractionEventType.dragStart,
          targetId: target.id,
          pointer: active.pointer,
        ),
      );
    }

    _applyDragPosition(active, localPosition, box.size, changing: true);
    return true;
  }

  void _handlePointerUp(PointerUpEvent event) {
    final active = _activeInteraction;
    if (active == null || active.pointer != event.pointer) return;

    // Clear active state before any callbacks or writes so late or re-entrant
    // events can never observe or repeat a terminal transition.
    _activeInteraction = null;
    final wasDragging = active.dragging;
    if (_activeDragTargetId != null) {
      setState(() => _activeDragTargetId = null);
    }

    final invalidReason = _invalidationReasonFor(active);
    if (invalidReason != null) {
      if (wasDragging) {
        widget.onInteraction?.call(
          AlgorithmControllerCanvasInteractionEvent(
            type: AlgorithmControllerCanvasInteractionEventType.dragCancel,
            targetId: active.capturedTarget.id,
            pointer: active.pointer,
            cancelReason: invalidReason,
          ),
        );
      }
      return;
    }

    if (!wasDragging) {
      _handleClickSelection(active);
      return;
    }

    final box = _canvasRenderBox();
    final target = active.capturedTarget;
    int? finalX = active.lastX;
    int? finalY = active.lastY;

    if (box != null && box.size.width > 0 && box.size.height > 0) {
      final localPosition = box.globalToLocal(event.position);
      if (target.xAxis case final xAxis? when active.initialX != null) {
        final computed = resolveCanvasAxisValue(
          slot: widget.slot,
          axis: xAxis,
          normalizedCoordinate: localPosition.dx / box.size.width,
        );
        if (computed != null) {
          if (computed != active.lastX) {
            active.dirtyX = true;
          }
          finalX = computed;
        }
      }
      if (target.yAxis case final yAxis? when active.initialY != null) {
        final computed = resolveCanvasAxisValue(
          slot: widget.slot,
          axis: yAxis,
          normalizedCoordinate: localPosition.dy / box.size.height,
        );
        if (computed != null) {
          if (computed != active.lastY) {
            active.dirtyY = true;
          }
          finalY = computed;
        }
      }
    }

    if (target.xAxis case final xAxis? when active.dirtyX && finalX != null) {
      widget.onWriteParameter(xAxis.parameterNumber, finalX, changing: false);
    }
    if (target.yAxis case final yAxis? when active.dirtyY && finalY != null) {
      widget.onWriteParameter(yAxis.parameterNumber, finalY, changing: false);
    }

    widget.onInteraction?.call(
      AlgorithmControllerCanvasInteractionEvent(
        type: AlgorithmControllerCanvasInteractionEventType.dragEnd,
        targetId: target.id,
        pointer: active.pointer,
        xValue: active.dirtyX ? finalX : null,
        yValue: active.dirtyY ? finalY : null,
      ),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final active = _activeInteraction;
    if (active == null || active.pointer != event.pointer) return;
    _cancelActiveInteraction(
      AlgorithmControllerCanvasCancelReason.pointerCancel,
    );
  }

  void _handleGestureRejected(int pointer) {
    final active = _activeInteraction;
    if (active == null || active.pointer != pointer) return;
    _cancelActiveInteraction(
      AlgorithmControllerCanvasCancelReason.gestureRejected,
    );
  }

  void _cancelActiveInteraction(
    AlgorithmControllerCanvasCancelReason reason, {
    bool notifyRebuild = true,
  }) {
    final active = _activeInteraction;
    _activeInteraction = null;
    _recognizer?.cancelActivePointer();

    if (active == null) {
      if (_activeDragTargetId != null && notifyRebuild && mounted) {
        setState(() => _activeDragTargetId = null);
      } else {
        _activeDragTargetId = null;
      }
      return;
    }

    final wasDragging = active.dragging;
    if (_activeDragTargetId != null) {
      if (notifyRebuild && mounted) {
        setState(() => _activeDragTargetId = null);
      } else {
        _activeDragTargetId = null;
      }
    }

    if (wasDragging) {
      widget.onInteraction?.call(
        AlgorithmControllerCanvasInteractionEvent(
          type: AlgorithmControllerCanvasInteractionEventType.dragCancel,
          targetId: active.capturedTarget.id,
          pointer: active.pointer,
          cancelReason: reason,
        ),
      );
    }
  }

  void _applyDragPosition(
    _ActiveCanvasInteraction active,
    Offset localPosition,
    Size canvasSize, {
    required bool changing,
  }) {
    final target = active.capturedTarget;
    int? writtenX;
    int? writtenY;

    if (target.xAxis case final xAxis? when active.initialX != null) {
      final nextX = resolveCanvasAxisValue(
        slot: widget.slot,
        axis: xAxis,
        normalizedCoordinate: localPosition.dx / canvasSize.width,
      );
      if (nextX != null && nextX != active.lastX) {
        active.lastX = nextX;
        active.dirtyX = true;
        writtenX = nextX;
        widget.onWriteParameter(
          xAxis.parameterNumber,
          nextX,
          changing: changing,
        );
      }
    }

    if (target.yAxis case final yAxis? when active.initialY != null) {
      final nextY = resolveCanvasAxisValue(
        slot: widget.slot,
        axis: yAxis,
        normalizedCoordinate: localPosition.dy / canvasSize.height,
      );
      if (nextY != null && nextY != active.lastY) {
        active.lastY = nextY;
        active.dirtyY = true;
        writtenY = nextY;
        widget.onWriteParameter(
          yAxis.parameterNumber,
          nextY,
          changing: changing,
        );
      }
    }

    if (writtenX != null || writtenY != null) {
      widget.onInteraction?.call(
        AlgorithmControllerCanvasInteractionEvent(
          type: AlgorithmControllerCanvasInteractionEventType.dragUpdate,
          targetId: target.id,
          pointer: active.pointer,
          xValue: writtenX,
          yValue: writtenY,
        ),
      );
    }
  }

  void _handleClickSelection(_ActiveCanvasInteraction active) {
    final selectableHits = [
      for (final target in active.downHitTargets)
        if (target.enabled && target.selectable) target,
    ];
    if (selectableHits.isEmpty) return;

    final AlgorithmControllerCanvasTarget chosen;
    if (widget.node.cycleOverlappingSelection && selectableHits.length > 1) {
      final currentIndex = selectableHits.indexWhere(
        (target) => target.id == _selectedTargetId,
      );
      chosen = currentIndex == -1
          ? selectableHits.first
          : selectableHits[(currentIndex + 1) % selectableHits.length];
    } else {
      chosen = selectableHits.first;
    }

    if (_selectedTargetId != chosen.id) {
      setState(() => _selectedTargetId = chosen.id);
    }
    _focusTarget(chosen);
    widget.onInteraction?.call(
      AlgorithmControllerCanvasInteractionEvent(
        type: AlgorithmControllerCanvasInteractionEventType.selected,
        targetId: chosen.id,
        pointer: active.pointer,
      ),
    );
  }

  void _focusTarget(AlgorithmControllerCanvasTarget target) {
    if (!target.enabled) return;
    final focusNode = _focusNodes[target.id];
    if (focusNode != null && focusNode.canRequestFocus) {
      focusNode.requestFocus();
    } else if (_canvasFocusNode.canRequestFocus) {
      _canvasFocusNode.requestFocus();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy == 0 || !event.scrollDelta.dy.isFinite) return;
    if (!_isSessionLive()) return;

    final box = _canvasRenderBox();
    if (box == null || box.size.width <= 0 || box.size.height <= 0) return;

    final localPosition = _localPositionFromGlobal(event.position);
    if (localPosition == null) return;

    final hits = hitTestCanvasTargets(
      widget.node.targets,
      localPosition,
      box.size,
    );
    // Only consume wheel when exactly one enabled target is unambiguously hit.
    if (hits.length != 1) return;

    final target = hits.single;
    final wheel = target.wheel;
    if (wheel == null) return;

    final preview = resolveCanvasWheelValue(
      slot: widget.slot,
      wheel: wheel,
      scrollDelta: event.scrollDelta,
    );
    if (preview == null) return;

    final generation = _sessionGeneration;
    final targetId = target.id;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      if (signal is! PointerScrollEvent) return;
      if (!_isSessionLive() || generation != _sessionGeneration) return;
      final liveTarget = _findTargetById(targetId);
      if (liveTarget == null ||
          !liveTarget.enabled ||
          liveTarget.wheel == null) {
        return;
      }
      final resolved = resolveCanvasWheelValue(
        slot: widget.slot,
        wheel: liveTarget.wheel!,
        scrollDelta: signal.scrollDelta,
      );
      if (resolved == null || !resolved.changed) return;

      widget.onWriteParameter(
        liveTarget.wheel!.parameterNumber,
        resolved.nextValue,
        changing: false,
      );
      widget.onInteraction?.call(
        AlgorithmControllerCanvasInteractionEvent(
          type: AlgorithmControllerCanvasInteractionEventType.wheel,
          targetId: targetId,
          wheelValue: resolved.nextValue,
        ),
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _activeInteraction != null) {
      _cancelActiveInteraction(AlgorithmControllerCanvasCancelReason.escapeKey);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final orderedTargets = orderCanvasTargets(widget.node.targets);
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _canvasFocusNode,
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        container: true,
        label: widget.node.semanticsLabel,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _handlePointerSignal,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _CanvasTargetGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _CanvasTargetGestureRecognizer
                  >(() => _CanvasTargetGestureRecognizer(), (instance) {
                    _recognizer = instance;
                    instance
                      ..onCheckPointerDown = _canAcceptPointerDown
                      ..onPointerDown = _handlePointerDown
                      ..onPointerMove = _handlePointerMove
                      ..onPointerUp = _handlePointerUp
                      ..onPointerCancel = _handlePointerCancel
                      ..onGestureRejected = _handleGestureRejected;
                  }),
            },
            child: LayoutBuilder(
              key: _canvasKey,
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      child: CustomPaint(painter: widget.painter),
                    ),
                    if (_selectedTargetId != null ||
                        _activeDragTargetId != null)
                      IgnorePointer(
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            painter: _CanvasInteractionOverlayPainter(
                              targets: widget.node.targets,
                              selectedTargetId: _selectedTargetId,
                              activeDragTargetId: _activeDragTargetId,
                              colorScheme: colorScheme,
                            ),
                          ),
                        ),
                      ),
                    IgnorePointer(
                      child: Stack(
                        children: [
                          for (final target in orderedTargets)
                            if (isCanvasTargetValid(target))
                              _buildTargetSemanticsNode(target, size),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetSemanticsNode(
    AlgorithmControllerCanvasTarget target,
    Size canvasSize,
  ) {
    final rect = canvasHitAreaBounds(target.hitArea, canvasSize);
    final focusNode = _focusNodes[target.id];
    final isSelected = target.selectable && _selectedTargetId == target.id;
    return Positioned.fromRect(
      rect: rect,
      child: Focus(
        focusNode: focusNode,
        canRequestFocus: target.enabled,
        skipTraversal: !target.enabled,
        onKeyEvent: _handleKeyEvent,
        onFocusChange: (hasFocus) {
          if (hasFocus &&
              target.enabled &&
              target.selectable &&
              _selectedTargetId != target.id) {
            setState(() => _selectedTargetId = target.id);
            widget.onInteraction?.call(
              AlgorithmControllerCanvasInteractionEvent(
                type: AlgorithmControllerCanvasInteractionEventType.selected,
                targetId: target.id,
              ),
            );
          }
        },
        child: Semantics(
          key: ValueKey('algorithm-controller-canvas-target:${target.id}'),
          container: true,
          enabled: target.enabled,
          focusable: target.enabled,
          focused: focusNode?.hasFocus ?? false,
          selected: target.selectable ? isSelected : null,
          label: target.label,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

final class _CanvasInteractionOverlayPainter extends CustomPainter {
  const _CanvasInteractionOverlayPainter({
    required this.targets,
    required this.selectedTargetId,
    required this.activeDragTargetId,
    required this.colorScheme,
  });

  final List<AlgorithmControllerCanvasTarget> targets;
  final String? selectedTargetId;
  final String? activeDragTargetId;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final target in targets) {
      if (!target.enabled || !isCanvasTargetValid(target)) continue;
      final isDragging = target.id == activeDragTargetId;
      final isSelected = target.id == selectedTargetId;
      if (!isDragging && !isSelected) continue;

      final paint = Paint()
        ..color = isDragging ? colorScheme.primary : colorScheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 2.5 : 1.5;

      switch (target.hitArea) {
        case AlgorithmControllerCanvasCircleHitArea(
          :final x,
          :final y,
          :final radius,
        ):
          final scale = math.min(size.width, size.height);
          canvas.drawCircle(
            Offset(x * size.width, y * size.height),
            radius * scale + 2,
            paint,
          );
        case AlgorithmControllerCanvasRectHitArea(
          :final x,
          :final y,
          :final width,
          :final height,
        ):
          canvas.drawRect(
            Rect.fromLTWH(
              x * size.width,
              y * size.height,
              width * size.width,
              height * size.height,
            ).inflate(1),
            paint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasInteractionOverlayPainter oldDelegate) {
    return oldDelegate.targets != targets ||
        oldDelegate.selectedTargetId != selectedTargetId ||
        oldDelegate.activeDragTargetId != activeDragTargetId ||
        oldDelegate.colorScheme != colorScheme;
  }
}

final class _CanvasTargetGestureRecognizer
    extends OneSequenceGestureRecognizer {
  bool Function(PointerDownEvent event)? onCheckPointerDown;
  void Function(PointerDownEvent event)? onPointerDown;
  bool? Function(PointerMoveEvent event)? onPointerMove;
  void Function(PointerUpEvent event)? onPointerUp;
  void Function(PointerCancelEvent event)? onPointerCancel;
  void Function(int pointer)? onGestureRejected;

  int? _activePointer;
  bool _accepted = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_activePointer != null) return false;
    final check = onCheckPointerDown;
    if (check == null || !check(event)) return false;
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _activePointer = event.pointer;
    _accepted = false;
    onPointerDown?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (_activePointer != event.pointer) return;

    if (event is PointerMoveEvent) {
      final result = onPointerMove?.call(event);
      if (result == null) {
        final pointer = event.pointer;
        _activePointer = null;
        _accepted = false;
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(pointer);
      } else if (result && !_accepted) {
        _accepted = true;
        resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent) {
      final pointer = event.pointer;
      _activePointer = null;
      final alreadyAccepted = _accepted;
      _accepted = false;
      if (!alreadyAccepted) {
        resolve(GestureDisposition.accepted);
      }
      stopTrackingPointer(pointer);
      onPointerUp?.call(event);
    } else if (event is PointerCancelEvent) {
      final pointer = event.pointer;
      _activePointer = null;
      _accepted = false;
      stopTrackingPointer(pointer);
      onPointerCancel?.call(event);
    }
  }

  void cancelActivePointer() {
    final pointer = _activePointer;
    if (pointer == null) return;
    _activePointer = null;
    _accepted = false;
    resolvePointer(pointer, GestureDisposition.rejected);
    stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    if (_activePointer == pointer) {
      _accepted = true;
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _accepted = false;
    stopTrackingPointer(pointer);
    onGestureRejected?.call(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    cancelActivePointer();
    super.dispose();
  }

  @override
  String get debugDescription => 'algorithmControllerCanvasTarget';
}
