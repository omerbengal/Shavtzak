import 'package:flutter/material.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';

/// Edit a task's assignee update: the short, shared status note.
///
/// Saves the trimmed text through [onSave]; an empty string clears the note.
/// The dialog stays open, with a spinner on the save button, until that
/// answers: it closes on success and shows the failure otherwise, so the text
/// is not lost.
Future<void> showAssigneeUpdateDialog(
  BuildContext context, {
  String? initialText,
  required Future<CrudActionResult> Function(String text) onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AssigneeUpdateDialog(
      initialText: initialText ?? '',
      onSave: onSave,
    ),
  );
}

class _AssigneeUpdateDialog extends StatefulWidget {
  const _AssigneeUpdateDialog({
    required this.initialText,
    required this.onSave,
  });

  final String initialText;
  final Future<CrudActionResult> Function(String text) onSave;

  @override
  State<_AssigneeUpdateDialog> createState() => _AssigneeUpdateDialogState();
}

class _AssigneeUpdateDialogState extends State<_AssigneeUpdateDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _isSaving = false;
  String? _saveError;

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

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    final result = await widget.onSave(_controller.text.trim());
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSaving = false;
      _saveError = result.message ?? 'השמירה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      // A save in flight cannot be walked away from with the back button.
      child: PopScope(
        canPop: !_isSaving,
        child: AlertDialog(
          title: const Text('עדכון סטטוס'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('assignee-update-text'),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  // Locked while saving: what was sent is what stays on screen.
                  readOnly: _isSaving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'מה מצב המשימה?',
                    helperText:
                        'העדכון מחליף את הקודם. השארת השדה ריק מוחקת אותו.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _saveError!,
                    key: const Key('assignee-update-error'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('assignee-update-cancel'),
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              key: const Key('assignee-update-save'),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('שמירה'),
            ),
          ],
        ),
      ),
    );
  }
}
