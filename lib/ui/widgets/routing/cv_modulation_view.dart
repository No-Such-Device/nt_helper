import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';

import 'accessibility_colors.dart';
import 'port_widget.dart';
import '../mapping_editor_bottom_sheet.dart';
import 'connection_painter.dart' show ConnectionPainter;

Color cvModulationColor(BuildContext context) {
  final theme = Theme.of(context);
  return AccessibilityColors.ensureContrast(
    theme.appColors.cvModulation,
    theme.colorScheme.surface,
  );
}

String cvInspectionSummary(CvModulation mapping, {String? destinationName}) {
  final source = mapping.contributors.length != 1
      ? '${mapping.busLabel} · ${mapping.snapshot}'
      : mapping.contributors
            .map(
              (c) =>
                  '${c.slotIndex == null ? '' : 'Slot ${c.slotIndex! + 1}: '}${c.algorithmName} - ${c.portName}',
            )
            .join('; ');
  return '$source → Slot ${mapping.destinationSlot + 1}: ${destinationName == null ? '' : '$destinationName - '}${mapping.parameterName}';
}

String? _destinationName(
  CvModulation mapping,
  List<RoutingAlgorithm> algorithms,
) => algorithms
    .where((a) => a.id == mapping.destinationAlgorithmId)
    .firstOrNull
    ?.algorithm
    .name;

void inspectCvModulations(BuildContext context, List<CvModulation> mappings) {
  final cubit = context.read<RoutingEditorCubit?>();
  Widget details(
    List<CvModulation> current,
    List<RoutingAlgorithm> algorithms,
  ) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mapping in mappings)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              current.where((m) => m.id == mapping.id).firstOrNull == null
                  ? '${mapping.parameterName}: mapping no longer available'
                  : cvInspectionSummary(
                      current.firstWhere((m) => m.id == mapping.id),
                      destinationName: _destinationName(mapping, algorithms),
                    ),
            ),
          ),
      ],
    ),
  );
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      semanticLabel: 'CV modulation',
      content: SizedBox(
        width: 440,
        height: (mappings.length * 64.0).clamp(96, 256),
        child: cubit == null
            ? details(mappings, const [])
            : BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
                bloc: cubit,
                builder: (context, state) => details(
                  state is RoutingEditorStateLoaded
                      ? [for (final a in state.algorithms) ...a.cvModulations]
                      : [],
                  state is RoutingEditorStateLoaded
                      ? state.algorithms
                      : const [],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> editCvModulations(
  BuildContext context,
  List<CvModulation> mappings,
) async {
  final targets = cvInputGroups(mappings).map((g) => g.first).toList();
  if (targets.isEmpty) return;
  CvModulation? selected = targets.first;
  if (targets.length > 1) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    selected = await showMenu<CvModulation>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final target in targets)
          PopupMenuItem(
            value: target,
            child: Text(cvInputLabel(mappings, target)),
          ),
      ],
    );
  }
  if (selected == null || !context.mounted) return;
  final state = context.read<RoutingEditorCubit>().state;
  if (state is! RoutingEditorStateLoaded) return;
  final algorithm = state.algorithms
      .where((a) => a.id == selected!.destinationAlgorithmId)
      .firstOrNull;
  if (algorithm == null ||
      !algorithm.cvModulations.any(
        (m) => m.parameterNumber == selected!.parameterNumber,
      )) {
    return;
  }
  await showParameterMappingEditor(
    context,
    algorithmIndex: algorithm.index,
    parameterNumber: selected.parameterNumber,
  );
}

/// An inspect-only affordance. It never enters the ordinary cable edit path.
class CvModulationButton extends StatelessWidget {
  final List<CvModulation> mappings;
  final bool compact;
  final VoidCallback? onInspect;
  final VoidCallback? onEdit;
  final Key? endpointKey;
  final String? displayLabel;
  final bool standardInput;
  final Widget? visual;
  final void Function(String id, Offset globalCenter)? onAnchor;
  const CvModulationButton({
    super.key,
    required this.mappings,
    this.compact = false,
    this.onInspect,
    this.onEdit,
    this.endpointKey,
    this.displayLabel,
    this.standardInput = false,
    this.visual,
    this.onAnchor,
  });

