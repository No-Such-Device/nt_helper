import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';

class Ntx8cvRoutingOutputs extends StatelessWidget {
  const Ntx8cvRoutingOutputs({
    super.key,
    required this.config,
    required this.profile,
    this.reserveOnly = false,
  });

  /// Measures the same row height without creating hidden scroll targets.
  final bool reserveOnly;
  final Ntx8cvRouting config;
  final DeviceIoProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Tooltip(
                message: config.description,
                child: Text(
                  config.scopeLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final row = Row(
                  children: [
                    for (final port
                        in config.ports(profile).take(reserveOnly ? 1 : 8))
                      Semantics(
                        label: port.description,
                        child: Focus(
                          child: Tooltip(
                            message: port.description!,
                            child: Container(
                              key: ValueKey(
                                'ntx8cv_summary_${port.hardwareIndex}',
                              ),
                              width: 116,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: ExcludeSemantics(
                                child: Text(
                                  '${port.name} · ${profile.labelForBus(port.busValue!)}${!config.available
                                      ? ' ?'
                                      : !port.isActive
                                      ? ' —'
                                      : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
                return reserveOnly
                    ? row
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: row,
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only physical output aligned beneath its AUX bus label.
class Ntx8cvBusAssignment extends StatelessWidget {
  const Ntx8cvBusAssignment({
    super.key,
    required this.config,
    required this.profile,
    required this.jack,
    this.onFocus,
  });

  final Ntx8cvRouting? config;
  final DeviceIoProfile profile;
  final int jack;
  final VoidCallback? onFocus;

  static double height(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: '8', style: Theme.of(context).textTheme.labelSmall),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = 14 + painter.height + 8;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final port = (config ?? const Ntx8cvRouting.unresolved()).ports(
      profile,
    )[jack - 1];
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height(context),
      child: Visibility(
        visible: config != null,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: ExcludeFocus(
          excluding: config == null,
          child: Semantics(
            label: port.description,
            child: Focus(
              onKeyEvent: (_, event) =>
                  event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.delete ||
                          event.logicalKey == LogicalKeyboardKey.backspace)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
              onFocusChange: (focused) {
                if (focused) onFocus?.call();
              },
              child: GestureDetector(
                onTap: onFocus,
                child: Tooltip(
                  message: port.description!,
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.circle_outlined,
                          size: 14,
                          color: port.isActive
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                        Text(
                          port.name,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
