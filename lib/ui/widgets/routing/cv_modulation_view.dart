import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';

import 'accessibility_colors.dart';
import 'connection_painter.dart' show ConnectionPainter;

Color cvModulationColor(BuildContext context) {
  final theme = Theme.of(context);
  return AccessibilityColors.ensureContrast(
    theme.appColors.cvModulation,
    theme.colorScheme.surface,
  );
}

void inspectCvModulations(BuildContext context, List<CvModulation> mappings) {
  final cubit = context.read<RoutingEditorCubit?>();
  Widget details(List<CvModulation> current) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mapping in mappings)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              current
                      .where((m) => m.id == mapping.id)
                      .firstOrNull
                      ?.description ??
                  '${mapping.parameterName}: mapping no longer available',
            ),
          ),
      ],
    ),
  );
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('CV modulation'),
      content: SizedBox(
        width: 440,
        height: 320,
        child: cubit == null
            ? details(mappings)
            : BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
                bloc: cubit,
                builder: (context, state) => details(
                  state is RoutingEditorStateLoaded
                      ? [for (final a in state.algorithms) ...a.cvModulations]
                      : [],
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

/// An inspect-only affordance. It never enters the ordinary cable edit path.
class CvModulationButton extends StatelessWidget {
  final List<CvModulation> mappings;
  final bool compact;
  final VoidCallback? onInspect;
  const CvModulationButton({
    super.key,
    required this.mappings,
    this.compact = false,
    this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    if (mappings.isEmpty) return const SizedBox.shrink();
    final label = mappings.length == 1
        ? mappings.single.label
        : '${mappings.first.label} +${mappings.length - 1}';
    final description = mappings.map((m) => m.description).join('\n\n');
    void inspect() {
      onInspect?.call();
      inspectCvModulations(context, mappings);
    }

    return Semantics(
      label: 'Inspect CV modulation: $description',
      excludeSemantics: true,
      button: true,
      onTap: inspect,
      child: Tooltip(
        message: description,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: cvModulationColor(context),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(28, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: inspect,
          child: compact
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'CV${mappings.length > 1 ? mappings.length : ''}',
                  ),
                )
              : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class CvModulationCurve extends CustomPainter {
  final List<(Offset, Offset)> endpoints;
  final Color color;
  CvModulationCurve({required this.endpoints, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (start, end) in endpoints) {
      canvas.drawPath(ConnectionPainter.createBezierPath(start, end), paint);
      // A diamond distinguishes modulation from ordinary signal ports.
      canvas.drawPath(
        Path()
          ..moveTo(end.dx - 4, end.dy)
          ..lineTo(end.dx, end.dy - 4)
          ..lineTo(end.dx + 4, end.dy)
          ..lineTo(end.dx, end.dy + 4)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CvModulationCurve oldDelegate) =>
      oldDelegate.color != color || oldDelegate.endpoints != endpoints;
}
