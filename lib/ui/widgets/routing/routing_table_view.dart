import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/routing_information.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/util/routing_analyzer.dart';
import 'package:nt_helper/util/routing_info_builder.dart';

/// OG-style signal flow table visualization for the routing editor.
///
/// Displays routing as a matrix: slots as rows, buses as columns, with
/// color-coded signal propagation and symbols for input/output/replace.
class RoutingTableView extends StatefulWidget {
  const RoutingTableView({super.key});

  @override
  State<RoutingTableView> createState() => _RoutingTableViewState();
}

class _RoutingTableViewState extends State<RoutingTableView> {
  static const double _cellWidth = 32;
  static const double _cellHeight = 28;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
      buildWhen: (prev, curr) {
        // Only rebuild when algorithm/connection data actually changes,
        // not on zoom, pan, focus, or other UI-only state changes.
        if (prev is! RoutingEditorStateLoaded ||
            curr is! RoutingEditorStateLoaded) {
          return true;
        }
        return prev.algorithms != curr.algorithms ||
            prev.connections != curr.connections ||
            prev.portOutputModes != curr.portOutputModes ||
            prev.deviceIoProfile != curr.deviceIoProfile;
      },
      builder: (context, state) {
        return state.when(
          initial: () => const Center(child: Text('Initializing...')),
          disconnected: () => const Center(child: Text('Disconnected')),
          loaded:
              (
                deviceIoProfile,
                physicalInputs,
                physicalOutputs,
                es5Inputs,
                algorithms,
                connections,
                buses,
                portOutputModes,
                nodePositions,
                zoomLevel,
                panOffset,
                isHardwareSynced,
                isPersistenceEnabled,
                lastSyncTime,
                lastPersistTime,
                lastError,
                subState,
                focusedAlgorithmIds,
                cascadeScrollTarget,
                auxBusUsage,
                hasExtendedAuxBuses,
              ) => _buildTable(
                context,
                algorithms: algorithms,
                portOutputModes: portOutputModes,
                deviceIoProfile: deviceIoProfile,
              ),
        );
      },
    );
  }

  Widget _buildTable(
    BuildContext context, {
    required List<RoutingAlgorithm> algorithms,
    required Map<String, OutputMode> portOutputModes,
    required DeviceIoProfile deviceIoProfile,
  }) {
    final routing = buildRoutingInfoFromEditor(
      algorithms,
      portOutputModes,
      deviceIoProfile: deviceIoProfile,
    );
    if (routing.isEmpty) {
      return Center(
        child: Text(
          'No algorithms loaded.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final analyzer = RoutingAnalyzer(
      routing: routing,
      deviceIoProfile: deviceIoProfile,
    );
    final slotCount = routing.length;
    final signals = analyzer.signals;
    final numBuses = _computeVisibleBusCount(
      signals,
      routing,
      deviceIoProfile: deviceIoProfile,
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colours = [
      scheme.surface,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerLow,
      scheme.primaryContainer,
      scheme.tertiaryFixedDim,
    ];

    // Pre-compute text styles once instead of per-cell
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final slotNameStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final cellStyle = theme.textTheme.labelSmall;
    final symbolStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 13);
    final pinnedBg = scheme.surfaceContainerHighest;
    final slotBg = scheme.surfaceContainer;
    final usedBg = scheme.secondaryContainer;
    final unusedBg = scheme.surfaceContainerLow;

    final pinnedRows = <TableRow>[];
    final mainRows = <TableRow>[];

    // Header row (top)
    pinnedRows.add(
      TableRow(
        children: [
          Container(
            height: _cellHeight,
            constraints: const BoxConstraints(minWidth: 80),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            color: pinnedBg,
            child: Text('Algorithm', style: headerStyle),
          ),
        ],
      ),
    );
    mainRows.add(
      TableRow(
        children: [
          for (int ch = 1; ch <= numBuses; ch++)
            Container(
              width: _cellWidth,
              height: _cellHeight,
              alignment: Alignment.center,
              color: _headerBg(ch, scheme, deviceIoProfile),
              child: Text(
                _columnLabel(ch, deviceIoProfile),
                style: headerStyle,
              ),
            ),
        ],
      ),
    );

    for (int s = 0; s < slotCount; s++) {
      final info = routing[s];
      final rowBefore = signals[s];
      final rowAfter = signals[s + 1];

      // Signal-above row
      pinnedRows.add(TableRow(children: [SizedBox(height: _cellHeight)]));
      mainRows.add(
        TableRow(
          children: [
            for (int ch = 1; ch <= numBuses; ch++)
              _signalAboveCell(ch, rowBefore, info, colours, scheme.error),
          ],
        ),
      );

      // Slot row
      pinnedRows.add(
        TableRow(
          children: [
            Container(
              height: _cellHeight,
              constraints: const BoxConstraints(minWidth: 80),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              color: slotBg,
              child: Text(
                '${info.algorithmIndex + 1}. ${info.algorithmName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: slotNameStyle,
              ),
            ),
          ],
        ),
      );
      mainRows.add(
        TableRow(
          children: [
            for (int ch = 1; ch <= numBuses; ch++)
              _slotCell(
                ch,
                signalsBefore: rowBefore,
                info: info,
                colours: colours,
                usedBg: usedBg,
                unusedBg: unusedBg,
                cellStyle: cellStyle,
                deviceIoProfile: deviceIoProfile,
              ),
          ],
        ),
      );

      // Signal-below row
      pinnedRows.add(TableRow(children: [SizedBox(height: _cellHeight)]));
      mainRows.add(
        TableRow(
          children: [
            for (int ch = 1; ch <= numBuses; ch++)
              _signalBelowCell(ch, rowAfter, info, colours, symbolStyle),
          ],
        ),
      );
    }

    // Header row (bottom)
    pinnedRows.add(
      TableRow(
        children: [
          Container(
            height: _cellHeight,
            constraints: const BoxConstraints(minWidth: 80),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            color: pinnedBg,
            child: Text('Algorithm', style: headerStyle),
          ),
        ],
      ),
    );
    mainRows.add(
      TableRow(
        children: [
          for (int ch = 1; ch <= numBuses; ch++)
            Container(
              width: _cellWidth,
              height: _cellHeight,
              alignment: Alignment.center,
              color: _headerBg(ch, scheme, deviceIoProfile),
              child: Text(
                _columnLabel(ch, deviceIoProfile),
                style: headerStyle,
              ),
            ),
        ],
      ),
    );

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned algorithm name column — scrolls with the main table
            Table(
              border: TableBorder(
                right: BorderSide(color: theme.dividerColor),
                horizontalInside: BorderSide(
                  color: theme.dividerColor,
                  width: 0.5,
                ),
              ),
              columnWidths: const {0: IntrinsicColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: pinnedRows,
            ),
            // Bus columns — horizontal scroll only
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  border: TableBorder(
                    verticalInside: BorderSide(
                      color: theme.dividerColor,
                      width: 0.5,
                    ),
                    horizontalInside: BorderSide(
                      color: theme.dividerColor,
                      width: 0.5,
                    ),
                  ),
                  columnWidths: {
                    for (int i = 0; i < numBuses; i++)
                      i: const FixedColumnWidth(_cellWidth),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: mainRows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalAboveCell(
    int ch,
    List<int> rowBefore,
    RoutingInformation info,
    List<Color> colours,
    Color errorColor,
  ) {
    final usesChannel = info.readsBus(ch, signals: true, mappings: false);
    final signalLevel = ch < rowBefore.length ? rowBefore[ch] : 0;
    final bgColor = colours[signalLevel + 3 * (ch & 1)];

    if (!usesChannel) {
      return Container(width: _cellWidth, height: _cellHeight, color: bgColor);
    }
    final unprovided = signalLevel == 0;
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      color: bgColor,
      child: Text(
        '\u2193',
        style: TextStyle(
          fontSize: 13,
          color: unprovided ? errorColor : null,
          fontWeight: unprovided ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _slotCell(
    int ch, {
    required List<int> signalsBefore,
    required RoutingInformation info,
    required List<Color> colours,
    required Color usedBg,
    required Color unusedBg,
    required TextStyle? cellStyle,
    required DeviceIoProfile deviceIoProfile,
  }) {
    final levelBefore = ch < signalsBefore.length ? signalsBefore[ch] : 0;
    final isUsed = info.usesBus(ch);

    final Color bgColor;
    if (isUsed) {
      bgColor = usedBg;
    } else if (levelBefore > 0) {
      bgColor = colours[levelBefore + 3 * (ch & 1)];
    } else {
      bgColor = unusedBg;
    }

    if (!isUsed) {
      return Container(width: _cellWidth, height: _cellHeight, color: bgColor);
    }
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      color: bgColor,
      child: Text(
        _condensedChannelLabel(ch, deviceIoProfile),
        style: cellStyle,
      ),
    );
  }

  Widget _signalBelowCell(
    int ch,
    List<int> rowAfter,
    RoutingInformation info,
    List<Color> colours,
    TextStyle? symbolStyle,
  ) {
    final signalLevel = ch < rowAfter.length ? rowAfter[ch] : 0;
    final bgColor = colours[signalLevel + 3 * (ch & 1)];
    final hasOutput = info.writesBus(ch);

    if (!hasOutput) {
      return Container(width: _cellWidth, height: _cellHeight, color: bgColor);
    }
    final replaced = info.replacesBus(ch);
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      color: bgColor,
      child: Text(replaced ? '\u2533' : '+', style: symbolStyle),
    );
  }

  int _computeVisibleBusCount(
    List<List<int>> signals,
    List<RoutingInformation> routing, {
    required DeviceIoProfile deviceIoProfile,
  }) {
    final es5Buses = deviceIoProfile.contextualEs5Buses;
    final maxBus = es5Buses.isEmpty ? deviceIoProfile.maxBus : es5Buses.last;
    final outputBuses = deviceIoProfile.outputBuses;
    final inputBuses = deviceIoProfile.inputBuses;
    int highestUsed = outputBuses.isNotEmpty
        ? outputBuses.last
        : inputBuses.isNotEmpty
        ? inputBuses.last
        : 0;
    for (final info in routing) {
      for (int ch = maxBus; ch > highestUsed; ch--) {
        if (info.usesBus(ch)) {
          highestUsed = ch;
          break;
        }
      }
    }
    final last = signals.last;
    for (int i = maxBus; i > highestUsed; i--) {
      if (i < last.length && last[i] != 0) {
        highestUsed = i;
        break;
      }
    }
    return highestUsed;
  }

  Color _headerBg(
    int ch,
    ColorScheme colorScheme,
    DeviceIoProfile deviceIoProfile,
  ) {
    if (deviceIoProfile.isInput(ch)) {
      return colorScheme.surfaceContainerHighest;
    }
    if (deviceIoProfile.isOutput(ch)) {
      return colorScheme.secondaryContainer;
    }
    return colorScheme.tertiaryContainer;
  }

  String _columnLabel(int ch, DeviceIoProfile deviceIoProfile) {
    final local = deviceIoProfile.localNumber(ch);
    return switch (deviceIoProfile.groupOf(ch)) {
      DeviceBusGroup.input => 'I$local',
      DeviceBusGroup.output => 'O$local',
      DeviceBusGroup.aux => 'A$local',
      null =>
        deviceIoProfile.contextualEs5Buses.indexOf(ch) == 0
            ? 'ES-L'
            : deviceIoProfile.contextualEs5Buses.indexOf(ch) == 1
            ? 'ES-R'
            : '$ch',
    };
  }

  String _condensedChannelLabel(int ch, DeviceIoProfile deviceIoProfile) =>
      '${deviceIoProfile.localNumber(ch) ?? ch}';
}
