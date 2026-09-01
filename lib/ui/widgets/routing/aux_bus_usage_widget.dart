import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/routing/bus_label_formatter.dart';

class AuxBusUsageWidget extends StatelessWidget {
  final Map<int, AuxBusUsageInfo> auxBusUsage;
  final DeviceIoProfile deviceIoProfile;
  final int? focusedBusNumber;
  final ValueChanged<int> onBusTapped;
  final Future<void> Function(int sourceBus, int destinationBus)? onBusMoved;

  const AuxBusUsageWidget({
    super.key,
    required this.auxBusUsage,
    required this.deviceIoProfile,
    required this.focusedBusNumber,
    required this.onBusTapped,
    this.onBusMoved,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final busList = deviceIoProfile.auxBuses;

    // Layout: single row for 8, 4 rows of 11 for extended
    final int columns = busList.isEmpty
        ? 1
        : busList.length > 11
        ? 11
        : busList.length;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int row = 0; row * columns < busList.length; row++)
            Padding(
              padding: EdgeInsets.only(top: row > 0 ? 2.0 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    int col = 0;
                    col < columns && row * columns + col < busList.length;
                    col++
                  )
                    Padding(
                      padding: EdgeInsets.only(left: col > 0 ? 2.0 : 0),
                      child: _BusSquare(
                        key: ValueKey(
                          'bus_${busList[row * columns + col]}_${(auxBusUsage[busList[row * columns + col]]?.sessionCount ?? 0) > 0}',
                        ),
                        busNumber: busList[row * columns + col],
                        deviceIoProfile: deviceIoProfile,
                        info: auxBusUsage[busList[row * columns + col]],
                        isFocused:
                            focusedBusNumber == busList[row * columns + col],
                        colorScheme: colorScheme,
                        onTap: onBusTapped,
                        onBusMoved: onBusMoved,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BusSquare extends StatelessWidget {
  final int busNumber;
  final DeviceIoProfile deviceIoProfile;
  final AuxBusUsageInfo? info;
  final bool isFocused;
  final ColorScheme colorScheme;
  final ValueChanged<int> onTap;
  final Future<void> Function(int sourceBus, int destinationBus)? onBusMoved;

  const _BusSquare({
    super.key,
    required this.busNumber,
    required this.deviceIoProfile,
    required this.info,
    required this.isFocused,
    required this.colorScheme,
    required this.onTap,
    this.onBusMoved,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = info?.sessionCount ?? 0;
    final isEmpty = sessions == 0;

    final Color fillColor;
    if (isEmpty) {
      fillColor = Colors.transparent;
    } else if (sessions == 1) {
      fillColor = context.appColors.success.color;
    } else if (sessions == 2) {
      fillColor = context.appColors.warning.color;
    } else {
      fillColor = colorScheme.error;
    }

    final borderColor = isFocused
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final borderWidth = isFocused ? 2.0 : 1.0;

    final label = BusLabelFormatter.formatBusValue(
      busNumber,
      deviceIoProfile: deviceIoProfile,
    );
    final tooltip = _buildTooltip(label);

    Widget squareWidget = Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
    );

    Widget child;

    if (!isEmpty && onBusMoved != null) {
      // Occupied squares: draggable via long-press, tappable via GestureDetector inside
      child = Draggable<int>(
        data: busNumber,
        feedback: Opacity(
          opacity: 0.4,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.primary, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.5, child: squareWidget),
        child: GestureDetector(
          onTap: () => onTap(busNumber),
          child: squareWidget,
        ),
      );
    } else if (isEmpty && onBusMoved != null) {
      // Empty squares: drop target only (not draggable)
      child = DragTarget<int>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) {
          onBusMoved?.call(details.data, busNumber);
        },
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: colorScheme.primary, width: 2),
              ),
            );
          }
          return squareWidget;
        },
      );
    } else {
      child = squareWidget;
    }

    // Wrap non-draggable squares with tap handler (draggable squares handle tap internally)
    if (isEmpty || onBusMoved == null) {
      child = GestureDetector(onTap: () => onTap(busNumber), child: child);
    }

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      triggerMode: (!isEmpty && onBusMoved != null)
          ? TooltipTriggerMode.tap
          : TooltipTriggerMode.longPress,
      child: child,
    );
  }

  String _buildTooltip(String label) {
    if (info == null || info!.sessionCount == 0) {
      return '$label: unused';
    }

    final sources = info!.sourceNames;
    final dests = info!.destNames;

    if (sources.isEmpty && dests.isEmpty) {
      return '$label: in use';
    }

    final lines = <String>[label];
    if (sources.isNotEmpty && dests.isNotEmpty) {
      for (final src in sources) {
        for (final dst in dests) {
          lines.add('$src -> $dst');
        }
      }
    } else if (sources.isNotEmpty) {
      for (final src in sources) {
        lines.add('$src (no readers)');
      }
    } else {
      for (final dst in dests) {
        lines.add('(no writers) -> $dst');
      }
    }
    return lines.join('\n');
  }
}
