import 'package:flutter/material.dart';

/// The admin's choice when prompted by [showUnsavedChangesDialog] while
/// leaving the assignments tab/screen with unsaved staged changes. See
/// docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md
/// ("Leave-guard").
enum LeaveDecision { save, leave, cancel }

/// Shows the "unsaved changes" leave-guard reminder. This is a **courtesy**
/// prompt, not data-protection — staged changes are already mirrored to the
/// browser cache and survive an accidental close/refresh, so `leave` never
/// loses anything.
///
/// Returns the admin's [LeaveDecision], or `null` if the dialog was
/// dismissed without tapping a button (e.g. barrier tap) — callers should
/// treat `null` the same as [LeaveDecision.cancel] (stay put).
Future<LeaveDecision?> showUnsavedChangesDialog(
  BuildContext context, {
  required int count,
}) {
  return showDialog<LeaveDecision>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('שינויי שיבוצים לא נשמרו'),
        content: Text('יש לך $count שינויים שלא נשמרו.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(LeaveDecision.cancel),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(LeaveDecision.leave),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('צא בלי לשמור'),
                Text(
                  'השינויים לא נמחקים, ניתן לשמור אחר כך',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(LeaveDecision.save),
            child: const Text('שמור והמשך'),
          ),
        ],
      ),
    ),
  );
}
