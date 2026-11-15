import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import '../../task/widgets/confirm_delete_dialog.dart';
import 'team_task_style.dart';

/// A task's update log: the field for a new update (when [canWrite]) and
/// every past update, newest first. Used by the task screen and by the quick
/// update card of "המשימות שלי" (Omer, round 5).
///
/// Round 10: each update has a ⋯ menu (עריכה / מחיקה) for its writer; with
/// [canEditAll] (a manager in "כל המשימות") for every update, also the ones
/// with no writer ("מהאקסל"). In "המשימות שלי" a manager is a member like
/// any other: only their own.
class TeamTaskUpdateLog extends StatefulWidget {
  const TeamTaskUpdateLog({
    super.key,
    required this.task,
    required this.canWrite,
    this.canEditAll = false,
  });

  final TeamTask task;
  final bool canWrite;
  final bool canEditAll;

  @override
  State<TeamTaskUpdateLog> createState() => _TeamTaskUpdateLogState();
}

class _TeamTaskUpdateLogState extends State<TeamTaskUpdateLog> {
  final TextEditingController _update = TextEditingController();
  bool _sending = false;

  /// The update being edited in place, and its draft.
  String? _editingId;
  final TextEditingController _edit = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _update.dispose();
    _edit.dispose();
    super.dispose();
  }

  bool _canChange(TaskUpdateEntry entry, String viewerId) =>
      widget.canEditAll || (entry.byId.isNotEmpty && entry.byId == viewerId);

  void _startEdit(TaskUpdateEntry entry) {
    _edit.text = entry.text;
    setState(() => _editingId = entry.id);
  }

  Future<void> _saveEdit(TaskUpdateEntry entry) async {
    final text = _edit.text.trim();
    if (text.isEmpty) return;
    if (text == entry.text) {
      setState(() => _editingId = null);
      return;
    }
    final task = widget.task;
    final completion = CrudActionCompleter();
    setState(() => _saving = true);
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? EditTeamTaskUpdate(task.parentId!, entry.id, text,
            subtaskId: task.id, completion: completion)
        : EditTeamTaskUpdate(task.id, entry.id, text, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.isSuccess) _editingId = null;
    });
    if (result.isFailure) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    }
  }

  Future<void> _delete(TaskUpdateEntry entry) {
    final task = widget.task;
    final bloc = context.read<TeamTaskBloc>();
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת עדכון',
      message: 'למחוק את העדכון "${entry.text}"?',
      keyPrefix: 'team-task-log-delete',
      onDelete: () {
        final completion = CrudActionCompleter();
        bloc.add(task.isSubtask
            ? DeleteTeamTaskUpdate(task.parentId!, entry.id,
                subtaskId: task.id, completion: completion)
            : DeleteTeamTaskUpdate(task.id, entry.id, completion: completion));
        return completion.future;
      },
    );
  }

  Widget _entryMenu(TaskUpdateEntry entry) {
    return SizedBox(
      width: 28,
      height: 24,
      child: PopupMenuButton<String>(
        key: Key('team-task-log-menu-${entry.id}'),
        tooltip: 'עוד',
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.more_horiz, color: TaskStyle.faintText),
        onSelected: (value) {
          if (value == 'edit') _startEdit(entry);
          if (value == 'delete') _delete(entry);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            key: Key('team-task-log-edit'),
            value: 'edit',
            child: Text('עריכה'),
          ),
          PopupMenuItem(
            key: Key('team-task-log-delete'),
            value: 'delete',
            child: Text('מחיקה'),
          ),
        ],
      ),
    );
  }

  Widget _editor(TaskUpdateEntry entry) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: RtlArrowKeys(
            multiline: true,
            child: TextField(
              key: const Key('team-task-log-edit-field'),
              controller: _edit,
              autofocus: true,
              readOnly: _saving,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('team-task-log-edit-cancel'),
          tooltip: 'ביטול',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : () => setState(() => _editingId = null),
          icon: const Icon(Icons.close, size: 18),
        ),
        IconButton(
          key: const Key('team-task-log-edit-save'),
          tooltip: 'שמירה',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : () => _saveEdit(entry),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
        ),
      ],
    );
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
    final state = context.watch<TeamTaskBloc>().state;
    final viewerId = state is TeamTasksLoaded ? state.viewer.id : '';
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_editingId == entry.id) _editor(entry) else Text(entry.text),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entry.byName ?? unknownMemberLabel} · ${logStamp(entry.at)}'
                        '${entry.editedAt != null ? ' · (נערך)' : ''}',
                        style: const TextStyle(fontSize: 12, color: TaskStyle.faintText),
                      ),
                    ),
                    if (_editingId != entry.id && _canChange(entry, viewerId))
                      _entryMenu(entry),
                  ],
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
