import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/debug/search_action_logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/task_utils.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
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

  // Each tab keeps a filter of its own. "My tasks" is the member's personal
  // view: its filter offers only what their own tasks hold and has no
  // assignee section. "All tasks" is the general one. Sharing one selection
  // would leave a choice made in one tab narrowing the other with nothing on
  // screen to untick it.
  TaskFilterSelection _mineFilter = const TaskFilterSelection();
  TaskFilterSelection _allFilter = const TaskFilterSelection();

  /// The filter of the tab on screen.
  TaskFilterSelection get _filter => _showAll ? _allFilter : _mineFilter;

  // Which cards show their subtasks. Kept here, not in the cards: the list
  // re-sorts on every change, and a card that moved would otherwise close.
  final Set<String> _expandedTaskIds = <String>{};

  late final FocusNode _searchFocusNode =
      createRtlCursorFixedFocusNode(_searchController);

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
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---- actions ----

  /// Send a mutation and wait for the backend's answer.
  Future<CrudActionResult> _send(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) {
    final completion = CrudActionCompleter();
    context.read<TaskBloc>().add(build(completion));
    return completion.future;
  }

  /// Send a mutation and report a failure in a snackbar. Success is silent:
  /// the change shows up through the stream.
  Future<void> _dispatch(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) async {
    final result = await _send(build);
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

  // The dialogs below stay open until the backend answers and show a failure
  // themselves, so what they send goes through _send, not the snackbar of
  // _dispatch. Only the ticks, which have no dialog, use _dispatch.

  Future<void> _createTask(TasksLoaded state, TeamMember user) {
    Logger.action('tap:taskAdd');
    return showTaskFormModal(
      context,
      events: state.events,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          _send((completion) => CreateTask(task, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _editTask(
    TaskItem existing,
    TasksLoaded state,
    TeamMember user,
  ) {
    Logger.action('tap:taskEdit');
    return showTaskFormModal(
      context,
      existing: existing,
      events: state.events,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          _send((completion) => UpdateTask(task, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _deleteTask(TaskItem task) {
    Logger.action('tap:taskDelete');
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteTaskDialog(
        task: task,
        onDelete: () => _send(
          (completion) => DeleteTask(task.id, completion: completion),
        ),
      ),
    );
  }

  Future<void> _editUpdate(TaskItem task) {
    Logger.action('tap:taskUpdate');
    return showAssigneeUpdateDialog(
      context,
      initialText: task.assigneeUpdate,
      onSave: (text) => _send(
        (completion) => SaveAssigneeUpdate(
          taskId: task.id,
          text: text,
          completion: completion,
        ),
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

  void _openFilter(List<TaskItem> allTasks, TeamMember user) {
    Logger.action('open:taskFilterModal');
    final forAllTasks = _showAll;
    // Offer only what would actually match something in this tab: the events
    // and members that appear on at least one of its tasks.
    final eventsById = <String, Event>{};
    final membersById = <String, TeamMember>{};
    for (final task in allTasks) {
      if (!forAllTasks && !task.isAssignedTo(user.id)) continue;
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

    showTaskFilterModal(
      context,
      current: _filter,
      events: events,
      // No assignee section under "my tasks": they are all the member's own.
      members: forAllTasks ? members : const [],
      // Applied on every tick, so the list narrows behind the open filter.
      onChanged: (selection) {
        if (!mounted) return;
        Logger.action('filter:tasks', {'groups': selection.activeCount});
        setState(() {
          if (forAllTasks) {
            _allFilter = selection;
          } else {
            _mineFilter = selection;
          }
        });
      },
    );
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
                body: TestEnvironmentIndicator(
                  child: _buildBody(state, user),
                ),
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

    final filter = _filter;
    final visible = sortTasks(
      filterTasks(
        state.tasks,
        now: _now,
        query: _query,
        onlyAssigneeId: _showAll ? null : user.id,
        statuses: filter.statuses,
        eventIds: filter.eventIds,
        assigneeIds: filter.assigneeIds,
        dueWithin: filter.dueSoon ? taskDueSoonWindow : null,
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
              // Explicit colours: the app theme's defaults for a selected
              // segment are white text on light orange, which is unreadable.
              // The dark primary is used rather than the regular one because
              // white on the regular primary falls short of 4.5:1.
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.primaryDark,
                selectedForegroundColor: Colors.white,
              ),
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
        _buildSearchBar(state.tasks, user),
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
                      isExpanded: _expandedTaskIds.contains(task.id),
                      onToggleExpanded: () => setState(() {
                        if (!_expandedTaskIds.remove(task.id)) {
                          _expandedTaskIds.add(task.id);
                        }
                      }),
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
  Widget _buildSearchBar(List<TaskItem> allTasks, TeamMember user) {
    final count = _filter.activeCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        key: const Key('tasks-search'),
        controller: _searchController,
        focusNode: _searchFocusNode,
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
                onPressed: () => _openFilter(allTasks, user),
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

/// Asks before deleting [task], then stays open with a spinner on the delete
/// button until the backend answers: it closes on success and shows the
/// failure otherwise.
class _DeleteTaskDialog extends StatefulWidget {
  const _DeleteTaskDialog({required this.task, required this.onDelete});

  final TaskItem task;
  final Future<CrudActionResult> Function() onDelete;

  @override
  State<_DeleteTaskDialog> createState() => _DeleteTaskDialogState();
}

class _DeleteTaskDialogState extends State<_DeleteTaskDialog> {
  bool _isDeleting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final result = await widget.onDelete();
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isDeleting = false;
      _error = result.message ?? 'המחיקה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      // A delete in flight cannot be walked away from with the back button.
      child: PopScope(
        canPop: !_isDeleting,
        child: AlertDialog(
          title: const Text('מחיקת משימה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('למחוק את "${widget.task.title}"? לא ניתן לשחזר.'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('task-delete-error'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: const Key('task-delete-cancel'),
              onPressed:
                  _isDeleting ? null : () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              key: const Key('task-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: _isDeleting ? null : _delete,
              child: _isDeleting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('מחיקה'),
            ),
          ],
        ),
      ),
    );
  }
}
