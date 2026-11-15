import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/disting_limits.dart';

class TemplateSlotSelectionList extends StatefulWidget {
  final FullPresetDetails template;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>> onSelectionChanged;
  final int currentTargetSlotCount;
  final int maxSlots;

  const TemplateSlotSelectionList({
    super.key,
    required this.template,
    required this.selectedIndices,
    required this.onSelectionChanged,
    this.currentTargetSlotCount = 0,
    this.maxSlots = DistingLimits.maxPresetSlots,
  });

  @override
  State<TemplateSlotSelectionList> createState() =>
      _TemplateSlotSelectionListState();
}

class _TemplateSlotSelectionListState extends State<TemplateSlotSelectionList> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<int> get _visibleIndices {
    final indices = <int>[];
    for (var i = 0; i < widget.template.slots.length; i++) {
      final slot = widget.template.slots[i];
      final haystack = [
        slot.algorithm.name,
        slot.algorithm.guid,
        slot.slot.customName ?? '',
      ].join(' ').toLowerCase();
      if (_query.isEmpty || haystack.contains(_query)) {
        indices.add(i);
      }
    }
    return indices;
  }

  void _setSelected(Set<int> next) {
    widget.onSelectionChanged(Set<int>.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleIndices;
    final selectedCount = widget.selectedIndices.length;
    final total = widget.currentTargetSlotCount + selectedCount;
    final overLimit = total > widget.maxSlots;
    final visibleSelected = visible.every(widget.selectedIndices.contains);
    final toggleSelectsAll = visible.isEmpty || !visibleSelected;

    return Semantics(
      container: true,
      label:
          'Template slot selection list for ${widget.template.preset.name}. ${widget.template.slots.length} ${widget.template.slots.length == 1 ? 'slot' : 'slots'}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search slots',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label:
                        '$selectedCount selected, ${widget.currentTargetSlotCount} current slots, $total of ${widget.maxSlots} maximum slots${overLimit ? ', over the slot limit' : ''}',
                    child: Text(
                      '$selectedCount selected + ${widget.currentTargetSlotCount} current = $total / ${widget.maxSlots}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: overLimit
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: toggleSelectsAll
                      ? 'Select all visible slots'
                      : 'Clear visible slot selection',
                  icon: Icon(
                    toggleSelectsAll ? Icons.select_all : Icons.deselect,
                  ),
                  onPressed: visible.isEmpty
                      ? null
                      : () {
                          final next = {...widget.selectedIndices};
                          if (toggleSelectsAll) {
                            next.addAll(visible);
                          } else {
                            next.removeAll(visible);
                          }
                          _setSelected(next);
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Semantics(
                      liveRegion: true,
                      child: Text('No slots match'),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, rowIndex) {
                      final templateIndex = visible[rowIndex];
                      final slot = widget.template.slots[templateIndex];
                      final checked = widget.selectedIndices.contains(
                        templateIndex,
                      );
                      final subtitleParts = <String>[
                        'Slot ${slot.slot.slotIndex}',
                        '${slot.parameterValues.length} params',
                        '${slot.mappings.length} mappings',
                      ];
                      final customName = slot.slot.customName;
                      if (customName != null && customName.isNotEmpty) {
                        subtitleParts.insert(1, customName);
                      }

                      return CheckboxListTile(
                        key: ValueKey('template-slot-$templateIndex'),
                        value: checked,
                        onChanged: (value) {
                          final next = {...widget.selectedIndices};
                          if (value == true) {
                            next.add(templateIndex);
                          } else {
                            next.remove(templateIndex);
                          }
                          _setSelected(next);
                        },
                        title: Text(slot.algorithm.name),
                        subtitle: Text(subtitleParts.join(' · ')),
                        secondary: Text(
                          '${slot.slot.slotIndex}',
                          style: theme.textTheme.titleMedium,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
