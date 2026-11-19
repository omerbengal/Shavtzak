import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/debounced_saver.dart';
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
import 'live_owners_picker.dart';
import 'task_link_picker.dart';
import 'team_task_actions.dart';
import 'team_task_split_view.dart';
import 'team_task_style.dart';
import 'team_task_mentions.dart';
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
    // A modal bottom sheet ignores the keyboard: on a phone (the web reports
    // the keyboard as a bottom inset while a field is edited) the sheet kept
    // its height and the "+ עדכון" field at the bottom of the log sat under
    // the keyboard (Omer, 17/11/2026). Lifting the sheet by the inset keeps
    // the list's viewport above the keyboard, so the focused field scrolls
    // into view there.
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: FractionallySizedBox(
        heightFactor: TaskStyle.sheetMaxSize,
        child: body(sheetContext),
      ),
    ),
  );
}

/// Everything about one task, live. A manager edits each value in place
/// (saved at once); an owner changes the status and writes in the log; the
/// rest is read-only.
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

  // Kept, not looked up: a picker's last change is sent as the sheet closes
  // and may be refused after it is gone.
  late final TeamTaskBloc _bloc = context.read<TeamTaskBloc>();
  ScaffoldMessengerState? _messenger;

  static const _ownersField = 'owners';
  static const _linkField = 'link';

  /// The owners and the link have no save button (Omer, 16/11/2026): every
  /// tick is saved, a moment after the last one, in one call.
  late final DebouncedSaver<List<String>> _owners = DebouncedSaver<List<String>>(
    send: (ids) => _sendField(_ownersField, (task) => task.copyWith(assigneeIds: ids, ownerIds: ids)),
    onDraft: (ids) => _draft(
        _ownersField, ids == null ? null : (task) => task.copyWith(assigneeIds: ids)),
    onFailure: _showError,
  );

  late final DebouncedSaver<TaskLinkChoice> _link = DebouncedSaver<TaskLinkChoice>(
    send: (choice) => _sendField(_linkField, (task) => _linked(task, choice)),
    onDraft: (choice) =>
        _draft(_linkField, choice == null ? null : (task) => _linked(task, choice)),
    // No event marked: the picker hands an event link with no id.
    validate: (choice) => choice.link?.type == TaskLinkType.event && choice.link!.id.isEmpty
        ? noEventMarkedHint
        : null,
    onFailure: _showError,
  );

  static TeamTask _linked(TeamTask task, TaskLinkChoice choice) =>
      task.copyWith(link: () => choice.link, eventIds: choice.linkedEventIds);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // Sends a change still waiting for its moment.
    _owners.dispose();
    _link.dispose();
    super.dispose();
  }

  void _draft(String field, TeamTask Function(TeamTask task)? apply) =>
      _bloc.add(TeamTaskDraftChanged(widget.taskId, field, apply));

  /// Sends [field] of the task as it stands now (other fields included, as
  /// any edit does), taking its draft over in the same step.
  Future<CrudActionResult> _sendField(String field, TeamTask Function(TeamTask task) apply) {
    final state = _bloc.state;
    final task = state is TeamTasksLoaded ? state.taskById(widget.taskId) : null;
    if (task == null) {
      _draft(field, null);
      return Future.value(const CrudActionResult.success());
    }
    final completion = CrudActionCompleter();
    _bloc.add(UpdateTeamTask(apply(task), completion: completion, draftField: field));
    return completion.future;
  }

  void _showError(String message) {
    _messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _report(CrudActionCompleter completion) {
    completion.future.then((result) {
      if (!mounted || result.isSuccess) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    });
  }

  /// Saves a manager's edit.
  void _edit(TeamTask task) {
    final completion = CrudActionCompleter();
    _bloc.add(UpdateTeamTask(task, completion: completion));
    _report(completion);
  }

  Future<void> _delete(TeamTask task) {
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
    // Tagged ("@") without owning it (19/11/2026): writes in the log, never
    // the status.
    final myTag = isTeamTaskTaggedOnly(task, viewerId) ? task.mentionOf(viewerId) : null;
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
                _section('שיוך', _linkValue(state, task, manage)),
                _section('סטטוס', _statusValue(state, task, manage || owner)),
                _section('דחיפות', _urgencyValue(task, manage)),
                _section('דד ליין', _deadlineValue(state, task, manage, late)),
                _section('אחראים', _ownersValue(task, manage, activeMembers, viewerId)),
                _section('אנשי קשר', _contactsValue(task, manage)),
                if (myTag != null) _section('תויגת', _myTagValue(state, task, myTag)),
                if (task.mentions.isNotEmpty) _section('מתויגים', _mentionsValue(state, task)),
                _section(
                  'יומן עדכונים',
                  TeamTaskUpdateLog(
                    task: task,
                    canWrite: manage || owner || myTag != null,
                    // Everyone's updates only in "כל המשימות" (round 10).
                    canEditAll: manage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The viewer's own tag: the box they tick when done, and who tagged them.
  Widget _myTagValue(TeamTasksLoaded state, TeamTask task, TeamTaskMention mention) {
    final by = state.members.where((m) => m.id == mention.byId).firstOrNull?.name;
    return Row(
      children: [
        MentionDoneBox(task: task, mention: mention),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            mention.isDone
                ? 'סימנת כבוצע'
                : 'סמן/י כבוצע כשסיימת${by == null ? '' : ' (תייג/ה: $by)'}',
            style: const TextStyle(color: TaskStyle.neutralText),
          ),
        ),
      ],
    );
  }

  /// Everyone tagged in the log, each with ✓ once they marked it done.
  Widget _mentionsValue(TeamTasksLoaded state, TeamTask task) {
    final names = {for (final m in state.members) m.id: m.name};
    return Wrap(
      key: const Key('team-task-mentions'),
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final mention in task.mentions)
          Chip(
            key: Key('team-task-mention-${mention.memberId}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: mention.isDone ? TaskStyle.doneLight : mentionLight,
            side: BorderSide.none,
            avatar: Icon(
              mention.isDone ? Icons.check : Icons.alternate_email,
              size: 16,
              color: mention.isDone ? TaskStyle.done : mentionColor,
            ),
            label: Text(names[mention.memberId] ?? unknownMemberLabel),
          ),
      ],
    );
  }

  /// The title, the description right under it (Omer, 16/11/2026: above the
  /// line that divides them from the other fields), and on the end the
  /// manager's red 🗑 next to ✕.
  Widget _header(TeamTask task, bool manage) {
    final title = Text(
      task.title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                manage
                    ? EditableValue<String>(
                        key: const Key('team-task-edit-title'),
                        value: task.title,
                        display: title,
                        sheetTitle: 'שם המשימה',
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
                if (manage || task.description.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: manage ? 0 : 8),
                    child: _descriptionValue(task, manage),
                  ),
              ],
            ),
          ),
          // "כל המשימות" (a manager's view) also shows when the task was
          // created, under ✕ and 🗑, left of the description (msg 4480).
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (manage)
                    IconButton(
                      key: const Key('team-task-delete'),
                      tooltip: 'מחיקת המשימה',
                      icon: const Icon(Icons.delete_outline, color: TaskStyle.delete),
                      onPressed: () => _delete(task),
                    ),
                  IconButton(
                    key: const Key('team-task-close'),
                    tooltip: 'סגירה',
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (manage)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12, top: 2),
                  child: TeamTaskCreatedText(
                    key: const Key('team-task-sheet-created'),
                    task: task,
                  ),
                ),
            ],
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
      TaskLinkType.event => task.hasSeveralEvents ? 'אירועים: ' : 'אירוע: ',
      TaskLinkType.category => 'קטגוריה: ',
      TaskLinkType.topic => 'נושא: ',
      TaskLinkType.pendingEvent => '$pendingEventLabel: ',
      null => '',
    };
    return _tappable(
      key: const Key('team-task-edit-link'),
      enabled: manage,
      onTap: () async {
        // Events are saved as they are marked (no button); a category, a
        // topic or "ללא שיוך" is one tap that closes the picker.
        final choice = await showTaskLinkPicker(
          context,
          initial: task.link,
          initialEventIds: task.linkedEventIds,
          liveEvents: LiveEventsLink(
            onChanged: (ids) => _link.change(TaskLinkChoice(
                TaskLink(TaskLinkType.event, ids.isEmpty ? '' : ids.first),
                eventIds: ids)),
            saver: _link,
            saved: () {
              final state = _bloc.state;
              return state is TeamTasksLoaded
                  ? state.taskById(widget.taskId)?.linkedEventIds ?? const []
                  : const [];
            },
          ),
        );
        if (choice != null) {
          final current = _bloc.state is TeamTasksLoaded
              ? (_bloc.state as TeamTasksLoaded).taskById(widget.taskId)
              : null;
          final same = current != null &&
              choice.link == current.link &&
              _sameIds(choice.linkedEventIds, current.linkedEventIds);
          if (!same) _link.change(choice);
        }
        _link.flush();
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
        if (canChange)
          TeamTaskStatusMenu(key: const Key('team-task-status'), task: task, child: chip)
        else
          chip,
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

  static bool _sameIds(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// The urgency (16/11/2026): a manager picks one of the three in place.
  Widget _urgencyValue(TeamTask task, bool manage) {
    if (!manage) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TeamTaskUrgencyChip(urgency: task.urgency, dense: false, showNormal: true),
      );
    }
    return TeamTaskUrgencyPicker(
      value: task.urgency,
      showLabel: false,
      onChanged: (urgency) {
        if (urgency != task.urgency) _edit(task.copyWith(urgency: urgency));
      },
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
    if (!manage) return chips;
    // No save button (Omer, 16/11/2026): each tick is saved at once.
    return _tappable(
      key: const Key('team-task-edit-owners'),
      enabled: true,
      onTap: () => showLiveOwnersPicker(
        context,
        taskId: widget.taskId,
        wide: widget.wide,
        offered: activeMembers,
        saver: _owners,
      ),
      child: chips,
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
