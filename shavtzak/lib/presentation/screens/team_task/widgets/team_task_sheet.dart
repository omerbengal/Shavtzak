import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../task/edit/editable_value.dart';
import '../../task/edit/value_editors.dart';
import '../../task/task_style.dart';
import '../../task/widgets/confirm_delete_dialog.dart';
import 'deadline_picker.dart';
import 'task_link_picker.dart';
import 'new_team_task_dialog.dart';
import 'team_task_actions.dart';
import 'team_task_row.dart';
import 'team_task_split_view.dart';
import 'team_task_style.dart';
import 'team_task_update_log.dart';

/// Opens one task: a sheet from the bottom on a phone, a centred panel (at
/// most 960 px) on a wide window, as the דו יומי task sheet.
///
/// [manage] false opens it as a member sees it even for a manager: a manager
/// edits tasks only from "כל המשימות"; in "המשימות שלי" they are a member like
/// any other (Omer, round 3).
///
/// Inside the list of a window wider than a phone ([TeamTaskPanelScope],
/// round 7) it opens in the list's side panel instead, with no new route.
Future<void> showTeamTaskSheet(BuildContext context, String taskId, {bool manage = true}) {
  final panel = TeamTaskPanelScope.maybeOf(context);
  if (panel != null) {
    panel.open(taskId);
    return Future.value();
  }
  final wide = MediaQuery.sizeOf(context).width >= TaskStyle.wideBreakpoint;
  final bloc = context.read<TeamTaskBloc>();
  Widget body(BuildContext _) => BlocProvider.value(
        value: bloc,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: TeamTaskSheet(taskId: taskId, wide: wide, manage: manage),
        ),
      );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: TaskStyle.wideSheetWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
          ),
          child: body(dialogContext),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: TaskStyle.sheetMaxSize,
      child: body(sheetContext),
    ),
  );
}

/// Everything about one task, live. A manager edits each value in place
/// (saved at once); an owner changes the status, ticks their own subtasks and
/// writes in the log; the rest is read-only.
class TeamTaskSheet extends StatefulWidget {
  const TeamTaskSheet({
    super.key,
    required this.taskId,
    required this.wide,
    this.manage = true,
    this.onClose,
  });

  final String taskId;
  final bool wide;

  /// In the side panel (round 7): closes it. Null = a route ([Navigator.pop]).
  final VoidCallback? onClose;

  /// Whether a manager gets the editing view here ([showTeamTaskSheet]).
  final bool manage;

  @override
  State<TeamTaskSheet> createState() => _TeamTaskSheetState();
}

class _TeamTaskSheetState extends State<TeamTaskSheet> {
  bool _closed = false;

  TeamTaskBloc get _bloc => context.read<TeamTaskBloc>();

  void _report(CrudActionCompleter completion) {
    completion.future.then((result) {
      if (!mounted || result.isSuccess) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    });
  }

  /// The task a subtask view belongs to, as it stands now.
  TeamTask? _parentOf(TeamTask view) {
    final state = _bloc.state;
    if (state is! TeamTasksLoaded || view.parentId == null) return null;
    return state.all.where((t) => t.id == view.parentId).firstOrNull;
  }

  /// Saves a manager's edit. A subtask is saved through its parent: the
  /// parent with this subtask's new fields.
  void _edit(TeamTask task) {
    var toSave = task;
    if (task.isSubtask) {
      final parent = _parentOf(task);
      if (parent == null) return;
      final edited = task.toSubtask();
      toSave = parent.copyWith(subtasks: [
        for (final subtask in parent.subtasks) subtask.id == task.id ? edited : subtask,
      ]);
    }
    final completion = CrudActionCompleter();
    _bloc.add(UpdateTeamTask(toSave, completion: completion));
    _report(completion);
  }

