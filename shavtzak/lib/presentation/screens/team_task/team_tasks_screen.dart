import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/team_task_rules.dart';
import '../../../core/utils/team_task_spotlight.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/team_task.dart';
import '../../bloc/team_task/team_task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import '../task/task_style.dart';
import 'widgets/new_team_task_dialog.dart';
import 'widgets/team_task_filter_bar.dart';
import 'widgets/team_task_row.dart';
import 'widgets/team_task_sheet.dart';
import 'widgets/team_task_split_view.dart';
import 'widgets/team_task_spotlight.dart';
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
  const TeamTasksScreen({super.key});

  @override
  State<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

class _TeamTasksScreenState extends State<TeamTasksScreen> {
  /// Whether a manager looks at every task ("כל המשימות") or at their own.
  bool _showAll = true;

  /// The task open in the side panel (a window wider than a phone, round 7);
  /// null = closed.
  String? _panelTaskId;

  /// The link cards folded to their header (round 7), by group key; kept
  /// while the screen is open, across both tabs.
  final Set<String> _collapsed = {};

  /// The rows a "בליץ" pass just changed: they flash green for a moment on
  /// the way back to the list; [_flashRound] restarts the flash.
  Set<String> _flash = const {};
  int _flashRound = 0;

  /// "בליץ" over [rows] (their tasks still to be done, the quietest
  /// first); [title] = what the pass covers (a long-pressed card).
  Future<void> _spotlight(List<TeamTask> rows, {String? title}) async {
    final queue = spotlightQueue(rows);
    Logger.action('tap:spotlightOpen', {'count': queue.length, 'scoped': title != null});
    if (queue.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('אין כאן משימות פתוחות')),
      );
      return;
    }
    final touched = await showTeamTaskSpotlight(
      context,
      taskIds: [for (final task in queue) task.id],
      title: title,
    );
    if (!mounted || touched.isEmpty) return;
    final round = ++_flashRound;
    setState(() => _flash = touched);
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    if (mounted && round == _flashRound) setState(() => _flash = const {});
  }

  void _openPanel(String taskId) {
    Logger.action('tap:teamTaskPanelOpen');
    setState(() => _panelTaskId = taskId);
  }

  void _closePanel() {
    Logger.action('tap:teamTaskPanelClose');
    setState(() => _panelTaskId = null);
  }

  void _toggleGroup(String key) {
    Logger.action('tap:teamTaskGroupFold', {'group': key});
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
    });
  }

  /// "סגירת כל השיוכים" / "פתיחת כל השיוכים" (round 7): one button that
  /// folds every card, then opens them all again.
  Widget _foldAllButton(List<TeamTaskGroup> groups) {
    final allClosed = groups.isNotEmpty && groups.every((g) => _collapsed.contains(g.key));
    return IconButton(
      key: const Key('team-tasks-fold-all'),
      tooltip: allClosed ? 'פתיחת כל השיוכים' : 'סגירת כל השיוכים',
      icon: Icon(allClosed ? Icons.unfold_more : Icons.unfold_less),
      onPressed: groups.isEmpty
          ? null
          : () {
              Logger.action('tap:teamTasksFoldAll', {'close': !allClosed});
              setState(() {
                if (allClosed) {
                  _collapsed.removeAll(groups.map((g) => g.key));
                } else {
                  _collapsed.addAll(groups.map((g) => g.key));
                }
              });
            },
    );
  }

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

  Widget _withBanner(Widget child) => TestEnvironmentIndicator(child: child);

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
                  leading: IconButton(
                    key: const Key('team-tasks-home'),
                    tooltip: 'חזרה לדף הבית',
                    icon: const Icon(Icons.home_outlined),
                    onPressed: () => _goHome(user),
                  ),
                  actions: [
                    if (state is TeamTasksLoaded) _foldAllButton(_shownGroups(state, canManage)),
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
                  ],
                ),
                // The panel opens on the left, where the button sits in RTL:
                // it moves to the right meanwhile.
                floatingActionButtonLocation: _splitting(context) && _panelTaskId != null
                    ? FloatingActionButtonLocation.startFloat
                    : null,
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
    final split = _splitting(context);
    Widget list(List<TeamTaskGroup> groups, {required bool all}) {
      final column = Column(
        children: [
          TeamTaskFilterBar(state: state, showOwner: all),
          if (!all)
            _SpotlightBar(
              count: spotlightQueue(groups.expand((g) => g.tasks)).length,
              onStart: () => _spotlight([for (final g in groups) ...g.tasks]),
            ),
          const Divider(height: 1),
          Expanded(
            child: _GroupedList(
              groups: groups,
              state: state,
              now: now,
              editing: all,
              viewerId: state.viewer.id,
              collapsed: _collapsed,
              onToggleGroup: _toggleGroup,
              selectedId: split ? _panelTaskId : null,
              flash: _flash,
              flashRound: _flashRound,
              onSpotlightGroup:
                  all ? null : (group) => _spotlight(group.tasks, title: group.label),
            ),
          ),
        ],
      );
      if (!split) return column;
      // Wider than a phone (round 7): a task opens in a panel on the left
      // and the list slides right, in both tabs, with no new screen.
      return TeamTaskPanelScope(
        open: _openPanel,
        close: _closePanel,
        child: TeamTaskSplitView(
          list: column,
          openTaskId: _panelTaskId,
          panelBuilder: (context, taskId) => TeamTaskSheet(
            taskId: taskId,
            wide: MediaQuery.sizeOf(context).width >= TaskStyle.wideBreakpoint,
            manage: all,
            onClose: _closePanel,
          ),
        ),
      );
    }

    if (!canManage) return list(state.mineGroups, all: false);
    return Column(
      children: [
        _tabs(),
        Expanded(
          child: _showAll ? list(state.allGroups, all: true) : list(state.mineGroups, all: false),
        ),
      ],
    );
  }

  /// The groups the list shows now (the tab).
  List<TeamTaskGroup> _shownGroups(TeamTasksLoaded state, bool canManage) {
    if (!canManage) return state.mineGroups;
    return _showAll ? state.allGroups : state.mineGroups;
  }

  /// Whether the window is wider than a phone: tasks open in the side panel.
  static bool _splitting(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= TeamTaskStyle.splitBreakpoint;

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
                setState(() {
                  _showAll = selection.first;
                  // The panel belongs to a tab (editing or not).
                  _panelTaskId = null;
                });
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
    required this.collapsed,
    required this.onToggleGroup,
    this.selectedId,
    this.flash = const {},
    this.flashRound = 0,
    this.onSpotlightGroup,
  });

  /// The rows a "בליץ" pass just changed, flashing green.
  final Set<String> flash;
  final int flashRound;

  /// "המשימות שלי": a long press on a card's header opens "בליץ" over
  /// that card's tasks only.
  final ValueChanged<TeamTaskGroup>? onSpotlightGroup;

  /// The cards folded to their header (round 7), by group key.
  final Set<String> collapsed;
  final ValueChanged<String> onToggleGroup;

  /// The task open in the side panel, highlighted.
  final String? selectedId;

  /// Whose rows these are (the viewer).
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
      final shown = widget.editing
          ? visibleSubtasks(task, state.filter, now: widget.now)
          : const <TeamSubtask>[];
      final open = widget.editing && task.subtasks.isNotEmpty && _isOpen(task, shown);
      rows.add(_flashed(task.id, TeamTaskRow(
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
        selected: task.id == widget.selectedId,
        canChangeStatus: !widget.editing,
        onAddUpdate: widget.editing ? null : () => showTeamTaskUpdatesDialog(context, task.id),
        onTap: () => showTeamTaskSheet(context, task.id, manage: widget.editing),
      )));
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
                    selected: subtask.id == widget.selectedId,
                    onTap: () => showTeamTaskSheet(context, subtask.id, manage: widget.editing),
                  ),
              ],
            ),
          ),
        ));
      }
    }
    final count = group.tasks.length;
    // Folded by a tap on its header (round 7); a search opens it, as it
    // opens a parent whose subtask matched.
    final folded = widget.collapsed.contains(group.key) && state.filter.searchText.isEmpty;
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
            Material(
              color: TaskStyle.stageHeader,
              child: InkWell(
                key: Key('team-task-group-${group.key}'),
                hoverColor: TeamTaskStyle.rowHover,
                onTap: () => widget.onToggleGroup(group.key),
                onLongPress: widget.onSpotlightGroup == null
                    ? null
                    : () => widget.onSpotlightGroup!(group),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
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
                      const SizedBox(width: 2),
                      Icon(
                        folded ? Icons.expand_more : Icons.expand_less,
                        key: Key('team-task-group-fold-${group.key}'),
                        size: 20,
                        color: TaskStyle.neutralText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: folded
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// [row] with a green flash that fades when [id] was just changed in a
  /// "בליץ" pass.
  Widget _flashed(String id, Widget row) {
    if (!widget.flash.contains(id)) return row;
    return TweenAnimationBuilder<double>(
      key: Key('team-task-flash-$id-${widget.flashRound}'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 2200),
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
      builder: (context, value, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(Colors.transparent, TaskStyle.doneLight, value),
        ),
        child: child,
      ),
      child: row,
    );
  }

  static String _groupKind(TaskLinkType? type) => switch (type) {
        TaskLinkType.event => 'אירוע · ',
        TaskLinkType.category => 'קטגוריה · ',
        TaskLinkType.topic => 'נושא · ',
        null => '',
      };
}

/// Above the list of "המשימות שלי": how many tasks are still to be done and
/// the "בליץ" button that goes through them one by one.
class _SpotlightBar extends StatelessWidget {
  const _SpotlightBar({required this.count, required this.onStart});

  final int count;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count == 1 ? 'משימה אחת פתוחה' : '$count משימות פתוחות',
                  key: const Key('spotlight-bar-count'),
                  style: const TextStyle(
                    fontSize: TaskStyle.rowMetaSize,
                    color: TaskStyle.neutralText,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('spotlight-start'),
                onPressed: onStart,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TaskStyle.mine,
                  backgroundColor: TaskStyle.currentLight,
                  side: const BorderSide(color: TaskStyle.mine),
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('בליץ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
