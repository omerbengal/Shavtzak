import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'team_task_style.dart';

/// A task's update log: the field for a new update (when [canWrite]) and
/// every past update, newest first. Used by the task screen and by the quick
/// update card of "המשימות שלי" (Omer, round 5).
class TeamTaskUpdateLog extends StatefulWidget {
  const TeamTaskUpdateLog({super.key, required this.task, required this.canWrite});

  final TeamTask task;
  final bool canWrite;

  @override
  State<TeamTaskUpdateLog> createState() => _TeamTaskUpdateLogState();
}

class _TeamTaskUpdateLogState extends State<TeamTaskUpdateLog> {
  final TextEditingController _update = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _update.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final task = widget.task;
    final text = _update.text.trim();
    if (text.isEmpty) return;
    final completion = CrudActionCompleter();
    setState(() => _sending = true);
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? AddTeamTaskUpdate(task.parentId!, text, subtaskId: task.id, completion: completion)
        : AddTeamTaskUpdate(task.id, text, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() => _sending = false);
    if (result.isSuccess) {
      _update.clear();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canWrite)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: RtlArrowKeys(
                  multiline: true,
                  child: TextField(
                    key: const Key('team-task-update-field'),
                    controller: _update,
                    readOnly: _sending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '+ עדכון',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('team-task-update-send'),
                tooltip: 'הוספת עדכון',
                onPressed: _sending ? null : _send,
                // Spins until the update is saved (Omer, round 4).
                icon: _sending
                    ? const SizedBox(
                        key: Key('team-task-update-sending'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        if (task.updates.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('אין עדכונים עדיין', style: TextStyle(color: TaskStyle.faintText)),
          ),
        for (final entry in task.updates)
          Container(
            key: Key('team-task-log-${entry.id}'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TaskStyle.updateBox,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.text),
                const SizedBox(height: 2),
                Text(
                  '${entry.byName ?? unknownMemberLabel} · ${logStamp(entry.at)}',
                  style: const TextStyle(fontSize: 12, color: TaskStyle.faintText),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The quick update card of "המשימות שלי" (Omer, round 5): the task's whole
/// log, newest first, with the field for a new update on top. It follows the
/// task live, so a sent update shows in the list at once.
Future<void> showTeamTaskUpdatesDialog(BuildContext context, String taskId) {
  final bloc = context.read<TeamTaskBloc>();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider.value(
      value: bloc,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocBuilder<TeamTaskBloc, TeamTaskState>(
          builder: (context, state) {
            final task = state is TeamTasksLoaded ? state.taskById(taskId) : null;
            return AlertDialog(
              key: const Key('team-task-updates-dialog'),
              title: Text(task?.title ?? ''),
              content: SizedBox(
                width: 460,
                child: task == null
                    ? const Text('המשימה נמחקה')
                    : SingleChildScrollView(
                        child: TeamTaskUpdateLog(task: task, canWrite: true),
                      ),
              ),
              actions: [
                TextButton(
                  key: const Key('team-task-updates-close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('סגירה'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
