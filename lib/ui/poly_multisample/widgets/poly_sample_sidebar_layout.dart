import 'dart:ui' show FontFeature;

import 'package:material_ui/material_ui.dart' hide FontFeature;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

class PolySampleSidebarLayout {
  const PolySampleSidebarLayout._();

  static const double panelWidth = 320.0;
  static const double outerPadding = 12.0;
  static const double contentWidth = 296.0;
  static const double rowHeight = 40.0;
  static const double iconButtonExtent = 40.0;
  static const double mappingLabelWidth = 92.0;
  static const double mappingValueWidth = 64.0;
  static const double frameLabelWidth = 72.0;
  static const double frameValueWidth = 60.0;
  static const double sliderLabelWidth = 92.0;
  static const double dbValueWidth = 64.0;
  static const double msValueWidth = 64.0;
  static const double unitValueWidth = 56.0;
  static const double fadeCurveDropdownWidth = 140.0;
  static const double rowGap = 4.0;
}

class PolySampleSidebarValueText extends StatelessWidget {
  const PolySampleSidebarValueText({
    super.key,
    required this.value,
    required this.width,
    this.semanticLabel,
    this.textAlign = TextAlign.right,
    this.alignment = Alignment.centerRight,
  });

  final String value;
  final double width;
  final String? semanticLabel;
  final TextAlign textAlign;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final effectiveStyle = style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final textWidget = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      textAlign: textAlign,
      style: effectiveStyle,
    );
    final alignedText = SizedBox(
      width: width,
      child: Align(alignment: alignment, child: textWidget),
    );
    if (semanticLabel == null) {
      return alignedText;
    }
    return Semantics(
      label: semanticLabel,
      value: value,
      child: ExcludeSemantics(child: alignedText),
    );
  }
}

class PolySampleSidebarIconButton extends StatelessWidget {
  const PolySampleSidebarIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: PolySampleSidebarLayout.iconButtonExtent,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        onTap: onPressed,
        excludeSemantics: true,
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          child: IconButton(
            tooltip: tooltip,
            constraints: BoxConstraints.tight(
              const Size.square(PolySampleSidebarLayout.iconButtonExtent),
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }
}

class PolySampleSidebarSliderValue extends StatelessWidget {
  const PolySampleSidebarSliderValue({
    super.key,
    required this.value,
    required this.width,
    required this.semanticLabel,
  });

  final String value;
  final double width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PolySampleSidebarValueText(
      value: value,
      width: width,
      semanticLabel: semanticLabel,
    );
  }
}
