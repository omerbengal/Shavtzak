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
import '../../../core/utils/task_utils.dart';
import '../../../domain/entities/event.dart';
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
import 'widgets/legacy_stage_list.dart';
import 'widgets/member_timeline.dart';
import 'widgets/task_card.dart';
import 'widgets/task_detail.dart';
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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final RowHold _rowHold = RowHold();

  /// Chosen on the first build that knows the user.
  EventTasksTab? _tab;
  SheetView? _sheet;
  bool _searching = false;

  /// Whose timeline "המשימות שלי" shows; null is the signed-in member. Only
  /// a debug build lets a manager pick someone else.
  String? _viewAsId;

  late DateTime _now;
  Timer? _ticker;

  DateTime _readClock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Back from here to the list must not bounce into an event again.
    TasksAutoOpen.spend();
    _now = _readClock();
    context.read<TaskBloc>().add(const LoadTasks());
    // A task turns orange or red because time passed, not because data
    // changed, so the colours need their own heartbeat.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = _readClock());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchLog.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  // ---- navigation within the screen ----

  void _setTab(EventTasksTab tab) {
    Logger.action('toggle:tasksTab', {'tab': tab.name});
    setState(() => _tab = tab);
  }

  void _openSheet(SheetView view) {
    Logger.action('open:taskSheet', {'view': _viewName(view)});
    setState(() => _sheet = view);
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
              return Scaffold(
                appBar: _buildAppBar(event),
                body: TestEnvironmentIndicator(
                  child: _buildBody(state, board, user),
                ),
                floatingActionButton: board != null &&
                        canManageTasks(user) &&
                        _tab == EventTasksTab.all
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

    return Column(
      children: [
        _buildTabs(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sheetRoom = sheet == null
                  ? 0.0
                  : constraints.maxHeight * TaskStyle.sheetInitialSize;
              return Stack(
                children: [
                  Positioned.fill(
                    child: _tab == EventTasksTab.mine
                        ? _buildMine(board, user, sheetRoom)
                        : _buildAll(board, user),
                  ),
                  if (sheet != null)
                    TaskSheet(
                      controller: _sheetController,
                      viewKey: sheet,
                      content: _sheetContent(sheet, board, user),
                      onClose: _closeSheet,
                      onBack: switch (sheet) {
                        TaskView(:final back?) => () => _openSheet(back),
                        _ => null,
                      },
                    ),
                ],
              );
            },
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

  Widget _buildAll(EventTaskBoard board, TeamMember user) {
    if (board.stages.isEmpty) {
      return _buildNoStages(user, board.event, forManagers: true);
    }
    final event = board.event;
    return LegacyStageList(
      groups: stagesToShow(
        stages: board.stages,
        visibleTasks: board.tasks,
        showEveryStage: true,
      ),
      eventTasks: board.tasks,
      canManage: canManageTasks(user),
      onEditStage: (stage) => editStage(stage, event, user),
      onDeleteStage: deleteStage,
      onAddTask: (stage) => createTask(event, stage, user),
      onCallPhone: callPhone,
      taskBuilder: (task, stage) => TaskCard(
        key: ValueKey(task.id),
        task: task,
        now: _now,
        canManage: canManageTasks(user),
        canUpdateProgress: canUpdateTaskProgress(task, user),
        onToggleSubtask: (subtask, isDone) =>
            toggleSubtask(task, subtask, isDone),
        onSetComplete: (isComplete) => setComplete(task, isComplete),
        onEditUpdate: () => editUpdate(task),
        onEdit: () => editTask(task, event, stage, user),
        onDelete: () => deleteTask(task),
      ),
    );
  }

  // ---- the sheet ----

  SheetContent _sheetContent(
    SheetView view,
    EventTaskBoard board,
    TeamMember user,
  ) {
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
          header: Text(stage.title),
          body: _resultsBody(
            view,
            board,
            user,
            rows,
            emptyText: 'אין עדיין משימות בשלב זה',
          ),
        );
      case ResultsView(:final kind, :final query):
        final (String title, List<TaskItem> matching) = switch (kind) {
          ResultsKind.search => _searchResults(board, query),
          ResultsKind.myLate => _myLateResults(board, user),
          // The calendar tab's lists arrive with the calendar.
          _ => ('', const <TaskItem>[]),
        };
        final rows = _rowHold.rows(view, matching: matching, all: board.tasks);
        return SheetContent(
          header: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  (String, List<TaskItem>) _searchResults(EventTaskBoard board, String query) {
    final matching = sortTasks(filterTasks(board.tasks, now: _now, query: query));
    return ('חיפוש: "$query" · ${matching.length}', matching);
  }

  (String, List<TaskItem>) _myLateResults(EventTaskBoard board, TeamMember user) {
    final viewerId = _viewAsId ?? user.id;
    final matching = lateTasks(
      [for (final task in board.tasks) if (task.isAssignedTo(viewerId)) task],
      _now,
    );
    return (
      hebrewCount(
        matching.length,
        one: 'משימה אחת שלך באיחור',
        many: 'משימות שלך באיחור',
      ),
      matching,
    );
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
      rowBuilder: (task) => TaskRow(
        task: task,
        now: _now,
        viewerId: user.id,
        canTick: canUpdateTaskProgress(task, user),
        onSetComplete: (isComplete) => setComplete(task, isComplete),
        onOpen: () => _openSheet(TaskView(task.id, back: view)),
        onCallPhone: callPhone,
      ),
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
