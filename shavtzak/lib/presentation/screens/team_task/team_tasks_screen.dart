import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/team_task_rules.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/team_task.dart';
import '../../bloc/team_task/team_task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/member_bar_buttons.dart';
import '../../widgets/test_environment_indicator.dart';
import '../task/task_style.dart';
import 'team_tasks_place.dart';
import 'widgets/new_team_task_dialog.dart';
import 'widgets/team_task_filter_bar.dart';
import 'widgets/team_task_row.dart';
import 'widgets/team_task_sheet.dart';
import 'widgets/team_task_style.dart';
import 'widgets/team_task_update_log.dart';
import 'widgets/topic_management_dialog.dart';

/// The team tasks screen ("משימות"): the headquarters team's tasks, grouped
/// by the event, category or topic they belong to.
///
/// Two tabs for a manager, "המשימות שלי" and "כל המשימות", as the דו יומי
/// event screen: the same segmented switch, "המשימות שלי" on the right, a
/// manager opening on every task. A member who is not a manager sees only
/// their own tasks, with no tabs.
class TeamTasksScreen extends StatefulWidget {
  const TeamTasksScreen({super.key, required this.place});

  final TeamTasksPlace place;

  @override
  State<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

// TEMP (round 6, remove before the merge): lets a task manager see
// "המשימות שלי" as another member sees it, to judge the screen on real data
// (the דו יומי screen's "תצוגה בתור", there in debug runs only). Remove this
// flag, [_TeamTasksScreenState._viewAsId] and everything under "view as".
const bool kTempTeamTasksViewAs = true;

class _TeamTasksScreenState extends State<TeamTasksScreen> {
  /// Whether a manager looks at every task ("כל המשימות") or at their own.
  bool _showAll = true;

  /// TEMP ([kTempTeamTasksViewAs]): whose "המשימות שלי" a manager looks at;
  /// null is their own.
  String? _viewAsId;

  void _subscribe(TeamMember user) {
    context.read<TeamTaskBloc>().add(TeamTasksSubscribe(user));
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<UserSelectionBloc>().state;
    if (auth is UserAuthenticated) _subscribe(auth.user);
  }

  void _goHome(TeamMember user) {
    Logger.action('tap:teamTasksHome');
    context.go('${EnvironmentService.instance.routePrefix}${AppRouter.homeFor(user)}');
  }

  Widget _withBanner(Widget child) =>
      widget.place == TeamTasksPlace.standalone ? TestEnvironmentIndicator(child: child) : child;

  Future<void> _newTask() async {
    Logger.action('tap:newTeamTask');
    final id = await showNewTeamTaskDialog(context);
    if (id == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('המשימה נוספה')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<UserSelectionBloc, UserSelectionState>(
        listener: (context, auth) {
          if (auth is UserAuthenticated) _subscribe(auth.user);
        },
        builder: (context, auth) {
          if (auth is! UserAuthenticated) {
            return const Scaffold(
              body: Center(child: Text('גישה לא מורשית - דרוש אימות')),
            );
          }
          final user = auth.user;
          return BlocBuilder<TeamTaskBloc, TeamTaskState>(
            builder: (context, state) {
              final canManage = canManageTeamTasks(user);
              // A manager edits only in "כל המשימות"; in "המשימות שלי" they are
              // a member like any other (Omer, round 3).
              final editing = canManage && _showAll;
              final scaffold = Scaffold(
                appBar: AppBar(
                  title: const Text('משימות'),
                  automaticallyImplyLeading: false,
                  leading: widget.place == TeamTasksPlace.standalone
                      ? IconButton(
                          key: const Key('team-tasks-home'),
                          tooltip: 'חזרה לדף הבית',
                          icon: const Icon(Icons.home_outlined),
                          onPressed: () => _goHome(user),
                        )
                      : const MemberSettingsButton(),
                  actions: [
                    // TEMP: see [kTempTeamTasksViewAs].
                    if (kTempTeamTasksViewAs && canManage && !_showAll && state is TeamTasksLoaded)
                      IconButton(
                        key: const Key('team-tasks-view-as'),
                        tooltip: 'תצוגה בתור חבר צוות אחר',
                        icon: Icon(_viewAsId == null ? Icons.people_outline : Icons.people),
                        onPressed: () => _pickViewer(state, user),
                      ),
                    if (editing)
                      PopupMenuButton<String>(
                        key: const Key('team-tasks-menu'),
                        tooltip: 'עוד',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (value) {
                          if (value == 'topics') showTopicManagementDialog(context);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            key: Key('team-tasks-menu-topics'),
                            value: 'topics',
                            child: Text('ניהול נושאים'),
                          ),
                        ],
                      ),
                    if (widget.place == TeamTasksPlace.tab) MemberBarActions(user: user),
                  ],
                ),
                floatingActionButton: editing
                    ? FloatingActionButton.extended(
                        key: const Key('team-task-new'),
                        onPressed: state is TeamTasksLoaded ? _newTask : null,
                        icon: const Icon(Icons.add),
                        label: const Text('משימה חדשה'),
                      )
                    : null,
                body: _withBanner(_body(state, canManage, user)),
              );
              return scaffold;
            },
          );
        },
      ),
    );
  }

