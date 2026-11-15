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
import 'widgets/task_link_picker.dart';
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
                    if (canManage)
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
                floatingActionButton: canManage
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
    Widget list(List<TeamTaskGroup> groups) => Column(
          children: [
            _FilterBar(state: state),
            const Divider(height: 1),
            Expanded(child: _GroupedList(groups: groups, state: state, now: now)),
          ],
        );
    if (!canManage) return list(state.mineGroups);
    return Column(
      children: [
        _tabs(),
        Expanded(child: list(_showAll ? state.allGroups : state.mineGroups)),
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
  const _GroupedList({required this.groups, required this.state, required this.now});

  final List<TeamTaskGroup> groups;
  final TeamTasksLoaded state;
  final DateTime now;

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
                  onTap: () => showTeamTaskSheet(context, task.id),
                ),
                // "כל המשימות": a parent's subtasks nested under it, by the
                // same status and owner filter.
                for (final subtask in task.subtasks)
                  if (state.filter.statuses.contains(subtask.status) &&
                      (state.filter.ownerId == null ||
                          subtask.assigneeIds.contains(state.filter.ownerId)))
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
                          onTap: () => showTeamTaskSheet(context, subtask.id),
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

/// One row of filters: status, owner, link.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state});

  final TeamTasksLoaded state;

  void _set(BuildContext context, TeamTaskFilter filter) =>
      context.read<TeamTaskBloc>().add(TeamTaskFilterChanged(filter));

  @override
  Widget build(BuildContext context) {
    final filter = state.filter;
    final ownerName = filter.ownerId == null
        ? null
        : state.members.where((m) => m.id == filter.ownerId).firstOrNull?.name;
    final linkName = taskLinkName(state, filter.link);
    final statusLabel = filter.statuses.length == TeamTaskStatus.values.length
        ? 'כל הסטטוסים'
        : filter.statuses.length == TeamTaskFilter.initial.statuses.length &&
                filter.statuses.containsAll(TeamTaskFilter.initial.statuses)
            ? 'סטטוס'
            : 'סטטוס (${filter.statuses.length})';
    final owners = {
      for (final task in state.all) ...task.ownerIds,
    };
    final ownerOptions = state.members.where((m) => owners.contains(m.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          PopupMenuButton<TeamTaskStatus>(
            key: const Key('team-filter-status'),
            tooltip: 'סינון לפי סטטוס',
            onSelected: (status) {
              final next = {...filter.statuses};
              if (!next.remove(status)) next.add(status);
              if (next.isEmpty) return;
              _set(context, filter.copyWith(statuses: next));
            },
            itemBuilder: (context) => [
              for (final status in TeamTaskStatus.values)
                CheckedPopupMenuItem(
                  value: status,
                  checked: filter.statuses.contains(status),
                  child: Text(status.hebrewLabel),
                ),
            ],
            child: _FilterChipLook(label: statusLabel, active: !filter.isInitial),
          ),
          if (state.canManage) ...[
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              key: const Key('team-filter-owner'),
              tooltip: 'סינון לפי אחראי',
              onSelected: (id) =>
                  _set(context, filter.copyWith(ownerId: () => id.isEmpty ? null : id)),
              itemBuilder: (context) => [
                const PopupMenuItem(value: '', child: Text('כל האחראים')),
                for (final member in ownerOptions)
                  PopupMenuItem(
                    value: member.id,
                    child: MemberNameText(name: member.name, permanent: member.isPermanent),
                  ),
              ],
              child: _FilterChipLook(
                label: ownerName ?? 'אחראי',
                active: filter.ownerId != null,
              ),
            ),
          ],
          const SizedBox(width: 6),
          InkWell(
            key: const Key('team-filter-link'),
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              if (filter.link != null) {
                _set(context, filter.copyWith(link: () => null));
                return;
              }
              final choice = await showTaskLinkPicker(context, allowNone: false);
              if (choice?.link == null || !context.mounted) return;
              _set(context, filter.copyWith(link: () => choice!.link));
            },
            child: _FilterChipLook(
              label: linkName == null ? 'שיוך' : '$linkName ✕',
              active: filter.link != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipLook extends StatelessWidget {
  const _FilterChipLook({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? TaskStyle.currentLight : Colors.transparent,
        border: Border.all(color: active ? TaskStyle.mine : TaskStyle.rest),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: TaskStyle.filterFontSize,
              color: active ? TaskStyle.mine : TaskStyle.neutralText,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: TaskStyle.neutralText),
        ],
      ),
    );
  }
}
