import 'package:flutter/material.dart';

/// Edit a task's assignee update: the short, shared status note.
///
/// Returns the trimmed text, an empty string when the note should be cleared,
/// or null when the dialog was cancelled.
Future<String?> showAssigneeUpdateDialog(
  BuildContext context, {
  String? initialText,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AssigneeUpdateDialog(initialText: initialText ?? ''),
  );
}

class _AssigneeUpdateDialog extends StatefulWidget {
  const _AssigneeUpdateDialog({required this.initialText});

  final String initialText;

  @override
  State<_AssigneeUpdateDialog> createState() => _AssigneeUpdateDialogState();
}

class _AssigneeUpdateDialogState extends State<_AssigneeUpdateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('עדכון סטטוס'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const Key('assignee-update-text'),
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'מה מצב המשימה?',
              helperText: 'העדכון מחליף את הקודם. השארת השדה ריק מוחקת אותו.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('assignee-update-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          FilledButton(
            key: const Key('assignee-update-save'),
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
  }
}
