import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/israel_calendar.dart';
import '../../../core/utils/team_task_rules.dart';
import '../../../core/utils/team_task_spotlight.dart';
import '../../../data/repositories/assignment_label_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/team_task.dart';
import '../../bloc/event_item/event_item_bloc.dart';
import '../../bloc/event_item/event_item_state.dart';
import '../../bloc/team_task/team_task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/event_team_members_dialog.dart';
import '../../widgets/member_bar_buttons.dart';
import '../../widgets/test_environment_indicator.dart';
import '../task/task_style.dart';
import 'team_tasks_place.dart';
import 'widgets/new_team_task_dialog.dart';
import 'widgets/task_link_picker.dart';
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
/// Lets a test see the once-per-session "בליץ" warm-up again.
@visibleForTesting
void resetTeamTasksBlitzWarmup() => _TeamTasksScreenState._blitzWarmed = false;

class TeamTasksScreen extends StatefulWidget {
  const TeamTasksScreen({super.key, this.place = TeamTasksPlace.standalone, this.openTaskId});

  /// The admins' own screen, or the members' "משימות" tab, which has the
  /// member bar's buttons instead of "home" and no test banner of its own
  /// (the shell has one).
  final TeamTasksPlace place;

  /// A task to open once the list is loaded: `?task=<id>`, the link a
  /// "שובצת למשימה" notification opens (web/sw.js).
  final String? openTaskId;

  /// "כל המשימות" opens with its cards folded (Omer, msg 4466). Tests of
  /// other things on that tab turn it off to reach the rows at once.
  @visibleForTesting
  static bool foldAllTabByDefault = true;

  /// "קיבוץ לפי אירועים" in "כל המשימות" (Omer, 19/11/2026): on = the
  /// events' sections inside each category's card (as before), off = one
  /// list per category. Kept for the app session, across the screen's
  /// openings.
  static bool groupByEvents = true;

  @override
  State<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

class _TeamTasksScreenState extends State<TeamTasksScreen> {
  /// Whether a manager looks at every task ("כל המשימות") or at their own.
  bool _showAll = true;

  /// The task open in the side panel (a window wider than a phone, round 7);
  /// null = closed.
  String? _panelTaskId;

  /// The cards (and event sections) the viewer folded or opened by hand,
  /// by key, against each tab's default; kept while the screen is open.
  /// "המשימות שלי" opens with every card open (round 7), "כל המשימות" with
  /// every card folded to its header (Omer, msg 4466), so a tap there
  /// opens one: [_collapsedIn].
  final Set<String> _toggledMine = {};
  final Set<String> _toggledAll = {};

  /// Whether the list shown is "כל המשימות" (a manager's first tab).
  bool _onAll(bool canManage) => canManage && _showAll;

  /// The keys folded now in the tab of [groups] ([all] = "כל המשימות"):
  /// the tab's default, flipped wherever the viewer tapped.
  Set<String> _collapsedIn(List<TeamTaskGroup> groups, {required bool all}) {
    final toggled = all ? _toggledAll : _toggledMine;
    final byDefault = all && TeamTasksScreen.foldAllTabByDefault
        ? {for (final group in groups) group.key}
        : const <String>{};
    return {
      ...byDefault.difference(toggled),
      ...toggled.difference(byDefault),
    };
  }

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

  /// [TeamTasksScreen.openTaskId] not handled yet.
  String? _pendingOpen;

  @override
  void didUpdateWidget(TeamTasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openTaskId != oldWidget.openTaskId && widget.openTaskId != null) {
      _pendingOpen = widget.openTaskId;
    }
  }