  Widget _body(TeamTaskState state, bool canManage, TeamMember user) {
    if (state is TeamTasksError) {
      return Center(child: Text(state.message));
    }
    if (state is! TeamTasksLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    Widget list(List<TeamTaskGroup> groups, {required bool all, String? viewerId}) => Column(
          children: [
            TeamTaskFilterBar(state: state, showOwner: all),
            const Divider(height: 1),
            Expanded(
              child: _GroupedList(
                groups: groups,
                state: state,
                now: now,
                editing: all,
                viewerId: viewerId ?? state.viewer.id,
              ),
            ),
          ],
        );
    if (!canManage) return list(state.mineGroups, all: false);
    final viewAsId = kTempTeamTasksViewAs ? _viewAsId : null;
    return Column(
      children: [
        _tabs(),
        if (!_showAll && viewAsId != null) _viewAsBanner(state, viewAsId, user),
        Expanded(
          child: _showAll
              ? list(state.allGroups, all: true)
              : viewAsId == null
                  ? list(state.mineGroups, all: false)
                  : list(_mineGroupsOf(state, viewAsId, now), all: false, viewerId: viewAsId),
        ),
      ],
    );
  }

  // ---- TEMP: view as another member ([kTempTeamTasksViewAs]) ----

  /// "המשימות שלי" of [memberId], built as the bloc builds the viewer's.
  static List<TeamTaskGroup> _mineGroupsOf(TeamTasksLoaded state, String memberId, DateTime now) {
    final eventCategoryById = {for (final e in state.events) e.id: e.categoryId};
    return groupTeamTasks(
      applyTeamTaskFilter(
        myTeamTaskRows(state.all, memberId),
        state.filter.copyWith(ownerId: () => null),
        eventCategoryById,
      ),
      now,
    );
  }

  Widget _viewAsBanner(TeamTasksLoaded state, String viewAsId, TeamMember user) {
    final name =
        state.members.where((m) => m.id == viewAsId).firstOrNull?.name ?? unknownMemberLabel;
    return Material(
      color: TaskStyle.soonLight,
      child: InkWell(
        key: const Key('team-tasks-view-as-banner'),
        onTap: () => _pickViewer(state, user),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('תצוגה בתור: $name (זמני, לבדיקה)')),
              IconButton(
                key: const Key('team-tasks-view-as-clear'),
                tooltip: 'חזרה למשימות שלי',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _viewAsId = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickViewer(TeamTasksLoaded state, TeamMember user) async {
    Logger.action('tap:teamTasksViewAs');
    // Everyone who owns a task (or a subtask), and the viewer.
    final owners = {user.id, for (final task in state.all) ...task.ownerIds};
    final people = state.members.where((m) => owners.contains(m.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('תצוגה בתור'),
          children: [
            for (final member in people)
              SimpleDialogOption(
                key: Key('team-tasks-view-as-${member.id}'),
                onPressed: () => Navigator.of(context).pop(member.id),
                child: Row(
                  children: [
                    Expanded(
                      child: MemberNameText(name: member.name, permanent: member.isPermanent),
                    ),
                    if (member.id == (_viewAsId ?? user.id))
                      const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _viewAsId = chosen == user.id ? null : chosen);
  }

  /// The דו יומי event screen's switch, with its colours.
  Widget _tabs() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              // Explicit colours: the app theme's defaults for a selected
              // segment are white text on light orange, which is unreadable.
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.primaryDark,
                selectedForegroundColor: Colors.white,
              ),
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('המשימות שלי', key: Key('team-tab-mine')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('כל המשימות', key: Key('team-tab-all')),
                ),
              ],
              selected: {_showAll},
              onSelectionChanged: (selection) {
                Logger.action('toggle:teamTasksTab', {'all': selection.first});
                setState(() => _showAll = selection.first);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The list as design A (Omer, round 3): a card per link, as the דו יומי
/// "המשימות שלי" stage cards (tinted header, white rows). In "כל המשימות" a
/// parent's subtasks fold under it ("2/4 ▾"), closed until opened; while a
/// search matches a subtask, its parent opens by itself.
class _GroupedList extends StatefulWidget {
  const _GroupedList({
    required this.groups,
    required this.state,
    required this.now,
    required this.editing,
    required this.viewerId,
  });

  /// Whose rows these are (TEMP: another member's while viewing as them).
  final String viewerId;

  final List<TeamTaskGroup> groups;
  final TeamTasksLoaded state;
  final DateTime now;

  /// "כל המשימות": subtasks nested under their parent, and a manager's
  /// tap opens the editing view.
  final bool editing;

  @override
  State<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends State<_GroupedList> {
  /// The parents whose subtasks were opened by hand.
  final Set<String> _open = {};

  bool _isOpen(TeamTask task, List<TeamSubtask> shown) {
    if (_open.contains(task.id)) return true;
    // Searching: open where a subtask is what matched.
    return widget.state.filter.searchText.isNotEmpty &&
        shown.isNotEmpty &&
        shown.length < task.subtasks.length;
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final state = widget.state;
    if (groups.isEmpty) {
      return const Center(
        child: Text('אין משימות להצגה', style: TextStyle(color: TaskStyle.faintText)),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          children: [
            for (final group in groups) _card(context, group, state),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, TeamTaskGroup group, TeamTasksLoaded state) {
    final rows = <Widget>[];
    for (final task in group.tasks) {
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, thickness: 1, color: TaskStyle.stageCardDivider));
      }
      final shown = widget.editing ? visibleSubtasks(task, state.filter) : const <TeamSubtask>[];
      final open = widget.editing && task.subtasks.isNotEmpty && _isOpen(task, shown);
      rows.add(TeamTaskRow(
        task: task,
        now: widget.now,
        viewerId: widget.viewerId,
        expanded: open,
        onToggleSubtasks: widget.editing && task.subtasks.isNotEmpty
            ? () => setState(() {
                  if (!_open.remove(task.id)) _open.add(task.id);
                })
            : null,
        // "המשימות שלי": the status and a new update without opening the
        // task (Omer, round 4); every row there is the viewer's own.
        canChangeStatus: !widget.editing,
        onAddUpdate: widget.editing ? null : () => showTeamTaskUpdatesDialog(context, task.id),
        onTap: () => showTeamTaskSheet(context, task.id, manage: widget.editing),
      ));
      if (open && shown.isNotEmpty) {
        rows.add(Padding(
          key: Key('team-task-subtasks-${task.id}'),
          padding: const EdgeInsetsDirectional.only(
            start: 12 + TeamTaskStyle.statusIconSize + 8,
            bottom: 8,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: TaskStyle.rest, width: 2),
              ),
            ),
            child: Column(
              children: [
                for (final subtask in shown)
                  TeamTaskRow(
                    task: TeamTask.subtaskView(task, subtask),
                    now: widget.now,
                    viewerId: widget.viewerId,
                    nested: true,
                    onTap: () => showTeamTaskSheet(context, subtask.id, manage: widget.editing),
                  ),
              ],
            ),
          ),
        ));
      }
    }
    final count = group.tasks.length;
    return Container(
      key: Key('team-task-card-${group.key}'),
      margin: const EdgeInsets.fromLTRB(
        TaskStyle.stageCardInset,
        TaskStyle.stageCardGap,
        TaskStyle.stageCardInset,
        0,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TaskStyle.stageCard,
        border: Border.all(
          color: TaskStyle.stageCardBorder,
          width: TaskStyle.stageCardBorderWidth,
        ),
        borderRadius: BorderRadius.circular(TaskStyle.stageCardRadius),
      ),
      // The rows' ink (hover, splash) is painted on this Material; under the
      // card's colour it would be hidden (Omer, round 4: no hover).
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: Key('team-task-group-${group.key}'),
              color: TaskStyle.stageHeader,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_groupKind(group.type)}${group.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    count == 1 ? 'משימה אחת' : '$count משימות',
                    style: const TextStyle(
                      fontSize: TaskStyle.rowMetaSize,
                      color: TaskStyle.neutralText,
                    ),
                  ),
                ],
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  static String _groupKind(TaskLinkType? type) => switch (type) {
        TaskLinkType.event => 'אירוע · ',
        TaskLinkType.category => 'קטגוריה · ',
        TaskLinkType.topic => 'נושא · ',
        null => '',
      };
}