  /// "+ תת-משימה" on a saved task: the first one on a task with owners asks
  /// first (Omer, round 2); then the subtask form, saved into the task.
  Future<void> _addSubtask(TeamTask task) async {
    if (task.subtasks.isEmpty && task.assigneeIds.isNotEmpty) {
      final split = await confirmFirstSubtask(context);
      if (!split || !mounted) return;
    }
    final subtask = await showSubtaskFormDialog(context, parentTitle: task.title);
    if (subtask == null || !mounted) return;
    // The task as it stands now: it may have changed while the form was open.
    final state = _bloc.state;
    final parent = (state is TeamTasksLoaded ? state.taskById(task.id) : null) ?? task;
    final subtasks = [...parent.subtasks, subtask];
    _edit(parent.copyWith(
      subtasks: subtasks,
      assigneeIds: const [],
      ownerIds: teamTaskOwnerIds(parent.copyWith(subtasks: subtasks)),
    ));
  }

  Future<void> _delete(TeamTask task) {
    if (task.isSubtask) {
      return showConfirmDeleteDialog(
        context,
        title: 'מחיקת תת-משימה',
        message: 'למחוק את "${task.title}" לגמרי? אפשר במקום זה לסמן "לא רלוונטי/בוטל".',
        keyPrefix: 'team-task-delete',
        onDelete: () {
          final parent = _parentOf(task);
          if (parent == null) return Future.value(const CrudActionResult.success());
          final subtasks = [
            for (final subtask in parent.subtasks)
              if (subtask.id != task.id) subtask,
          ];
          final completion = CrudActionCompleter();
          _bloc.add(UpdateTeamTask(
            parent.copyWith(
              subtasks: subtasks,
              ownerIds: teamTaskOwnerIds(parent.copyWith(subtasks: subtasks)),
            ),
            completion: completion,
          ));
          return completion.future;
        },
      );
    }
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת משימה',
      message: 'למחוק את "${task.title}" לגמרי? אפשר במקום זה לסמן "לא רלוונטי/בוטל".',
      keyPrefix: 'team-task-delete',
      onDelete: () {
        final completion = CrudActionCompleter();
        _bloc.add(DeleteTeamTask(task.id, completion: completion));
        return completion.future;
      },
    );
  }

  Future<void> _pickDeadline(TeamTasksLoaded state, TeamTask task) async {
    final picked = await pickTeamTaskDeadline(
      context,
      initial: task.deadlineDate,
    );
    if (picked == null || !mounted) return;
    _edit(task.copyWith(deadline: () => dateKey(picked)));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TeamTaskBloc, TeamTaskState>(
      builder: (context, state) {
        if (state is! TeamTasksLoaded) return const SizedBox.shrink();
        final task = state.taskById(widget.taskId);
        if (task == null) {
          // Deleted, here or by someone else: close THIS sheet, once. A pop
          // would hit whatever is on top (the delete confirm, still waiting
          // for the backend, refuses it) and leave an empty sheet whose
          // barrier dims the screen until a tap.
          if (!_closed) {
            _closed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final onClose = widget.onClose;
              if (onClose != null) {
                onClose();
                return;
              }
              final route = ModalRoute.of(context);
              if (route == null || !route.isActive) return;
              final navigator = Navigator.of(context);
              if (route.isCurrent) {
                navigator.pop();
              } else {
                navigator.removeRoute(route);
              }
            });
          }
          return const SizedBox.shrink();
        }
        return _content(state, task);
      },
    );
  }

  Widget _content(TeamTasksLoaded state, TeamTask task) {
    final manage = state.canManage && widget.manage;
    final viewerId = state.viewer.id;
    final owner = isTeamTaskOwner(task, viewerId);
    final activeMembers = state.members.where((m) => m.isActive && !m.isArchived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final now = DateTime.now();
    final late = isTeamTaskLate(task, now);

    return Material(
      key: const Key('team-task-panel'),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _header(task, manage),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // A subtask belongs where its parent does.
                _section('שיוך', _linkValue(state, task, manage && !task.isSubtask)),
                // A parent's status follows its subtasks; nobody sets it (round 4).
                _section(
                    'סטטוס', _statusValue(state, task, (manage || owner) && task.subtasks.isEmpty)),
                _section('דד ליין', _deadlineValue(state, task, manage, late)),
                // A subtask is one line of text (Omer, round 10): no
                // description. One saved before keeps showing, read-only,
                // until Omer decides what becomes of them.
                if (!task.isSubtask)
                  _section('תיאור', _descriptionValue(task, manage))
                else if (task.description.isNotEmpty)
                  _section(
                    'תיאור (מלפני השינוי)',
                    Text(task.description, key: const Key('team-task-legacy-description')),
                  ),
                _section('אחראים', _ownersValue(task, manage, activeMembers, viewerId)),
                _section('אנשי קשר', _contactsValue(task, manage)),
                if (!task.isSubtask)
                  _section(
                    task.subtasks.isEmpty
                        ? 'תתי-משימות'
                        : 'תתי-משימות (${task.doneSubtasks}/${task.subtasks.length})',
                    _subtasksValue(task, manage, viewerId),
                  ),
                _section(
                  'יומן עדכונים',
                  TeamTaskUpdateLog(
                    task: task,
                    canWrite: manage || owner,
                    // Everyone's updates only in "כל המשימות" (round 10).
                    canEditAll: manage,
                  ),
                ),
                if (manage) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('team-task-delete'),
                      style: TextButton.styleFrom(foregroundColor: TaskStyle.delete),
                      onPressed: () => _delete(task),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(task.isSubtask ? 'מחיקת תת-המשימה' : 'מחיקת המשימה'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(TeamTask task, bool manage) {
    final title = Text(
      task.title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    // What this card is: a parent of subtasks, or a subtask (and of what).
    final kind = task.isSubtask
        ? 'תת-משימה של: ${task.parentTitle}'
        : (task.subtasks.isNotEmpty ? 'משימת אב' : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
                    // A subtask's line opens its parent (a subtask owner
                    // reaches the parent only from here).
                    child: InkWell(
                      key: const Key('team-task-kind'),
                      onTap: task.isSubtask
                          ? () => showTeamTaskSheet(context, task.parentId!, manage: widget.manage)
                          : null,
                      child: Text(
                        kind,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: task.isSubtask ? TaskStyle.edit : TaskStyle.neutralText,
                          decoration: task.isSubtask ? TextDecoration.underline : null,
                        ),
                      ),
                    ),
                  ),
                manage
                    ? EditableValue<String>(
                        key: const Key('team-task-edit-title'),
                        value: task.title,
                        display: title,
                        sheetTitle: task.isSubtask ? 'תת-המשימה' : 'שם המשימה',
                        wide: widget.wide,
                        validate: (draft) => draft.trim().isEmpty ? 'חובה להזין כותרת' : null,
                        editor: (context, draft, onChanged, onSubmit) => TextValueEditor(
                          initial: draft,
                          onChanged: onChanged,
                          onSubmit: onSubmit,
                        ),
                        onCommit: (value) => _edit(task.copyWith(title: value.trim())),
                      )
                    : Padding(padding: const EdgeInsets.all(8), child: title),
              ],
            ),
          ),
          IconButton(
            key: const Key('team-task-close'),
            tooltip: 'סגירה',
            icon: const Icon(Icons.close),
            onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: TaskStyle.faintText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _tappable(
      {required Key key,
      required bool enabled,
      required VoidCallback onTap,
      required Widget child}) {
    if (!enabled) return child;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(TaskStyle.editRadius),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
    );
  }

  Widget _linkValue(TeamTasksLoaded state, TeamTask task, bool manage) {
    final label = task.link == null ? noLinkLabel : teamTaskLinkLabel(task);
    final kind = switch (task.link?.type) {
      TaskLinkType.event => 'אירוע: ',
      TaskLinkType.category => 'קטגוריה: ',
      TaskLinkType.topic => 'נושא: ',
      TaskLinkType.pendingEvent => '$pendingEventLabel: ',
      null => '',
    };
    return _tappable(
      key: const Key('team-task-edit-link'),
      enabled: manage,
      onTap: () async {
        final choice = await showTaskLinkPicker(context, initial: task.link);
        if (choice == null || choice.link == task.link) return;
        _edit(task.copyWith(link: () => choice.link));
      },
      child: Text('$kind$label'),
    );
  }

  Widget _statusValue(TeamTasksLoaded state, TeamTask task, bool canChange) {
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamTaskStatusChip(status: task.status),
        if (canChange) const Icon(Icons.arrow_drop_down, color: TaskStyle.neutralText),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A parent's chip tells that its status updates by itself (round 5).
        if (canChange || isTeamTaskParent(task))
          TeamTaskStatusMenu(key: const Key('team-task-status'), task: task, child: chip)
        else
          chip,
        if (task.subtasks.isNotEmpty)
          const Padding(
            key: Key('team-task-status-auto'),
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'נקבע אוטומטית לפי הסטטוסים של תתי-המשימות',
              style: TextStyle(fontSize: 12, color: TaskStyle.faintText),
            ),
          ),
        if (task.status == TeamTaskStatus.duplicate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'כפילות של: ${state.duplicateOriginalLabel(task)}',
              style: const TextStyle(color: TaskStyle.neutralText),
            ),
          ),
      ],
    );
  }

  Widget _deadlineValue(TeamTasksLoaded state, TeamTask task, bool manage, bool late) {
    final date = task.deadlineDate;
    final text = Text(
      date == null ? 'ללא דד ליין' : (late ? '${fullDate(date)} · באיחור' : fullDate(date)),
      style: TextStyle(
        color: late ? TaskStyle.late : null,
        fontWeight: late ? FontWeight.w600 : null,
      ),
    );
    if (!manage) return text;
    return Row(
      children: [
        _tappable(
          key: const Key('team-task-edit-deadline'),
          enabled: true,
          onTap: () => _pickDeadline(state, task),
          child: text,
        ),
        if (date != null)
          IconButton(
            key: const Key('team-task-clear-deadline'),
            tooltip: 'בלי דד ליין',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => _edit(task.copyWith(deadline: () => null)),
          ),
      ],
    );
  }

  Widget _descriptionValue(TeamTask task, bool manage) {
    final display = Text(
      task.description.isEmpty ? (manage ? 'הוספת תיאור' : 'ללא תיאור') : task.description,
      style: TextStyle(color: task.description.isEmpty ? TaskStyle.faintText : null),
    );
    if (!manage) return display;
    return EditableValue<String>(
      key: const Key('team-task-edit-description'),
      value: task.description,
      display: display,
      sheetTitle: 'תיאור',
      wide: widget.wide,
      editor: (context, draft, onChanged, onSubmit) => TextValueEditor(
        initial: draft,
        multiline: true,
        onChanged: onChanged,
        onSubmit: onSubmit,
      ),
      onCommit: (value) => _edit(task.copyWith(description: value.trim())),
    );
  }

  Widget _ownersValue(
    TeamTask task,
    bool manage,
    List<TeamMember> activeMembers,
    String viewerId,
  ) {
    final owners = teamTaskOwnerChips(task);
    final chips = owners.isEmpty
        ? const Text('אין אחראים', style: TextStyle(color: TaskStyle.faintText))
        : Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final owner in owners)
                MemberNameChip(
                  name: owner.name,
                  permanent: owner.permanent,
                  highlight: owner.id == viewerId,
                ),
            ],
          );
    if (task.subtasks.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chips,
          const SizedBox(height: 2),
          const Text(
            'במשימה עם תתי-משימות, האחראים הם האחראים על תתי-המשימות',
            style: TextStyle(fontSize: 12, color: TaskStyle.faintText),
          ),
        ],
      );
    }
    if (!manage) return chips;
    return EditableValue<List<String>>(
      key: const Key('team-task-edit-owners'),
      value: task.assigneeIds,
      display: chips,
      sheetTitle: 'אחראים',
      wide: widget.wide,
      inDialog: true,
      editor: (context, draft, onChanged, onSubmit) => AssigneesEditor(
        initial: draft,
        offered: activeMembers,
        current: task.owners,
        onChanged: onChanged,
        emptyLabel: 'אין חברי צוות',
        notOfferedLabel: 'כבר לא פעיל/ה בצוות',
        pickedFirst: true,
        showPermanentMark: true,
      ),
      onCommit: (ids) => _edit(task.copyWith(assigneeIds: ids, ownerIds: ids)),
    );
  }

  Widget _contactsValue(TeamTask task, bool manage) {
    final list = _contactLines(task.contacts, 'team-task-contact');
    if (!manage) {
      return task.contacts.isEmpty
          ? const Text('אין אנשי קשר', style: TextStyle(color: TaskStyle.faintText))
          : list;
    }
    return EditableValue<List<StageContact>>(
      key: const Key('team-task-edit-contacts'),
      value: task.contacts,
      display: task.contacts.isEmpty
          ? const Text('הוספת אנשי קשר', style: TextStyle(color: TaskStyle.faintText))
          : list,
      sheetTitle: 'אנשי קשר',
      wide: widget.wide,
      inDialog: true,
      editor: (context, draft, onChanged, onSubmit) =>
          ContactsEditor(initial: draft, onChanged: onChanged),
      validate: (draft) => draft.any((c) => c.name.trim().isEmpty) ? 'לכל איש קשר נדרש שם' : null,
      onCommit: (contacts) => _edit(task.copyWith(contacts: contacts)),
    );
  }

  Widget _contactLines(List<StageContact> contacts, String keyPrefix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final contact in contacts)
          _ContactLine(key: Key('$keyPrefix-${contact.id}'), contact: contact),
      ],
    );
  }

  /// The subtasks as rows like the list's (status, deadline, owners), each
  /// opening its own task screen; its status circle opens the status menu
  /// for a manager or the subtask's owner (Omer, round 4: a status, not a
  /// tick). A manager adds one with "+ תת-משימה".
  Widget _subtasksValue(TeamTask task, bool manage, String viewerId) {
    final now = DateTime.now();
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final subtask in task.subtasks)
          TeamTaskRow(
            key: Key('team-subtask-row-${subtask.id}'),
            task: TeamTask.subtaskView(task, subtask),
            now: now,
            viewerId: viewerId,
            nested: true,
            canChangeStatus: manage || subtask.assigneeIds.contains(viewerId),
            onTap: () => showTeamTaskSheet(context, subtask.id, manage: widget.manage),
          ),
      ],
    );
    if (!manage) {
      return task.subtasks.isEmpty
          ? const Text('אין תתי-משימות', style: TextStyle(color: TaskStyle.faintText))
          : rows;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rows,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('team-task-add-subtask'),
            onPressed: () => _addSubtask(task),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('תת-משימה'),
          ),
        ),
      ],
    );
  }
}

/// One contact: name, role, and the phone, which asks "להתקשר ל…?" first.
class _ContactLine extends StatelessWidget {
  const _ContactLine({super.key, required this.contact});

  final StageContact contact;

  Future<void> _call(BuildContext context) async {
    final call = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const Key('confirm-call'),
          title: Text('להתקשר ל${contact.name}?'),
          content: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(contact.phone, style: const TextStyle(fontSize: 18)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton.icon(
              key: const Key('confirm-call-button'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.phone),
              label: const Text('התקשר'),
            ),
          ],
        ),
      ),
    );
    if (call != true) return;
    final uri = Uri(scheme: 'tel', path: contact.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final role = contact.role.isEmpty ? '' : ' · ${contact.role}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(child: Text('${contact.name}$role')),
          if (contact.phone.isNotEmpty) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _call(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone, size: 14, color: TaskStyle.mine),
                  const SizedBox(width: 2),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(contact.phone, style: const TextStyle(color: TaskStyle.mine)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