  /// Opens [_pendingOpen] once the tasks are there, as a tap on its row
  /// would; a task that is gone says so.
  void _openPendingTask(TeamTaskState state, bool canManage) {
    final id = _pendingOpen;
    if (id == null || state is! TeamTasksLoaded) return;
    _pendingOpen = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Logger.action('open:teamTaskFromLink', {'found': state.taskById(id) != null});
      if (state.taskById(id) == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('המשימה לא נמצאה')),
        );
        return;
      }
      // A task of the viewer's own (a "שובצת למשימה" notification) opens
      // over "המשימות שלי", so closing it lands there (Omer, 17/11/2026).
      if (canManage && _showAll && state.mine.any((task) => task.id == id)) {
        setState(() => _showAll = false);
      }
      // "כל המשימות" opens with its cards folded (Omer, msg 4466): the card
      // holding the task opens, so its row shows beside the open task.
      if (_onAll(canManage)) {
        final holding = [
          for (final group in state.allGroups)
            if (group.allTasks.any((task) => task.id == id)) group.key,
        ];
        setState(() => _setFolded(holding, fold: false, all: true));
      }
      if (_splitting(context)) {
        _openPanel(id);
      } else {
        showTeamTaskSheet(context, id, manage: canManage && _showAll);
      }
    });
  }

  void _openPanel(String taskId) {
    Logger.action('tap:teamTaskPanelOpen');
    setState(() => _panelTaskId = taskId);
    _holdPlace(taskId);
  }

  void _closePanel() {
    Logger.action('tap:teamTaskPanelClose');
    setState(() => _panelTaskId = null);
    _holdPlace(null);
  }

  /// The task open in the side panel keeps its place in the list until the
  /// panel closes, another task opens or the tab changes (Omer, msg 4476):
  /// [TeamTaskHoldPlace].
  TeamTaskBloc? _bloc;

  void _holdPlace(String? taskId) {
    final bloc = _bloc;
    if (bloc != null && !bloc.isClosed) bloc.add(TeamTaskHoldPlace(taskId));
  }

  void _toggleGroup(String key, {required bool all}) {
    Logger.action('tap:teamTaskGroupFold', {'group': key, 'all': all});
    final toggled = all ? _toggledAll : _toggledMine;
    setState(() {
      if (!toggled.remove(key)) toggled.add(key);
    });
  }

  /// Folds ([fold]) or opens the cards [keys] of one tab, whatever that
  /// tab's default.
  void _setFolded(Iterable<String> keys, {required bool fold, required bool all}) {
    final toggled = all ? _toggledAll : _toggledMine;
    // "כל המשימות" folds a card by default: there opening it is the flip.
    final foldedByDefault = all && TeamTasksScreen.foldAllTabByDefault;
    for (final key in keys) {
      final flipped = foldedByDefault ? !fold : fold;
      if (flipped) {
        toggled.add(key);
      } else {
        toggled.remove(key);
      }
    }
  }

  /// "סגירת כל השיוכים" / "פתיחת כל השיוכים" (round 7): one button that
  /// folds every card, then opens them all again.
  Widget _foldAllButton(List<TeamTaskGroup> groups, {required bool all}) {
    final collapsed = _collapsedIn(groups, all: all);
    final allClosed = groups.isNotEmpty && groups.every((g) => collapsed.contains(g.key));
    return IconButton(
      key: const Key('team-tasks-fold-all'),
      tooltip: allClosed ? 'פתיחת כל השיוכים' : 'סגירת כל השיוכים',
      icon: Icon(allClosed ? Icons.unfold_more : Icons.unfold_less),
      onPressed: groups.isEmpty
          ? null
          : () {
              Logger.action('tap:teamTasksFoldAll', {'close': !allClosed});
              setState(() => _setFolded(groups.map((g) => g.key), fold: !allClosed, all: all));
            },
    );
  }

  void _subscribe(TeamMember user) {
    context.read<TeamTaskBloc>().add(TeamTasksSubscribe(user));
  }

  /// The first "בליץ" of a browser tab stuttered, the next ones did not
  /// (Omer, 16/11/2026): in a tab the web engine pays for everything new the
  /// first time it is drawn - the emoji's fallback font (downloaded,
  /// registered, every text laid out again) and the GPU programs of the
  /// card's shadows and layers. So once the screen has settled
  /// ([_warmupDelay], after its own opening transition) it pays them here,
  /// while nothing moves: the emoji are laid out offstage
  /// ([spotlightWarmupGlyphs]) and, once per app session, "בליץ" itself is
  /// drawn for a moment ([_blitzWarmFor]) under this screen's opaque
  /// background, unseen and untouchable.
  static const Duration _warmupDelay = Duration(milliseconds: 900);
  static const Duration _blitzWarmFor = Duration(milliseconds: 700);
  static bool _blitzWarmed = false;
  bool _warm = false;
  bool _blitzWarming = false;
  Timer? _warmTimer;
  Timer? _blitzWarmTimer;

  /// The hidden "בליץ" while it warms up (see [_warmupDelay]), else nothing.
  Widget _blitzWarmup(TeamTaskState state) {
    if (!_warm || _blitzWarmed || state is! TeamTasksLoaded) return const SizedBox.shrink();
    final queue = spotlightQueue(state.mine);
    if (queue.isEmpty) return const SizedBox.shrink();
    if (!_blitzWarming) {
      _blitzWarming = true;
      _blitzWarmTimer = Timer(_blitzWarmFor, () {
        _blitzWarmed = true;
        if (mounted) setState(() {});
      });
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ExcludeFocus(
          child: TeamTaskSpotlight(taskIds: [for (final task in queue) task.id]),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<TeamTaskBloc>();
  }

  @override
  void initState() {
    super.initState();
    _pendingOpen = widget.openTaskId;
    final auth = context.read<UserSelectionBloc>().state;
    if (auth is UserAuthenticated) _subscribe(auth.user);
    _warmTimer = Timer(_warmupDelay, () {
      if (mounted) setState(() => _warm = true);
    });
  }

  @override
  void dispose() {
    if (_panelTaskId != null) _holdPlace(null);
    _warmTimer?.cancel();
    _blitzWarmTimer?.cancel();
    super.dispose();
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
              _openPendingTask(state, canManage);
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
                    if (state is TeamTasksLoaded)
                      _foldAllButton(_shownGroups(state, canManage), all: _onAll(canManage)),
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
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Under the screen's opaque background: drawn, never seen.
                  _blitzWarmup(state),
                  scaffold,
                  if (_warm && state is TeamTasksLoaded)
                    Offstage(
                      child: Text(spotlightWarmupGlyphs(state.mine, base: spotlightEmoji)),
                    ),
                ],
              );
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
          if (all) _groupByEventsSwitch(),
          if (!all)
            _SpotlightBar(
              count: spotlightQueue(_uniqueTasks(groups)).length,
              onStart: () => _spotlight(_uniqueTasks(groups)),
            ),
          const Divider(height: 1),
          Expanded(
            child: _GroupedList(
              groups: groups,
              state: state,
              now: now,
              editing: all,
              flat: all && !TeamTasksScreen.groupByEvents,
              // The event's "שיבוצים" window, for whoever sees it in
              // "מסך מנהלים" (round 10).
              showAssignments: user.isAdmin || user.canAccessSummaryScreen,
              viewerId: state.viewer.id,
              collapsed: _collapsedIn(groups, all: all),
              onToggleGroup: (key) => _toggleGroup(key, all: all),
              selectedId: split ? _panelTaskId : null,
              flash: _flash,
              flashRound: _flashRound,
              onSpotlightGroup:
                  all ? null : (group) => _spotlight(group.allTasks, title: group.label),
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
            // Another task = a new sheet, so its pickers' waiting changes
            // are sent for the right task.
            key: ValueKey('team-task-panel-$taskId'),
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
          child: _showAll ? list(_allGroups(state), all: true) : list(state.mineGroups, all: false),
        ),
      ],
    );
  }

  /// Every task of [groups] once (a task of several events is on several).
  static List<TeamTask> _uniqueTasks(List<TeamTaskGroup> groups) {
    final seen = <String>{};
    return [
      for (final group in groups)
        for (final task in group.allTasks)
          if (seen.add(task.id)) task,
    ];
  }

  /// The groups the list shows now (the tab).
  List<TeamTaskGroup> _shownGroups(TeamTasksLoaded state, bool canManage) {
    if (!canManage) return state.mineGroups;
    return _showAll ? _allGroups(state) : state.mineGroups;
  }

  /// "כל המשימות" as the switch wants it ([TeamTasksScreen.groupByEvents]).
  static List<TeamTaskGroup> _allGroups(TeamTasksLoaded state) => TeamTasksScreen.groupByEvents
      ? state.allGroups
      : flattenTeamTaskGroups(state.allGroups, compare: compareTeamTasksByOwners);

  /// The "קיבוץ לפי אירועים" switch, under the filters of "כל המשימות".
  Widget _groupByEventsSwitch() {
    final on = TeamTasksScreen.groupByEvents;
    void toggle(bool value) {
      Logger.action('toggle:teamTasksGroupByEvents', {'on': value});
      setState(() => TeamTasksScreen.groupByEvents = value);
      _holdPlace(null);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => toggle(!on),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'קיבוץ לפי אירועים',
                  style: TextStyle(
                    fontSize: TaskStyle.filterFontSize,
                    color: on ? TaskStyle.mine : TaskStyle.neutralText,
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    key: const Key('team-tasks-group-by-events'),
                    value: on,
                    onChanged: toggle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                _holdPlace(null);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The list as design A (Omer, round 3): a card per group, as the דו יומי
/// "המשימות שלי" stage cards (tinted header, white rows). A category's card
/// holds its events as titled sections (16/11/2026, [groupTeamTasks]).
class _GroupedList extends StatefulWidget {
  const _GroupedList({
    required this.groups,
    required this.state,
    required this.now,
    required this.editing,
    required this.viewerId,
    required this.collapsed,
    required this.onToggleGroup,
    this.showAssignments = false,
    this.selectedId,
    this.flash = const {},
    this.flashRound = 0,
    this.onSpotlightGroup,
    this.flat = false,
  });

  /// "קיבוץ לפי אירועים" off: a category's card is one list, with no
  /// "משויכות לקטגוריה" line, and every row carries its events' names.
  final bool flat;

  /// The rows a "בליץ" pass just changed, flashing green.
  final Set<String> flash;
  final int flashRound;

  /// "המשימות שלי": a long press on a card's header opens "בליץ" over
  /// that card's tasks only.
  final ValueChanged<TeamTaskGroup>? onSpotlightGroup;
  /// The 👥 button on an event's card (round 10).
  final bool showAssignments;

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

  /// "כל המשימות": a manager's tap opens the editing view.
  final bool editing;

  @override
  State<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends State<_GroupedList> {
  /// The event's assignments as the live "תמונת שיבוצים" picture of "מי איתי
  /// באירוע?" (Omer, msg 4581: the 👥 showed the old list), with its share
  /// button, as the 👥 of every event in "מסך מנהלים" (round 10).
  Future<void> _showAssignments(Event event) async {
    Logger.action('open:teamTaskEventAssignments', {'eventId': event.id});
    await showDialog<void>(
      context: context,
      builder: (_) => EventTeamMembersDialog(
        event: event,
        currentUserId: widget.viewerId,
        labels: context.read<AssignmentLabelRepository>().watchAssignmentLabels(),
        eventItems: context.read<EventItemBloc>().state.catalogue,
        title: 'שיבוצים ל${event.name}',
        canShare: true,
        emptyText: 'אין עדיין שיבוצים לאירוע',
      ),
    );
  }

  /// "+" on a card (round 10): a new task already linked to it.
  Future<void> _newTaskIn(TaskLink link) async {
    Logger.action('tap:newTeamTaskInCard', {'link': link.type.key});
    final id = await showNewTeamTaskDialog(context, link: link);
    if (id == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('המשימה נוספה')),
    );
  }

  /// A "אירוע שעוד לא נוצר" becomes the real event: pick it, confirm, and
  /// every task of the placeholder moves there (round 10).
  Future<void> _linkPending(TeamTaskGroup group, TaskLink link) async {
    Logger.action('tap:linkPendingEvent');
    final bloc = context.read<TeamTaskBloc>();
    final choice = await showTaskLinkPicker(
      context,
      eventsOnly: true,
      title: 'קישור "${group.label}" לאירוע בשבצק',
    );
    final target = choice?.link;
    if (target == null || !mounted) return;
    final state = widget.state;
    final eventName =
        state.events.where((e) => e.id == target.id).firstOrNull?.name ?? 'האירוע';
    final count = state.all.where((task) => task.link == link).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const Key('link-pending-confirm'),
          title: const Text('קישור לאירוע בשבצק'),
          content: Text(count == 1
              ? 'המשימה של "${group.label}" תעבור לאירוע "$eventName", ו"${group.label}" יוסר מהרשימה.'
              : '$count המשימות של "${group.label}" יעברו לאירוע "$eventName", ו"${group.label}" יוסר מהרשימה.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              key: const Key('link-pending-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('קישור'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final completion = CrudActionCompleter();
    bloc.add(LinkPendingEvent(link.id, target.id, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(result.isSuccess
          ? 'המשימות עברו לאירוע "$eventName"'
          : (result.message ?? 'הקישור נכשל')),
    ));
  }

  /// The small buttons on a card's header (round 10) or on an event's title
  /// inside a category's card ([key] = that section's).
  List<Widget> _headerButtons(TeamTaskGroup group, {String? key, TaskLink? link, Event? event}) {
    link ??= group.link;
    event ??= group.event;
    key ??= group.key;
    if (link == null) return const [];
    Widget button(String prefix, String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          key: Key('$prefix-$key'),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          iconSize: 20,
          color: TaskStyle.neutralText,
          icon: Icon(icon),
          onPressed: onPressed,
        );
    return [
      if (link.type == TaskLinkType.event && event != null && widget.showAssignments)
        button('team-task-group-assignments', 'שיבוצים', Icons.people_outline,
            () => _showAssignments(event!)),
      if (widget.editing && link.type == TaskLinkType.pendingEvent)
        button('team-task-group-link-pending', 'קישור לאירוע בשבצק', Icons.link,
            () => _linkPending(group, link!)),
      if (widget.editing)
        button('team-task-group-add', 'משימה חדשה כאן', Icons.add, () => _newTaskIn(link!)),
    ];
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
            // A card per tab and group: switching to "המשימות שלי" builds its
            // cards anew, so their rows just show, with no fold animation
            // from the other tab's height (Omer, msg 4024).
            for (final group in groups)
              KeyedSubtree(
                key: ValueKey('team-task-card-${widget.editing}-${group.key}'),
                child: _card(context, group, state),
              ),
          ],
        ),
      ),
    );
  }

  /// One task's row; [showEvents] adds the chips of a task of several
  /// events (16/11/2026).
  Widget _row(TeamTask task) => _flashed(
        task.id,
        TeamTaskRow(
          task: task,
          now: widget.now,
          viewerId: widget.viewerId,
          // With the events' sections gone (the switch off), every row
          // names its events.
          showEvents: task.hasSeveralEvents || (widget.flat && task.events.isNotEmpty),
          // "המשימות שלי": the status and a new update without opening the
          // task (Omer, round 4); every row there is the viewer's own.
          selected: task.id == widget.selectedId,
          canChangeStatus: !widget.editing,
          // "כל המשימות" only (msg 4480).
          showCreated: widget.editing,
          onAddUpdate: widget.editing ? null : () => showTeamTaskUpdatesDialog(context, task.id),
          onTap: () => showTeamTaskSheet(context, task.id, manage: widget.editing),
        ),
      );

  static const Widget _rowDivider =
      Divider(height: 1, thickness: 1, color: TaskStyle.stageCardDivider);

  /// One event inside a category's card: its title row (name, days, 👥 and
  /// "+"; a tap folds it) and its tasks.
  List<Widget> _section(TeamTaskGroup group, TeamTaskSection section, TeamTasksLoaded state) {
    final folded = widget.collapsed.contains(section.key) && state.filter.searchText.isEmpty;
    final event = section.event;
    // An event that ended reads a little fainter.
    final past = event != null &&
        DateTime(event.endDate.year, event.endDate.month, event.endDate.day)
            .isBefore(IsraelCalendar.calendarDay(widget.now));
    final days = event == null ? '' : _eventDays(event);
    final count = section.tasks.length;
    return [
      Material(
        color: TeamTaskStyle.sectionHeader,
        child: InkWell(
          key: Key('team-task-section-${section.key}'),
          hoverColor: TeamTaskStyle.rowHover,
          onTap: () => widget.onToggleGroup(section.key),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 6, 4),
            child: Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 16, color: past ? TaskStyle.faintText : TaskStyle.neutralText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: section.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (days.isNotEmpty)
                        TextSpan(
                          text: '  $days',
                          style: const TextStyle(
                            fontSize: TaskStyle.rowMetaSize,
                            color: TaskStyle.neutralText,
                          ),
                        ),
                    ]),
                    style: TextStyle(color: past ? TaskStyle.neutralText : null),
                  ),
                ),
                ..._headerButtons(
                  group,
                  key: section.key,
                  link: TaskLink(TaskLinkType.event, section.eventId),
                  event: event,
                ),
                const SizedBox(width: 4),
                Text(
                  count == 1 ? 'משימה אחת' : '$count משימות',
                  style: const TextStyle(
                    fontSize: TaskStyle.rowMetaSize,
                    color: TaskStyle.neutralText,
                  ),
                ),
                Icon(
                  folded ? Icons.expand_more : Icons.expand_less,
                  key: Key('team-task-section-fold-${section.key}'),
                  size: 18,
                  color: TaskStyle.neutralText,
                ),
              ],
            ),
          ),
        ),
      ),
      if (!folded)
        for (final (i, task) in section.tasks.indexed) ...[
          if (i > 0) _rowDivider,
          _row(task),
        ],
    ];
  }

  /// "15.11" or "15.11-17.11".
  static String _eventDays(Event event) {
    final start = shortDate(event.startDate);
    final end = shortDate(event.endDate);
    return start == end ? start : '$start-$end';
  }

  /// A labelled list inside a category's card (Omer, 16/11/2026): a thin line
  /// in the category's colour with a small title, above the category's own
  /// tasks ("משויכות לקטגוריה") and above its tasks of several events
  /// ("משויכות לכמה אירועים"). Each list that is there gets its line, so
  /// every list is always labelled.
  Widget _listSeparator(Key key, String label, int? colorValue, {double top = 10}) {
    final line = Expanded(
      child: Container(height: 1.5, color: TeamTaskStyle.categorySeparator(colorValue)),
    );
    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(12, top, 12, 6),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: TaskStyle.rowMetaSize,
                color: TaskStyle.neutralText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }

  Widget _card(BuildContext context, TeamTaskGroup group, TeamTasksLoaded state) {
    // A category's card takes the category's colour (Omer, 16/11/2026).
    final isCategory = group.type == TaskLinkType.category;
    final colorValue = isCategory
        ? state.categories.where((c) => c.id == group.link?.id).firstOrNull?.colorValue
        : null;
    final rows = <Widget>[];
    // A category's own tasks: a labelled list of their own.
    if (isCategory && !widget.flat && group.tasks.isNotEmpty) {
      rows.add(_listSeparator(
        Key('team-task-own-separator-${group.key}'),
        'משויכות לקטגוריה',
        colorValue,
        top: 8,
      ));
    }
    for (final (i, task) in group.tasks.indexed) {
      if (i > 0) rows.add(_rowDivider);
      rows.add(_row(task));
    }
    // The tasks of several events: a list of their own, after its line.
    if (group.severalEventTasks.isNotEmpty) {
      rows.add(_listSeparator(
        Key('team-task-several-separator-${group.key}'),
        'משויכות לכמה אירועים',
        colorValue,
        top: rows.isEmpty ? 8 : 10,
      ));
    }
    for (final (i, task) in group.severalEventTasks.indexed) {
      if (i > 0) rows.add(_rowDivider);
      rows.add(_row(task));
    }
    for (final section in group.sections) {
      if (rows.isNotEmpty) rows.add(_rowDivider);
      rows.addAll(_section(group, section, state));
    }
    final count = group.allTasks.length;
    // Folded by a tap on its header (round 7); a search opens it.
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
              key: Key('team-task-group-header-${group.key}'),
              color: TeamTaskStyle.categoryHeader(colorValue),
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
                          '${teamTaskGroupKind(group.type)}${group.label}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ..._headerButtons(group),
                      const SizedBox(width: 4),
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
