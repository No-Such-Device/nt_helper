import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Dialog that displays RTT (Round-Trip Time) statistics for SysEx messages.
///
/// Shows a table with timing stats broken down by message type, including
/// count, average, min, max, and last RTT for each message type.
class RttStatsDialog extends StatefulWidget {
  final IDistingMidiManager? midiManager;
  final List<AlgorithmInfo>? algorithms;
  final Map<String, dynamic>? ccNotificationDiagnostics;

  const RttStatsDialog({
    super.key,
    this.midiManager,
    this.algorithms,
    this.ccNotificationDiagnostics,
  });

  @override
  State<RttStatsDialog> createState() => _RttStatsDialogState();
}

class _RttStatsDialogState extends State<RttStatsDialog> {
  Map<String, Map<String, dynamic>>? _rttStats;
  Map<String, dynamic>? _schedulerDiagnostics;
  Map<int, double>? _slowAlgorithmInfo;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  void _refreshStats() {
    setState(() {
      _rttStats = widget.midiManager?.getRttStatsByMessageType();
      _schedulerDiagnostics = widget.midiManager?.getSchedulerDiagnostics();
      _slowAlgorithmInfo = widget.midiManager?.getSlowAlgorithmInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, semanticLabel: 'Back'),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('RTT Statistics'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, semanticLabel: 'Refresh'),
              tooltip: 'Refresh',
              onPressed: _refreshStats,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    if (widget.midiManager == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.wifi_off, size: 64, color: mutedColor),
            ),
            const SizedBox(height: 16),
            Text(
              'No MIDI connection available.',
              style: TextStyle(fontSize: 16, color: mutedColor),
            ),
          ],
        ),
      );
    }

    if (_rttStats == null || _rttStats!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.hourglass_empty, size: 64, color: mutedColor),
            ),
            const SizedBox(height: 16),
            Text(
              'No RTT data collected yet.',
              style: TextStyle(fontSize: 16, color: mutedColor),
            ),
            const SizedBox(height: 8),
            Text(
              'RTT stats are collected as requests are made.',
              style: TextStyle(fontSize: 14, color: mutedColor),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          if (_schedulerDiagnostics != null) _buildSummaryCard(),
          const SizedBox(height: 16),

          // RTT by message type table
          Text(
            'RTT by Message Type',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _buildRttTable(),

          // Slow Algorithm Info section
          if (_slowAlgorithmInfo != null && _slowAlgorithmInfo!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Slow Algorithm Info Requests (>50ms)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _buildSlowAlgorithmTable(),
          ],
        ],
      ),
    );
  }

  Widget _buildSlowAlgorithmTable() {
    if (_slowAlgorithmInfo == null || _slowAlgorithmInfo!.isEmpty) {
      return const Text('No slow requests recorded');
    }

    // Sort by RTT descending (slowest first)
    final sortedEntries = _slowAlgorithmInfo!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Helper to look up algorithm info by index
    AlgorithmInfo? getAlgorithmByIndex(int index) {
      if (widget.algorithms == null ||
          index < 0 ||
          index >= widget.algorithms!.length) {
        return null;
      }
      return widget.algorithms![index];
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Index')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('GUID')),
            DataColumn(label: Text('RTT (ms)'), numeric: true),
          ],
          rows: sortedEntries.map((entry) {
            final algoInfo = getAlgorithmByIndex(entry.key);
            return DataRow(
              cells: [
                DataCell(Text('${entry.key}')),
                DataCell(Text(algoInfo?.name ?? 'Unknown')),
                DataCell(Text(algoInfo?.guid ?? 'N/A')),
                DataCell(Text(entry.value.toStringAsFixed(2))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final diag = _schedulerDiagnostics!;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall Statistics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _buildStatItem(
                  'Requests',
                  '${diag['rttRequestsCompleted'] ?? 0}',
                  Icons.check_circle,
                  appColors.success.color,
                ),
                _buildStatItem(
                  'Timeouts',
                  '${diag['rttRequestsTimedOut'] ?? 0}',
                  Icons.error,
                  scheme.error,
                ),
                _buildStatItem(
                  'Avg RTT',
                  '${diag['rttAvgMs'] ?? 'N/A'} ms',
                  Icons.timer,
                  appColors.info.color,
                ),
                _buildStatItem(
                  'Min RTT',
                  '${diag['rttMinMs'] ?? 'N/A'} ms',
                  Icons.arrow_downward,
                  scheme.secondary,
                ),
                _buildStatItem(
                  'Max RTT',
                  '${diag['rttMaxMs'] ?? 'N/A'} ms',
                  Icons.arrow_upward,
                  appColors.warning.color,
                ),
                _buildStatItem(
                  'Last RTT',
                  '${diag['rttLastMs'] ?? 'N/A'} ms',
                  Icons.schedule,
                  appColors.categoricalAt(3).color,
                ),
                _buildStatItem(
                  'CC Dispatched',
                  '${diag['ccMessagesDispatched'] ?? 0}',
                  Icons.music_note,
                  scheme.primary,
                ),
                _buildStatItem(
                  'CC Callback',
                  diag['ccCallbackRegistered'] == true ? 'Yes' : 'No',
                  Icons.link,
                  diag['ccCallbackRegistered'] == true
                      ? appColors.success.color
                      : scheme.error,
                ),
                if (widget.ccNotificationDiagnostics != null) ...[
                  _buildStatItem(
                    'CC Lookup Size',
                    '${widget.ccNotificationDiagnostics!['lookupSize'] ?? 0}',
                    Icons.table_chart,
                    (widget.ccNotificationDiagnostics!['lookupSize'] ?? 0) > 0
                        ? appColors.success.color
                        : scheme.error,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRttTable() {
    // Sort by count (most frequent first)
    final sortedEntries = _rttStats!.entries.toList()
      ..sort((a, b) {
        final countA = a.value['count'] as int? ?? 0;
        final countB = b.value['count'] as int? ?? 0;
        return countB.compareTo(countA);
      });

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Message Type')),
            DataColumn(label: Text('Count'), numeric: true),
            DataColumn(label: Text('Timeouts'), numeric: true),
            DataColumn(label: Text('Avg (ms)'), numeric: true),
            DataColumn(label: Text('Min (ms)'), numeric: true),
            DataColumn(label: Text('Max (ms)'), numeric: true),
            DataColumn(label: Text('Last (ms)'), numeric: true),
          ],
          rows: sortedEntries.map((entry) {
            final stats = entry.value;
            final timeouts = stats['timeouts'] as int? ?? 0;
            return DataRow(
              cells: [
                DataCell(Text(_formatMessageType(entry.key))),
                DataCell(Text('${stats['count'] ?? 0}')),
                DataCell(
                  Text(
                    '$timeouts',
                    style: timeouts > 0
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                ),
                DataCell(Text(stats['avgMs'] ?? 'N/A')),
                DataCell(Text(stats['minMs'] ?? 'N/A')),
                DataCell(Text(stats['maxMs'] ?? 'N/A')),
                DataCell(Text(stats['lastMs'] ?? 'N/A')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Format message type name for display (e.g., respPresetName -> Preset Name)
  String _formatMessageType(String messageType) {
    // Remove 'resp' prefix if present
    var name = messageType;
    if (name.startsWith('resp')) {
      name = name.substring(4);
    }

    // Convert camelCase to Title Case with spaces
    final buffer = StringBuffer();
    for (int i = 0; i < name.length; i++) {
      final char = name[i];
      if (i > 0 && char.toUpperCase() == char && char.toLowerCase() != char) {
        buffer.write(' ');
      }
      buffer.write(i == 0 ? char.toUpperCase() : char);
    }
    return buffer.toString();
  }
}

/// Extension method to easily show the RTT stats dialog
extension RttStatsDialogExtension on BuildContext {
  Future<void> showRttStatsDialog(
    IDistingMidiManager? midiManager, {
    List<AlgorithmInfo>? algorithms,
    Map<String, dynamic>? ccNotificationDiagnostics,
  }) {
    return showDialog<void>(
      context: this,
      builder: (context) => RttStatsDialog(
        midiManager: midiManager,
        algorithms: algorithms,
        ccNotificationDiagnostics: ccNotificationDiagnostics,
      ),
    );
  }
}
