import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';

final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// One task on the tasks screen.
///
/// Tinted by its [TaskDueStatus], with a text chip so colour is never the only
/// signal. A task with subtasks shows a progress bar and lists them when the
/// card is pressed; a task without subtasks carries its own completion
/// checkbox instead.
///
/// The card is display-only: every action is reported through a callback and
/// the result arrives back as a new [task] from the bloc.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.now,
    required this.canManage,
    required this.canUpdateProgress,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onToggleSubtask,
    required this.onSetComplete,
    required this.onEditUpdate,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskItem task;

  /// The current time, injected so the colour rules can be tested.
  final DateTime now;

  /// Whether the viewer may edit and delete the task.
  final bool canManage;

  /// Whether the viewer may tick subtasks, complete the task and write its
  /// update.
  final bool canUpdateProgress;

  /// Whether the subtasks are shown. Owned by the screen, not the card: the
  /// list rebuilds and reorders cards whenever any task changes, and a card
  /// that kept this itself would snap shut each time it moved.
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  final void Function(Subtask subtask, bool isDone) onToggleSubtask;
  final ValueChanged<bool> onSetComplete;
  final VoidCallback onEditUpdate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = taskDueStatus(task, now);
    final style = _StatusStyle.of(status);
    final theme = Theme.of(context);

    return Card(
      key: Key('task-card-${task.id}'),
      color: style.tint,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      // The whole card opens and closes the subtasks. Its buttons and
      // checkboxes take their own presses first.
      child: InkWell(
        onTap: task.hasSubtasks ? onToggleExpanded : null,
        child: Container(
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: style.accent, width: 4),
            ),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme, status, style),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task.hasAssemblyTime)
                      _InfoLine(
                        icon: Icons.schedule,
                        text: 'התייצבות ${task.assemblyTime}',
                        color: status == TaskDueStatus.overdue ||
                                status == TaskDueStatus.dueToday
                            ? style.accent
                            : null,
                      ),
                    _InfoLine(
                      icon: Icons.person_outline,
                      text: task.assignees.isEmpty
                          ? 'ללא אחראים'
                          : task.assignees.map((member) => member.name).join(', '),
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(task.description, style: theme.textTheme.bodyMedium),
                    ],
                    if (task.hasSubtasks) ...[
                      const SizedBox(height: 12),
                      _buildProgress(theme, style),
                    ],
                    const SizedBox(height: 12),
                    _buildUpdateBlock(theme),
                    const SizedBox(height: 8),
                    Text(
                      'עודכן לאחרונה: ${_dateTimeFormat.format(task.updatedAt)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    if (task.hasSubtasks && isExpanded) ...[
                      const SizedBox(height: 8),
                      ...task.subtasks.map(_buildSubtask),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    TaskDueStatus status,
    _StatusStyle style,
  ) {
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
              color: task.isComplete ? Colors.grey.shade700 : null,
            ),
          ),
        ),
        if (style.label != null) ...[
          const SizedBox(width: 8),
          _StatusChip(label: style.label!, color: style.accent),
        ],
        if (canManage) ...[
          IconButton(
            key: Key('task-edit-${task.id}'),
            tooltip: 'עריכה',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('task-delete-${task.id}'),
            tooltip: 'מחיקה',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: onDelete,
          ),
        ],
      ],
    );
  }

  Widget _buildProgress(ThemeData theme, _StatusStyle style) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: Key('task-progress-${task.id}'),
              value: task.progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              color: task.isComplete ? Colors.green.shade400 : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Kept left-to-right so "2/3" never renders as "3/2" under RTL.
        Text(
          '${task.doneSubtaskCount}/${task.subtasks.length}',
          textDirection: TextDirection.ltr,
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

    final byline = [
      if (task.assigneeUpdateByName != null) task.assigneeUpdateByName!,
      if (task.assigneeUpdateAt != null)
        _dateTimeFormat.format(task.assigneeUpdateAt!),
    ].join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(update, style: theme.textTheme.bodyMedium),
                if (byline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    byline,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          if (updateButton != null) updateButton,
        ],
      ),
    );
  }

  Widget _buildSubtask(Subtask subtask) {
    return Card(
      key: Key('subtask-${subtask.id}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: subtask.isDone ? Colors.green.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      // Swallows a press that misses the checkbox, so aiming at a subtask
      // never closes the list it is in.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: _buildSubtaskRow(subtask),
      ),
    );
  }

  Widget _buildSubtaskRow(Subtask subtask) {
    return Row(
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
                color: subtask.isDone ? Colors.grey.shade700 : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The colours and label for one [TaskDueStatus].
class _StatusStyle {
  const _StatusStyle({required this.accent, this.tint, this.label});

  /// Card background; null leaves the default card colour.
  final Color? tint;
  final Color accent;
  final String? label;

  static _StatusStyle of(TaskDueStatus status) {
    switch (status) {
      case TaskDueStatus.completed:
        return _StatusStyle(
          tint: Colors.green.shade50,
          accent: Colors.green.shade400,
          label: 'הושלמה',
        );
      case TaskDueStatus.overdue:
        return _StatusStyle(
          tint: Colors.red.shade50,
          accent: Colors.red.shade400,
          label: 'באיחור',
        );
      case TaskDueStatus.dueToday:
        return _StatusStyle(
          tint: Colors.orange.shade50,
          accent: Colors.orange.shade400,
          label: 'להיום',
        );
      case TaskDueStatus.open:
        return _StatusStyle(accent: Colors.grey.shade400);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.grey.shade800;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: effectiveColor),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: effectiveColor),
            ),
          ),
        ],
      ),
    );
  }
}
