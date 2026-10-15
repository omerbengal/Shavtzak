import 'package:flutter/material.dart';

/// Asks whether to leave a form that holds unsaved changes. True means leave.
///
/// [keyPrefix] names the two buttons `<prefix>-discard-stay` and
/// `<prefix>-discard-leave`, so each form's tests can find its own.
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  required String keyPrefix,
}) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('שינויים לא נשמרו'),
        content: const Text('האם אתה בטוח שברצונך לצאת? השינויים לא יישמרו.'),
        actions: [
          TextButton(
            key: Key('$keyPrefix-discard-stay'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('חזרה לעריכה'),
          ),
          TextButton(
            key: Key('$keyPrefix-discard-leave'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('צא ללא שמירה'),
          ),
        ],
      ),
    ),
  );
  return leave == true;
}
