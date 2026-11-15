import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/utils/pdf_text_extractor.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as path;

class ChatInputBar extends StatefulWidget {
  final bool isProcessing;
  final bool enabled;
  final void Function(
    String text,
    List<ChatImageAttachment> imageAttachments,
    List<ChatFileAttachment> fileAttachments,
  )
  onSend;
  final VoidCallback onCancel;
  final VoidCallback onSettings;
  final FocusNode? focusNode;

  const ChatInputBar({
    super.key,
    required this.isProcessing,
    this.enabled = true,
    required this.onSend,
    required this.onCancel,
    required this.onSettings,
    this.focusNode,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const _maxAttachments = 6;
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxPdfBytes = 20 * 1024 * 1024;
  static const _maxTextFileBytes = 2 * 1024 * 1024;
  static const _maxPdfTextContentChars = 120000;

  final _controller = TextEditingController();
  FocusNode? _ownedFocusNode;
  bool _isExpanded = false;
  bool _hasTyped = false;
  bool _isDragOver = false;
  double _availableWidth = 0;
  final List<ChatImageAttachment> _imageAttachments = [];
  final List<ChatFileAttachment> _fileAttachments = [];

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkExpansion);
    _controller.addListener(_checkHasTyped);
  }

  void _checkHasTyped() {
    if (!_hasTyped && _controller.text.isNotEmpty) {
      setState(() => _hasTyped = true);
      _controller.removeListener(_checkHasTyped);
    }
  }

  void _checkExpansion() {
    if (_availableWidth <= 0) return;

    // Once expanded, only shrink back when text is cleared (i.e. message sent).
    if (_isExpanded) {
      if (_controller.text.isEmpty) {
        setState(() => _isExpanded = false);
      }
      return;
    }

    final text = _controller.text;
    bool shouldExpand = false;

    if (text.contains('\n')) {
      shouldExpand = true;
    } else {
      const textFieldPadding = 32.0;
      final textWidth = _availableWidth - textFieldPadding;

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: double.infinity);

      shouldExpand = textPainter.width > textWidth;
      textPainter.dispose();
    }

