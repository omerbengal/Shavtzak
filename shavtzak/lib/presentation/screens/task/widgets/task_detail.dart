import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../task_style.dart';
import 'update_note_box.dart';

final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// One task, in full: the sheet's view of a single task.
///
/// A task with subtasks shows a progress bar and lists them; one without
/// carries its own completion box instead. Display-only: every action is
/// reported through a callback and the result arrives back as a new [task].
class TaskDetail extends StatelessWidget {
  const TaskDetail({
    super.key,
    required this.task,
    required this.viewerId,
    required this.now,
    required this.canManage,
    required this.canUpdateProgress,
    required this.onToggleSubtask,
    required this.onSetComplete,
    required this.onEditUpdate,
    required this.onEdit,
    required this.onDelete,
    required this.onCallPhone,
  });

  final TaskItem task;

  /// Who is looking; they get no call button on their own name.
  final String viewerId;

  /// The current time, injected so the colour rules can be tested.
  final DateTime now;

  /// Whether the viewer may edit and delete the task.
  final bool canManage;

  /// Whether the viewer may tick subtasks, complete the task and write its
  /// update.
  final bool canUpdateProgress;

  final void Function(Subtask subtask, bool isDone) onToggleSubtask;
  final ValueChanged<bool> onSetComplete;
  final VoidCallback onEditUpdate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onCallPhone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: Key('task-detail-${task.id}'),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStageLine(theme),
                const SizedBox(height: 8),
                ..._buildAssignees(theme),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(task.description, style: theme.textTheme.bodyMedium),
                ],
                if (task.hasSubtasks) ...[
                  const SizedBox(height: 12),
                  _buildProgress(theme),
                ],
                const SizedBox(height: 12),
                _buildUpdateBlock(theme),
                const SizedBox(height: 8),
                Text(
                  'עודכן לאחרונה: ${_dateTimeFormat.format(task.updatedAt)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: TaskStyle.neutralText),
                ),
                if (task.hasSubtasks) ...[
                  const SizedBox(height: 8),
                  ...task.subtasks.map(_buildSubtask),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final status = taskDueStatus(task, now);
    final (String? label, Color color) = switch (status) {
      TaskDueStatus.completed => ('הושלמה', TaskStyle.done),
      TaskDueStatus.overdue => ('באיחור', TaskStyle.late),
      // No "להיום": all of today is today.
      _ => (null, TaskStyle.rest),
    };
    return Row(
      children: [
        if (!task.hasSubtasks)
          Checkbox(
            key: Key('task-complete-${task.id}'),
            value: task.isComplete,
            onChanged: canUpdateProgress
                ? (value) => onSetComplete(value ?? false)
                : null,
          )
        else
          const SizedBox(width: 8),
        Expanded(
          child: Text(
            task.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              decoration: task.isComplete
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              color: task.isComplete ? TaskStyle.faintText : null,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (canManage) ...[
          IconButton(
            key: Key('task-edit-${task.id}'),
            tooltip: 'עריכה',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit, color: TaskStyle.edit),
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('task-delete-${task.id}'),
            tooltip: 'מחיקה',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete, color: TaskStyle.delete),
            onPressed: onDelete,
          ),
        ],
      ],
    );
  }

  /// "סדנאות · התייצבות 15:00", the time orange in the next half hour and red
  /// once late; or "סדנאות · ללא שעה".
  Widget _buildStageLine(ThemeData theme) {
    final isLate = taskDueStatus(task, now) == TaskDueStatus.overdue;
    final isSoon = isDueSoon(task, now);
    final stageTitle = task.stage?.title;
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(color: TaskStyle.neutralText),
        children: [
          if (stageTitle != null) TextSpan(text: '$stageTitle · '),
          TextSpan(
            text: task.hasAssemblyTime
                ? 'התייצבות ${ltr(task.assemblyTime!)}'
                : 'ללא שעה',
            style: TextStyle(
              color: isLate
                  ? TaskStyle.lateDark
                  : (isSoon ? TaskStyle.soonDark : TaskStyle.neutralText),
              fontWeight:
                  isLate || isSoon ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAssignees(ThemeData theme) {
    if (task.assignees.isEmpty) {
      return [
        Text(
          'ללא אחראים',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: TaskStyle.neutralText),
        ),
      ];
    }
    return [for (final member in task.assignees) _buildAssignee(theme, member)];
  }

  Widget _buildAssignee(ThemeData theme, TeamMember member) {
    final phone = member.id == viewerId ? '' : member.phoneNumber ?? '';
    return Row(
      children: [
        const Icon(Icons.person_outline, size: 18, color: TaskStyle.neutralText),
        const SizedBox(width: 6),
        Expanded(child: Text(member.name, style: theme.textTheme.bodyMedium)),
        if (phone.isNotEmpty)
          IconButton(
            key: Key('task-detail-call-${member.id}'),
            tooltip: 'התקשרות',
            iconSize: 20,
            color: TaskStyle.mine,
            icon: const Icon(Icons.phone),
            onPressed: () => onCallPhone(phone),
          ),
      ],
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: Key('task-progress-${task.id}'),
              value: task.progress,
              minHeight: 8,
              backgroundColor: TaskStyle.rest,
              color: task.isComplete ? TaskStyle.done : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          ltr('${task.doneSubtaskCount}/${task.subtasks.length}'),
          style: theme.textTheme.labelLarge,
        ),
      ],
    );
  }

  Widget _buildUpdateBlock(ThemeData theme) {
    final update = task.assigneeUpdate;
    final hasUpdate = update != null && update.isNotEmpty;
    if (!hasUpdate && !canUpdateProgress) return const SizedBox.shrink();

    final updateButton = canUpdateProgress
        ? TextButton.icon(
            key: Key('task-update-${task.id}'),
            onPressed: onEditUpdate,
            icon: const Icon(Icons.edit_note, size: 20),
            label: Text(hasUpdate ? 'עדכון' : 'הוספת עדכון'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          )
        : null;

    if (!hasUpdate) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: updateButton,
      );
    }

    return UpdateNoteBox(task: task, trailing: updateButton);
  }

  Widget _buildSubtask(Subtask subtask) {
    return Card(
      key: Key('subtask-${subtask.id}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: subtask.isDone ? TaskStyle.doneLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: TaskStyle.rest),
      ),
      child: Row(
        children: [
          Checkbox(
            value: subtask.isDone,
            onChanged: canUpdateProgress
                ? (value) => onToggleSubtask(subtask, value ?? false)
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Text(
                subtask.title,
                style: TextStyle(
                  decoration: subtask.isDone
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  color: subtask.isDone ? TaskStyle.neutralText : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
