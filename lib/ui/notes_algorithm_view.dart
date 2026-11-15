import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/firmware_version.dart';

class NotesAlgorithmView extends StatefulWidget {
  final Slot slot;

  const NotesAlgorithmView({
    super.key,
    required this.slot,
    required FirmwareVersion firmwareVersion,
  });

  @override
  State<NotesAlgorithmView> createState() => _NotesAlgorithmViewState();
}

class _NotesAlgorithmViewState extends State<NotesAlgorithmView> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _textController;
  late final FocusNode _editorFocusNode;
  final int _maxLinesCount = 7;
  final int _maxLineLength = 31;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _getCurrentText());
    _editorFocusNode = FocusNode(debugLabel: 'NotesAlgorithmView.editor');
  }

  @override
  void dispose() {
    _textController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NotesAlgorithmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update text controller if the slot data changed and we're not editing
    if (!_isEditing && oldWidget.slot != widget.slot) {
      _textController.text = _getCurrentText();
    }
  }

  String _getCurrentText() {
    // Combine all value strings into a single text, preserving empty lines
    // Parameters 1-7 correspond to indices 1-7 in valueStrings
    final lines = <String>[];
    for (
      int i = 1;
      i <= _maxLinesCount && i < widget.slot.valueStrings.length;
      i++
    ) {
      final line = widget.slot.valueStrings[i].value;
      lines.add(line); // Don't filter out empty lines
    }

    // Remove trailing empty lines for cleaner editing experience
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }

    return lines.join('\n');
  }

  List<String> _splitTextIntoLines(String text) {
    final lines = <String>[];

    if (text.trim().isEmpty) {
      return lines;
    }

    // Split by user line breaks first
    final userLines = text.split('\n');

    for (final userLine in userLines) {
      // Stop if we've already reached the maximum number of lines
      if (lines.length >= _maxLinesCount) {
        break;
      }

      // Clean up the current user line (collapse multiple spaces)
      final cleanLine = userLine.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleanLine.isEmpty) {
        // User entered an empty line - add it as empty
        lines.add('');
        continue;
      }

      // If the line fits within the character limit, add it as-is
      if (cleanLine.length <= _maxLineLength) {
        lines.add(cleanLine);
      } else {
        // Line is too long, need to wrap it
        final words = cleanLine.split(' ');
        String currentLine = '';

        for (final word in words) {
          // Check if adding this word would exceed line length
          final testLine = currentLine.isEmpty ? word : '$currentLine $word';

          if (testLine.length <= _maxLineLength) {
            currentLine = testLine;
          } else {
            // Current line is full, start a new one
            if (currentLine.isNotEmpty) {
              lines.add(currentLine);
              currentLine = word;
            } else {
              // Single word is too long, truncate it
              lines.add(word.substring(0, _maxLineLength));
              currentLine = '';
            }

            // Stop if we've reached the maximum number of lines
            if (lines.length >= _maxLinesCount) {
              break;
            }
          }
        }

        // Add the last line if it's not empty and we haven't exceeded max lines
        if (currentLine.isNotEmpty && lines.length < _maxLinesCount) {
          lines.add(currentLine);
        }

        // Stop processing if we've reached the line limit
        if (lines.length >= _maxLinesCount) {
          break;
        }
      }
    }

    return lines;
  }

  bool _validateText(String text) {
    final lines = _splitTextIntoLines(text);

    // Check if we have too many lines
    if (lines.length > _maxLinesCount) {
      _showError(
        'Text uses ${lines.length} lines, but only $_maxLinesCount lines are supported',
      );
      return false;
    }

    // Check if any individual line exceeds the character limit
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].length > _maxLineLength) {
        _showError(
          'Line ${i + 1} is ${lines[i].length} characters, but maximum is $_maxLineLength',
        );
        return false;
      }
    }

    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _saveText() async {
    final text = _textController.text;

    if (!_validateText(text)) {
      return;
    }

    // Prevent multiple simultaneous save operations
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Saving notes...',
      TextDirection.ltr,
    );

    final lines = _splitTextIntoLines(text);
    final cubit = context.read<DistingCubit>();

    try {
      // Set each line parameter (parameters 1-7 are the text lines) with timeout
      for (int i = 0; i < _maxLinesCount; i++) {
        final lineText = i < lines.length ? lines[i] : '';

        // Add timeout to prevent hanging
        await cubit
            .updateParameterString(
              algorithmIndex: widget.slot.algorithm.algorithmIndex,
              parameterNumber: i + 1, // Parameters 1-7, not 0-6
              value: lineText,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Timeout saving line ${i + 1}');
              },
            );
      }

      // Refresh the slot data from the module to ensure UI is up to date
      await cubit
          .refreshSlot(widget.slot.algorithm.algorithmIndex)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              // Don't fail the save if refresh times out, just log it
            },
          );

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Notes saved',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        _showError('Failed to save text: $e');
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Failed to save notes',
          TextDirection.ltr,
        );
      }
    }
  }

  void _cancelEdit() {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isEditing = false;
      _textController.text = _getCurrentText();
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Edit cancelled',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DistingCubit, DistingState>(
      builder: (context, state) {
        // Check if editing is supported based on firmware version
        final bool supportsEditing =
            state is DistingStateSynchronized &&
            state.firmwareVersion.hasSetPropertyStringSupport; // 1.10+ firmware

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Edit/Save/Cancel buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_isEditing && supportsEditing) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isEditing = true;
                          });
                          // autofocus is unreliable when an ancestor Focus
                          // already holds primary focus; grab it explicitly.
                          _editorFocusNode.requestFocus();
                          SemanticsService.sendAnnouncement(
                            View.of(context),
                            'Editing mode. Enter your notes text.',
                            TextDirection.ltr,
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ] else if (!supportsEditing && !_isEditing) ...[
                      // Show a disabled button with tooltip for older firmware
                      Tooltip(
                        message: 'Text editing requires firmware 1.10 or later',
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                        ),
                      ),
                    ] else if (_isEditing) ...[
                      TextButton(
                        onPressed: _isSaving ? null : _cancelEdit,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveText,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Saving...' : 'Save'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Text display or editor
                Expanded(
                  child: _isEditing ? _buildTextEditor() : _buildTextDisplay(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextDisplay() {
    final allText = <String>[];
    for (
      int i = 1;
      i <= _maxLinesCount && i < widget.slot.valueStrings.length;
      i++
    ) {
      allText.add(widget.slot.valueStrings[i].value.trim());
    }
    final combinedText = allText.where((l) => l.isNotEmpty).join('. ');

    return Semantics(
      label: combinedText.isEmpty ? 'Notes: empty' : 'Notes: $combinedText',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              int i = 1;
              i <= _maxLinesCount && i < widget.slot.valueStrings.length;
              i++
            )
              Builder(
                builder: (context) {
                  final valueToDisplay = widget.slot.valueStrings[i].value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      valueToDisplay.trim(),
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructions
        Text(
          'Enter text with up to $_maxLinesCount lines, $_maxLineLength characters per line. Press Enter to create line breaks.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),

        // Text field
        Expanded(
          child: Shortcuts(
            shortcuts: {
              for (final key in _digitKeys) ...<SingleActivator, Intent>{
                SingleActivator(key):
                    const DoNothingAndStopPropagationTextIntent(),
                SingleActivator(key, shift: true):
                    const DoNothingAndStopPropagationTextIntent(),
              },
              for (final activator in KeyBindingService().globalShortcuts.keys)
                activator: const DoNothingAndStopPropagationTextIntent(),
            },
            child: TextField(
              controller: _textController,
              focusNode: _editorFocusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Enter your notes here...\n\nPress Enter to create line breaks.\nLong lines will wrap automatically.',
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                ),
              ),
              inputFormatters: [
                // Allow reasonable input length for editing
                LengthLimitingTextInputFormatter(500),
              ],
            ),
          ),
        ),

        // Real-time feedback with line preview
        StreamBuilder<String>(
          stream: Stream.periodic(
            const Duration(milliseconds: 300),
            (_) => _textController.text,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            final text = snapshot.data!;
            final lines = _splitTextIntoLines(text);
            final isValidLines = lines.length <= _maxLinesCount;

            // Check if any line is too long
            final hasLongLines = lines.any(
              (line) => line.length > _maxLineLength,
            );
            final isValid = isValidLines && !hasLongLines;

            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line count
                  Row(
                    children: [
                      Text(
                        '${lines.length}/$_maxLinesCount lines',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isValidLines
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (hasLongLines) ...[
                        const SizedBox(width: 16),
                        Text(
                          'Some lines too long',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                    ],
                  ),

                  // Line preview if there are lines
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Preview:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline
                              .withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < lines.length; i++)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Line ${i + 1}: ${lines[i].isEmpty ? '(empty)' : lines[i]}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontFamily: 'monospace',
                                          color:
                                              (i >= _maxLinesCount ||
                                                  lines[i].length >
                                                      _maxLineLength)
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                Text(
                                  '(${lines[i].length}/$_maxLineLength)',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: lines[i].length > _maxLineLength
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.7),
                                      ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Warning if invalid
                  if (!isValid) ...[
                    const SizedBox(height: 8),
                    Text(
                      !isValidLines
                          ? 'Too many lines - only the first $_maxLinesCount will be saved'
                          : 'Lines too long - they will be wrapped or truncated',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

const _digitKeys = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];
