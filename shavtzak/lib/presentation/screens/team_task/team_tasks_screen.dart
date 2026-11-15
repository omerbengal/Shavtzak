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

class _TeamTasksScreenState extends State<TeamTasksScreen> {
  /// Whether a manager looks at every task ("כל המשימות") or at their own.
  bool _showAll = true;

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

  Widget _withBanner(Widget child) => widget.place == TeamTasksPlace.standalone
      ? TestEnvironmentIndicator(child: child)
      : child;

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
                body: _withBanner(_body(state, canManage)),
              );
              return scaffold;
            },
          );
        },
      ),
    );
  }

  Widget _body(TeamTaskState state, bool canManage) {
    if (state is TeamTasksError) {
      return Center(child: Text(state.message));
    }
    if (state is! TeamTasksLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    Widget list(List<TeamTaskGroup> groups, {required bool all}) => Column(
          children: [
            TeamTaskFilterBar(state: state, showOwner: all),
            const Divider(height: 1),
            Expanded(
              child: _GroupedList(groups: groups, state: state, now: now, editing: all),
            ),
          ],
        );
    if (!canManage) return list(state.mineGroups, all: false);
    return Column(
      children: [
        _tabs(),
        Expanded(
          child: _showAll
              ? list(state.allGroups, all: true)
              : list(state.mineGroups, all: false),
        ),
      ],
    );
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

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.groups,
    required this.state,
    required this.now,
    required this.editing,
  });

  final List<TeamTaskGroup> groups;
  final TeamTasksLoaded state;
  final DateTime now;

  /// "כל המשימות": subtasks nested under their parent, and a manager's
  /// tap opens the editing view.
  final bool editing;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(
        child: Text('אין משימות להצגה', style: TextStyle(color: TaskStyle.faintText)),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final group in groups) ...[
              Container(
                key: Key('team-task-group-${group.key}'),
                width: double.infinity,
                color: TaskStyle.stageHeader,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  '${_groupKind(group.type)}${group.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final task in group.tasks) ...[
                TeamTaskRow(
                  task: task,
                  now: now,
                  viewerId: state.viewer.id,
                  onTap: () => showTeamTaskSheet(context, task.id, manage: editing),
                ),
                // "כל המשימות": a parent's subtasks nested under it, by the
                // same filters.
                if (editing)
                  for (final subtask in visibleSubtasks(task, state.filter))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 28),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: TaskStyle.chip, width: 3),
                          ),
                        ),
                        child: TeamTaskRow(
                          task: TeamTask.subtaskView(task, subtask),
                          now: now,
                          viewerId: state.viewer.id,
                          nested: true,
                          onTap: () => showTeamTaskSheet(context, subtask.id, manage: editing),
                        ),
                      ),
                    ),
                const Divider(height: 1, indent: 12, endIndent: 12),
              ],
            ],
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

