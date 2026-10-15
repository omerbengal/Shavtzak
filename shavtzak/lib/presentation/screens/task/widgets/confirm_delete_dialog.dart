import 'package:flutter/material.dart';

import '../../../../core/utils/crud_action_result.dart';

/// Asks before deleting, then stays open with a spinner on the delete button
/// until [onDelete] answers: it closes on success and shows the failure
/// otherwise.
///
/// [keyPrefix] names the buttons `<prefix>-cancel` and `<prefix>-confirm` and
/// the error `<prefix>-error`.
Future<void> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String keyPrefix,
  required Future<CrudActionResult> Function() onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ConfirmDeleteDialog(
      title: title,
      message: message,
      keyPrefix: keyPrefix,
      onDelete: onDelete,
    ),
  );
}

class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({
    required this.title,
    required this.message,
    required this.keyPrefix,
    required this.onDelete,
  });

  final String title;
  final String message;
  final String keyPrefix;
  final Future<CrudActionResult> Function() onDelete;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  bool _isDeleting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final result = await widget.onDelete();
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isDeleting = false;
      _error = result.message ?? 'המחיקה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefix = widget.keyPrefix;
    return Directionality(
      textDirection: TextDirection.rtl,
      // A delete in flight cannot be walked away from with the back button.
      child: PopScope(
        canPop: !_isDeleting,
        child: AlertDialog(
          title: Text(widget.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: Key('$prefix-error'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: Key('$prefix-cancel'),
              onPressed:
                  _isDeleting ? null : () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              key: Key('$prefix-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: _isDeleting ? null : _delete,
              child: _isDeleting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('מחיקה'),
            ),
          ],
        ),
      ),
    );
  }
}
