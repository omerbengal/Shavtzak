import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import 'team_task_style.dart';

/// The quick actions on one task, shared by the task screen and the rows of
/// "המשימות שלי" (Omer, round 4): change the status, add an update.

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
  bloc.add(SetTeamTaskStatus(task.id, status, duplicateOfId: original, completion: completion));
  final result = await completion.future;
  if (!result.isSuccess) {
    messenger?.showSnackBar(SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')));
  }
}

/// Which task [task] duplicates. Null = cancelled.
Future<String?> pickDuplicateOriginal(
  BuildContext context,
  TeamTasksLoaded state,
  TeamTask task,
) {
  final others = state.all
      .where((t) => t.id != task.id && t.status != TeamTaskStatus.duplicate)
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));
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
                        subtitle: Text(teamTaskLinkLabel(other)),
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

/// The status menu's options: the five statuses, each with its status circle
/// at the start of the word (on its right, Omer round 5), the pair centred
/// (round 4). [without] leaves options out (Blitz has its own "סיימתי").
List<PopupMenuEntry<TeamTaskStatus>> teamTaskStatusMenuItems(
        {Set<TeamTaskStatus> without = const {}}) =>
    [
      for (final status in TeamTaskStatus.values)
        if (!without.contains(status))
          PopupMenuItem(
            key: Key('team-task-status-option-${status.hebrewLabel}'),
            value: status,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TeamTaskStatusIcon(status: status, size: TeamTaskStyle.smallStatusIconSize),
                  const SizedBox(width: 8),
                  Text(status.hebrewLabel),
                ],
              ),
            ),
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
