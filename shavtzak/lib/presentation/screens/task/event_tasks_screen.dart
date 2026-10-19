import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/debug/search_action_logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/task_import_files.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/task_progress.dart';
import '../../../core/utils/task_schedule.dart';
import '../../../core/utils/task_utils.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import 'row_hold.dart';
import 'sheet_view.dart';
import 'task_screen_actions.dart';
import 'task_style.dart';
import 'tasks_auto_open.dart';
import 'widgets/assignee_check_line.dart';
import 'widgets/calendar_tab.dart';
import 'widgets/day_calendar.dart';
import 'widgets/event_summary.dart';
import 'widgets/member_timeline.dart';
import 'widgets/stage_panel.dart';
import 'widgets/stage_sheet_view.dart';
import 'widgets/stage_task_table.dart';
import 'widgets/task_detail.dart';
import 'widgets/task_filter_bar.dart';
import 'widgets/task_results_list.dart';
import 'widgets/task_row.dart';
import 'widgets/task_sheet.dart';

/// The event screen's two views.
enum EventTasksTab { mine, all }

/// One דו יומי event's tasks, at `/tasks/<eventId>`.
///
/// Two tabs over one low sheet: "המשימות שלי", the viewer's tasks threaded
/// through the stages, and "כל השלבים", every stage. Managers land on the
/// second, everyone else on the first; both are open to every signed-in
/// member. The sheet is where a task, a stage or a list of results is read
/// and acted on, from either tab; the search in the app bar fills it too.
class EventTasksScreen extends StatefulWidget {
  const EventTasksScreen({
    super.key,
    required this.eventId,
    this.clock,
    this.importFiles = const BrowserTaskImportFiles(),
  });

  final String eventId;

  /// Picking the import file and saving the template; faked in tests.
  final TaskImportFiles importFiles;

  /// The current time. Injected by tests; defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<EventTasksScreen> createState() => _EventTasksScreenState();
}

