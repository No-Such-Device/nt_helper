import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

class RenameSlotDialog extends StatefulWidget {
  final String initialName;

  const RenameSlotDialog({super.key, required this.initialName});

  @override
  State<RenameSlotDialog> createState() => _RenameSlotDialogState();
}

class _RenameSlotDialogState extends State<RenameSlotDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCancel() {
    // Return null to indicate “no new name”
    Navigator.of(context).pop(null);
  }

  void _onConfirm() {
    // Return the typed name
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Slot'),
      content: DigitShortcutBlocker(
        child: TextField(
          controller: _controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
          onSubmitted: (_) => _onConfirm(),
        ),
      ),
      actions: [
        TextButton(onPressed: _onCancel, child: const Text('CANCEL')),
        ElevatedButton(onPressed: _onConfirm, child: const Text('OK')),
      ],
    );
  }
}
