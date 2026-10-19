import 'package:flutter/material.dart';

import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../task_style.dart';

/// A task's assignees as chips, shared by the phone row and the wide table:
/// the viewer's own filled in [TaskStyle.mine], a removed one struck through
/// in red with a note, and a call button for whoever has a phone.
class AssigneeChips extends StatelessWidget {
  const AssigneeChips({
    super.key,
    required this.task,
    required this.viewerId,
    required this.removedAssigneeIds,
    required this.onCallPhone,
    required this.keyPrefix,
  });

  final TaskItem task;
  final String viewerId;
  final List<String> removedAssigneeIds;
  final ValueChanged<String> onCallPhone;

  /// Starts every chip's and call button's key, such as 'task-row' for
  /// `task-row-assignee-<task>-<member>` and `task-row-call-<task>-<member>`.
  final String keyPrefix;

  /// The assignees that get a chip: a member on record, or a removed id.
  static List<String> shownIds(TaskItem task, List<String> removedAssigneeIds) {
    final known = {for (final member in task.assignees) member.id};
    final removed = removedAssigneeIds.toSet();
    return [
      for (final memberId in task.assigneeIds)
        if (known.contains(memberId) || removed.contains(memberId)) memberId,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final membersById = {for (final member in task.assignees) member.id: member};
    final removed = removedAssigneeIds.toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final memberId in shownIds(task, removedAssigneeIds))
          _buildAssignee(
              memberId, membersById[memberId], removed.contains(memberId)),
      ],
    );
  }

  Widget _buildAssignee(String memberId, TeamMember? member, bool isRemoved) {
    final isMine = memberId == viewerId && !isRemoved;
    final phone = member?.phoneNumber ?? '';
    // A Wrap, not a Row: in a narrow column the note goes under the chip
    // instead of overflowing.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          key: Key('$keyPrefix-assignee-${task.id}-$memberId'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isMine
                ? TaskStyle.mine
                : (isRemoved ? TaskStyle.lateLight : TaskStyle.chip),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            member?.name ?? 'חבר צוות שנמחק',
            style: TextStyle(
              fontSize: 12.5,
              color: isMine
                  ? Colors.white
                  : (isRemoved ? TaskStyle.lateDark : TaskStyle.neutralText),
              decoration: isRemoved
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
        ),
        if (phone.isNotEmpty)
          IconButton(
            key: Key('$keyPrefix-call-${task.id}-$memberId'),
            tooltip: 'התקשרות',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            iconSize: 18,
            color: TaskStyle.mine,
            icon: const Icon(Icons.phone),
            onPressed: () => onCallPhone(phone),
          ),
        if (isRemoved) ...[
          const SizedBox(width: 4),
          const Text(
            'כבר לא משובץ לאירוע',
            style: TextStyle(
              fontSize: TaskStyle.rowMetaSize,
              color: TaskStyle.lateDark,
            ),
          ),
        ],
      ],
    );
  }
}