class _EventTasksScreenState extends State<EventTasksScreen>
    with TaskScreenActions<EventTasksScreen> {
  @override
  DateTime get actionTime => _now;

  @override
  TaskImportFiles get importFiles => widget.importFiles;

  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode =
      createRtlCursorFixedFocusNode(_searchController);
  final SearchActionLogger _searchLog = SearchActionLogger('tasks');
  final RowHold _rowHold = RowHold();

  /// Chosen on the first build that knows the user.
  EventTasksTab? _tab;
  SheetView? _sheet;
  bool _searching = false;

  /// Whose timeline "המשימות שלי" shows; null is the signed-in member. Only
  /// a debug build lets a manager pick someone else.
  String? _viewAsId;

  /// The day "כל השלבים" shows: today during the event, the first day
  /// otherwise, taken once; then wherever the member or the sheet moves it.
  DateTime? _calendarDay;

  /// The stage the calendar scrolls to, and a counter asking it to.
  String? _focusStageId;
  int _focusRequest = 0;
  final GlobalKey _focusKey = GlobalKey();

  /// The members assigned to the event, for the managers' check. Null until
  /// the first answer, and null means no check: never flag every task while
  /// the list is still on its way.
  Set<String>? _assignedIds;
  StreamSubscription<List<TeamMember>>? _assignedSubscription;

  /// The board as last built, to find the stage a sheet is about.
  EventTaskBoard? _board;

  late DateTime _now;
  Timer? _ticker;

  /// A hidden tab's timers sleep, so coming back brings "now" up to date at
  /// once rather than at the next tick.
  late final AppLifecycleListener _lifecycle;

  DateTime _readClock() => (widget.clock ?? DateTime.now)();

  /// Ticks as each new minute begins, so the time shown matches the
  /// phone's clock rather than lagging by however far into a minute the
  /// screen was opened.
  void _scheduleTick() {
    final current = _readClock();
    final intoMinute = Duration(
      seconds: current.second,
      milliseconds: current.millisecond,
      microseconds: current.microsecond,
    );
    _ticker = Timer(const Duration(minutes: 1) - intoMinute, () {
      if (!mounted) return;
      setState(() => _now = _readClock());
      _scheduleTick();
    });
  }

  @override
  void initState() {
    super.initState();
    // Back from here to the list must not bounce into an event again.
    TasksAutoOpen.spend();
    _now = _readClock();
    context.read<TaskBloc>().add(const LoadTasks());
    // A task turns orange or red because time passed, not because data
    // changed, so the colours need their own heartbeat.
    _scheduleTick();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (mounted) setState(() => _now = _readClock());
    });
    final auth = context.read<UserSelectionBloc>().state;
    if (auth is UserAuthenticated && canManageTasks(auth.user)) {
      _assignedSubscription = context
          .read<TaskRepository>()
          .watchEventAssignees(widget.eventId)
          .listen((members) {
        if (!mounted) return;
        setState(() => _assignedIds = {for (final member in members) member.id});
      });
    }
  }

  @override
  void dispose() {
    _assignedSubscription?.cancel();
    _lifecycle.dispose();
    _ticker?.cancel();
    _searchLog.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---- navigation within the screen ----

  void _setTab(EventTasksTab tab) {
    Logger.action('toggle:tasksTab', {'tab': tab.name});
    setState(() => _tab = tab);
  }

  void _openSheet(SheetView view) {
    Logger.action('open:taskSheet', {'view': _viewName(view)});
    setState(() {
      final previous = _sheet;
      _sheet = view;
      // A stage, or a task, brings the calendar to its day and its block;
      // results move nothing, and neither does switching within a stage.
      final stage = _stageOf(view);
      if (stage != null &&
          (previous == null || _stageOf(previous)?.id != stage.id)) {
        final date = stage.date;
        _calendarDay = DateTime(date.year, date.month, date.day);
        _focusStageId = stage.id;
        _focusRequest++;
      }
    });
  }

  /// The one stage [view] is about, if it is about one.
  Stage? _stageOf(SheetView view) {
    final board = _board;
    if (board == null) return null;
    switch (view) {
      case StageView(:final stageId):
        return board.stageById(stageId);
      case TaskView(:final taskId):
        final task = board.taskById(taskId);
        return task == null ? null : board.stageById(task.stageId);
      case ResultsView():
        return null;
    }
  }

  void _closeSheet() {
    Logger.action('close:taskSheet');
    setState(() {
      _sheet = null;
      _rowHold.clear();
    });
  }

  static String _viewName(SheetView view) => switch (view) {
        StageView() => 'stage',
        ResultsView(:final kind) => kind.name,
        TaskView() => 'task',
      };

  /// Whether [view] is the search results, or a task opened from them.
  static bool _isSearch(SheetView? view) => switch (view) {
        ResultsView(kind: ResultsKind.search) => true,
        TaskView(:final back) => _isSearch(back),
        _ => false,
      };

  void _openSearch() {
    Logger.action('tap:tasksSearch');
    setState(() => _searching = true);
  }

  void _closeSearch() {
    Logger.action('tap:tasksSearchClose');
    _searchController.clear();
    _searchLog.onQueryChanged('');
    setState(() {
      _searching = false;
      if (_isSearch(_sheet)) {
        _sheet = null;
        _rowHold.clear();
      }
    });
  }

  void _onQueryChanged(String value) {
    _searchLog.onQueryChanged(value);
    final query = value.trim();
    setState(() {
      if (query.isNotEmpty) {
        _sheet = ResultsView(ResultsKind.search, query: query);
      } else if (_isSearch(_sheet)) {
        _sheet = null;
        _rowHold.clear();
      }
    });
  }

  void _backToEvents() {
    Logger.action('tap:tasksBackToEvents');
    context.go('${EnvironmentService.instance.routePrefix}/tasks');
  }

  /// [view] as it can be shown on [board]: a task that is gone gives way to
  /// the list it was opened from, a stage that is gone closes the sheet.
  SheetView? _resolve(SheetView? view, EventTaskBoard board) {
    return switch (view) {
      null => null,
      TaskView(:final taskId, :final back) =>
        board.taskById(taskId) != null ? view : _resolve(back, board),
      StageView(:final stageId) => board.stageById(stageId) != null ? view : null,
      ResultsView() => view,
    };
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, authState) {
          if (authState is! UserAuthenticated) {
            return const Scaffold(
              body: Center(child: Text('גישה לא מורשית - דרוש אימות')),
            );
          }
          final user = authState.user;
          _tab ??=
              canManageTasks(user) ? EventTasksTab.all : EventTasksTab.mine;
          return BlocBuilder<TaskBloc, TaskState>(
            builder: (context, state) {
              final loaded = state is TasksLoaded ? state : null;
              final event = loaded == null ? null : _findEvent(loaded);
              final board = event == null
                  ? null
                  : eventTaskBoard(
                      event,
                      stages: loaded!.stages,
                      tasks: loaded.tasks,
                    );
              final isWideWindow = MediaQuery.sizeOf(context).width >=
                  TaskStyle.wideBreakpoint;
              return Scaffold(
                appBar: _buildAppBar(event),
                body: TestEnvironmentIndicator(
                  child: _buildBody(state, board, user),
                ),
                // On a computer it sits over the calendar, on the start side;
                // on a phone it steps aside while the sheet is open.
                floatingActionButtonLocation:
                    isWideWindow ? FloatingActionButtonLocation.startFloat : null,
                floatingActionButton: board != null &&
                        canManageTasks(user) &&
                        _tab == EventTasksTab.all &&
                        (_sheet == null || isWideWindow)
                    ? FloatingActionButton.extended(
                        key: const Key('stage-add'),
                        onPressed: () => createStage(board.event, user),
                        icon: const Icon(Icons.add),
                        label: const Text('שלב חדש'),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Event? event) {
    return AppBar(
      title: _searching
          ? TextField(
              key: const Key('tasks-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              cursorColor: Colors.white,
              style: const TextStyle(color: Colors.white, fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'חיפוש משימה או אדם...',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onChanged: _onQueryChanged,
            )
          : Text(event?.name ?? 'משימות דו יומי'),
      // The back arrow on the far left, pointing left, with search beside it.
      automaticallyImplyLeading: false,
      actions: [
        if (_searching)
          IconButton(
            key: const Key('tasks-search-close'),
            tooltip: 'סגירת החיפוש',
            icon: const Icon(Icons.close),
            onPressed: _closeSearch,
          )
        else
          IconButton(
            key: const Key('tasks-search-open'),
            tooltip: 'חיפוש',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        IconButton(
          key: const Key('tasks-back'),
          tooltip: 'חזרה לרשימת האירועים',
          // Mirrored under RTL, so it draws pointing left.
          icon: const Icon(Icons.arrow_forward),
          onPressed: _backToEvents,
        ),
      ],
    );
  }

  /// The screen's event, if it is an active דו יומי event.
  Event? _findEvent(TasksLoaded state) {
    for (final event in state.events) {
      if (event.id != widget.eventId) continue;
      if (event.isDeactivated || event.categoryId != duYomiCategoryId) {
        return null;
      }
      return event;
    }
    return null;
  }

  Widget _buildBody(TaskState state, EventTaskBoard? board, TeamMember user) {
    if (state is TasksError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(state.message),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('tasks-retry'),
              onPressed: () => context.read<TaskBloc>().add(const LoadTasks()),
              icon: const Icon(Icons.refresh),
              label: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }
    if (state is! TasksLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (board == null) return _buildUnknownEvent();

    _board = board;
    final sheet = _resolve(_sheet, board);
    if (sheet != _sheet) {
      // What the sheet showed is gone; settle on what it shows now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _sheet = _resolve(_sheet, board);
          if (_sheet == null) _rowHold.clear();
        });
      });
    }

    final VoidCallback? onBack = switch (sheet) {
      TaskView(:final back?) => () => _openSheet(back),
      _ => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        // The layout follows the window's width, not the role.
        final isWide = constraints.maxWidth >= TaskStyle.wideBreakpoint;
        if (isWide && _tab == EventTasksTab.all && board.stages.isNotEmpty) {
          return Column(
            children: [
              _readableWidth(_buildTabs()),
              Expanded(child: _buildAllWide(board, user, sheet, onBack)),
            ],
          );
        }
        final phone = Column(
          children: [
            _buildTabs(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, inner) {
                  final sheetRoom = sheet == null
                      ? 0.0
                      : inner.maxHeight * TaskStyle.sheetInitialSize;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: _tab == EventTasksTab.mine
                            ? _buildMine(board, user, sheetRoom)
                            : _buildAll(board, user, sheet, sheetRoom),
                      ),
                      if (sheet != null)
                        TaskSheet(
                          viewKey: sheet,
                          content: _sheetContent(sheet, board, user),
                          onClose: _closeSheet,
                          onBack: onBack,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
        // "המשימות שלי" keeps its phone layout on a wide screen, centred.
        return isWide ? _readableWidth(phone) : phone;
      },
    );
  }

  Widget _readableWidth(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: TaskStyle.readableWidth),
          child: child,
        ),
      );

  /// "כל השלבים" on a computer: the summary, filters and check in a toolbar,
  /// the calendar on the right with the days side by side, and the sheet's
  /// content as a panel on the left. Nothing fades: the panel covers no part
  /// of the calendar.
  Widget _buildAllWide(
    EventTaskBoard board,
    TeamMember user,
    SheetView? sheet,
    VoidCallback? onBack,
  ) {
    final days = calendarDays(board.event, board.stages);
    final chosen = _calendarDay ??= initialCalendarDay(days, _now);
    final day = days.contains(chosen) ? chosen : days.first;
    final sideBySide = days.length <= TaskStyle.maxSideBySideDays;
    final removed = _removedAssigneeTasks(board, user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          key: const Key('wide-toolbar'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: EventSummary(
                    event: board.event,
                    progress: taskProgress(board.tasks, _now),
                  ),
                ),
                TaskFilterBar(
                  lateCount: lateTasks(board.tasks, _now).length,
                  soonCount: dueSoonTasks(board.tasks, _now).length,
                  active: _activeFilter(sheet),
                  onChanged: _onFilterChanged,
                ),
              ],
            ),
            if (removed.isNotEmpty)
              AssigneeCheckLine(
                count: removed.length,
                wide: true,
                onTap: () =>
                    _openSheet(const ResultsView(ResultsKind.removedAssignees)),
              ),
            const Divider(height: 1),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: TaskStyle.calendarFlex,
                child: Column(
                  children: [
                    if (!sideBySide)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: CalendarDayChips(
                          days: days,
                          selectedDay: day,
                          now: _now,
                          onSelectDay: (next) {
                            Logger.action('tap:calendarDay');
                            setState(() => _calendarDay = next);
                          },
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        // Room at the bottom for the floating button.
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                        child: _buildCalendar(
                          board,
                          user,
                          sheet,
                          sideBySide ? days : [day],
                          hourHeight: TaskStyle.wideHourHeight,
                          fadeOthers: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: TaskStyle.panelFlex,
                child: StagePanel(
                  viewKey: sheet,
                  content: sheet == null
                      ? null
                      : _sheetContent(sheet, board, user, wide: true),
                  onClose: _closeSheet,
                  onBack: onBack,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<EventTasksTab>(
          showSelectedIcon: false,
          // Explicit colours: the app theme's defaults for a selected
          // segment are white text on light orange, which is unreadable.
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppTheme.primaryDark,
            selectedForegroundColor: Colors.white,
          ),
          segments: const [
            ButtonSegment(
              value: EventTasksTab.mine,
              label: Text('המשימות שלי', key: Key('tab-mine')),
            ),
            ButtonSegment(
              value: EventTasksTab.all,
              label: Text('כל השלבים', key: Key('tab-all')),
            ),
          ],
          selected: {_tab!},
          onSelectionChanged: (selection) => _setTab(selection.first),
        ),
      ),
    );
  }

  // ---- "המשימות שלי" ----

  Widget _buildMine(EventTaskBoard board, TeamMember user, double sheetRoom) {
    if (board.stages.isEmpty) {
      return _buildNoStages(user, board.event, forManagers: false);
    }
    final viewerId = _viewAsId ?? user.id;
    final timeline = MemberTimeline(
      key: ValueKey('timeline-$viewerId'),
      board: board,
      viewerId: viewerId,
      now: _now,
      canTick: viewerId == user.id,
      onOpenTask: (task) => _openSheet(TaskView(task.id)),
      onOpenStage: (stage) => _openSheet(StageView(stage.id)),
      onSetComplete: setComplete,
      onToggleSubtask: toggleSubtask,
      onOpenMyLate: () => _openSheet(const ResultsView(ResultsKind.myLate)),
      onShowAllStages: () => _setTab(EventTasksTab.all),
      bottomPadding: sheetRoom,
    );
    if (!(kDebugMode && canManageTasks(user))) return timeline;
    return Column(
      children: [
        _buildViewAs(board, user),
        Expanded(child: timeline),
      ],
    );
  }

  /// Debug runs only: lets a manager see any member's timeline, read-only,
  /// to judge it on real data.
  Widget _buildViewAs(EventTaskBoard board, TeamMember user) {
    final people = <String, String>{user.id: user.name};
    for (final task in board.tasks) {
      for (final member in task.assignees) {
        people[member.id] = member.name;
      }
    }
    final viewerId = _viewAsId ?? user.id;
    return Material(
      color: TaskStyle.soonLight,
      child: InkWell(
        key: const Key('view-as'),
        onTap: () => _pickViewer(people, user),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('תצוגה בתור: ${people[viewerId] ?? ''}')),
              const Text(
                'הרצה מקומית בלבד',
                style: TextStyle(fontSize: 11, color: TaskStyle.neutralText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickViewer(Map<String, String> people, TeamMember user) async {
    Logger.action('tap:viewAs');
    final sorted = people.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('תצוגה בתור'),
          children: [
            for (final person in sorted)
              SimpleDialogOption(
                key: Key('view-as-${person.key}'),
                onPressed: () => Navigator.of(context).pop(person.key),
                child: Text(person.value),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _viewAsId = chosen == user.id ? null : chosen);
  }

  // ---- "כל השלבים" ----

  Widget _buildAll(
    EventTaskBoard board,
    TeamMember user,
    SheetView? sheet,
    double sheetRoom,
  ) {
    if (board.stages.isEmpty) {
      return _buildNoStages(user, board.event, forManagers: true);
    }
    final days = calendarDays(board.event, board.stages);
    // It opens on the stage of now.
    _focusStageId ??= timelineAnchor(board.stages, _now)?.id;
    final removed = _removedAssigneeTasks(board, user);
    return CalendarTab(
      top: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EventSummary(
            event: board.event,
            progress: taskProgress(board.tasks, _now),
          ),
          if (removed.isNotEmpty)
            AssigneeCheckLine(
              count: removed.length,
              onTap: () =>
                  _openSheet(const ResultsView(ResultsKind.removedAssignees)),
            ),
        ],
      ),
      filterBar: TaskFilterBar(
        lateCount: lateTasks(board.tasks, _now).length,
        soonCount: dueSoonTasks(board.tasks, _now).length,
        active: _activeFilter(sheet),
        onChanged: _onFilterChanged,
      ),
      calendar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final day in days) ...[
            CalendarDayDivider(day: day, now: _now),
            _buildCalendar(board, user, sheet, [day]),
          ],
        ],
      ),
      focusKey: _focusKey,
      focusRequest: _focusRequest,
      bottomPadding: sheetRoom,
    );
  }

  /// The calendar of [days], outlining what the sheet is about.
  DayCalendar _buildCalendar(
    EventTaskBoard board,
    TeamMember user,
    SheetView? sheet,
    List<DateTime> days, {
    double hourHeight = TaskStyle.hourHeight,
    bool fadeOthers = true,
  }) {
    final stagesByDay = <DateTime, List<Stage>>{};
    for (final stage in board.stages) {
      final date = stage.date;
      stagesByDay
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(stage);
    }
    return DayCalendar(
      days: days,
      stagesByDay: stagesByDay,
      progressByStage: {
        for (final stage in board.stages)
          stage.id: taskProgress(board.tasksOf(stage.id), _now),
      },
      mineByStage: {
        for (final stage in board.stages)
          stage.id: board
              .tasksOf(stage.id)
              .where((task) => task.isAssignedTo(user.id))
              .length,
      },
      currentStageIds: {
        for (final stage in currentStages(board.stages, _now)) stage.id,
      },
      now: _now,
      hourHeight: hourHeight,
      outlinedStageIds: _outlinedStages(sheet, board, user),
      fadeOthers: fadeOthers && sheet != null,
      focusStageId: _focusStageId,
      focusKey: _focusKey,
      onOpenStage: (stage, {required missingOnly}) =>
          _openSheet(StageView(stage.id, missingOnly: missingOnly)),
    );
  }

  /// The stages the sheet is about: its stage, a task's stage, or the
  /// stages its results come from.
  Set<String> _outlinedStages(
    SheetView? view,
    EventTaskBoard board,
    TeamMember user,
  ) {
    switch (view) {
      case null:
        return const {};
      case StageView(:final stageId):
        return {stageId};
      case TaskView(:final taskId):
        final task = board.taskById(taskId);
        return task == null ? const {} : {task.stageId};
      case ResultsView():
        return {
          for (final task in _results(view, board, user).$2) task.stageId,
        };
    }
  }

  /// The filter behind the sheet, also while a task opened from it shows.
  static TaskFilter? _activeFilter(SheetView? view) => switch (view) {
        ResultsView(kind: ResultsKind.late) => TaskFilter.late,
        ResultsView(kind: ResultsKind.dueSoon) => TaskFilter.dueSoon,
        TaskView(:final back) => _activeFilter(back),
        _ => null,
      };

  void _onFilterChanged(TaskFilter? filter) {
    Logger.action('toggle:taskFilter', {'filter': filter?.name});
    switch (filter) {
      case null:
        _closeSheet();
      case TaskFilter.late:
        _openSheet(const ResultsView(ResultsKind.late));
      case TaskFilter.dueSoon:
        _openSheet(const ResultsView(ResultsKind.dueSoon));
    }
  }

  /// The tasks whose assignee was taken off the event, for managers once
  /// the event's assignees are known; none before that.
  List<TaskItem> _removedAssigneeTasks(EventTaskBoard board, TeamMember user) {
    final assigned = _assignedIds;
    if (assigned == null || !canManageTasks(user)) return const [];
    return tasksWithRemovedAssignees(board.tasks, assigned);
  }

  // ---- the sheet ----

  /// What the sheet, or with [wide] the side panel, shows for [view]. On a
  /// wide screen a stage's tasks are one table.
  SheetContent _sheetContent(
    SheetView view,
    EventTaskBoard board,
    TeamMember user, {
    bool wide = false,
  }) {
    switch (view) {
      case TaskView(:final taskId):
        final task = board.taskById(taskId)!;
        final stage = board.stageById(task.stageId)!;
        return SheetContent(
          header: const Text('פרטי המשימה'),
          body: TaskDetail(
            task: task,
            now: _now,
            canManage: canManageTasks(user),
            canUpdateProgress: canUpdateTaskProgress(task, user),
            onToggleSubtask: (subtask, isDone) =>
                toggleSubtask(task, subtask, isDone),
            onSetComplete: (isComplete) => setComplete(task, isComplete),
            onEditUpdate: () => editUpdate(task),
            onEdit: () => editTask(task, board.event, stage, user),
            onDelete: () => deleteTask(task),
            onCallPhone: callPhone,
          ),
        );
      case StageView(:final stageId, :final missingOnly):
        final stage = board.stageById(stageId)!;
        final stageTasks = board.tasksOf(stageId);
        final rows = _rowHold.rows(
          view,
          matching: missingOnly
              ? [for (final task in stageTasks) if (!task.isComplete) task]
              : stageTasks,
          all: stageTasks,
        );
        return SheetContent(
          header: StageSheetHeader(
            stage: stage,
            canManage: canManageTasks(user),
            onEdit: () => editStage(stage, board.event, user),
            onDelete: () => deleteStage(stage, stageTasks.length),
          ),
          body: StageSheetBody(
            stage: stage,
            rows: rows,
            progress: taskProgress(stageTasks, _now),
            missingOnly: missingOnly,
            onSwitch: (missing) =>
                _openSheet(StageView(stageId, missingOnly: missing)),
            rowBuilder: (task) => _taskRow(task, view, user),
            canManage: canManageTasks(user),
            onAddTask: () => createTask(board.event, stage, user),
            onCallPhone: callPhone,
            tableBuilder: wide
                ? (rows) => _stageTable(rows, view, board, user)
                : null,
          ),
        );
      case ResultsView():
        final (title, matching, subtitle) = _results(view, board, user);
        final rows = _rowHold.rows(view, matching: matching, all: board.tasks);
        return SheetContent(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: TaskStyle.neutralText,
                  ),
                ),
            ],
          ),
          body: _resultsBody(
            view,
            board,
            user,
            rows,
            emptyText: 'לא נמצאו משימות תואמות',
          ),
        );
    }
  }

  /// A list's title, the tasks matching it now, earliest due first, and an
  /// optional line under the title. The count in the title is live; the
  /// rows shown are held separately.
  (String, List<TaskItem>, String?) _results(
    ResultsView view,
    EventTaskBoard board,
    TeamMember user,
  ) {
    switch (view.kind) {
      case ResultsKind.search:
        final matching =
            sortTasks(filterTasks(board.tasks, now: _now, query: view.query));
        return ('חיפוש: "${view.query}" · ${matching.length}', matching, null);
      case ResultsKind.myLate:
        final viewerId = _viewAsId ?? user.id;
        final matching = lateTasks(
          [for (final task in board.tasks) if (task.isAssignedTo(viewerId)) task],
          _now,
        );
        final title = hebrewCount(
          matching.length,
          one: 'משימה אחת שלך באיחור',
          many: 'משימות שלך באיחור',
        );
        return (title, matching, null);
      case ResultsKind.late:
        final matching = lateTasks(board.tasks, _now);
        final count =
            hebrewCount(matching.length, one: 'משימה אחת', many: 'משימות');
        return ('באיחור · $count', matching, 'מכל השלבים, הוותיקה ראשונה');
      case ResultsKind.dueSoon:
        final matching = dueSoonTasks(board.tasks, _now);
        return (
          'התייצבות בחצי שעה הקרובה · ${matching.length}',
          matching,
          'מכל השלבים, הקרובה ראשונה',
        );
      case ResultsKind.removedAssignees:
        final matching = _removedAssigneeTasks(board, user);
        final title = hebrewCount(
          matching.length,
          one: 'משימה אחת של מי שכבר לא משובץ לאירוע',
          many: 'משימות של מי שכבר לא משובץ לאירוע',
        );
        return (title, matching, null);
    }
  }

  Widget _resultsBody(
    SheetView view,
    EventTaskBoard board,
    TeamMember user,
    List<TaskItem> rows, {
    required String emptyText,
  }) {
    return TaskResultsList(
      groups: stagesToShow(
        stages: board.stages,
        visibleTasks: rows,
        showEveryStage: false,
      ),
      emptyText: emptyText,
      rowBuilder: (task) => _taskRow(task, view, user),
    );
  }

  /// A stage's tasks as the wide panel's table; a row opens over [from].
  Widget _stageTable(
    List<TaskItem> rows,
    SheetView from,
    EventTaskBoard board,
    TeamMember user,
  ) {
    final assigned = _assignedIds;
    return StageTaskTable(
      tasks: rows,
      now: _now,
      viewerId: user.id,
      canTick: (task) => canUpdateTaskProgress(task, user),
      canManage: canManageTasks(user),
      removedAssigneeIds: (task) => assigned == null || !canManageTasks(user)
          ? const []
          : removedAssigneeIds(task, assigned),
      onSetComplete: setComplete,
      onOpen: (task) => _openSheet(TaskView(task.id, back: from)),
      onEdit: (task) =>
          editTask(task, board.event, board.stageById(task.stageId)!, user),
      onDelete: deleteTask,
      onCallPhone: callPhone,
    );
  }

  /// A task in one of the sheet's lists; it opens over [from]. A manager
  /// sees an assignee taken off the event struck through on any row.
  Widget _taskRow(TaskItem task, SheetView from, TeamMember user) {
    final assigned = _assignedIds;
    return TaskRow(
      task: task,
      now: _now,
      viewerId: user.id,
      canTick: canUpdateTaskProgress(task, user),
      onSetComplete: (isComplete) => setComplete(task, isComplete),
      onOpen: () => _openSheet(TaskView(task.id, back: from)),
      onCallPhone: callPhone,
      removedAssigneeIds: assigned == null || !canManageTasks(user)
          ? const []
          : removedAssigneeIds(task, assigned),
    );
  }

  // ---- empty and unknown ----

  Widget _buildUnknownEvent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'האירוע לא נמצא',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('tasks-unknown-back'),
              onPressed: _backToEvents,
              child: const Text('לרשימת האירועים'),
            ),
          ],
        ),
      ),
    );
  }

  /// An event with no stages yet. On "כל השלבים" a manager also gets the way
  /// to add one, and the Excel import, which fills an empty event only.
  Widget _buildNoStages(
    TeamMember user,
    Event event, {
    required bool forManagers,
  }) {
    final isManager = forManagers && canManageTasks(user);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('אין עדיין שלבים לאירוע זה', style: theme.textTheme.titleMedium),
            if (isManager) ...[
              const SizedBox(height: 6),
              Text(
                'אפשר להוסיף שלב בכפתור "שלב חדש"',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('tasks-import'),
                    onPressed: () => importFromExcel(event, user),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('ייבוא מאקסל'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('tasks-import-template'),
                    onPressed: () => downloadTemplate(event),
                    icon: const Icon(Icons.download),
                    label: const Text('הורדת תבנית'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
