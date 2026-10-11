import 'package:flutter/material.dart';

import '../../../../core/utils/rtl_text_field_utils.dart';

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
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    // The field autofocuses onto an existing note, which is exactly the case
    // the RTL caret fix exists for: Hebrew mixed with digits.
    _focusNode = createRtlCursorFixedFocusNode(_controller);
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
            focusNode: _focusNode,
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
