import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/constraint_labels.dart';
import '../../../../domain/entities/team_member.dart';

/// What the admin chose in [showPendingConstraintAssignDialog].
enum PendingConstraintAssignChoice { assign, assignAndApprove }

/// Asks before assigning [member], whose pending [constraints] block the
/// event. Null when the admin cancels (or dismisses the dialog).
Future<PendingConstraintAssignChoice?> showPendingConstraintAssignDialog({
  required BuildContext context,
  required TeamMember member,
  required List<DateConstraint> constraints,
}) {
  return showDialog<PendingConstraintAssignChoice>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.priority_high, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(child: Text('מגבלה ממתינה לאישור')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ל${member.name} יש מגבלה שעדיין לא אושרה בזמן האירוע:'),
            const SizedBox(height: 8),
            for (final constraint in constraints)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _keepTimeRangesLtr(constraintShortLabel(constraint)),
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (constraint.note?.trim().isNotEmpty == true)
                      Text(
                        constraint.note!.trim(),
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text('לשבץ בכל זאת?'),
          ],
        ),
        // Three buttons do not fit one row on a phone, and the dialog's own
        // overflow wraps them unevenly: stack them full-width, main one first.
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  Logger.action(
                      'tap:pendingConstraintAssign:assignAndApprove');
                  Navigator.of(context)
                      .pop(PendingConstraintAssignChoice.assignAndApprove);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('שבץ ואשר מגבלה'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Logger.action('tap:pendingConstraintAssign:assign');
                  Navigator.of(context)
                      .pop(PendingConstraintAssignChoice.assign);
                },
                child: const Text('שבץ בלי לאשר'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  Logger.action('tap:pendingConstraintAssign:cancel');
                  Navigator.of(context).pop();
                },
                child: const Text('ביטול'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Wraps each "16:00–20:00" in a left-to-right isolate, so a right-to-left
/// line does not draw it as "20:00–16:00".
String _keepTimeRangesLtr(String text) => text.replaceAllMapped(
      RegExp(r'\d{1,2}:\d{2}\s*–\s*\d{1,2}:\d{2}'),
      (m) => '\u2066${m[0]}\u2069',
    );
