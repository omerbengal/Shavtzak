import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/debug/search_action_logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/task_utils.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import 'widgets/assignee_update_dialog.dart';
import 'widgets/task_card.dart';
import 'widgets/task_filter_modal.dart';
import 'widgets/task_form_modal.dart';

/// The דו יומי task screen, at `/tasks`.
///
/// Reachable only by link: nothing in the app navigates here. Every signed-in
/// member can read every task; the list opens on the member's own tasks.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.clock});

  /// The current time. Injected by tests; defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SearchActionLogger _searchLog = SearchActionLogger('tasks');

  bool _showAll = false;
  String _query = '';
  TaskFilterSelection _filter = const TaskFilterSelection();

  late DateTime _now;
  Timer? _ticker;

  DateTime _readClock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
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
    _searchController.dispose();
    super.dispose();
  }

  // ---- actions ----

  /// Send a mutation and report a failure in a snackbar. Success is silent:
  /// the change shows up through the stream.
  Future<void> _dispatch(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) async {
    final completion = CrudActionCompleter();
    context.read<TaskBloc>().add(build(completion));
    final result = await completion.future;
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'הפעולה נכשלה. נסו שוב.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  Future<void> _createTask(TasksLoaded state, TeamMember user) async {
    Logger.action('tap:taskAdd');
    final task = await showTaskFormModal(
      context,
      events: state.events,
      members: state.members,
      currentUserId: user.id,
      now: _now,
    );
    if (task == null || !mounted) return;
    await _dispatch((completion) => CreateTask(task, completion: completion));
  }

  Future<void> _editTask(
    TaskItem existing,
    TasksLoaded state,
    TeamMember user,
  ) async {
    Logger.action('tap:taskEdit');
    final task = await showTaskFormModal(
      context,
      existing: existing,
      events: state.events,
      members: state.members,
      currentUserId: user.id,
      now: _now,
    );
    if (task == null || !mounted) return;
    await _dispatch((completion) => UpdateTask(task, completion: completion));
  }

  Future<void> _deleteTask(TaskItem task) async {
    Logger.action('tap:taskDelete');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משימה'),
          content: Text('למחוק את "${task.title}"? לא ניתן לשחזר.'),
          actions: [
            TextButton(
              key: const Key('task-delete-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              key: const Key('task-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('מחיקה'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _dispatch(
      (completion) => DeleteTask(task.id, completion: completion),
    );
  }

  Future<void> _editUpdate(TaskItem task) async {
    Logger.action('tap:taskUpdate');
    final text = await showAssigneeUpdateDialog(
      context,
      initialText: task.assigneeUpdate,
    );
    if (text == null || !mounted) return;
    await _dispatch(
      (completion) => SaveAssigneeUpdate(
        taskId: task.id,
        text: text,
        completion: completion,
      ),
    );
  }

  void _toggleSubtask(TaskItem task, Subtask subtask, bool isDone) {
    Logger.action('toggle:subtask', {'on': isDone});
    _dispatch(
      (completion) => ToggleSubtask(
        taskId: task.id,
        subtaskId: subtask.id,
        isDone: isDone,
        completion: completion,
      ),
    );
  }

  void _setComplete(TaskItem task, bool isComplete) {
    Logger.action('toggle:taskComplete', {'on': isComplete});
    _dispatch(
      (completion) => SetTaskComplete(
        taskId: task.id,
        isComplete: isComplete,
        completion: completion,
      ),
    );
  }

  Future<void> _openFilter(List<TaskItem> allTasks) async {
    Logger.action('open:taskFilterModal');
    // Offer only what would actually match something: events and members that
    // appear on at least one task.
    final eventsById = <String, Event>{};
    final membersById = <String, TeamMember>{};
    for (final task in allTasks) {
      final event = task.event;
      if (event != null) eventsById[event.id] = event;
      for (final member in task.assignees) {
        membersById[member.id] = member;
      }
    }
    final events = eventsById.values.toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final members = membersById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final selection = await showTaskFilterModal(
      context,
      current: _filter,
      events: events,
      members: members,
    );
    if (selection == null || !mounted) return;
    Logger.action('filter:tasks', {'groups': selection.activeCount});
    setState(() => _filter = selection);
  }

  void _goHome(TeamMember user) {
    Logger.action('tap:tasksHome');
    final prefix = EnvironmentService.instance.routePrefix;
    final String home;
    if (user.isAdmin) {
      home = '/admin';
    } else if (user.canAccessSummaryScreen ||
        user.canAccessShamapExport ||
        user.canAccessConstraintsExamining) {
      home = '/choice';
    } else {
      home = '/user/assignments';
    }
    context.go('$prefix$home');
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
          return BlocBuilder<TaskBloc, TaskState>(
            builder: (context, state) {
              final loaded = state is TasksLoaded ? state : null;
              return Scaffold(
                appBar: AppBar(
                  title: const Text('משימות דו יומי'),
                  leading: IconButton(
                    key: const Key('tasks-home'),
                    tooltip: 'חזרה לדף הבית',
                    icon: const Icon(Icons.home_outlined),
                    onPressed: () => _goHome(user),
                  ),
                ),
                body: _buildBody(state, user),
                floatingActionButton: loaded != null && canManageTasks(user)
                    ? FloatingActionButton.extended(
                        key: const Key('tasks-add'),
                        onPressed: () => _createTask(loaded, user),
                        icon: const Icon(Icons.add),
                        label: const Text('משימה חדשה'),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(TaskState state, TeamMember user) {
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
              onPressed: () =>
                  context.read<TaskBloc>().add(const LoadTasks()),
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

    final visible = sortTasks(
      filterTasks(
        state.tasks,
        now: _now,
        query: _query,
        onlyAssigneeId: _showAll ? null : user.id,
        statuses: _filter.statuses,
        eventIds: _filter.eventIds,
        assigneeIds: _filter.assigneeIds,
      ),
      _now,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('המשימות שלי')),
                ButtonSegment(value: true, label: Text('כל המשימות')),
              ],
              selected: {_showAll},
              onSelectionChanged: (selection) {
                Logger.action('toggle:tasksShowAll', {'on': selection.first});
                setState(() => _showAll = selection.first);
              },
            ),
          ),
        ),
        _buildSearchBar(state.tasks),
        Expanded(
          child: visible.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  // Room for the floating button below the last card.
                  padding: const EdgeInsets.only(top: 4, bottom: 96),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final task = visible[index];
                    return TaskCard(
                      key: ValueKey(task.id),
                      task: task,
                      now: _now,
                      canManage: canManageTasks(user),
                      canUpdateProgress: canUpdateTaskProgress(task, user),
                      onToggleSubtask: (subtask, isDone) =>
                          _toggleSubtask(task, subtask, isDone),
                      onSetComplete: (isComplete) =>
                          _setComplete(task, isComplete),
                      onEditUpdate: () => _editUpdate(task),
                      onEdit: () => _editTask(task, state, user),
                      onDelete: () => _deleteTask(task),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Mirrors the look of `EventSearchFilterBar`: one field with the clear and
  /// filter buttons inside it.
  Widget _buildSearchBar(List<TaskItem> allTasks) {
    final count = _filter.activeCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        key: const Key('tasks-search'),
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'חיפוש משימה או אירוע...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'נקה חיפוש',
                  onPressed: () {
                    Logger.action('tap:clearSearch', {'field': 'tasks'});
                    _searchController.clear();
                    _searchLog.onQueryChanged('');
                    setState(() => _query = '');
                  },
                ),
              IconButton(
                key: const Key('tasks-filter'),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: Icon(
                    Icons.filter_list,
                    color: count > 0 ? Colors.blue.shade700 : null,
                  ),
                ),
                tooltip: count == 0 ? 'סינון' : 'סינון: $count פעילים',
                onPressed: () => _openFilter(allTasks),
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          _searchLog.onQueryChanged(value);
          setState(() => _query = value);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final isNarrowed = _query.trim().isNotEmpty || !_filter.isEmpty;
    final String title;
    String? hint;
    if (isNarrowed) {
      title = 'לא נמצאו משימות תואמות';
    } else if (_showAll) {
      title = 'אין משימות';
    } else {
      title = 'אין לך משימות';
      hint = 'אפשר לעבור ל"כל המשימות" כדי לראות את של כולם';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
