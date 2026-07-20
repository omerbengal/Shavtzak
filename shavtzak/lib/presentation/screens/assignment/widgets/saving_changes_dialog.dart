import 'package:flutter/material.dart';

/// Blocking "saving…" feedback shown while [SaveStagedChanges] is in flight.
///
/// Used by the assignments tab-switch leave-guard
/// (`SwipeablePageView._onBottomNavTapped`, the `LeaveDecision.save`
/// branch) so choosing "שמור והמשך" gives the same visual feedback as the
/// on-screen Save button's mutation overlay (see
/// assignment_list_screen.dart's `_buildMutationDialogOverlay` /
/// `_startMutation('שומר שינויים...')`).
///
/// This widget only renders the dialog's content — it is non-dismissible by
/// virtue of how the caller shows it (`showDialog(barrierDismissible:
/// false, ...)`), and the caller is responsible for popping it once the
/// save completes.
class SavingChangesDialog extends StatelessWidget {
  const SavingChangesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Text('שומר שינויים...'),
          ],
        ),
      ),
    );
  }
}
