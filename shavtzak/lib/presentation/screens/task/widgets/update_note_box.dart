import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

final DateFormat _bylineFormat = DateFormat('dd/MM/yyyy HH:mm');

/// A task's assignee update in a grey box: the note, wrapped in full, and
/// under it who wrote it and when. The same box in the task, in "המשימות
/// שלי" and in the sheet's lists.
class UpdateNoteBox extends StatelessWidget {
  const UpdateNoteBox({
    super.key,
    required this.task,
    this.boxKey,
    this.trailing,
  });

  final TaskItem task;

  /// A key for the box itself, for tests and focus.
  final Key? boxKey;

  /// Drawn at the end of the box, as the task's edit button.
  final Widget? trailing;

  /// Whether [task] has a note to show.
  static bool hasNote(TaskItem task) =>
      task.assigneeUpdate != null && task.assigneeUpdate!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byline = [
      if (task.assigneeUpdateByName != null) task.assigneeUpdateByName!,
      if (task.assigneeUpdateAt != null)
        _bylineFormat.format(task.assigneeUpdateAt!),
    ].join(', ');
    return Container(
      key: boxKey,
      width: double.infinity,
      padding: EdgeInsetsDirectional.fromSTEB(12, 8, trailing == null ? 12 : 4, 8),
      decoration: BoxDecoration(
        color: TaskStyle.updateBox,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.assigneeUpdate ?? '', style: theme.textTheme.bodyMedium),
                if (byline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    byline,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: TaskStyle.neutralText),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
