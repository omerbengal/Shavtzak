import 'package:flutter/material.dart';

import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../task/task_style.dart';
import 'team_task_style.dart';

/// One task in the list (design A, Omer round 3): the status circle, the
/// title, and under it the deadline (red when late) and the owners'
/// initials. A subtask shown on its own ("המשימות שלי") has its parent's
/// title above it; a [nested] one is a compact line under its parent.
///
/// [subtaskCount] (a parent in "כל המשימות") shows "done/all ▾" at the end;
/// tapping it calls [onToggleSubtasks].
class TeamTaskRow extends StatelessWidget {
  const TeamTaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.viewerId,
    required this.onTap,
    this.nested = false,
    this.expanded = false,
    this.onToggleSubtasks,
  });

  /// Under its parent's row (or in its parent's screen): one compact line,
  /// without the parent's title above it.
  final bool nested;

  final TeamTask task;
  final DateTime now;
  final String viewerId;
  final VoidCallback onTap;

  /// Whether the subtasks under this row are open (the arrow's direction).
  final bool expanded;
  final VoidCallback? onToggleSubtasks;

  @override
  Widget build(BuildContext context) {
    final faded = !task.status.isActive;
    return InkWell(
      key: Key('team-task-row-${task.id}'),
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.6 : 1,
        child: nested ? _nested() : _full(),
      ),
    );
  }

  TextStyle _titleStyle(double size, FontWeight weight) {
    final done = task.status == TeamTaskStatus.done;
    return TextStyle(
      fontSize: size,
      fontWeight: done ? FontWeight.w500 : weight,
      color: done ? TaskStyle.faintText : null,
      decoration: done ? TextDecoration.lineThrough : null,
    );
  }

  List<Widget> _owners(double size) => [
        for (final owner in teamTaskOwnerChips(task))
          MemberInitialsAvatar(
            memberId: owner.id,
            name: owner.name,
            highlight: owner.id == viewerId,
            size: size,
          ),
      ];

  Widget _nested() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 12, 5),
      child: Row(
        children: [
          TeamTaskStatusIcon(status: task.status, size: TeamTaskStyle.subtaskIconSize),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.title,
              style: _titleStyle(TaskStyle.subtaskSize, FontWeight.w400),
            ),
          ),
          const SizedBox(width: 6),
          Wrap(spacing: 4, children: _owners(TeamTaskStyle.subtaskAvatarSize)),
        ],
      ),
    );
  }

  Widget _full() {
    final late = isTeamTaskLate(task, now);
    final deadline = task.deadlineDate;
    final owners = _owners(TeamTaskStyle.avatarSize);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.isSubtask)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: TeamTaskStyle.statusIconSize + 8,
                bottom: 2,
              ),
              child: Text(
                task.parentTitle ?? '',
                key: Key('team-task-parent-${task.id}'),
                style: const TextStyle(
                  fontSize: TaskStyle.rowMetaSize,
                  color: TaskStyle.neutralText,
                ),
              ),
            ),
          Row(
            children: [
              TeamTaskStatusIcon(status: task.status, size: TeamTaskStyle.statusIconSize),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: _titleStyle(TaskStyle.rowTitleSize, FontWeight.w600),
                ),
              ),
              if (task.subtasks.isNotEmpty)
                InkWell(
                  key: Key('team-task-progress-${task.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onToggleSubtasks,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${task.doneSubtasks}/${task.subtasks.length}',
                          style: const TextStyle(
                            fontSize: TaskStyle.rowMetaSize,
                            color: TaskStyle.mine,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (onToggleSubtasks != null)
                          Icon(
                            expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            size: 20,
                            color: TaskStyle.mine,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (deadline != null || owners.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: TeamTaskStyle.statusIconSize + 8,
                top: 5,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (deadline != null)
                    Text(
                      late ? 'באיחור · עד ${shortDate(deadline)}' : 'עד ${shortDate(deadline)}',
                      key: Key('team-task-deadline-${task.id}'),
                      style: TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        color: late ? TaskStyle.late : TaskStyle.neutralText,
                        fontWeight: late ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ...owners,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
