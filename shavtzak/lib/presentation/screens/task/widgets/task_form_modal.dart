import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../widgets/date_picker_dialog.dart';
import '../../event/widgets/event_time_field.dart';

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
final DateFormat _timeFormat = DateFormat('HH:mm');

/// Create a task, or edit [existing].
///
/// Returns the task to save, or null when cancelled. The form only decides the
/// fields a task manager edits; progress, completion and timestamps on the
/// returned task are whatever [existing] had and are ignored by the backend.
///
/// [events] and [members] are the full lists: the form narrows them to future
/// events and assignable members itself.
Future<TaskItem?> showTaskFormModal(
  BuildContext context, {
  TaskItem? existing,
  required List<Event> events,
  required List<TeamMember> members,
  required String currentUserId,
  DateTime? now,
}) {
  return showDialog<TaskItem>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TaskFormModal(
      existing: existing,
      events: events,
      members: members,
      currentUserId: currentUserId,
      now: now ?? DateTime.now(),
    ),
  );
}

/// One editable subtask row. Keeps the subtask's identity and done state so a
/// rename does not reset its progress.
class _SubtaskDraft {
  _SubtaskDraft({required this.id, required this.isDone, String title = ''})
      : controller = TextEditingController(text: title);

  final String id;
  final bool isDone;
  final TextEditingController controller;
}

class _TaskFormModal extends StatefulWidget {
  const _TaskFormModal({
    required this.existing,
    required this.events,
    required this.members,
    required this.currentUserId,
    required this.now,
  });

  final TaskItem? existing;
  final List<Event> events;
  final List<TeamMember> members;
  final String currentUserId;
  final DateTime now;

  @override
  State<_TaskFormModal> createState() => _TaskFormModalState();
}

class _TaskFormModalState extends State<_TaskFormModal> {
  static const _uuid = Uuid();

  late final List<Event> _pickableEvents;
  late final List<TeamMember> _assignableMembers;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _dueTimeController;
  late final List<_SubtaskDraft> _subtasks;

  String? _eventId;
  DateTime? _dueDate;
  // Insertion-ordered, so assignees keep the order they were picked in.
  final Set<String> _assigneeIds = <String>{};

  bool get _isEditing => widget.existing != null;

  bool get _canSave =>
      _eventId != null &&
      _titleController.text.trim().isNotEmpty &&
      _assigneeIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _pickableEvents = pickableTaskEvents(
      widget.events,
      now: widget.now,
      current: existing?.event,
    );
    _assignableMembers = assignableTaskMembers(
      widget.members,
      currentAssigneeIds: existing?.assigneeIds ?? const [],
    );

    // An event that no longer exists cannot stay selected: the dropdown would
    // have no item for it. The manager has to pick a new one.
    final existingEventId = existing?.eventId;
    _eventId = _pickableEvents.any((event) => event.id == existingEventId)
        ? existingEventId
        : null;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');

    final dueAt = existing?.dueAt;
    _dueDate = dueAt;
    _dueTimeController = TextEditingController(
      text: dueAt == null ? '' : _timeFormat.format(dueAt),
    );

    final assignableIds = _assignableMembers.map((member) => member.id).toSet();
    _assigneeIds.addAll(
      (existing?.assigneeIds ?? const <String>[]).where(assignableIds.contains),
    );

    _subtasks = [
      for (final subtask in existing?.subtasks ?? const <Subtask>[])
        _SubtaskDraft(
          id: subtask.id,
          isDone: subtask.isDone,
          title: subtask.title,
        ),
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dueTimeController.dispose();
    for (final draft in _subtasks) {
      draft.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: true,
        initialStartDate: _dueDate,
        title: 'בחר תאריך יעד',
      ),
    );
    final picked = result?['startDate'];
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  void _clearDueDate() {
    setState(() {
      _dueDate = null;
      _dueTimeController.clear();
    });
  }

  void _addSubtask() {
    setState(() {
      _subtasks.add(_SubtaskDraft(id: _uuid.v4(), isDone: false));
    });
  }

  void _removeSubtask(_SubtaskDraft draft) {
    setState(() => _subtasks.remove(draft));
    draft.controller.dispose();
  }

