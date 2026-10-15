import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../../event/widgets/event_time_field.dart';
import 'discard_changes_dialog.dart';

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

/// Create a task, or edit [existing].
///
/// The form saves through [onSave] and stays open, with a spinner on the save
/// button, until that answers: it closes on success and shows the failure
/// otherwise, so nothing typed is lost. An edit can only be saved once
/// something in it changed, and cancelling a form that holds changes asks
/// first. The form only decides the fields a task manager edits; progress,
/// completion and timestamps on the saved task are whatever [existing] had and
/// are ignored by the backend.
///
/// The task sits under [stage] of [event]: neither is chosen here, and the
/// task's day is the stage's. [watchEventAssignees] is the live list of
/// members a task on the event may be assigned to.
Future<void> showTaskFormModal(
  BuildContext context, {
  TaskItem? existing,
  required Event event,
  required Stage stage,
  required Stream<List<TeamMember>> Function(String eventId)
      watchEventAssignees,
  required Future<CrudActionResult> Function(TaskItem task) onSave,
  required String currentUserId,
  DateTime? now,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TaskFormModal(
      existing: existing,
      event: event,
      stage: stage,
      watchEventAssignees: watchEventAssignees,
      onSave: onSave,
      currentUserId: currentUserId,
      now: now ?? DateTime.now(),
    ),
  );
}

/// One editable subtask row. Keeps the subtask's identity and done state so a
/// rename does not reset its progress.
class _SubtaskDraft {
  _SubtaskDraft({required this.id, required this.isDone, String title = ''})
      : controller = TextEditingController(text: title) {
    focusNode = createRtlCursorFixedFocusNode(controller);
  }

  final String id;
  final bool isDone;
  final TextEditingController controller;
  late final FocusNode focusNode;

  void dispose() {
    focusNode.dispose();
    controller.dispose();
  }
}

class _TaskFormModal extends StatefulWidget {
  const _TaskFormModal({
    required this.existing,
    required this.event,
    required this.stage,
    required this.watchEventAssignees,
    required this.onSave,
    required this.currentUserId,
    required this.now,
  });

  final TaskItem? existing;
  final Event event;
  final Stage stage;
  final Stream<List<TeamMember>> Function(String eventId) watchEventAssignees;
  final Future<CrudActionResult> Function(TaskItem task) onSave;
  final String currentUserId;
  final DateTime now;

  @override
  State<_TaskFormModal> createState() => _TaskFormModalState();
}

class _TaskFormModalState extends State<_TaskFormModal> {
  static const _uuid = Uuid();

  // Chosen once per form, so saving again after a failure sends the same task
  // rather than a second one.
  late final String _newTaskId = _uuid.v4();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _assemblyTimeController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _descriptionFocusNode;
  late final List<_SubtaskDraft> _subtasks;

  // Narrows the rows of the open assignee dropdown. Only a view filter: it
  // never changes who is assigned.
  final TextEditingController _assigneeSearchController =
      TextEditingController();
  late final FocusNode _assigneeSearchFocusNode =
      createRtlCursorFixedFocusNode(_assigneeSearchController);
  String _assigneeQuery = '';

  String? _assemblyTimeError;

  // Who is assigned, by id, in the order they were picked. The members
  // themselves are kept so that someone picked stays listed after they drop
  // out of the event's own list.
  final Map<String, TeamMember> _picked = <String, TeamMember>{};

  // The members assigned to the event, live. Null until the first list
  // arrives.
  List<TeamMember>? _eventAssignees;
  StreamSubscription<List<TeamMember>>? _assigneesSubscription;
  bool _assigneesFailed = false;
  bool _assigneesOpen = false;

  bool _isSaving = false;
  String? _saveError;

  // What the form held when it opened; see [_currentValue].
  late final List<Object?> _openingValue;

  bool get _isEditing => widget.existing != null;

  bool get _canSave =>
      !_isSaving &&
      _titleController.text.trim().isNotEmpty &&
      _picked.isNotEmpty &&
      // Saving an edit that changes nothing would only bump its "updated" time.
      (!_isEditing || _hasChanges);

  /// What a save would send, as plain values. Reduced the way a save reduces
  /// it, so spaces around a text and empty subtask rows are not a change, and
  /// neither is the order the same assignees were picked in.
  List<Object?> _currentValue() {
    return [
      _titleController.text.trim(),
      _descriptionController.text.trim(),
      _assemblyTimeController.text.trim(),
      _picked.keys.toList()..sort(),
      [
        for (final draft in _subtasks)
          if (draft.controller.text.trim().isNotEmpty) ...[
            draft.id,
            draft.controller.text.trim(),
          ],
      ],
    ];
  }

  bool get _hasChanges =>
      !const DeepCollectionEquality().equals(_currentValue(), _openingValue);

  bool get _canOpenAssignees => _eventAssignees != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _titleFocusNode = createRtlCursorFixedFocusNode(_titleController);
    _descriptionFocusNode =
        createRtlCursorFixedFocusNode(_descriptionController);

