import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/edit/value_editors.dart';
import '../../task/task_style.dart';
import 'task_link_picker.dart';
import 'team_task_style.dart';

/// "+ משימה חדשה": the title, what it belongs to, the deadline, the owners
/// and a description. Subtasks and contacts are added on the task itself
/// once it is saved.
///
/// Returns the new task's id, or null when cancelled.
Future<String?> showNewTeamTaskDialog(BuildContext context, {TaskLink? link}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _NewTeamTaskDialog(initialLink: link),
      ),
    ),
  );
}

class _NewTeamTaskDialog extends StatefulWidget {
  const _NewTeamTaskDialog({this.initialLink});

  final TaskLink? initialLink;

  @override
  State<_NewTeamTaskDialog> createState() => _NewTeamTaskDialogState();
}

class _NewTeamTaskDialogState extends State<_NewTeamTaskDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late TaskLink? _link = widget.initialLink;
  DateTime? _deadline;
  List<String> _owners = const [];
  String? _titleError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save(TeamTasksLoaded state) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'חובה להזין כותרת');
      return;
    }
    final now = DateTime.now();
    final task = TeamTask(
      id: const Uuid().v4(),
      title: title,
      description: _description.text.trim(),
      link: _link,
      assigneeIds: _owners,
      ownerIds: _owners,
      deadline: _deadline == null ? null : dateKey(_deadline!),
      createdAt: now,
      createdById: state.viewer.id,
      updatedAt: now,
    );
    final completion = CrudActionCompleter();
    setState(() {
      _saving = true;
      _error = null;
    });
    context.read<TeamTaskBloc>().add(CreateTeamTask(task, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _saving = false;
        _error = result.message;
      });
      return;
    }
    Navigator.of(context).pop(task.id);
  }

  Future<void> _pickOwners(TeamTasksLoaded state) async {
    final members = state.members.where((m) => m.isActive && !m.isArchived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    var draft = [..._owners];
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אחראים'),
          content: AssigneesEditor(
            initial: draft,
            offered: members,
            current: const [],
            onChanged: (ids) => draft = ids,
            emptyLabel: 'אין חברי צוות',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ביטול')),
            FilledButton(
              key: const Key('new-team-task-owners-ok'),
              onPressed: () => Navigator.of(context).pop(draft),
              child: const Text('אישור'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _owners = picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TeamTaskBloc>().state;
    if (state is! TeamTasksLoaded) return const SizedBox.shrink();
    final linkName = taskLinkName(state, _link);
    final ownerNames = [
      for (final id in _owners)
        state.members.where((m) => m.id == id).firstOrNull?.name ?? '',
    ];
    return AlertDialog(
      title: const Text('משימה חדשה'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RtlArrowKeys(
                child: TextField(
                  key: const Key('new-team-task-title'),
                  controller: _title,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'כותרת',
                    errorText: _titleError,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_titleError != null) setState(() => _titleError = null);
                  },
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const Key('new-team-task-link'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link),
                title: Text(linkName ?? 'שיוך: אירוע, קטגוריה או נושא'),
                subtitle: _link == null ? const Text('ללא שיוך') : null,
                onTap: () async {
                  final choice = await showTaskLinkPicker(context, initial: _link);
                  if (choice != null) setState(() => _link = choice.link);
                },
              ),
              ListTile(
                key: const Key('new-team-task-deadline'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_deadline == null ? 'דד ליין (לא חובה)' : fullDate(_deadline!)),
                trailing: _deadline == null
                    ? null
                    : IconButton(
                        tooltip: 'בלי דד ליין',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _deadline = null),
                      ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _deadline ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    helpText: 'דד ליין',
                    cancelText: 'ביטול',
                    confirmText: 'בחירה',
                  );
                  if (picked != null) setState(() => _deadline = picked);
                },
              ),
              ListTile(
                key: const Key('new-team-task-owners'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(ownerNames.isEmpty ? 'אחראים' : ownerNames.join(', ')),
                onTap: () => _pickOwners(state),
              ),
              const SizedBox(height: 8),
              RtlArrowKeys(
                multiline: true,
                child: TextField(
                  key: const Key('new-team-task-description'),
                  controller: _description,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'תיאור',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: TaskStyle.late)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          key: const Key('new-team-task-save'),
          onPressed: _saving ? null : () => _save(state),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
