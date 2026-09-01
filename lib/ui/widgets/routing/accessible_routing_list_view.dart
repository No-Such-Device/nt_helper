import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// A list-based representation of the routing editor for screen reader users.
///
/// Provides the same information as the visual canvas but in an accessible
/// list format with sections for algorithms and connections.
class AccessibleRoutingListView extends StatelessWidget {
  const AccessibleRoutingListView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
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
              ) => _buildListView(
                context,
                algorithms,
                connections,
                physicalInputs,
                physicalOutputs,
                deviceIoProfile: deviceIoProfile,
              ),
        );
      },
    );
  }

  Widget _buildListView(
    BuildContext context,
    List<RoutingAlgorithm> algorithms,
    List<Connection> connections,
    List<Port> physicalInputs,
    List<Port> physicalOutputs, {
    required DeviceIoProfile deviceIoProfile,
  }) {
    final theme = Theme.of(context);
    final cubit = context.read<RoutingEditorCubit>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Algorithms section
        Semantics(
          header: true,
          child: Text(
            'Algorithms (${algorithms.length})',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        ...algorithms.map(
          (algo) => _buildAlgorithmTile(context, algo, connections, algorithms),
        ),

        const Divider(height: 32),

        // Connections section
        Semantics(
          header: true,
          child: Text(
            'Connections (${connections.length})',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        if (connections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No connections. Use the canvas view to create connections between ports.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...connections.map(
            (conn) => _buildConnectionTile(
              context,
              conn,
              algorithms,
              cubit,
              deviceIoProfile: deviceIoProfile,
            ),
          ),
      ],
    );
  }

  Widget _buildAlgorithmTile(
    BuildContext context,
    RoutingAlgorithm algo,
    List<Connection> connections,
    List<RoutingAlgorithm> algorithms,
  ) {
    final theme = Theme.of(context);
    final inputCount = algo.inputPorts.length;
    final outputCount = algo.outputPorts.length;
    final connectedPorts = connections
        .where(
          (c) =>
              algo.inputPorts.any((p) => p.id == c.destinationPortId) ||
              algo.outputPorts.any((p) => p.id == c.sourcePortId),
        )
        .length;

    return Card(
      child: Semantics(
        label:
            'Slot ${algo.index + 1}: ${algo.algorithm.name}. '
            '$inputCount inputs, $outputCount outputs, '
            '$connectedPorts active connections',
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '${algo.index + 1}',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(algo.algorithm.name),
          subtitle: Text(
            '$inputCount inputs, $outputCount outputs, $connectedPorts connections',
          ),
          children: [
            if (algo.inputPorts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Inputs:', style: theme.textTheme.labelLarge),
                ),
              ),
              ...algo.inputPorts.map(
                (port) => _buildPortListItem(
                  context,
                  port,
                  connections,
                  true,
                  algorithms,
                ),
              ),
            ],
            if (algo.outputPorts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Outputs:', style: theme.textTheme.labelLarge),
                ),
              ),
              ...algo.outputPorts.map(
                (port) => _buildPortListItem(
                  context,
                  port,
                  connections,
                  false,
                  algorithms,
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPortListItem(
    BuildContext context,
    Port port,
    List<Connection> connections,
    bool isInput,
    List<RoutingAlgorithm> algorithms,
  ) {
    final connectedTo = connections.where(
      (c) =>
          (isInput && c.destinationPortId == port.id) ||
          (!isInput && c.sourcePortId == port.id),
    );

    String connectionInfo;
    if (connectedTo.isEmpty) {
      connectionInfo = 'Not connected';
    } else {
      final names = connectedTo.map((c) {
        final otherPortId = isInput ? c.sourcePortId : c.destinationPortId;
        return _findPortName(otherPortId, algorithms);
      });
      connectionInfo = names.join(', ');
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        isInput ? Icons.arrow_forward : Icons.arrow_back,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(port.name),
      subtitle: Text(connectionInfo),
    );
  }

  Widget _buildConnectionTile(
    BuildContext context,
    Connection conn,
    List<RoutingAlgorithm> algorithms,
    RoutingEditorCubit cubit, {
    required DeviceIoProfile deviceIoProfile,
  }) {
    final theme = Theme.of(context);
    final sourceName = _findPortName(conn.sourcePortId, algorithms);
    final destName = _findPortName(conn.destinationPortId, algorithms);
    final isAlgoToAlgo =
        conn.connectionType == ConnectionType.algorithmToAlgorithm;
    final auxLabel = isAlgoToAlgo
        ? _formatBusLabel(conn.busNumber, deviceIoProfile: deviceIoProfile)
        : null;

    final reason = cubit.deletionBlockReasonForConnection(conn);
    final canDelete = reason == null;

    final semanticLabel = auxLabel != null
        ? '$sourceName to $destName via $auxLabel'
        : '$sourceName to $destName';

    return Semantics(
      label: semanticLabel,
      child: ListTile(
        leading: Icon(Icons.link, color: theme.colorScheme.primary),
        title: Text('$sourceName \u2192 $destName'),
        subtitle: auxLabel != null ? Text('via $auxLabel') : null,
        trailing: canDelete
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete this connection',
                onPressed: () {
                  cubit.deleteConnectionWithSmartBusLogic(conn.id);
                  SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Connection deleted from $sourceName to $destName',
                    TextDirection.ltr,
                  );
                },
              )
            : Tooltip(
                message: reason,
                child: Icon(
                  Icons.lock_outline,
                  color: theme.colorScheme.outline,
                ),
              ),
      ),
    );
  }

  String _formatBusLabel(
    int? busNumber, {
    required DeviceIoProfile deviceIoProfile,
  }) {
    if (busNumber == null) return 'Unknown bus';
    final label = deviceIoProfile.labelForBus(busNumber);
    if (label != null) return label;
    final es5Index = deviceIoProfile.contextualEs5Buses.indexOf(busNumber);
    if (es5Index == 0) return 'ES-5 Left';
    if (es5Index == 1) return 'ES-5 Right';
    return 'Bus $busNumber';
  }

  String _findPortName(String portId, List<RoutingAlgorithm> algorithms) {
    for (final algo in algorithms) {
      for (final port in [...algo.inputPorts, ...algo.outputPorts]) {
        if (port.id == portId) {
          return '${algo.algorithm.name}: ${port.name}';
        }
      }
    }
    // Check if it's a physical port
    if (portId.startsWith('hw_in_')) {
      final num = portId.replaceFirst('hw_in_', '');
      return 'Input $num';
    }
    if (portId.startsWith('hw_out_')) {
      final num = portId.replaceFirst('hw_out_', '');
      return 'Output $num';
    }
    if (portId.startsWith('es5_')) {
      final suffix = portId.replaceFirst('es5_', '');
      return 'ES-5 $suffix';
    }
    return portId;
  }
}