    if (shouldExpand) {
      setState(() => _isExpanded = true);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _imageAttachments.isEmpty && _fileAttachments.isEmpty) {
      return;
    }
    widget.onSend(
      text,
      List.unmodifiable(_imageAttachments),
      List.unmodifiable(_fileAttachments),
    );
    _controller.clear();
    setState(() {
      _imageAttachments.clear();
      _fileAttachments.clear();
    });
    _focusNode.requestFocus();
  }

  Future<void> _attachFiles() async {
    final result = await FilePicker.pickFiles();
    if (!mounted) return;
    for (final file in result) {
      if (!_canAddAttachment()) break;
      final mimeType = _mimeTypeForName(file.name);
      final size = file.lengthSync() ?? await file.length();
      if (!mounted) return;
      if (size == null) {
        _showAttachmentError('Could not determine the size of ${file.name}.');
        continue;
      }
      if (mimeType.startsWith('image/')) {
        if (size > _maxImageBytes) {
          _showAttachmentError('${file.name} is larger than 10 MB.');
          continue;
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        _addImage(bytes, name: file.name);
        continue;
      }
      if (!_isAttachableFileMime(mimeType)) {
        _showAttachmentError(
          '${file.name} is not a supported attachment type.',
        );
        continue;
      }
      final maxBytes = _maxBytesForMime(mimeType);
      if (size > maxBytes) {
        _showAttachmentError(
          '${file.name} is larger than ${_formatBytes(maxBytes)}.',
        );
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _addFile(bytes, name: file.name, mimeType: mimeType);
    }
  }

  Future<void> _handlePasteShortcut() async {
    final bytes = await Pasteboard.image;
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty && _canAddAttachment()) {
      _addImage(bytes, name: 'clipboard.png');
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _replaceSelection(data!.text!);
  }

  void _replaceSelection(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final replacement = selection.isValid
        ? value.text.replaceRange(selection.start, selection.end, text)
        : value.text + text;
    final offset = selection.isValid
        ? selection.start + text.length
        : replacement.length;
    _controller.value = value.copyWith(
      text: replacement,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  Future<void> _attachDroppedFiles(List<XFile> files) async {
    if (!widget.enabled || widget.isProcessing) return;
    for (final file in files) {
      if (!_canAddAttachment()) break;
      final fileName = file.name.isNotEmpty
          ? file.name
          : path.basename(file.path);
      final mimeType = _mimeTypeForName(fileName);
      final size = await file.length();
      if (!mounted) return;

      if (mimeType.startsWith('image/')) {
        if (size > _maxImageBytes) {
          _showAttachmentError('$fileName is larger than 10 MB.');
          continue;
        }
        _addImage(await file.readAsBytes(), name: fileName);
        continue;
      }

      if (!_isAttachableFileMime(mimeType)) {
        _showAttachmentError('$fileName is not a supported attachment type.');
        continue;
      }
      final maxBytes = _maxBytesForMime(mimeType);
      if (size > maxBytes) {
        _showAttachmentError(
          '$fileName is larger than ${_formatBytes(maxBytes)}.',
        );
        continue;
      }
      _addFile(await file.readAsBytes(), name: fileName, mimeType: mimeType);
    }
  }

  void _addImage(List<int> bytes, {String? name}) {
    if (bytes.length > _maxImageBytes) {
      _showAttachmentError('${name ?? 'Image'} is larger than 10 MB.');
      return;
    }
    final normalized = _normalizeImageBytes(bytes);
    if (normalized == null) {
      _showAttachmentError('${name ?? 'Image'} is not a supported image.');
      return;
    }
    final extension = _imageExtensionForMime(normalized.mimeType);
    final fileName = _imageNameWithExtension(name ?? 'image$extension');
    setState(() {
      _imageAttachments.add(
        ChatImageAttachment(
          data: base64Encode(normalized.bytes),
          mimeType: normalized.mimeType,
          name: fileName,
        ),
      );
    });
  }

  void _addFile(
    List<int> bytes, {
    required String name,
    required String mimeType,
  }) {
    String? textContent;
    if (mimeType == 'application/pdf') {
      final extracted = extractPdfText(bytes).trim();
      if (extracted.isNotEmpty) {
        textContent = _truncateAttachmentText(
          extracted,
          _maxPdfTextContentChars,
        );
      }
    } else if (_isTextFileMime(mimeType)) {
      try {
        textContent = utf8.decode(bytes);
      } on FormatException {
        _showAttachmentError('$name is not valid UTF-8 text.');
        return;
      }
    }
    setState(() {
      _fileAttachments.add(
        ChatFileAttachment(
          name: name,
          data: base64Encode(bytes),
          mimeType: mimeType,
          sizeBytes: bytes.length,
          textContent: textContent,
        ),
      );
    });
  }

  bool _canAddAttachment() {
    if (_imageAttachments.length + _fileAttachments.length < _maxAttachments) {
      return true;
    }
    _showAttachmentError('Attach up to $_maxAttachments files per message.');
    return false;
  }

  bool _isAttachableFileMime(String mimeType) {
    return mimeType == 'application/pdf' || _isTextFileMime(mimeType);
  }

  bool _isTextFileMime(String mimeType) {
    return mimeType == 'application/json' || mimeType.startsWith('text/');
  }

  int _maxBytesForMime(String mimeType) {
    return mimeType == 'application/pdf' ? _maxPdfBytes : _maxTextFileBytes;
  }

  String _truncateAttachmentText(String content, int maxChars) {
    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n\n[truncated: ${content.length - maxChars} chars omitted; use local workspace search/read tools for targeted sections]';
  }

  ({List<int> bytes, String mimeType})? _normalizeImageBytes(List<int> bytes) {
    final sniffed = _sniffImageMime(bytes);
    if (sniffed != null) return (bytes: bytes, mimeType: sniffed);

    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return null;
    final pngBytes = img.encodePng(decoded);
    return (bytes: pngBytes, mimeType: 'image/png');
  }

  String? _sniffImageMime(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'image/gif';
    }
    return null;
  }

  String _imageExtensionForMime(String mimeType) {
    return switch (mimeType) {
      'image/jpeg' => '.jpg',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      _ => '.png',
    };
  }

  String _imageNameWithExtension(String name) {
    final ext = path.extension(name).toLowerCase();
    if (ext == '.png' ||
        ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.webp' ||
        ext == '.gif') {
      return name;
    }
    return '$name.png';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${bytes ~/ (1024 * 1024)} MB';
    return '${bytes ~/ 1024} KB';
  }

  void _showAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _removeImage(int index) {
    setState(() => _imageAttachments.removeAt(index));
  }

  void _removeFile(int index) {
    setState(() => _fileAttachments.removeAt(index));
  }

  String _mimeTypeForName(String fileName) {
    switch (path.extension(fileName).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.json':
      case '.ntpreset':
      case '.preset':
        return 'application/json';
      case '.txt':
      case '.md':
      case '.markdown':
      case '.csv':
      case '.yaml':
      case '.yml':
      case '.toml':
      case '.xml':
      case '.lua':
      case '.dart':
      case '.js':
      case '.ts':
      case '.py':
      case '.sh':
        return 'text/plain';
      case '.syx':
      case '.o':
      case '.wasm':
      case '.bin':
      case '.dat':
        return 'application/octet-stream';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_checkExpansion);
    _controller.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _availableWidth =
                constraints.maxWidth -
                4 // SizedBox before send button
                -
                48; // send/cancel IconButton width
            _availableWidth -= 40; // attachment IconButton width
            if (!_isExpanded) {
              _availableWidth -= 40; // settings IconButton width
            }
            return Row(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _isExpanded
                      ? const SizedBox.shrink()
                      : Semantics(
                          label: 'Chat settings',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            tooltip: 'Chat settings',
                            onPressed: widget.onSettings,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                ),
                Semantics(
                  label: 'Attach image or file',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.attach_file, size: 20),
                    tooltip: 'Attach image or file',
                    onPressed: !widget.enabled || widget.isProcessing
                        ? null
                        : _attachFiles,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_imageAttachments.isNotEmpty)
                        _ImageAttachmentStrip(
                          attachments: _imageAttachments,
                          onRemove: _removeImage,
                        ),
                      if (_fileAttachments.isNotEmpty)
                        _FileAttachmentStrip(
                          attachments: _fileAttachments,
                          onRemove: _removeFile,
                        ),
                      Shortcuts(
                        shortcuts: {
                          LogicalKeySet(LogicalKeyboardKey.enter):
                              const _SendIntent(),
                          SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                              const _PasteIntent(),
                          SingleActivator(
                            LogicalKeyboardKey.keyV,
                            control: true,
                          ): const _PasteIntent(),
                          for (final key
                              in _digitKeys) ...<SingleActivator, Intent>{
                            SingleActivator(key):
                                const DoNothingAndStopPropagationTextIntent(),
                            SingleActivator(key, shift: true):
                                const DoNothingAndStopPropagationTextIntent(),
                          },
                          for (final activator
                              in KeyBindingService().globalShortcuts.keys)
                            activator:
                                const DoNothingAndStopPropagationTextIntent(),
                        },
                        child: Actions(
                          actions: {
                            _SendIntent: CallbackAction<_SendIntent>(
                              onInvoke: (_) {
                                if (!widget.isProcessing) _handleSend();
                                return null;
                              },
                            ),
                            _PasteIntent: CallbackAction<_PasteIntent>(
                              onInvoke: (_) {
                                if (!widget.isProcessing) {
                                  unawaited(_handlePasteShortcut());
                                }
                                return null;
                              },
                            ),
                          },
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            decoration: InputDecoration(
                              hintText: _hasTyped
                                  ? null
                                  : 'Ask about your preset...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              isDense: true,
                            ),
                            enabled: widget.enabled && !widget.isProcessing,
                            textInputAction: TextInputAction.send,
                            onSubmitted: !widget.enabled || widget.isProcessing
                                ? null
                                : (_) => _handleSend(),
                            maxLines: 3,
                            minLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.isProcessing)
                  Semantics(
                    label: 'Cancel',
                    button: true,
                    child: IconButton(
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: 'Cancel',
                      onPressed: widget.onCancel,
                    ),
                  )
                else
                  Semantics(
                    label: 'Send message',
                    button: true,
                    child: IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip: 'Send',
                      onPressed: widget.enabled ? _handleSend : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return DropTarget(
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        onDragDone: (details) async {
          setState(() => _isDragOver = false);
          await _attachDroppedFiles(details.files);
        },
        child: Stack(
          children: [
            content,
            if (_isDragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return content;
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _ImageAttachmentStrip extends StatelessWidget {
  final List<ChatImageAttachment> attachments;
  final ValueChanged<int> onRemove;

  const _ImageAttachmentStrip({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 58,
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  base64Decode(attachment.data),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: const CircleBorder(),
                  child: Tooltip(
                    message: 'Remove image attachment',
                    child: Semantics(
                      label: 'Remove image attachment',
                      button: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onRemove(index),
                        child: Icon(
                          Icons.cancel,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FileAttachmentStrip extends StatelessWidget {
  final List<ChatFileAttachment> attachments;
  final ValueChanged<int> onRemove;

  const _FileAttachmentStrip({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return InputChip(
            avatar: Icon(
              attachment.mimeType == 'application/pdf'
                  ? Icons.picture_as_pdf
                  : Icons.description_outlined,
              size: 16,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
            onDeleted: () => onRemove(index),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
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