    _assemblyTimeController =
        TextEditingController(text: existing?.assemblyTime ?? '');

    // The task's assignees stay picked whoever the event's list holds, so
    // saving an edit never drops someone the manager did not touch.
    for (final member in existing?.assignees ?? const <TeamMember>[]) {
      _picked[member.id] = member;
    }

    _subtasks = [
      for (final subtask in existing?.subtasks ?? const <Subtask>[])
        _SubtaskDraft(
          id: subtask.id,
          isDone: subtask.isDone,
          title: subtask.title,
        ),
    ];

    _openingValue = _currentValue();

    _watchAssignees(widget.event.id);
  }

  @override
  void dispose() {
    _assigneesSubscription?.cancel();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _assigneeSearchFocusNode.dispose();
    _assigneeSearchController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _assemblyTimeController.dispose();
    for (final draft in _subtasks) {
      draft.dispose();
    }
    super.dispose();
  }

  /// Follow who is assigned to [eventId].
  void _watchAssignees(String eventId) {
    _assigneesSubscription = widget.watchEventAssignees(eventId).listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _eventAssignees = members;
          _assigneesFailed = false;
          // Someone picked who was renamed shows their new name.
          for (final member in members) {
            if (_picked.containsKey(member.id)) _picked[member.id] = member;
          }
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _assigneesFailed = true);
      },
    );
  }

  void _addSubtask() {
    setState(() {
      _subtasks.add(_SubtaskDraft(id: _uuid.v4(), isDone: false));
    });
  }

  void _removeSubtask(_SubtaskDraft draft) {
    setState(() => _subtasks.remove(draft));
    // Disposed after the frame that drops the row, not while its TextField is
    // still mounted on these objects.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  /// Close without saving. A form that holds changes asks first.
  Future<void> _cancel() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final leave =
        await confirmDiscardChanges(context, keyPrefix: 'task-form');
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    // An empty time is fine and means "by the end of that day". A time that
    // was typed but is not a real time is refused rather than quietly saved
    // as something the manager did not enter.
    final assemblyTime = _assemblyTimeController.text.trim();
    if (assemblyTime.isNotEmpty && !isValidDueTime(assemblyTime)) {
      setState(() => _assemblyTimeError =
          'שעת ההתייצבות אינה תקינה. יש להזין שעה כמו 09:30, או להשאיר ריק.');
      return;
    }
    final subtasks = [
      for (final draft in _subtasks)
        if (draft.controller.text.trim().isNotEmpty)
          Subtask(
            id: draft.id,
            title: draft.controller.text.trim(),
            isDone: draft.isDone,
          ),
    ];
    final assigneeIds = _picked.keys.toList();
    final assignees = _picked.values.toList();

    final existing = widget.existing;
    final TaskItem task;
    if (existing == null) {
      task = TaskItem(
        id: _newTaskId,
        eventId: widget.event.id,
        stageId: widget.stage.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subtasks: subtasks,
        assemblyTime: assemblyTime.isEmpty ? null : assemblyTime,
        assigneeIds: assigneeIds,
        // Placeholders: the backend stamps the real times.
        createdAt: widget.now,
        createdById: widget.currentUserId,
        updatedAt: widget.now,
        event: widget.event,
        stage: widget.stage,
        assignees: assignees,
      );
    } else {
      task = existing.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subtasks: subtasks,
        assemblyTime: assemblyTime.isEmpty ? null : assemblyTime,
        clearAssemblyTime: assemblyTime.isEmpty,
        assigneeIds: assigneeIds,
        event: widget.event,
        stage: widget.stage,
        assignees: assignees,
      );
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    final result = await widget.onSave(task);
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSaving = false;
      _saveError = result.message ?? 'השמירה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      // The back button and Escape go the way of the cancel button: a save in
      // flight cannot be walked away from, and unsaved changes ask first.
      child: PopScope(
        canPop: !_isSaving && !_hasChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_isSaving) _cancel();
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
                  child: Text(
                    _isEditing ? 'עריכת משימה' : 'משימה חדשה',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Flexible(
                  // Locked while saving: what was sent is what stays on screen.
                  child: AbsorbPointer(
                    absorbing: _isSaving,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildStageField(theme),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('task-form-title'),
                            controller: _titleController,
                            focusNode: _titleFocusNode,
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
                            focusNode: _descriptionFocusNode,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 5000,
                            decoration: const InputDecoration(
                              labelText: 'תיאור',
                              border: OutlineInputBorder(),
                              counterText: '',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          _buildAssemblyTimeField(theme),
                          const SizedBox(height: 20),
                          _buildAssignees(theme),
                          const SizedBox(height: 20),
                          _buildSubtasks(theme),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      _saveError!,
                      key: const Key('task-form-save-error'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const Key('task-form-cancel'),
                        onPressed: _isSaving ? null : _cancel,
                        child: const Text('ביטול'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('task-form-save'),
                        onPressed: _canSave ? _save : null,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
      ),
    );
  }

  /// The stage the task sits under, and so its day: shown, not chosen.
  Widget _buildStageField(ThemeData theme) {
    final stage = widget.stage;
    return InputDecorator(
      key: const Key('task-form-stage'),
      decoration: const InputDecoration(
        labelText: 'שלב',
        border: OutlineInputBorder(),
        enabled: false,
      ),
      child: Text(
        '${stage.title} · ${_dateFormat.format(stage.date)}',
        style: theme.textTheme.bodyLarge
            ?.copyWith(color: theme.disabledColor),
      ),
    );
  }

  Widget _buildAssemblyTimeField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EventTimeField(
          controller: _assemblyTimeController,
          label: 'שעת התייצבות',
          hint: 'לא חובה',
          logKey: 'taskAssembly',
          onChanged: () => setState(() => _assemblyTimeError = null),
        ),
        if (_assemblyTimeError != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, start: 12),
            child: Text(
              _assemblyTimeError!,
              key: const Key('task-form-assembly-time-error'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  /// The rows the open dropdown can show: the event's members, then anyone
  /// picked who is not among them.
  List<TeamMember> get _offeredMembers {
    final assigned = _eventAssignees ?? const <TeamMember>[];
    final assignedIds = {for (final member in assigned) member.id};
    return [
      ...assigned,
      ..._picked.values.where((member) => !assignedIds.contains(member.id)),
    ];
  }

  static String _searchable(String text) =>
      normalizeForSearch(text.trim()).toLowerCase();

  void _clearAssigneeSearch() {
    _assigneeSearchController.clear();
    setState(() => _assigneeQuery = '');
  }

  void _toggleAssigneesOpen() {
    // The search belongs to one opening of the dropdown; the next starts clean.
    _assigneeSearchController.clear();
    setState(() {
      _assigneesOpen = !_assigneesOpen;
      _assigneeQuery = '';
    });
  }

  void _setPicked(TeamMember member, bool isPicked) {
    // A search has done its job once its result is ticked: empty it and put
    // the cursor back, ready for the next name.
    final wasSearching = _assigneeQuery.isNotEmpty;
    if (wasSearching) _assigneeSearchController.clear();
    setState(() {
      if (isPicked) {
        _picked[member.id] = member;
      } else {
        _picked.remove(member.id);
      }
      _assigneeQuery = '';
    });
    if (wasSearching) _assigneeSearchFocusNode.requestFocus();
  }

  /// Why the dropdown cannot be opened yet, or null when it can.
  String? get _assigneesHint {
    if (_assigneesFailed) return 'טעינת המשובצים נכשלה';
    if (_eventAssignees == null) return 'טוען משובצים...';
    return null;
  }

  /// A dropdown that opens in place: closed it is one field naming who is
  /// picked, open it grows a search row and the event's members under it.
  Widget _buildAssignees(ThemeData theme) {
    final canOpen = _canOpenAssignees;
    final isOpen = canOpen && _assigneesOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('task-form-assignees'),
          onTap: canOpen ? _toggleAssigneesOpen : null,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            isEmpty: _picked.isEmpty,
            decoration: InputDecoration(
              labelText: 'אחראים',
              border: const OutlineInputBorder(),
              enabled: canOpen,
              helperText: _assigneesHint,
              suffixIcon: Icon(
                isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              ),
            ),
            child: _picked.isEmpty
                ? null
                : Text(_picked.values.map((member) => member.name).join(', ')),
          ),
        ),
        if (isOpen) ...[
          const SizedBox(height: 4),
          _buildAssigneeMenu(theme),
        ],
      ],
    );
  }

  Widget _buildAssigneeMenu(ThemeData theme) {
    final offered = _offeredMembers;
    final query = _searchable(_assigneeQuery);
    final visible = query.isEmpty
        ? offered
        : offered
            .where((member) => _searchable(member.name).contains(query))
            .toList();
    return Material(
      key: const Key('task-form-assignee-menu'),
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'אין משובצים לאירוע זה',
                style: theme.textTheme.bodySmall,
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                key: const Key('task-form-assignee-search'),
                controller: _assigneeSearchController,
                focusNode: _assigneeSearchFocusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'חיפוש חבר צוות...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _assigneeQuery.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('task-form-assignee-search-clear'),
                          tooltip: 'נקה חיפוש',
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: _clearAssigneeSearch,
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _assigneeQuery = value),
              ),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'לא נמצאו חברי צוות',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final member in visible)
                CheckboxListTile(
                  key: Key('task-form-assignee-${member.id}'),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(member.name),
                  value: _picked.containsKey(member.id),
                  onChanged: (value) => _setPicked(member, value ?? false),
                ),
          ],
        ],
      ),
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
                      focusNode: _subtasks[index].focusNode,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: 'תת-משימה ${index + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
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
