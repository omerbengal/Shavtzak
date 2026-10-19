import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';
import 'assignee_chips.dart';

final DateFormat _timeFormat = DateFormat('HH:mm');
final DateFormat _dayTimeFormat = DateFormat('dd/MM HH:mm');

/// One task in a list: in the sheet, under a stage or in filter and search
/// results.
///
/// Display-only: ticking, calling and opening are reported through the
/// callbacks, and the result comes back as a new [task]. Ticking a row never
/// moves it; the list decides the order.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.viewerId,
    required this.canTick,
    required this.onSetComplete,
    required this.onOpen,
    required this.onCallPhone,
    this.removedAssigneeIds = const [],
  });

  final TaskItem task;

  /// The current time, injected so the colour rules can be tested.
  final DateTime now;

  /// Who is looking: their own chip is drawn in [TaskStyle.mine].
  final String viewerId;

  /// Whether the viewer may complete the task from its tick box.
  final bool canTick;

  final ValueChanged<bool> onSetComplete;
  final VoidCallback onOpen;
  final ValueChanged<String> onCallPhone;

  /// Assignees no longer on the event, from the managers' check. They show
  /// struck through in red; one without a member record still gets a chip.
  final List<String> removedAssigneeIds;

  @override
  Widget build(BuildContext context) {
    final isLate = taskDueStatus(task, now) == TaskDueStatus.overdue;
    final hasChips =
        AssigneeChips.shownIds(task, removedAssigneeIds).isNotEmpty;
    final update = _updateLine();
    return InkWell(
      key: Key('task-row-${task.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 40, child: _buildLeading()),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleLine(isLate),
                  const SizedBox(height: 2),
                  _buildTime(isLate),
                  if (hasChips) ...[
                    const SizedBox(height: 6),
                    AssigneeChips(
                      task: task,
                      viewerId: viewerId,
                      removedAssigneeIds: removedAssigneeIds,
                      onCallPhone: onCallPhone,
                      keyPrefix: 'task-row',
                    ),
                  ],
                  if (update != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      update,
                      key: Key('task-row-update-${task.id}'),
                      style: const TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        color: TaskStyle.neutralText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tick box for a task without subtasks; its subtasks done over total
  /// for one with them, which completes by itself once they all are.
  Widget _buildLeading() {
    if (task.hasSubtasks) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Center(
          child: Text(
            ltr('${task.doneSubtaskCount}/${task.subtasks.length}'),
            style: TextStyle(
              fontSize: TaskStyle.rowMetaSize,
              fontWeight: FontWeight.w600,
              color: task.isComplete ? TaskStyle.doneDark : TaskStyle.neutralText,
            ),
          ),
        ),
      );
    }
    return Checkbox(
      key: Key('task-row-tick-${task.id}'),
      value: task.isComplete,
      onChanged: canTick ? (value) => onSetComplete(value ?? false) : null,
    );
  }

  Widget _buildTitleLine(bool isLate) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Wraps in full: a name never collapses into "…".
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: TaskStyle.rowTitleSize,
                fontWeight: FontWeight.w600,
                decoration: task.isComplete
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: task.isComplete ? TaskStyle.faintText : null,
              ),
            ),
          ),
          if (isLate) ...[
            const SizedBox(width: 6),
            Container(
              key: Key('task-row-late-${task.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: TaskStyle.late,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'באיחור',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The report time, orange in the next half hour and red once late; never
  /// a countdown.
  Widget _buildTime(bool isLate) {
    final isSoon = isDueSoon(task, now);
    final color = isLate
        ? TaskStyle.lateDark
        : (isSoon ? TaskStyle.soonDark : TaskStyle.neutralText);
    return Text(
      task.hasAssemblyTime
          ? 'התייצבות ${ltr(task.assemblyTime!)}'
          : 'ללא שעה',
      key: Key('task-row-time-${task.id}'),
      style: TextStyle(
        fontSize: TaskStyle.rowMetaSize,
        color: color,
        fontWeight: isLate || isSoon ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  /// The note, then its author and time ("מחכים למקרן · נועה לוי, 14:22"):
  /// the time alone on today, with the date on any other day. Null when the
  /// task has no update.
  String? _updateLine() {
    final note = task.assigneeUpdate;
    if (note == null || note.isEmpty) return null;
    final at = task.assigneeUpdateAt;
    final isToday = at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
    final byline = [
      if (task.assigneeUpdateByName != null) task.assigneeUpdateByName!,
      if (at != null) ltr((isToday ? _timeFormat : _dayTimeFormat).format(at)),
    ].join(', ');
    return byline.isEmpty ? note : '$note · $byline';
  }
}
