import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/semantics.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/template_metadata.dart';
import 'package:nt_helper/services/template_share_service.dart';
import 'package:nt_helper/ui/template_manager/template_slot_selection_list.dart';

class CreateTemplateFromPresetDialog extends StatefulWidget {
  final AppDatabase? database;
  final FullPresetDetails source;

  const CreateTemplateFromPresetDialog({
    super.key,
    this.database,
    required this.source,
  });

  static Future<void> show(
    BuildContext context, {
    AppDatabase? database,
    required FullPresetDetails source,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 720,
          height: 640,
          child: CreateTemplateFromPresetDialog(
            database: database,
            source: source,
          ),
        ),
      ),
    );
  }

  @override
  State<CreateTemplateFromPresetDialog> createState() =>
      _CreateTemplateFromPresetDialogState();
}

class _CreateTemplateFromPresetDialogState
    extends State<CreateTemplateFromPresetDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final TextEditingController _authorController;
  Set<int> _selected = {};
  bool _creating = false;
  bool _loadingFromFile = false;
  String? _error;

  AppDatabase get _database => widget.database ?? context.read<AppDatabase>();

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.source.preset.name} Template',
    );
    _categoryController = TextEditingController(
      text: widget.source.preset.category ?? '',
    );
    _descriptionController = TextEditingController();
    _tagsController = TextEditingController();
    _authorController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final selected = _selected.toList()..sort();
    final name = _nameController.text.trim();
    if (name.isEmpty || selected.isEmpty || _creating) return;

    setState(() {
      _creating = true;
      _error = null;
    });
    _announce('Creating template from selected preset slots.');

    try {
      final metadata = TemplateMetadata(
        description: _nullIfEmpty(_descriptionController.text),
        tags: _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false),
        author: _nullIfEmpty(_authorController.text),
      );

      final copiedSlots = <FullPresetSlot>[];
      final missingAlgorithms = <String, AlgorithmEntry>{};
      for (var outputIndex = 0; outputIndex < selected.length; outputIndex++) {
        final sourceSlot = widget.source.slots[selected[outputIndex]];
        final existingAlgorithm = await _database.metadataDao
            .getAlgorithmByGuid(sourceSlot.slot.algorithmGuid);
        final algorithm = existingAlgorithm ?? sourceSlot.algorithm;
        if (existingAlgorithm == null) {
          missingAlgorithms[algorithm.guid] = algorithm;
        }

        copiedSlots.add(
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: outputIndex,
              algorithmGuid: sourceSlot.slot.algorithmGuid,
              customName: sourceSlot.slot.customName,
            ),
            algorithm: algorithm,
            specificationValues: List<int>.from(sourceSlot.specificationValues),
            parameterValues: Map<int, int>.from(sourceSlot.parameterValues),
            parameterStringValues: Map<int, String>.from(
              sourceSlot.parameterStringValues,
            ),
            mappings: Map<int, PackedMappingData>.from(sourceSlot.mappings),
          ),
        );
      }

      if (missingAlgorithms.isNotEmpty) {
        await _database.metadataDao.upsertAlgorithms(
          missingAlgorithms.values.toList(growable: false),
        );
      }

      await _database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: name,
            lastModified: DateTime.now(),
            isTemplate: true,
            category: _nullIfEmpty(_categoryController.text),
            templateMetadata: metadata.toJsonString(),
          ),
          slots: copiedSlots,
        ),
        isTemplate: true,
      );

      if (!mounted) return;
      _announce('Created $name template.');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        setState(() => _creating = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.toString();
      });
      _announce('Create template failed.');
    }
  }

  Future<void> _loadFromFile() async {
    if (_creating || _loadingFromFile) return;
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import Template JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = file?.path;
    if (path == null) return;

    setState(() {
      _loadingFromFile = true;
      _error = null;
    });
    _announce('Importing template JSON.');
    try {
      await TemplateShareService(_database)
          .importTemplate(await File(path).readAsString());
      if (!mounted) return;
      _announce('Imported template.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFromFile = false;
        _error = error.toString();
      });
      _announce('Template import failed.');
    }
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _selected.isNotEmpty && _nameController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text('Create Template')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: const ValueKey('template-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    key: const ValueKey('template-category'),
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    key: const ValueKey('template-description'),
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    key: const ValueKey('template-tags'),
                    controller: _tagsController,
                    decoration: const InputDecoration(labelText: 'Tags'),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    key: const ValueKey('template-author'),
                    controller: _authorController,
                    decoration: const InputDecoration(labelText: 'Author'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: TemplateSlotSelectionList(
              template: widget.source,
              selectedIndices: _selected,
              onSelectionChanged: (next) => setState(() => _selected = next),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: _loadingFromFile
                      ? SizedBox.square(
                          dimension: 18,
                          child: Semantics(
                            liveRegion: true,
                            label: 'Importing template JSON',
                            child: ExcludeSemantics(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.file_open_outlined,
                          semanticLabel: 'Import template from file',
                        ),
                  label: const Text('Import from file'),
                  onPressed: _creating || _loadingFromFile
                      ? null
                      : _loadFromFile,
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canCreate && !_creating && !_loadingFromFile
                      ? _create
                      : null,
                  child: _creating
                      ? SizedBox.square(
                          dimension: 18,
                          child: Semantics(
                            liveRegion: true,
                            label: 'Creating template',
                            child: ExcludeSemantics(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : const Text('Create template'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
