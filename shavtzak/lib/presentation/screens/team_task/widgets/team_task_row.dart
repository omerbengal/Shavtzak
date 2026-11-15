import 'package:flutter/material.dart';

import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../task/task_style.dart';
import 'team_task_style.dart';

/// One task in the list: status, title, deadline (red when late), owners and
/// the subtasks done.
class TeamTaskRow extends StatelessWidget {
  const TeamTaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.viewerId,
    required this.onTap,
  });

  final TeamTask task;
  final DateTime now;
  final String viewerId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = isTeamTaskLate(task, now);
    final deadline = task.deadlineDate;
    final faded = !task.status.isActive;
    final names = teamTaskOwnerNames(task);
    return InkWell(
      key: Key('team-task-row-${task.id}'),
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: TaskStyle.rowTitleSize,
                        fontWeight: FontWeight.w600,
                        decoration: task.status == TeamTaskStatus.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TeamTaskStatusChip(status: task.status, dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
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
                  if (task.subtasks.isNotEmpty)
                    Text(
                      '${task.doneSubtasks}/${task.subtasks.length}',
                      key: Key('team-task-progress-${task.id}'),
                      style: const TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        color: TaskStyle.neutralText,
                      ),
                    ),
                  for (var i = 0; i < names.length; i++)
                    MemberNameChip(
                      name: names[i],
                      highlight: task.ownerIds[i] == viewerId,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