  void _save() {
    if (!_canSave) return;
    final eventId = _eventId!;
    final event = _pickableEvents.firstWhere((event) => event.id == eventId);
    final dueAt = composeDueAt(_dueDate, _dueTimeController.text);
    final subtasks = [
      for (final draft in _subtasks)
        if (draft.controller.text.trim().isNotEmpty)
          Subtask(
            id: draft.id,
            title: draft.controller.text.trim(),
            isDone: draft.isDone,
          ),
    ];
    final assigneeIds = _assigneeIds.toList();
    final assignees = [
      for (final id in assigneeIds)
        ..._assignableMembers.where((member) => member.id == id),
    ];

    final existing = widget.existing;
    final TaskItem task;
    if (existing == null) {
      task = TaskItem(
        id: _uuid.v4(),
        eventId: eventId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subtasks: subtasks,
        dueAt: dueAt,
        assigneeIds: assigneeIds,
        // Placeholders: the backend stamps the real times.
        createdAt: widget.now,
        createdById: widget.currentUserId,
        updatedAt: widget.now,
        event: event,
        assignees: assignees,
      );
    } else {
      task = existing.copyWith(
        eventId: eventId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subtasks: subtasks,
        dueAt: dueAt,
        clearDueAt: dueAt == null,
        assigneeIds: assigneeIds,
        event: event,
        assignees: assignees,
      );
    }
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
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
                child: Text(
                  _isEditing ? 'עריכת משימה' : 'משימה חדשה',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEventField(),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('task-form-title'),
                        controller: _titleController,
                        maxLength: 200,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'כותרת',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('task-form-description'),
                        controller: _descriptionController,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 5000,
                        decoration: const InputDecoration(
                          labelText: 'תיאור',
                          border: OutlineInputBorder(),
                          counterText: '',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDueFields(theme),
                      const SizedBox(height: 20),
                      _buildAssignees(theme),
                      const SizedBox(height: 20),
                      _buildSubtasks(theme),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('task-form-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ביטול'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('task-form-save'),
                      onPressed: _canSave ? _save : null,
                      child: const Text('שמירה'),
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

  Widget _buildEventField() {
    return DropdownButtonFormField<String>(
      key: const Key('task-form-event'),
      initialValue: _eventId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'אירוע',
        border: const OutlineInputBorder(),
        helperText: _pickableEvents.isEmpty ? 'אין אירועים עתידיים' : null,
      ),
      items: [
        for (final event in _pickableEvents)
          DropdownMenuItem<String>(
            value: event.id,
            child: Text(
              '${event.name} · ${_dateFormat.format(event.startDate)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => setState(() => _eventId = value),
    );
  }

  Widget _buildDueFields(ThemeData theme) {
    final dueDate = _dueDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('task-form-due-date'),
                onPressed: _pickDueDate,
                icon: const Icon(Icons.event),
                label: Text(
                  dueDate == null
                      ? 'תאריך יעד (לא חובה)'
                      : 'תאריך יעד: ${_dateFormat.format(dueDate)}',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            if (dueDate != null)
              IconButton(
                key: const Key('task-form-due-clear'),
                tooltip: 'הסרת תאריך היעד',
                icon: const Icon(Icons.close),
                onPressed: _clearDueDate,
              ),
          ],
        ),
        // The time only means something next to a date, so it appears with it.
        if (dueDate != null) ...[
          const SizedBox(height: 12),
          EventTimeField(
            controller: _dueTimeController,
            label: 'שעת יעד',
            hint: 'ללא שעה: עד סוף היום',
            logKey: 'taskDue',
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _buildAssignees(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('אחראים', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_assignableMembers.isEmpty)
          Text('אין חברי צוות פעילים', style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final member in _assignableMembers)
                FilterChip(
                  key: Key('task-form-assignee-${member.id}'),
                  label: Text(member.name),
                  selected: _assigneeIds.contains(member.id),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _assigneeIds.add(member.id);
                      } else {
                        _assigneeIds.remove(member.id);
                      }
                    });
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSubtasks(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('תתי-משימות', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var index = 0; index < _subtasks.length; index++)
          KeyedSubtree(
            key: ObjectKey(_subtasks[index]),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('task-form-subtask-$index'),
                      controller: _subtasks[index].controller,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: 'תת-משימה ${index + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('task-form-subtask-remove-$index'),
                    tooltip: 'הסרת תת-המשימה',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeSubtask(_subtasks[index]),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          key: const Key('task-form-add-subtask'),
          onPressed: _subtasks.length >= 50 ? null : _addSubtask,
          icon: const Icon(Icons.add),
          label: const Text('הוספת תת-משימה'),
        ),
      ],
    );
  }
}
