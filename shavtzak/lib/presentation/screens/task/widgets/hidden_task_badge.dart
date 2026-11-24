import 'package:flutter/material.dart';

import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

/// The "מוסתרת" chip a manager sees next to a hidden task's title. Team
/// members never get a hidden task, so they never see it.
class HiddenTaskBadge extends StatelessWidget {
  const HiddenTaskBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: TaskStyle.hiddenChip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'מוסתרת',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A hidden task's row sits on a grey background, so it reads as "not out
/// yet" at a glance. [Ink] keeps the row's tap ripple visible on it.
Widget greyIfHidden(TaskItem task, Widget child) => task.isHidden
    ? Ink(color: TaskStyle.hiddenRow, child: child)
    : child;

/// The eye button that hides a task or shows it again. The icon is the
/// task's state, not the action (Omer, msg 6357): a plain eye = visible to
/// the team, a crossed-out eye = hidden. The tooltip names the action.
class HideTaskButton extends StatelessWidget {
  const HideTaskButton({
    super.key,
    required this.task,
    required this.onPressed,
    this.compact = false,
  });

  final TaskItem task;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('task-hide-${task.id}'),
      tooltip: task.isHidden ? 'הצגה לצוות' : 'הסתרה מהצוות',
      visualDensity: compact ? VisualDensity.compact : null,
      icon: Icon(
        task.isHidden ? Icons.visibility_off : Icons.visibility,
        color: TaskStyle.hiddenChip,
      ),
      onPressed: onPressed,
    );
  }
}
