import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/app_text_field.dart';
import '../../task/edit/value_editors.dart';
import '../../task/widgets/discard_changes_dialog.dart';
import 'deadline_picker.dart';
import 'task_link_picker.dart';
import 'team_task_style.dart';

/// "+ משימה חדשה": the whole task, before it exists, in the shape of the
/// דו יומי task form, in Omer's order (round 10): what it belongs to (one or
/// more events, a category or a topic), title, description, owners (an
/// in-place dropdown with a search), deadline, urgency (16/11/2026), then
/// contacts. [link] comes preset from a card's "+" (round 10). Subtasks were
/// removed (Omer, 16/11/2026).
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

class _TeamTaskForm extends StatefulWidget {
  const _TeamTaskForm({this.initialLink});

  final TaskLink? initialLink;

  @override
  State<_TeamTaskForm> createState() => _TeamTaskFormState();
}

class _TeamTaskFormState extends State<_TeamTaskForm> {
  // Chosen once per form, so saving again after a failure sends the same task.
  late final String _id = const Uuid().v4();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late TaskLink? _link = widget.initialLink;

  /// Every event picked (a task of several events), [_link]'s first.
  late List<String> _eventIds = widget.initialLink?.type == TaskLinkType.event
      ? [widget.initialLink!.id]
      : const [];
  DateTime? _deadline;
  TeamTaskUrgency _urgency = TeamTaskUrgency.normal;
  List<String> _owners = const [];
  bool _ownersOpen = false;
  List<StageContact> _contacts = const [];
  bool _showContacts = false;
  String? _titleError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    return _title.text.trim().isNotEmpty ||
        _description.text.trim().isNotEmpty ||
        _link != widget.initialLink ||
        _eventIds.length > 1 ||
        _deadline != null ||
        _urgency != TeamTaskUrgency.normal ||
        _owners.isNotEmpty ||
        _contacts.isNotEmpty;
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
      setState(() => _titleError = 'חובה להזין כותרת');
      return;
    }
    if (_contacts.any((c) => c.name.trim().isEmpty)) {
      setState(() => _error = 'לכל איש קשר נדרש שם');
      return;
    }
    final now = DateTime.now();
    final task = TeamTask(
      id: _id,
      title: title,
      description: _description.text.trim(),
      link: _link,
      eventIds: _link?.type == TaskLinkType.event ? _eventIds : const [],
      urgency: _urgency,
      assigneeIds: _owners,
      ownerIds: _owners,
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
                    Text('משימה חדשה',
                        key: const Key('new-team-task-heading'),
                        style: theme.textTheme.titleLarge),
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
                        _linkField(state),
                        const SizedBox(height: 16),
                        AppTextField(
                          key: const Key('new-team-task-title'),
                          controller: _title,
                          // No autofocus (Omer, 25/11/2026): an iPhone opens
                          // no keyboard for a focus that is not in a tap, so
                          // the field only looked ready.
                          maxLength: 200,
                          minLines: 1,
                          maxLines: 1,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'כותרת',
                            prefixIcon: const Icon(Icons.title),
                            errorText: _titleError,
                            border: const OutlineInputBorder(),
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() => _titleError = null),
                        ),
                        ...[
                          const SizedBox(height: 16),
                          AppTextField(
                            key: const Key('new-team-task-description'),
                            controller: _description,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'תיאור',
                              prefixIcon: Icon(Icons.notes),
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _ownersField(state, active),
                        const SizedBox(height: 16),
                        _deadlineField(state),
                        const SizedBox(height: 16),
                        InputDecorator(
                          key: const Key('new-team-task-urgency'),
                          decoration: const InputDecoration(
                            labelText: 'דחיפות',
                            prefixIcon: Icon(Icons.flag_outlined),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsetsDirectional.fromSTEB(0, 14, 12, 10),
                          ),
                          child: TeamTaskUrgencyPicker(
                            value: _urgency,
                            showLabel: false,
                            onChanged: (urgency) => setState(() => _urgency = urgency),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _contactsSection(theme),
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
    required IconData icon,
    IconData? trailing = Icons.arrow_drop_down,
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
          // The field's own icon on the right (the start, in Hebrew).
          prefixIcon: Icon(icon),
          suffixIcon: value != null && onClear != null
              ? IconButton(
                  tooltip: 'ניקוי',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                )
              : trailing == null
                  ? null
                  : Icon(trailing),
        ),
        child: value == null ? null : Text(value),
      ),
    );
  }

  Widget _linkField(TeamTasksLoaded state) {
    return _pickerField(
      key: const Key('new-team-task-link'),
      label: 'שיוך: אירוע (אחד או יותר), קטגוריה או נושא',
      icon: Icons.label_outline,
      value: _eventIds.length > 1
          ? _eventIds
              .map((id) => taskLinkName(state, TaskLink(TaskLinkType.event, id)) ?? 'אירוע שנמחק')
              .join(', ')
          : taskLinkName(state, _link),
      onTap: () async {
        final choice =
            await showTaskLinkPicker(context, initial: _link, initialEventIds: _eventIds);
        if (choice != null) {
          setState(() {
            _link = choice.link;
            _eventIds = choice.linkedEventIds;
          });
        }
      },
      onClear: () => setState(() {
        _link = null;
        _eventIds = const [];
      }),
    );
  }

  Widget _deadlineField(TeamTasksLoaded state) {
    return _pickerField(
      key: const Key('new-team-task-deadline'),
      label: 'דד ליין (לא חובה)',
      value: _deadline == null ? null : fullDate(_deadline!),
      // The calendar moved from the left to the right (msg 4480).
      icon: Icons.event,
      trailing: null,
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
              prefixIcon: const Icon(Icons.group_outlined),
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
        Row(
          key: const Key('new-team-task-contacts-title'),
          children: [
            const Icon(Icons.contact_phone_outlined, size: 20),
            const SizedBox(width: 8),
            Text('אנשי קשר', style: theme.textTheme.titleSmall),
          ],
        ),
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
}
