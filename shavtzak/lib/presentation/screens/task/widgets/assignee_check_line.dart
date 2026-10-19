import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../task_style.dart';

/// The managers' one pre-event check, as one red line: tasks whose assignee
/// was taken off the event. Shown only when there is something to fix.
class AssigneeCheckLine extends StatelessWidget {
  const AssigneeCheckLine({
    super.key,
    required this.count,
    required this.onTap,
    this.wide = false,
  });

  final int count;
  final VoidCallback onTap;

  /// On a computer the line sits in the toolbar and says what it is for.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = hebrewCount(
      count,
      one: 'משימה אחת של מי שכבר לא משובץ לאירוע',
      many: 'משימות של מי שכבר לא משובץ לאירוע',
    );
    return Material(
      color: TaskStyle.lateLight,
      child: InkWell(
        key: const Key('assignee-check'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.person_off_outlined,
                size: 18,
                color: TaskStyle.lateDark,
              ),
              const SizedBox(width: 8),
              if (wide)
                const Text(
                  'לבדיקה: ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TaskStyle.lateDark,
                  ),
                ),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TaskStyle.lateDark,
                  ),
                ),
              ),
              const Icon(Icons.chevron_left, color: TaskStyle.lateDark),
            ],
          ),
        ),
      ),
    );
  }
}
