import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/debug/logger.dart';
import '../../../core/debug/search_action_logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/task_utils.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import 'widgets/assignee_update_dialog.dart';
import 'widgets/confirm_delete_dialog.dart';
import 'widgets/stage_card.dart';
import 'widgets/stage_form_modal.dart';
import 'widgets/task_card.dart';
import 'widgets/task_filter_modal.dart';
import 'widgets/task_form_modal.dart';

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

/// "21/10/2026" for a one-day event, "21/10/2026 – 22/10/2026" otherwise.
String taskEventDates(Event event) {
  final days = eventDays(event);
  if (days.length == 1) return _dateFormat.format(days.single);
  return '${_dateFormat.format(days.first)} – ${_dateFormat.format(days.last)}';
}

/// One דו יומי event's tasks, at `/tasks/<eventId>`: its stages, and the tasks
/// under each.
///
/// Every signed-in member can read it. The screen opens on the member's own
/// tasks; "כל המשימות" shows everyone's and every stage.
class EventTasksScreen extends StatefulWidget {
  const EventTasksScreen({super.key, required this.eventId, this.clock});

  final String eventId;

  /// The current time. Injected by tests; defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<EventTasksScreen> createState() => _EventTasksScreenState();
}

class _EventTasksScreenState extends State<EventTasksScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SearchActionLogger _searchLog = SearchActionLogger('tasks');

  bool _showAll = false;
  String _query = '';

  // Each tab keeps a filter of its own. "My tasks" is the member's personal
  // view and has no assignee section; "all tasks" is the general one.
  TaskFilterSelection _mineFilter = const TaskFilterSelection();
  TaskFilterSelection _allFilter = const TaskFilterSelection();

  TaskFilterSelection get _filter => _showAll ? _allFilter : _mineFilter;

  // Kept here, not in the cards: the list re-sorts on every change, and a card
  // that moved would otherwise close.
  final Set<String> _openStageIds = <String>{};
  final Set<String> _openStageDetails = <String>{};

  late final FocusNode _searchFocusNode =
      createRtlCursorFixedFocusNode(_searchController);

  late DateTime _now;
  Timer? _ticker;

  DateTime _readClock() => (widget.clock ?? DateTime.now)();

  bool get _isNarrowed => _query.trim().isNotEmpty || !_filter.isEmpty;

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

  Future<CrudActionResult> _send(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) {
    final completion = CrudActionCompleter();
    context.read<TaskBloc>().add(build(completion));
    return completion.future;
  }

  /// For the ticks, which have no dialog: a failure goes to a snackbar.
  Future<void> _dispatch(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) async {
    final result = await _send(build);
    if (!mounted || result.isSuccess) return;
    _showError(result.message ?? 'הפעולה נכשלה. נסו שוב.');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  Future<void> _createStage(Event event, TeamMember user) {
    Logger.action('tap:stageAdd');
    return showStageFormModal(
      context,
      event: event,
      onSave: (stage) =>
          _send((completion) => CreateStage(stage, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _editStage(Stage stage, Event event, TeamMember user) {
    Logger.action('tap:stageEdit');
    return showStageFormModal(
      context,
      existing: stage,
      event: event,
      onSave: (next) =>
          _send((completion) => UpdateStage(next, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _deleteStage(Stage stage, int taskCount) {
    Logger.action('tap:stageDelete', {'tasks': taskCount});
    final tasksLine = switch (taskCount) {
      0 => '',
      1 => ' תימחק גם המשימה שבו.',
      _ => ' יימחקו גם $taskCount המשימות שבו.',
    };
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת שלב',
      message: 'למחוק את השלב "${stage.title}"?$tasksLine לא ניתן לשחזר.',
      keyPrefix: 'stage-delete',
      onDelete: () =>
          _send((completion) => DeleteStage(stage.id, completion: completion)),
    );
  }

  Future<void> _createTask(Event event, Stage stage, TeamMember user) {
    Logger.action('tap:taskAdd');
    return showTaskFormModal(
      context,
      event: event,
      stage: stage,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          _send((completion) => CreateTask(task, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _editTask(
    TaskItem existing,
    Event event,
    Stage stage,
    TeamMember user,
  ) {
    Logger.action('tap:taskEdit');
    return showTaskFormModal(
      context,
      existing: existing,
      event: event,
      stage: stage,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          _send((completion) => UpdateTask(task, completion: completion)),
      currentUserId: user.id,
      now: _now,
    );
  }

  Future<void> _deleteTask(TaskItem task) {
    Logger.action('tap:taskDelete');
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת משימה',
      message: 'למחוק את "${task.title}"? לא ניתן לשחזר.',
      keyPrefix: 'task-delete',
      onDelete: () =>
          _send((completion) => DeleteTask(task.id, completion: completion)),
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

  Future<void> _callPhone(String phone) async {
    Logger.action('tap:stageContactCall');
    final uri =
        Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[-\s()]'), ''));
    final launched = await canLaunchUrl(uri) && await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('טלפון: $phone')));
    }
  }

  void _openFilter(List<TaskItem> eventTasks, TeamMember user) {
    Logger.action('open:taskFilterModal');
    final forAllTasks = _showAll;
    final membersById = <String, TeamMember>{};
    for (final task in eventTasks) {
      for (final member in task.assignees) {
        membersById[member.id] = member;
      }
    }
    final members = membersById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    showTaskFilterModal(
      context,
      current: _filter,
      // No assignee section under "my tasks": they are all the member's own.
      members: forAllTasks ? members : const [],
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

  void _backToEvents() {
    Logger.action('tap:tasksBackToEvents');
    context.go('${EnvironmentService.instance.routePrefix}/tasks');
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
              final event = loaded == null ? null : _findEvent(loaded);
              return Scaffold(
                appBar: AppBar(
                  title: Text(event?.name ?? 'משימות דו יומי'),
                  // On the far left, pointing left.
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      key: const Key('tasks-back'),
                      tooltip: 'חזרה לרשימת האירועים',
                      // Mirrored under RTL, so it draws pointing left.
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _backToEvents,
                    ),
                  ],
                ),
                body: TestEnvironmentIndicator(
                  child: _buildBody(state, event, user),
                ),
                floatingActionButton: event != null && canManageTasks(user)
                    ? FloatingActionButton.extended(
                        key: const Key('stage-add'),
                        onPressed: () => _createStage(event, user),
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

  Widget _buildBody(TaskState state, Event? event, TeamMember user) {
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
    if (event == null) return _buildUnknownEvent();

    final stages =
        state.stages.where((stage) => stage.eventId == event.id).toList();
    final stageIds = {for (final stage in stages) stage.id};
    // A task whose stage is gone has nowhere to be shown.
    final eventTasks = state.tasks
        .where((task) =>
            task.eventId == event.id && stageIds.contains(task.stageId))
        .toList();
    final filter = _filter;
    final visible = sortTasks(
      filterTasks(
        eventTasks,
        now: _now,
        query: _query,
        onlyAssigneeId: _showAll ? null : user.id,
        statuses: filter.statuses,
        assigneeIds: filter.assigneeIds,
        dueWithin: filter.dueSoon ? taskDueSoonWindow : null,
      ),
      _now,
    );
    final groups = stagesToShow(
      stages: stages,
      visibleTasks: visible,
      showEveryStage: _showAll && !_isNarrowed,
    );

    return Column(
      children: [
        _buildHeader(event),
        Padding(
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
        _buildSearchBar(eventTasks, user),
        Expanded(
          child: groups.isEmpty
              ? _buildEmptyState(hasStages: stages.isNotEmpty, user: user)
              : ListView.builder(
                  // Room for the floating button below the last card.
                  padding: const EdgeInsets.only(top: 4, bottom: 96),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final stage = group.stage;
                    final stageTasks = eventTasks
                        .where((task) => task.stageId == stage.id)
                        .toList();
                    return StageCard(
                      key: ValueKey(stage.id),
                      stage: stage,
                      tasks: group.tasks,
                      allTasks: stageTasks,
                      canManage: canManageTasks(user),
                      isOpen: _openStageIds.contains(stage.id),
                      onToggleOpen: () => setState(() {
                        if (!_openStageIds.remove(stage.id)) {
                          _openStageIds.add(stage.id);
                        }
                      }),
                      isDetailsOpen: _openStageDetails.contains(stage.id),
                      onToggleDetails: () => setState(() {
                        if (!_openStageDetails.remove(stage.id)) {
                          _openStageDetails.add(stage.id);
                        }
                      }),
                      onEdit: () => _editStage(stage, event, user),
                      onDelete: () => _deleteStage(stage, stageTasks.length),
                      onAddTask: () => _createTask(event, stage, user),
                      onCallPhone: _callPhone,
                      taskBuilder: (task) => TaskCard(
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
                        onEdit: () => _editTask(task, event, stage, user),
                        onDelete: () => _deleteTask(task),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(Event event) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('event-header'),
      width: double.infinity,
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _HeaderItem(icon: Icons.event, text: taskEventDates(event)),
          if (event.location.isNotEmpty)
            _HeaderItem(icon: Icons.place_outlined, text: event.location),
        ],
      ),
    );
  }

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

  /// Mirrors the look of `EventSearchFilterBar`: one field with the clear and
  /// filter buttons inside it.
  Widget _buildSearchBar(List<TaskItem> eventTasks, TeamMember user) {
    final count = _filter.activeCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        key: const Key('tasks-search'),
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'חיפוש משימה...',
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
                onPressed: () => _openFilter(eventTasks, user),
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

  Widget _buildEmptyState({required bool hasStages, required TeamMember user}) {
    final String title;
    String? hint;
    if (!hasStages) {
      title = 'אין עדיין שלבים לאירוע זה';
      if (canManageTasks(user)) hint = 'אפשר להוסיף שלב בכפתור "שלב חדש"';
    } else if (_isNarrowed) {
      title = 'לא נמצאו משימות תואמות';
    } else {
      title = 'אין לך משימות באירוע זה';
      hint = 'אפשר לעבור ל"כל המשימות" כדי לראות את כל השלבים';
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

class _HeaderItem extends StatelessWidget {
  const _HeaderItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade800),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
