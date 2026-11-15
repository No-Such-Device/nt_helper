import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/semantics.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/template_metadata.dart';
import 'package:nt_helper/services/template_share_service.dart';
import 'package:nt_helper/ui/template_manager/create_template_from_preset_dialog.dart';
import 'package:nt_helper/ui/template_manager/template_apply_dialog.dart';
import 'package:nt_helper/ui/template_manager/template_slot_selection_list.dart';

typedef TemplateDeviceApplyCallback = Future<void> Function(
  FullPresetDetails template,
  List<int> selectedIndices,
);

typedef CurrentPresetSourceLoader = Future<FullPresetDetails?> Function();

class TemplateManagerScreen extends StatefulWidget {
  final AppDatabase? database;
  final TemplateDeviceApplyCallback? onApplyDevice;
  final VoidCallback? onCancelDeviceApply;
  final CurrentPresetSourceLoader? loadCurrentPresetSource;

  const TemplateManagerScreen({
    super.key,
    this.database,
    this.onApplyDevice,
    this.onCancelDeviceApply,
    this.loadCurrentPresetSource,
  });

  @override
  State<TemplateManagerScreen> createState() => _TemplateManagerScreenState();
}

class _TemplateManagerScreenState extends State<TemplateManagerScreen> {
  late Future<List<FullPresetDetails>> _templatesFuture;
  FullPresetDetails? _selected;
  Set<int> _selectedSlots = {};
  bool _isApplying = false;
  bool _isDragOver = false;
  bool _isImporting = false;
  int _applyRun = 0;

  AppDatabase get _database => widget.database ?? context.read<AppDatabase>();

  @override
  void initState() {
    super.initState();
    _templatesFuture = _database.presetsDao.getTemplates();
  }

  @override
  void dispose() {
    if (_isApplying) {
      widget.onCancelDeviceApply?.call();
    }
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _templatesFuture = _database.presetsDao.getTemplates();
      _selected = null;
      _selectedSlots = {};
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  bool get _supportsDrop {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
  }

  Future<void> _loadTemplateFromFile() async {
    if (_isApplying || _isImporting) return;
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import Template JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = file?.path;
    if (path == null) return;

    await _importTemplateJson(await File(path).readAsString());
  }

  Future<void> _exportSelectedTemplate() async {
    final template = _selected;
    if (_isApplying || _isImporting || template == null) return;

    final jsonText = TemplateShareService(_database).encodeTemplate(template);
    final path = await FilePicker.saveFile(
      mimeType: 'application/json',
      dialogTitle: 'Export Template JSON',
      fileName: '${_safeFileName(template.preset.name)}.json',
      bytes: Uint8List.fromList(utf8.encode(jsonText)),
    );
    if (path == null) return;

    if (!mounted) return;
    _announce('Exported ${template.preset.name} template.');
  }

  Future<void> _importDroppedFiles(List<XFile> files) async {
    final jsonFiles = files
        .where((file) => file.path.toLowerCase().endsWith('.json'))
        .toList(growable: false);
    if (jsonFiles.isEmpty) {
      _announce('No template JSON file found in drop.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drop a Template Manager JSON file.')),
      );
      return;
    }

