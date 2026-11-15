import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/edit/value_editors.dart';
import '../../task/task_style.dart';
import '../../task/widgets/discard_changes_dialog.dart';
import 'deadline_picker.dart';
import 'task_link_picker.dart';
import 'team_subtasks_editor.dart';
import 'team_task_style.dart';

/// "+ משימה חדשה": the whole task, before it exists, in the shape of the
/// דו יומי task form: title, description, what it belongs to, deadline,
/// owners (an in-place dropdown with a search), contacts and subtasks (each
/// with its owner and contacts). A task with subtasks has no owners of its
/// own: theirs are its owners, so the owners field steps aside.
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
  // Chosen once per form, so saving again after a failure sends the same task.
  final String _id = const Uuid().v4();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late TaskLink? _link = widget.initialLink;
  DateTime? _deadline;
  List<String> _owners = const [];
  bool _ownersOpen = false;
  List<StageContact> _contacts = const [];
  bool _showContacts = false;
  List<TeamSubtask> _subtasks = const [];
  String? _titleError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _title.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _link != widget.initialLink ||
      _deadline != null ||
      _owners.isNotEmpty ||
      _contacts.isNotEmpty ||
      _subtasks.isNotEmpty;

  Future<void> _cancel() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmDiscardChanges(context, keyPrefix: 'new-team-task');
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<void> _save(TeamTasksLoaded state) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'חובה להזין כותרת');
      return;
    }
    final contacts = [..._contacts, for (final s in _subtasks) ...s.contacts];
    if (contacts.any((c) => c.name.trim().isEmpty)) {
      setState(() => _error = 'לכל איש קשר נדרש שם');
      return;
    }
    final now = DateTime.now();
    final owners = _subtasks.isEmpty
        ? _owners
        : _subtasks.map((s) => s.assigneeId).whereType<String>().toSet().toList();
    final task = TeamTask(
      id: _id,
      title: title,
      description: _description.text.trim(),
      link: _link,
      assigneeIds: _subtasks.isEmpty ? _owners : const [],
      ownerIds: owners,
      subtasks: _subtasks,
      contacts: _contacts,
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
        _error = result.message ?? 'השמירה נכשלה. נסו שוב.';
      });
      return;
    }
    Navigator.of(context).pop(task.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TeamTaskBloc>().state;
    if (state is! TeamTasksLoaded) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final active = state.members.where((m) => m.isActive && !m.isArchived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return PopScope(
      canPop: !_saving && !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _cancel();
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text('משימה חדשה', style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RtlArrowKeys(
                          child: TextField(
                            key: const Key('new-team-task-title'),
                            controller: _title,
                            autofocus: true,
                            maxLength: 200,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'כותרת',
                              errorText: _titleError,
                              border: const OutlineInputBorder(),
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() => _titleError = null),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _linkField(state),
                        const SizedBox(height: 16),
                        _deadlineField(state),
                        if (_subtasks.isEmpty) ...[
                          const SizedBox(height: 16),
                          _ownersField(state, active),
                        ],
                        const SizedBox(height: 20),
                        _contactsSection(theme),
                        const SizedBox(height: 20),
                        Text('תתי-משימות', style: theme.textTheme.titleSmall),
                        if (_subtasks.isNotEmpty)
                          const Text(
                            'במשימה עם תתי-משימות, האחראים הם האחראים על תתי-המשימות',
                            style: TextStyle(fontSize: 12, color: TaskStyle.faintText),
                          ),
                        const SizedBox(height: 4),
                        TeamSubtasksEditor(
                          initial: const [],
                          members: active,
                          startWithLine: false,
                          onChanged: (subtasks) => setState(() => _subtasks = subtasks),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    _error!,
                    key: const Key('new-team-task-error'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('new-team-task-cancel'),
                      onPressed: _saving ? null : _cancel,
                      child: const Text('ביטול'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('new-team-task-save'),
                      onPressed: _saving ? null : () => _save(state),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('שמירה'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A form field that opens a picker: label, value, and an ✕ when set.
  Widget _pickerField({
    required Key key,
    required String label,
    required String? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
    IconData icon = Icons.arrow_drop_down,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value != null && onClear != null
              ? IconButton(
                  tooltip: 'ניקוי',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                )
              : Icon(icon),
        ),
        child: value == null ? null : Text(value),
      ),
    );
  }

  Widget _linkField(TeamTasksLoaded state) {
    return _pickerField(
      key: const Key('new-team-task-link'),
      label: 'שיוך: אירוע, קטגוריה או נושא',
      value: taskLinkName(state, _link),
      onTap: () async {
        final choice = await showTaskLinkPicker(context, initial: _link);
        if (choice != null) setState(() => _link = choice.link);
      },
      onClear: () => setState(() => _link = null),
    );
  }

  Widget _deadlineField(TeamTasksLoaded state) {
    return _pickerField(
      key: const Key('new-team-task-deadline'),
      label: 'דד ליין (לא חובה)',
      value: _deadline == null ? null : fullDate(_deadline!),
      icon: Icons.event,
      onTap: () async {
        final picked = await pickTeamTaskDeadline(
          context,
          initial: _deadline,
        );
        if (picked != null) setState(() => _deadline = picked);
      },
      onClear: () => setState(() => _deadline = null),
    );
  }

  /// The דו יומי form's owners dropdown: closed, one field naming who is
  /// picked; open, a search and the team under it.
  Widget _ownersField(TeamTasksLoaded state, List<TeamMember> active) {
    final names = [
      for (final id in _owners)
        state.members.firstWhereOrNull((m) => m.id == id)?.name ?? '',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('new-team-task-owners'),
          onTap: () => setState(() => _ownersOpen = !_ownersOpen),
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            isEmpty: _owners.isEmpty,
            decoration: InputDecoration(
              labelText: 'אחראים',
              border: const OutlineInputBorder(),
              suffixIcon: Icon(_ownersOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down),
            ),
            child: _owners.isEmpty ? null : Text(names.join(', ')),
          ),
        ),
        if (_ownersOpen) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: AssigneesEditor(
              initial: _owners,
              offered: active,
              current: const [],
              maxWidth: double.infinity,
              emptyLabel: 'אין חברי צוות',
              onChanged: (ids) => setState(() => _owners = ids),
            ),
          ),
        ],
      ],
    );
  }

  Widget _contactsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('אנשי קשר', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (_showContacts)
          ContactsEditor(
            initial: const [],
            onChanged: (contacts) => setState(() => _contacts = contacts),
          )
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('new-team-task-add-contact'),
              onPressed: () => setState(() => _showContacts = true),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('איש קשר'),
            ),
          ),
      ],
    );
  }
}
