import 'dart:math' as math;
import 'ntx8cv_routing_outputs.dart';

import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/routing_information.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/util/routing_analyzer.dart';
import 'package:nt_helper/util/routing_info_builder.dart';

import 'cv_modulation_view.dart';

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
  static const int _slotRowCount = 3;
  static const int _firstSignalRow = 1;

  @override
  Widget build(BuildContext context) {
    return Ntx8cvRoutingFrame(
      child: BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
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
                  ntx8cvRouting,
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
      ),
    );
  }

  Widget _buildTable(
    BuildContext context, {
    required List<RoutingAlgorithm> algorithms,
    required Map<String, OutputMode> portOutputModes,
    required DeviceIoProfile deviceIoProfile,
  }) {
    final modulations = [
      for (final algorithm in algorithms) ...algorithm.cvModulations,
    ];
    final routing = buildRoutingInfoFromEditor(
      algorithms,
      portOutputModes,
      deviceIoProfile: deviceIoProfile,
    );
    if (routing.isEmpty) {
      return Center(
        child: Text(
          'No algorithms loaded.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

    final trails = _cvTrailCells(algorithms, routing, modulations, numBuses);
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
      pinnedRows.add(
        TableRow(
          children: [
            SizedBox(
              height: _cellHeight,
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 30,
                  child: Builder(
                    builder: (buttonContext) {
                      final mappings = modulations
                          .where(
                            (m) =>
                                m.destinationSlot == info.algorithmIndex &&
                                !deviceIoProfile.contains(m.bus),
                          )
                          .toList();
                      return CvModulationButton(
                        compact: true,
                        mappings: mappings,
                        onEdit: () =>
                            editCvModulations(buttonContext, mappings),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      mainRows.add(
        TableRow(
          children: [
            for (int ch = 1; ch <= numBuses; ch++)
              _signalAboveCell(
                ch,
                rowBefore,
                info,
                colours,
                scheme.error,
                modulations
                    .where(
                      (m) =>
                          m.destinationSlot == info.algorithmIndex &&
                          m.bus == ch,
                    )
                    .toList(),
                trail: trails[(mainRows.length, ch)],
              ),
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
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 32),
                    child: Text(
                      '${info.algorithmIndex + 1}. ${info.algorithmName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: slotNameStyle,
                    ),
                  ),
                ],
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
                trail: trails[(mainRows.length, ch)],
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
              _signalBelowCell(
                ch,
                rowAfter,
                info,
                colours,
                symbolStyle,
                trail: trails[(mainRows.length, ch)],
              ),
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

    final scrollBehavior = ScrollConfiguration.of(context)
        .copyWith(overscroll: false);
    return ScrollConfiguration(
      behavior: scrollBehavior,
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
            // Bus columns — horizontal scroll only. A left-button mouse
            // drag on the table also scrolls, so an ordinary mouse can
            // navigate without a trackpad or modifier key.
            Expanded(
              child: ScrollConfiguration(
                behavior: scrollBehavior.copyWith(
                  dragDevices: {
                    ...scrollBehavior.dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
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
            ),
          ],
        ),
      ),
    );
  }

  Map<(int, int), (double, double)> _cvTrailCells(
    List<RoutingAlgorithm> algorithms,
    List<RoutingInformation> routing,
    List<CvModulation> modulations,
    int numBuses,
  ) {
    final slotRows = {
      for (final (i, slot) in routing.indexed)
        slot.algorithmIndex: _firstSignalRow + i * _slotRowCount,
    };
    final outputs = {
      for (final algorithm in algorithms)
        for (final output in algorithm.outputPorts)
          if (output.isActive)
            output.id: (
              row: slotRows[algorithm.index]! + 2,
              bus: output.busValue,
            ),
    };
    final trails = <(int, int), (double, double)>{};
    for (final mapping in modulations) {
      final output = outputs[mapping.contributors.singleOrNull?.portId];
      final targetRow = slotRows[mapping.destinationSlot];
      if (output == null ||
          targetRow == null ||
          output.row >= targetRow ||
          output.bus != mapping.bus ||
          mapping.bus < 1 ||
          mapping.bus > numBuses) {
        continue;
      }

      for (var row = output.row; row <= targetRow; row++) {
        final cell = (row, mapping.bus);
        // Leave room for the output glyph and CV text at the endpoints.
        final start = row == output.row ? _cellHeight * .75 : 0.0;
        final end = row == targetRow ? _cellHeight / 2 - 5 : _cellHeight;
        final existing = trails[cell];
        trails[cell] = existing == null
            ? (start, end)
            : (math.min(existing.$1, start), math.max(existing.$2, end));
      }
    }
    return trails;
  }

  Widget _signalCell({
    required Color color,
    required (double, double)? trail,
    Widget? child,
  }) {
    const x = _cellWidth / 2;
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      color: color,
      child: trail == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: CustomPaint(
                    painter: CvModulationCurve(
                      color: cvModulationColor(context),
                      endpoints: [(Offset(x, trail.$1), Offset(x, trail.$2))],
                    ),
                  ),
                ),
                if (child != null) Center(child: child),
              ],
            ),
    );
  }

  Widget _signalAboveCell(
    int ch,
    List<int> rowBefore,
    RoutingInformation info,
    List<Color> colours,
    Color errorColor,
    List<CvModulation> modulations, {
    required (double, double)? trail,
  }) {
    final usesChannel = info.readsBus(ch, signals: true, mappings: false);
    final signalLevel = ch < rowBefore.length ? rowBefore[ch] : 0;
    final bgColor = colours[signalLevel + 3 * (ch & 1)];

    final unprovided = signalLevel == 0;
    return _signalCell(
      trail: trail,
      color: modulations.isEmpty
          ? bgColor
          : Color.alphaBlend(
              cvModulationColor(context).withValues(alpha: 0.14),
              bgColor,
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (usesChannel)
            Text(
              '\u2193',
              style: TextStyle(
                fontSize: 13,
                color: unprovided ? errorColor : null,
                fontWeight: unprovided ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          if (modulations.isNotEmpty)
            Expanded(
              child: Builder(
                builder: (buttonContext) => CvModulationButton(
                  key: ValueKey('cv-cell-${info.algorithmIndex}-$ch'),
                  mappings: modulations,
                  onEdit: () => editCvModulations(buttonContext, modulations),
                  compact: true,
                ),
              ),
            ),
        ],
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
    required (double, double)? trail,
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

    return _signalCell(
      trail: trail,
      color: bgColor,
      child: isUsed
          ? Text(_condensedChannelLabel(ch, deviceIoProfile), style: cellStyle)
          : null,
    );
  }

  Widget _signalBelowCell(
    int ch,
    List<int> rowAfter,
    RoutingInformation info,
    List<Color> colours,
    TextStyle? symbolStyle, {
    required (double, double)? trail,
  }) {
    final signalLevel = ch < rowAfter.length ? rowAfter[ch] : 0;
    final bgColor = colours[signalLevel + 3 * (ch & 1)];
    final hasOutput = info.writesBus(ch);

    final replaced = info.replacesBus(ch);
    return _signalCell(
      trail: trail,
      color: bgColor,
      child: hasOutput
          ? Text(replaced ? '\u2533' : '+', style: symbolStyle)
          : null,
    );
  }

  int _computeVisibleBusCount(
    List<List<int>> signals,
    List<RoutingInformation> routing, {
    required DeviceIoProfile deviceIoProfile,
  }) {
    final es5Buses = deviceIoProfile.contextualEs5Buses;
    final maxBus = es5Buses.isEmpty ? deviceIoProfile.maxBus : es5Buses.last;
    int highestUsed =
        deviceIoProfile.outputBuses.lastOrNull ??
        deviceIoProfile.inputBuses.lastOrNull ??
        0;

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