    for (final file in jsonFiles) {
      await _importTemplateJson(await file.readAsString());
    }
  }

  Future<void> _importTemplateJson(String jsonText) async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    _announce('Importing template JSON.');
    try {
      final service = TemplateShareService(_database);
      final presetId = await service.importTemplate(jsonText);
      final imported = await _database.presetsDao.getFullPresetDetails(
        presetId,
      );
      if (!mounted) return;
      _refresh();
      _announce('Imported ${imported?.preset.name ?? 'template'}.');
    } catch (error) {
      if (!mounted) return;
      _announce('Template import failed.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Template import failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _isDragOver = false;
        });
      }
    }
  }

  String _safeFileName(String name) {
    final sanitized = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return sanitized.isEmpty ? 'template' : sanitized;
  }

  Future<void> _editSelectedMetadata() async {
    final template = _selected;
    if (_isApplying || template == null) return;

    final saved = await _EditTemplateMetadataDialog.show(
      context,
      template: template,
      database: _database,
    );
    if (mounted && saved == true) {
      _refresh();
    }
  }

  Future<void> _deleteSelectedTemplate() async {
    final template = _selected;
    if (_isApplying || template == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('Delete "${template.preset.name}" from saved templates?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _database.presetsDao.deletePreset(template.preset.id);
    if (mounted) _refresh();
  }

  Set<int> _allSlotIndices(FullPresetDetails template) {
    return {for (var i = 0; i < template.slots.length; i++) i};
  }

  void _selectTemplate(FullPresetDetails template) {
    setState(() {
      _selected = template;
      _selectedSlots = _allSlotIndices(template);
    });
    _announce(
      '${template.preset.name} selected. ${template.slots.length} slots selected.',
    );
  }

  Future<void> _applySelected(BuildContext context) async {
    final template = _selected;
    if (_isApplying || template == null || _selectedSlots.isEmpty) return;

    final selected = _selectedSlots.toList()..sort();
    final applyDevice = widget.onApplyDevice;
    if (applyDevice == null) {
      await TemplateApplyDialog.show(
        context,
        database: _database,
        template: template,
        selectedIndices: _selectedSlots,
      );
      return;
    }

    final applyRun = ++_applyRun;
    setState(() => _isApplying = true);
    _announce(
      'Applying ${selected.length} selected ${selected.length == 1 ? 'slot' : 'slots'} from ${template.preset.name}.',
    );
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await applyDevice(template, selected);
      if (!mounted || applyRun != _applyRun) return;
      setState(() => _isApplying = false);
      _announce('Applied template slots.');
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (error) {
      if (!mounted || applyRun != _applyRun) return;
      _announce('Template apply failed.');
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted && applyRun == _applyRun) {
        setState(() => _isApplying = false);
      }
    }
  }

  void _cancelApply() {
    if (!_isApplying) return;
    _applyRun++;
    widget.onCancelDeviceApply?.call();
    setState(() => _isApplying = false);
    _announce('Template apply cancelled.');
  }

  Future<void> _createFromCurrentPreset() async {
    final loader = widget.loadCurrentPresetSource;
    if (loader == null) return;

    final source = await loader();
    if (!mounted) return;
    if (source == null || source.slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No current preset slots to template.')),
      );
      return;
    }

    await CreateTemplateFromPresetDialog.show(
      context,
      database: _database,
      source: source,
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text('Template Manager')),
        actions: [
          IconButton(
            tooltip: 'Refresh templates',
            icon: const Icon(Icons.refresh, semanticLabel: 'Refresh templates'),
            onPressed: _isImporting ? null : _refresh,
          ),
        ],
      ),
      body: _wrapDropTarget(
        FutureBuilder<List<FullPresetDetails>>(
          future: _templatesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Error loading templates: ${snapshot.error}'),
              );
            }

            final templates = snapshot.data ?? const <FullPresetDetails>[];
            if (templates.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text('No templates found.'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(
                            Icons.file_open_outlined,
                            semanticLabel: 'Import template from file',
                          ),
                          label: const Text('Import from file'),
                          onPressed: _loadTemplateFromFile,
                        ),
                        FilledButton.icon(
                          icon: const Icon(
                            Icons.add,
                            semanticLabel: 'New from current preset',
                          ),
                          label: const Text('New from current preset'),
                          onPressed: widget.loadCurrentPresetSource == null
                              ? null
                              : () => _createFromCurrentPreset(),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            if (_selected == null) {
              _selected = templates.first;
              _selectedSlots = _allSlotIndices(_selected!);
            }
            final selected = _selected!;

            return LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                final list = _TemplateManagerList(
                  templates: templates,
                  selectedId: selected.preset.id,
                  canCreateFromCurrentPreset:
                      widget.loadCurrentPresetSource != null,
                  onCreateFromCurrentPreset: () => _createFromCurrentPreset(),
                  canModifySelected: !_isApplying,
                  canImportExport: !_isApplying && !_isImporting,
                  onImportTemplate: _loadTemplateFromFile,
                  onExportSelected: _exportSelectedTemplate,
                  onEditSelected: _editSelectedMetadata,
                  onDeleteSelected: _deleteSelectedTemplate,
                  onSelected: _isApplying ? (_) {} : _selectTemplate,
                );
                final detail = _TemplateManagerDetail(
                  template: selected,
                  selectedSlots: _selectedSlots,
                  isApplying: _isApplying,
                  appliesToDevice: widget.onApplyDevice != null,
                  onApplySelected: () => _applySelected(context),
                  onCancelApply: _cancelApply,
                  onSelectionChanged: (next) {
                    if (_isApplying) return;
                    setState(() => _selectedSlots = next);
                  },
                );

                if (narrow) {
                  return Column(
                    children: [
                      SizedBox(height: 220, child: list),
                      const Divider(height: 1),
                      Expanded(child: detail),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 320, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: detail),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _wrapDropTarget(Widget child) {
    final content = Stack(
      children: [
        child,
        if (_isDragOver)
          Positioned.fill(
            child: Semantics(
              liveRegion: true,
              label: 'Drop target active. Drop template JSON to import.',
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(32),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Drop template JSON to import',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_isImporting)
          Center(
            child: Semantics(
              liveRegion: true,
              label: 'Importing template JSON',
              child: ExcludeSemantics(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );

    if (!_supportsDrop) return content;
    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragOver = true);
        _announce('Drop target active. Drop template JSON to import.');
      },
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: (details) => _importDroppedFiles(details.files),
      child: content,
    );
  }
}

class _TemplateManagerList extends StatelessWidget {
  final List<FullPresetDetails> templates;
  final int selectedId;
  final bool canCreateFromCurrentPreset;
  final VoidCallback onCreateFromCurrentPreset;
  final bool canModifySelected;
  final bool canImportExport;
  final VoidCallback onImportTemplate;
  final VoidCallback onExportSelected;
  final VoidCallback onEditSelected;
  final VoidCallback onDeleteSelected;
  final ValueChanged<FullPresetDetails> onSelected;

  const _TemplateManagerList({
    required this.templates,
    required this.selectedId,
    required this.canCreateFromCurrentPreset,
    required this.onCreateFromCurrentPreset,
    required this.canModifySelected,
    required this.canImportExport,
    required this.onImportTemplate,
    required this.onExportSelected,
    required this.onEditSelected,
    required this.onDeleteSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<FullPresetDetails>>{};
    for (final template in templates) {
      final category = template.preset.category?.trim();
      grouped
          .putIfAbsent(
            category == null || category.isEmpty ? 'Uncategorized' : category,
            () => [],
          )
          .add(template);
    }
    final categories = grouped.keys.toList()..sort();

    return Semantics(
      container: true,
      label:
          'Template list, ${templates.length} ${templates.length == 1 ? 'template' : 'templates'}',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'New from current preset',
                  icon: const Icon(
                    Icons.add,
                    semanticLabel: 'New from current preset',
                  ),
                  onPressed: canCreateFromCurrentPreset
                      ? onCreateFromCurrentPreset
                      : null,
                ),
                IconButton(
                  tooltip: 'Import template from file',
                  icon: const Icon(
                    Icons.file_open_outlined,
                    semanticLabel: 'Import template from file',
                  ),
                  onPressed: canImportExport ? onImportTemplate : null,
                ),
                IconButton(
                  tooltip: 'Export selected template',
                  icon: const Icon(
                    Icons.file_download_outlined,
                    semanticLabel: 'Export selected template',
                  ),
                  onPressed: canImportExport ? onExportSelected : null,
                ),
                IconButton(
                  tooltip: 'Edit metadata',
                  icon: const Icon(
                    Icons.edit_outlined,
                    semanticLabel: 'Edit selected template metadata',
                  ),
                  onPressed: canModifySelected ? onEditSelected : null,
                ),
                IconButton(
                  tooltip: 'Delete template',
                  icon: const Icon(
                    Icons.delete_outline,
                    semanticLabel: 'Delete selected template',
                  ),
                  onPressed: canModifySelected ? onDeleteSelected : null,
                ),
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  label: '${templates.length} templates',
                  child: Text(
                    '${templates.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final category in categories) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Semantics(
                      header: true,
                      child: Text(
                        category,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  for (final template
                      in grouped[category]!..sort(
                        (a, b) => a.preset.name.compareTo(b.preset.name),
                      ))
                    _TemplateListTile(
                      template: template,
                      selected: template.preset.id == selectedId,
                      onTap: () => onSelected(template),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateListTile extends StatelessWidget {
  final FullPresetDetails template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateListTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = TemplateMetadata.fromJsonString(
      template.preset.templateMetadata,
    );
    final firstTag = metadata.tags.isEmpty ? null : metadata.tags.first;
    final semanticParts = <String>[
      template.preset.name,
      '${template.slots.length} ${template.slots.length == 1 ? 'slot' : 'slots'}',
      if ((template.preset.category ?? '').isNotEmpty)
        'category ${template.preset.category}',
      if (firstTag != null) 'tag $firstTag',
      if (selected) 'selected',
    ];

    return Semantics(
      button: true,
      selected: selected,
      label: semanticParts.join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          selected: selected,
          leading: const Icon(Icons.star_outline),
          title: Text(template.preset.name),
          subtitle: Text('${template.slots.length} slots'),
          trailing: firstTag == null
              ? null
              : Chip(
                  label: Text(firstTag),
                  visualDensity: VisualDensity.compact,
                ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _EditTemplateMetadataDialog extends StatefulWidget {
  final FullPresetDetails template;
  final AppDatabase database;

  const _EditTemplateMetadataDialog({
    required this.template,
    required this.database,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FullPresetDetails template,
    required AppDatabase database,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) =>
          _EditTemplateMetadataDialog(template: template, database: database),
    );
  }

  @override
  State<_EditTemplateMetadataDialog> createState() =>
      _EditTemplateMetadataDialogState();
}

class _EditTemplateMetadataDialogState
    extends State<_EditTemplateMetadataDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final TextEditingController _authorController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final metadata = TemplateMetadata.fromJsonString(
      widget.template.preset.templateMetadata,
    );
    _nameController = TextEditingController(text: widget.template.preset.name);
    _categoryController = TextEditingController(
      text: widget.template.preset.category ?? '',
    );
    _descriptionController = TextEditingController(
      text: metadata.description ?? '',
    );
    _tagsController = TextEditingController(text: metadata.tags.join(', '));
    _authorController = TextEditingController(text: metadata.author ?? '');
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

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

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
      await widget.database.presetsDao.updateTemplateMetadata(
        presetId: widget.template.preset.id,
        name: name,
        category: _nullIfEmpty(_categoryController.text),
        templateMetadata: metadata.toJsonString(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty && !_saving;

    return AlertDialog(
      title: Semantics(header: true, child: Text('Edit template metadata')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('edit-template-name'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const ValueKey('edit-template-category'),
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                key: const ValueKey('edit-template-description'),
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                key: const ValueKey('edit-template-tags'),
                controller: _tagsController,
                decoration: const InputDecoration(labelText: 'Tags'),
              ),
              TextField(
                key: const ValueKey('edit-template-author'),
                controller: _authorController,
                decoration: const InputDecoration(labelText: 'Author'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _saving
              ? SizedBox.square(
                  dimension: 18,
                  child: Semantics(
                    liveRegion: true,
                    label: 'Saving template metadata',
                    child: ExcludeSemantics(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : const Icon(
                  Icons.save_outlined,
                  semanticLabel: 'Save template metadata',
                ),
          label: const Text('Save'),
          onPressed: canSave ? _save : null,
        ),
      ],
    );
  }
}

class _TemplateManagerDetail extends StatelessWidget {
  final FullPresetDetails template;
  final Set<int> selectedSlots;
  final bool isApplying;
  final bool appliesToDevice;
  final VoidCallback onApplySelected;
  final VoidCallback? onCancelApply;
  final ValueChanged<Set<int>> onSelectionChanged;

  const _TemplateManagerDetail({
    required this.template,
    required this.selectedSlots,
    required this.isApplying,
    required this.appliesToDevice,
    required this.onApplySelected,
    this.onCancelApply,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = TemplateMetadata.fromJsonString(
      template.preset.templateMetadata,
    );
    final tags = metadata.tags.join(', ');
    final selectedCount = selectedSlots.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                label:
                    '${template.preset.name}, template details, ${template.slots.length} ${template.slots.length == 1 ? 'slot' : 'slots'}',
                child: Text(
                  template.preset.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if ((template.preset.category ?? '').isNotEmpty)
                Text('Category: ${template.preset.category!}'),
              if (tags.isNotEmpty) Chip(label: Text(tags)),
              if ((metadata.author ?? '').isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ExcludeSemantics(
                      child: Icon(Icons.person_outline, size: 18),
                    ),
                    const SizedBox(width: 6),
                    Text(metadata.author!),
                  ],
                ),
            ],
          ),
        ),
        if ((metadata.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(metadata.description!),
          ),
        const Divider(height: 1),
        Expanded(
          child: TemplateSlotSelectionList(
            template: template,
            selectedIndices: selectedSlots,
            onSelectionChanged: onSelectionChanged,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isApplying && appliesToDevice) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Applying $selectedCount selected',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onCancelApply,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.icon(
                icon: isApplying
                    ? SizedBox.square(
                        dimension: 18,
                        child: Semantics(
                          liveRegion: true,
                          label: 'Applying selected template slots',
                          child: ExcludeSemantics(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.playlist_add,
                        semanticLabel: 'Apply selected template slots',
                      ),
                label: const Text('Apply selected'),
                onPressed: selectedSlots.isEmpty || isApplying
                    ? null
                    : onApplySelected,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
