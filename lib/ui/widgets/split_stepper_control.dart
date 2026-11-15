import 'package:material_ui/material_ui.dart';

class SplitStepperControl extends StatelessWidget {
  const SplitStepperControl({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.onDecrement,
    required this.onIncrement,
  }) : smallStepLabel = null,
       largeStepLabel = null,
       smallStepSemanticsLabel = null,
       largeStepSemanticsLabel = null,
       onSmallDecrement = null,
       onSmallIncrement = null,
       onLargeDecrement = null,
       onLargeIncrement = null;

  const SplitStepperControl.largeAndSmall({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.smallStepLabel,
    required this.largeStepLabel,
    required this.smallStepSemanticsLabel,
    required this.largeStepSemanticsLabel,
    required this.onSmallDecrement,
    required this.onSmallIncrement,
    required this.onLargeDecrement,
    required this.onLargeIncrement,
  }) : onDecrement = null,
       onIncrement = null;

  final String label;
  final String valueLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String? smallStepLabel;
  final String? largeStepLabel;
  final String? smallStepSemanticsLabel;
  final String? largeStepSemanticsLabel;
  final VoidCallback? onSmallDecrement;
  final VoidCallback? onSmallIncrement;
  final VoidCallback? onLargeDecrement;
  final VoidCallback? onLargeIncrement;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = smallStepLabel == null
        ? <_SplitStepperActionSpec>[
            _SplitStepperActionSpec(
              tooltip: 'Decrease $label',
              child: const Icon(Icons.remove, size: 16),
              onPressed: onDecrement,
              width: 32,
            ),
            _SplitStepperActionSpec(
              tooltip: 'Increase $label',
              child: const Icon(Icons.add, size: 16),
              onPressed: onIncrement,
              width: 32,
            ),
          ]
        : <_SplitStepperActionSpec>[
            _SplitStepperActionSpec(
              tooltip: 'Decrease $label by $largeStepSemanticsLabel',
              child: Text(
                '−$largeStepLabel',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: onLargeDecrement,
              width: 54,
            ),
            _SplitStepperActionSpec(
              tooltip: 'Decrease $label by $smallStepSemanticsLabel',
              child: Text(
                '−$smallStepLabel',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: onSmallDecrement,
              width: 54,
            ),
            _SplitStepperActionSpec(
              tooltip: 'Increase $label by $smallStepSemanticsLabel',
              child: Text(
                '+$smallStepLabel',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: onSmallIncrement,
              width: 54,
            ),
            _SplitStepperActionSpec(
              tooltip: 'Increase $label by $largeStepSemanticsLabel',
              child: Text(
                '+$largeStepLabel',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: onLargeIncrement,
              width: 54,
            ),
          ];

    return Semantics(
      container: true,
      label: label,
      value: valueLabel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colorScheme.surfaceContainerHighest,
          shape: StadiumBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              _SplitStepperSegment(action: actions[index]),
              if (index < actions.length - 1)
                SizedBox(
                  height: 32,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitStepperActionSpec {
  const _SplitStepperActionSpec({
    required this.tooltip,
    required this.child,
    required this.onPressed,
    required this.width,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final double width;
}

class _SplitStepperSegment extends StatelessWidget {
  const _SplitStepperSegment({required this.action});

  final _SplitStepperActionSpec action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.tooltip,
      enabled: action.onPressed != null,
      onTap: action.onPressed,
      excludeSemantics: true,
      child: IconButton(
        constraints: BoxConstraints.tightFor(width: action.width, height: 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: action.tooltip,
        onPressed: action.onPressed,
        icon: action.child,
      ),
    );
  }
}
