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
import 'team_task_style.dart';

/// "+ משימה חדשה": the whole task, before it exists, in the shape of the
/// דו יומי task form, in Omer's order (round 10): what it belongs to, title,
/// description, owners (an in-place dropdown with a search), deadline, then
/// contacts and subtasks. [link] comes preset from a card's "+" (round 10).
/// A subtask is a task of its own: "+ תת-משימה" opens this same form for it
/// ([showSubtaskFormDialog]), with one text line and no description. A task with subtasks has no owners of its own
/// (theirs are its owners), so the owners field steps aside and the title
/// reads "משימת אב חדשה".
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
        child: _TeamTaskForm(initialLink: link),
      ),
    ),
  );
}

/// The task form for one subtask of task "[parentTitle]": a new one, or
/// [initial] to edit. The same fields as a task, without the link (the
/// parent's) and without subtasks. Nothing is saved here: the subtask comes
/// back to the caller, null when cancelled.
Future<TeamSubtask?> showSubtaskFormDialog(
  BuildContext context, {
  required String parentTitle,
  TeamSubtask? initial,
}) {
  return showDialog<TeamSubtask>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _TeamTaskForm(subtaskOf: parentTitle, initialSubtask: initial),
      ),
    ),
  );
}

/// Asks what to do when a task that has owners gets its first subtask
/// (Omer, round 2): a task with subtasks has no owners of its own. True =
/// create subtasks and remove the task's owners; false / null = keep it one
/// task.
Future<bool> confirmFirstSubtask(BuildContext context) async {
  final split = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('למשימה יש אחראים'),
        content: const Text(
          'למשימה עם תתי-משימות אין אחראים משלה: האחראים הם האחראים על תתי-המשימות.',
        ),
        actions: [
          TextButton(
            key: const Key('first-subtask-keep'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('להשאיר כמשימה אחת'),
          ),
          FilledButton(
            key: const Key('first-subtask-split'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ליצור תתי-משימות ולהסיר את האחראים'),
          ),
        ],
      ),
    ),
  );
  return split ?? false;
}

class _TeamTaskForm extends StatefulWidget {
  const _TeamTaskForm({this.initialLink, this.subtaskOf, this.initialSubtask});

  final TaskLink? initialLink;

  /// Set = the form of a subtask of the task with this title.
  final String? subtaskOf;
  final TeamSubtask? initialSubtask;

  bool get isSubtask => subtaskOf != null;

  @override
  State<_TeamTaskForm> createState() => _TeamTaskFormState();
}

class _TeamTaskFormState extends State<_TeamTaskForm> {
  // Chosen once per form, so saving again after a failure sends the same task.
  late final String _id = widget.initialSubtask?.id ?? const Uuid().v4();
  late final TextEditingController _title =
      TextEditingController(text: widget.initialSubtask?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initialSubtask?.description ?? '');
  late TaskLink? _link = widget.initialLink;
  late DateTime? _deadline = _parseDate(widget.initialSubtask?.deadline);
  late List<String> _owners = widget.initialSubtask?.assigneeIds ?? const [];
  bool _ownersOpen = false;
  late List<StageContact> _contacts = widget.initialSubtask?.contacts ?? const [];
  late bool _showContacts = _contacts.isNotEmpty;
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