  @override
  Widget build(BuildContext context) {
    if (mappings.isEmpty) return const SizedBox.shrink();
    final label =
        displayLabel ??
        (mappings.length == 1
            ? mappings.single.label
            : '${mappings.first.label} +${mappings.length - 1}');
    final state = context.read<RoutingEditorCubit?>()?.state;
    final algorithms = state is RoutingEditorStateLoaded
        ? state.algorithms
        : <RoutingAlgorithm>[];
    final description = mappings
        .map(
          (m) => cvInspectionSummary(
            m,
            destinationName: _destinationName(m, algorithms),
          ),
        )
        .join('\n');
    void inspect() {
      onInspect?.call();
      if (onEdit != null) {
        onEdit!();
      } else {
        inspectCvModulations(context, mappings);
      }
    }

    final actionLabel = onEdit == null
        ? 'Inspect CV modulation'
        : mappings.map((m) => m.parameterNumber).toSet().length == 1
        ? 'Edit ${mappings.first.parameterName} mapping'
        : 'Edit parameter mappings';
    return Semantics(
      label: '$actionLabel: $description',
      excludeSemantics: true,
      button: true,
      onTap: inspect,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) =>
            event.logicalKey == LogicalKeyboardKey.delete ||
                event.logicalKey == LogicalKeyboardKey.backspace
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: GestureDetector(
          onPanStart: (_) {},
          onLongPress: () {},
          child: Tooltip(
            message: description,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): inspect,
                const SingleActivator(LogicalKeyboardKey.space): inspect,
              },
              child: standardInput
                  ? PortWidget(
                      label: label,
                      isInput: true,
                      portId: mappings.first.id,
                      anchorKey: endpointKey is GlobalKey
                          ? endpointKey! as GlobalKey
                          : null,
                      interactionKind: PortInteractionKind.cvModulation,
                      isConnected: true,
                      onTap: inspect,
                      onPortPositionResolved: (_, center, _) {
                        for (final mapping in mappings) {
                          onAnchor?.call(mapping.id, center);
                        }
                      },
                    )
                  : TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: cvModulationColor(context),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(28, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: inspect,
                      child:
                          visual ??
                          (compact
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'CV${mappings.length > 1 ? mappings.length : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                )
                              : Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class CvModulationCurve extends CustomPainter {
  final List<(Offset, Offset)> endpoints;
  final Color color;
  final Set<Offset> sourceHalos;
  final double sourceHaloRadius;
  final bool graphInput;
  CvModulationCurve({
    required this.endpoints,
    required this.color,
    this.sourceHalos = const {},
    this.sourceHaloRadius = 8,
    this.graphInput = false,
  });

  static Path pathFor(Offset source, Offset target, {bool graphInput = false}) {
    if (graphInput) {
      final bend = ((target.dx - source.dx).abs() / 2).clamp(30.0, 150.0);
      return Path()
        ..moveTo(source.dx, source.dy)
        ..cubicTo(
          source.dx + bend,
          source.dy,
          target.dx - bend,
          target.dy,
          target.dx,
          target.dy,
        );
    }
    return (source.dx - target.dx).abs() < 0.5
        ? (Path()
            ..moveTo(source.dx, source.dy)
            ..lineTo(target.dx, target.dy))
        : ConnectionPainter.createBezierPath(source, target);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final center in sourceHalos) {
      canvas.drawCircle(center, sourceHaloRadius, paint);
    }
    for (final (start, end) in endpoints) {
      final path = pathFor(start, end, graphInput: graphInput);
      paint.strokeCap = StrokeCap.round;
      for (final metric in path.computeMetrics()) {
        for (var distance = 0.0; distance < metric.length; distance += 7) {
          canvas.drawPath(
            metric.extractPath(
              distance,
              (distance + 2).clamp(0, metric.length),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(CvModulationCurve oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.endpoints != endpoints ||
      oldDelegate.sourceHalos != sourceHalos ||
      oldDelegate.sourceHaloRadius != sourceHaloRadius ||
      oldDelegate.graphInput != graphInput;
}

List<List<CvModulation>> cvInputGroups(List<CvModulation> mappings) {
  final byParameter = <int, List<CvModulation>>{};
  for (final mapping in mappings) {
    (byParameter[mapping.parameterNumber] ??= []).add(mapping);
  }
  return [for (final p in byParameter.keys.toList()..sort()) byParameter[p]!];
}

String cvInputLabel(List<CvModulation> mappings, CvModulation target) =>
    '${target.parameterName}${mappings.any((m) => m.parameterNumber != target.parameterNumber && m.parameterName == target.parameterName) ? ' (p${target.parameterNumber})' : ''}';

class CvVirtualInputs extends StatefulWidget {
  final List<CvModulation> mappings;
  final VoidCallback onInspect;
  final void Function(String id, Offset globalCenter) onAnchor;
  const CvVirtualInputs({
    super.key,
    required this.mappings,
    required this.onInspect,
    required this.onAnchor,
  });
  @override
  State<CvVirtualInputs> createState() => _CvVirtualInputsState();
}

class _CvVirtualInputsState extends State<CvVirtualInputs> {
  final keys = <int, GlobalKey>{};
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final group in cvInputGroups(widget.mappings))
        CvModulationButton(
          key: ValueKey('cv-virtual-input-${group.first.parameterNumber}'),
          mappings: group,
          displayLabel: cvInputLabel(widget.mappings, group.first),
          standardInput: true,
          endpointKey: keys.putIfAbsent(
            group.first.parameterNumber,
            () => GlobalKey(),
          ),
          onAnchor: widget.onAnchor,
          onInspect: widget.onInspect,
        ),
    ],
  );
}
