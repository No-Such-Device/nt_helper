import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/services/settings_service.dart';

/// A compact CPU monitor widget that displays CPU usage information.
/// Shows the two main CPU usage numbers with a tooltip containing slot breakdown.
/// Automatically pauses CPU monitoring when not visible and resumes when visible.
class CpuMonitorWidget extends StatefulWidget {
  const CpuMonitorWidget({super.key, this.paused = false});

  /// Temporarily hides the widget and pauses polling while another workflow
  /// owns the same device communication path.
  final bool paused;

  @override
  State<CpuMonitorWidget> createState() => _CpuMonitorWidgetState();
}

class _CpuMonitorWidgetState extends State<CpuMonitorWidget> {
  late DistingCubit _distingCubit;
  bool _isVisible = false;
  CpuUsage? _lastCpuUsage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _distingCubit = context.read<DistingCubit>();
  }

  void _updateVisibility(bool isVisible) {
    if (_isVisible != isVisible) {
      _isVisible = isVisible;
      if (isVisible) {
        _distingCubit.resumeCpuMonitoring();
      } else {
        _distingCubit.pauseCpuMonitoring();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to CPU monitor setting changes
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().cpuMonitorEnabledNotifier,
      builder: (context, cpuMonitorEnabled, _) {
        // Check if CPU monitor is disabled in settings
        if (!cpuMonitorEnabled || widget.paused) {
          _updateVisibility(false);
          return const SizedBox.shrink();
        }

        return BlocBuilder<DistingCubit, DistingState>(
          buildWhen: (previous, current) {
            final prevShow =
                previous is DistingStateSynchronized &&
                !previous.offline &&
                !previous.demo;
            final currShow =
                current is DistingStateSynchronized &&
                !current.offline &&
                !current.demo;
            return prevShow != currShow;
          },
          builder: (context, state) {
            // Only show CPU monitor when connected to a physical device
            final shouldShow =
                state is DistingStateSynchronized &&
                !state.offline &&
                !state.demo;

            if (!shouldShow) {
              // Pause monitoring when not showing
              _updateVisibility(false);
              return const SizedBox.shrink();
            }

            // Resume monitoring when visible
            _updateVisibility(true);

            return StreamBuilder<CpuUsage?>(
              stream: _distingCubit.cpuUsageStream,
              builder: (context, snapshot) {
                final currentCpuUsage = snapshot.data;
                if (currentCpuUsage != null) {
                  _lastCpuUsage = currentCpuUsage;
                }

                final cpuUsage = currentCpuUsage ?? _lastCpuUsage;
                return _buildCpuDisplay(
                  context: context,
                  cpu1: cpuUsage?.cpu1,
                  cpu2: cpuUsage?.cpu2,
                  slotUsages: cpuUsage?.slotUsages ?? [],
                  isWaitingForSample: cpuUsage == null,
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    // Pause monitoring when widget is disposed
    _updateVisibility(false);
    super.dispose();
  }

  Widget _buildCpuDisplay({
    required BuildContext context,
    required int? cpu1,
    required int? cpu2,
    required List<int> slotUsages,
    required bool isWaitingForSample,
  }) {
    final theme = Theme.of(context);

    // Check if either CPU measurement is above 90%
    final bool isHighUsage =
        (cpu1 != null && cpu1 > 90) || (cpu2 != null && cpu2 > 90);

    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: isHighUsage
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant,
    );

    // Build tooltip content with slot breakdown
    final tooltipContent = _buildTooltipContent(
      context: context,
      cpu1: cpu1,
      cpu2: cpu2,
      slotUsages: slotUsages,
      isWaitingForSample: isWaitingForSample,
    );

    final semanticLabel = isWaitingForSample
        ? 'CPU monitor: waiting for usage sample'
        : 'CPU usage: Audio thread ${cpu1 ?? 0}%, Overall CPU ${cpu2 ?? 0}%${isHighUsage ? ', warning: high usage' : ''}';

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltipContent,
        preferBelow: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.memory,
                size: 14,
                color: isHighUsage
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                isWaitingForSample
                    ? '--% | --%'
                    : '${cpu1 ?? 0}% | ${cpu2 ?? 0}%',
                style: textStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildTooltipContent({
    required BuildContext context,
    required int? cpu1,
    required int? cpu2,
    required List<int> slotUsages,
    required bool isWaitingForSample,
  }) {
    if (isWaitingForSample) {
      return 'Waiting for CPU usage sample...';
    }

    final buffer = StringBuffer();
    buffer.writeln('CPU Usage:');
    buffer.writeln('Audio thread: ${cpu1 ?? 0}%');
    buffer.writeln('Overall CPU: ${cpu2 ?? 0}%');

    if (slotUsages.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Algorithm Slots:');
      for (int i = 0; i < slotUsages.length; i++) {
        buffer.writeln('Slot ${i + 1}: ${slotUsages[i]}%');
      }
    }

    return buffer.toString().trim();
  }
}

/// Read-only CPU values for the System dialog.
///
/// This surface listens to the existing CPU stream, so it shares the cubit's
/// listener-driven polling, retry and backoff behavior. It deliberately does
/// not call the explicit pause/resume methods owned by the persistent bottom
/// bar; opening or closing the dialog therefore cannot pause another visible
/// CPU consumer.
class CpuStatusPanel extends StatefulWidget {
  const CpuStatusPanel({super.key, this.paused = false});

  final bool paused;

  @override
  State<CpuStatusPanel> createState() => _CpuStatusPanelState();
}

class _CpuStatusPanelState extends State<CpuStatusPanel> {
  CpuUsage? _lastCpuUsage;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DistingCubit>();

    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().cpuMonitorEnabledNotifier,
      builder: (context, cpuMonitorEnabled, _) {
        if (!cpuMonitorEnabled) {
          return const _CpuStatusReadings(status: 'Monitoring disabled');
        }
        if (widget.paused) {
          return const _CpuStatusReadings(status: 'Monitoring paused');
        }

        return BlocBuilder<DistingCubit, DistingState>(
          buildWhen: (previous, current) {
            final previousIsLive =
                previous is DistingStateSynchronized &&
                !previous.offline &&
                !previous.demo;
            final currentIsLive =
                current is DistingStateSynchronized &&
                !current.offline &&
                !current.demo;
            return previousIsLive != currentIsLive;
          },
          builder: (context, state) {
            final isLive =
                state is DistingStateSynchronized &&
                !state.offline &&
                !state.demo;
            if (!isLive) {
              return const _CpuStatusReadings(status: 'Unavailable');
            }

            return StreamBuilder<CpuUsage?>(
              stream: cubit.cpuUsageStream,
              builder: (context, snapshot) {
                final currentCpuUsage = snapshot.data;
                if (currentCpuUsage != null) {
                  _lastCpuUsage = currentCpuUsage;
                }
                return _CpuStatusReadings(
                  usage: currentCpuUsage ?? _lastCpuUsage,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CpuStatusReadings extends StatelessWidget {
  const _CpuStatusReadings({this.usage, this.status = 'Waiting for sample'});

  final CpuUsage? usage;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final statusStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: usage == null
          ? 'CPU status: $status'
          : 'CPU status: Audio thread ${usage!.cpu1}%, Overall CPU ${usage!.cpu2}%',
      child: Column(
        key: const ValueKey('system-cpu-status'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('CPU', style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
          _CpuStatusRow(
            label: 'Audio thread',
            value: usage == null ? status : '${usage!.cpu1}%',
            valueStyle: usage == null ? statusStyle : valueStyle,
          ),
          _CpuStatusRow(
            label: 'Overall CPU',
            value: usage == null ? status : '${usage!.cpu2}%',
            valueStyle: usage == null ? statusStyle : valueStyle,
          ),
        ],
      ),
    );
  }
}

class _CpuStatusRow extends StatelessWidget {
  const _CpuStatusRow({
    required this.label,
    required this.value,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: valueStyle),
          ),
        ],
      ),
    );
  }
}
