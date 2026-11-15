import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../task/widgets/assignee_update_dialog.dart';

/// The quick actions on one task, shared by the task screen, the rows of
/// "המשימות שלי" and a parent's subtask list (Omer, round 4): change the
/// status, add an update. A subtask view ([TeamTask.isSubtask]) acts on that
/// subtask inside its parent.

/// Sets [task]'s status; "כפילות" first asks which task it duplicates. A
/// refusal shows as a snackbar.
Future<void> changeTeamTaskStatus(
  BuildContext context,
  TeamTask task,
  TeamTaskStatus status,
) async {
  final bloc = context.read<TeamTaskBloc>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final state = bloc.state;
  if (state is! TeamTasksLoaded) return;
  String? original;
  if (status == TeamTaskStatus.duplicate) {
    original = await pickDuplicateOriginal(context, state, task);
    if (original == null) return;
  }
  final completion = CrudActionCompleter();
  bloc.add(task.isSubtask
      ? SetTeamTaskStatus(task.parentId!, status,
          subtaskId: task.id, duplicateOfId: original, completion: completion)
      : SetTeamTaskStatus(task.id, status, duplicateOfId: original, completion: completion));
  final result = await completion.future;
  if (!result.isSuccess) {
    messenger?.showSnackBar(SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')));
  }
}

/// Which task [task] duplicates: a sister subtask (listed first) or another
/// task. Null = cancelled.
Future<String?> pickDuplicateOriginal(
  BuildContext context,
  TeamTasksLoaded state,
  TeamTask task,
) {
  final parent =
      task.parentId == null ? null : state.all.where((t) => t.id == task.parentId).firstOrNull;
  final sisters = [
    if (parent != null)
      for (final subtask in parent.subtasks)
        if (subtask.id != task.id && subtask.status != TeamTaskStatus.duplicate)
          TeamTask.subtaskView(parent, subtask),
  ];
  final others = [
    ...sisters,
    ...state.all
        .where(
            (t) => t.id != task.id && t.id != task.parentId && t.status != TeamTaskStatus.duplicate)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title)),
  ];
  return showDialog<String>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('כפילות של איזו משימה?'),
        content: SizedBox(
          width: 360,
          height: 360,
          child: others.isEmpty
              ? const Center(child: Text('אין משימות אחרות'))
              : ListView(
                  children: [
                    for (final other in others)
                      ListTile(
                        key: Key('duplicate-original-${other.id}'),
                        dense: true,
                        title: Text(other.title),
                        subtitle: Text(other.isSubtask
                            ? 'תת-משימה של ${other.parentTitle}'
                            : teamTaskLinkLabel(other)),
                        onTap: () => Navigator.of(context).pop(other.id),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
        ],
      ),
    ),
  );
}

/// The status menu's options: the five statuses, each word centred (Omer,
/// round 4).
List<PopupMenuEntry<TeamTaskStatus>> teamTaskStatusMenuItems() => [
      for (final status in TeamTaskStatus.values)
        PopupMenuItem(
          key: Key('team-task-status-option-${status.hebrewLabel}'),
          value: status,
          child: Center(child: Text(status.hebrewLabel)),
        ),
    ];

/// [child] opening the status menu of [task].
class TeamTaskStatusMenu extends StatelessWidget {
  const TeamTaskStatusMenu({super.key, required this.task, required this.child});

  final TeamTask task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TeamTaskStatus>(
      tooltip: 'שינוי סטטוס',
      padding: EdgeInsets.zero,
      onSelected: (status) {
        if (status != task.status) changeTeamTaskStatus(context, task, status);
      },
      itemBuilder: (context) => teamTaskStatusMenuItems(),
      child: child,
    );
  }
}

/// A small dialog that adds one update to [task]'s log, the דו יומי update
/// dialog: it stays open with a spinner until the backend answers.
Future<void> showAddTeamTaskUpdateDialog(BuildContext context, TeamTask task) {
  final bloc = context.read<TeamTaskBloc>();
  return showAssigneeUpdateDialog(
    context,
    title: task.title,
    hintText: 'מה התחדש?',
    helperText: null,
    saveLabel: 'הוספה',
    onSave: (text) {
      if (text.isEmpty) {
        return Future.value(const CrudActionResult.failure('חובה להזין עדכון'));
      }
      final completion = CrudActionCompleter();
      bloc.add(task.isSubtask
          ? AddTeamTaskUpdate(task.parentId!, text, subtaskId: task.id, completion: completion)
          : AddTeamTaskUpdate(task.id, text, completion: completion));
      return completion.future;
    },
  );
}