  static DateTime? _parseDate(String? key) {
    if (key == null) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  bool get _hasChanges {
    final initial = widget.initialSubtask;
    if (initial != null) {
      return _title.text.trim() != initial.title ||
          (_deadline == null ? null : dateKey(_deadline!)) != initial.deadline ||
          !_sameList(_owners, initial.assigneeIds) ||
          _contacts != initial.contacts;
    }
    return _title.text.trim().isNotEmpty ||
        _description.text.trim().isNotEmpty ||
        _link != widget.initialLink ||
        _deadline != null ||
        _owners.isNotEmpty ||
        _contacts.isNotEmpty ||
        _subtasks.isNotEmpty;
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  String get _heading {
    if (widget.isSubtask) {
      return widget.initialSubtask == null ? 'תת-משימה חדשה' : 'עריכת תת-משימה';
    }
    return _subtasks.isEmpty ? 'משימה חדשה' : 'משימת אב חדשה';
  }

  Future<void> _addSubtask() async {
    if (_subtasks.isEmpty && _owners.isNotEmpty) {
      final split = await confirmFirstSubtask(context);
      if (!split || !mounted) return;
      setState(() {
        _owners = const [];
        _ownersOpen = false;
      });
    }
    final subtask = await showSubtaskFormDialog(
      context,
      parentTitle: _title.text.trim(),
    );
    if (subtask != null && mounted) setState(() => _subtasks = [..._subtasks, subtask]);
  }

  Future<void> _editSubtask(TeamSubtask subtask) async {
    final edited = await showSubtaskFormDialog(
      context,
      parentTitle: _title.text.trim(),
      initial: subtask,
    );
    if (edited == null || !mounted) return;
    setState(() => _subtasks = [
          for (final s in _subtasks) s.id == edited.id ? edited : s,
        ]);
  }

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
      setState(() => _titleError =
          widget.isSubtask ? 'חובה להזין את תת-המשימה' : 'חובה להזין כותרת');
      return;
    }
    if (_contacts.any((c) => c.name.trim().isEmpty)) {
      setState(() => _error = 'לכל איש קשר נדרש שם');
      return;
    }
    if (widget.isSubtask) {
      final base = widget.initialSubtask ?? TeamSubtask(id: _id, title: title);
      final members = {for (final m in state.members) m.id: m};
      // One line of text (round 10); a description saved before is kept as
      // is until Omer decides what becomes of it.
      Navigator.of(context).pop(base.copyWith(
        title: title,
        assigneeIds: _owners,
        assignees: _owners.map((id) => members[id]).whereType<TeamMember>().toList(),
        contacts: _contacts,
        deadline: () => _deadline == null ? null : dateKey(_deadline!),
      ));
      return;
    }
    final now = DateTime.now();
    final owners = _subtasks.isEmpty
        ? _owners
        : {for (final s in _subtasks) ...s.assigneeIds}.toList();
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_heading,
                        key: const Key('new-team-task-heading'),
                        style: theme.textTheme.titleLarge),
                    if (widget.isSubtask && widget.subtaskOf!.isNotEmpty)
                      Text(
                        'של המשימה: ${widget.subtaskOf}',
                        style: const TextStyle(color: TaskStyle.neutralText),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Omer's order (round 10): link, title, description,
                        // owners, deadline.
                        if (!widget.isSubtask) ...[
                          _linkField(state),
                          const SizedBox(height: 16),
                        ],
                        RtlArrowKeys(
                          multiline: widget.isSubtask,
                          child: TextField(
                            key: const Key('new-team-task-title'),
                            controller: _title,
                            autofocus: true,
                            maxLength: 200,
                            minLines: 1,
                            maxLines: widget.isSubtask ? 3 : 1,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: widget.isSubtask ? 'תת-משימה' : 'כותרת',
                              errorText: _titleError,
                              border: const OutlineInputBorder(),
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() => _titleError = null),
                          ),
                        ),
                        if (!widget.isSubtask) ...[
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
                        ],
                        if (_subtasks.isEmpty) ...[
                          const SizedBox(height: 16),
                          _ownersField(state, active),
                        ],
                        const SizedBox(height: 16),
                        _deadlineField(state),
                        const SizedBox(height: 20),
                        _contactsSection(theme),
                        if (!widget.isSubtask) ...[
                          const SizedBox(height: 20),
                          _subtasksSection(theme),
                        ],
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
                          : Text(widget.isSubtask ? 'אישור' : 'שמירה'),
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
    final picked = [
      for (final id in _owners)
        if (state.members.firstWhereOrNull((m) => m.id == id) case final member?) member,
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
            child: _owners.isEmpty
                ? null
                : Text.rich(TextSpan(children: [
                    for (var i = 0; i < picked.length; i++) ...[
                      if (i > 0) const TextSpan(text: ', '),
                      TextSpan(text: picked[i].name),
                      if (picked[i].isPermanent)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: PermanentMemberMark(),
                        ),
                    ],
                  ])),
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
              pickedFirst: true,
              showPermanentMark: true,
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
            initial: _contacts,
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

  /// The subtasks so far, each a row like a task's (owners, deadline): a tap
  /// opens it in the subtask form, ✕ removes it; "+ תת-משימה" adds one.
  Widget _subtasksSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('תתי-משימות', style: theme.textTheme.titleSmall),
        if (_subtasks.isNotEmpty)
          const Text(
            'במשימה עם תתי-משימות, האחראים הם האחראים על תתי-המשימות',
            style: TextStyle(fontSize: 12, color: TaskStyle.faintText),
          ),
        const SizedBox(height: 4),
        for (final (i, subtask) in _subtasks.indexed)
          SubtaskSummaryTile(
            key: Key('new-team-subtask-$i'),
            subtask: subtask,
            onTap: () => _editSubtask(subtask),
            onRemove: () => setState(() => _subtasks = [
                  for (final s in _subtasks)
                    if (s.id != subtask.id) s,
                ]),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('new-team-task-add-subtask'),
            onPressed: _addSubtask,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('תת-משימה'),
          ),
        ),
      ],
    );
  }
}

/// One subtask in a form: title, owners and deadline; a tap edits it.
class SubtaskSummaryTile extends StatelessWidget {
  const SubtaskSummaryTile({
    super.key,
    required this.subtask,
    required this.onTap,
    this.onRemove,
  });

  final TeamSubtask subtask;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final deadline = subtask.deadline;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtask.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (deadline != null)
                          Text(
                            fullDate(DateTime.parse(deadline)),
                            style: const TextStyle(
                              fontSize: TaskStyle.rowMetaSize,
                              color: TaskStyle.neutralText,
                            ),
                          ),
                        for (final member in subtask.assignees)
                          MemberNameChip(name: member.name, permanent: member.isPermanent),
                        if (subtask.assignees.isEmpty)
                          const Text(
                            'אין אחראים',
                            style: TextStyle(
                              fontSize: TaskStyle.rowMetaSize,
                              color: TaskStyle.faintText,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'הסרה',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
