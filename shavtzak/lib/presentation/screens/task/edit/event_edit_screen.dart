import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/services/task_import_files.dart';
import '../../../../core/utils/task_edit_overlay.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../data/repositories/task_repository.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/task/task_bloc.dart';
import '../../../bloc/user_selection/user_selection_bloc.dart';
import '../../../bloc/user_selection/user_selection_state.dart';
import '../task_screen_actions.dart';
import '../task_style.dart';
import '../tasks_place.dart';
import '../../../widgets/edge_slide_over.dart';
import 'edit_context.dart';
import 'event_assignments_quick_view.dart';
import 'edit_rules.dart';
import 'stage_edit_card.dart';

/// The managers' editing screen of one דו יומי event: every stage as a soft
/// card with all its details, and every task with all of its, each value
/// edited where it sits and saved at once.
///
/// Not a progress screen: nothing here ticks, counts or colours by time.
/// A value just sent is shown, and built on, until the live stream brings
/// it back ([EditOverlay]); a refusal puts the stored value back and says so.
class EventEditScreen extends StatefulWidget {
  const EventEditScreen({
    super.key,
    required this.eventId,
    required this.place,
    this.clock,
    this.importFiles = const BrowserTaskImportFiles(),
  });

  final String eventId;
  final TasksPlace place;
  final DateTime Function()? clock;
  final TaskImportFiles importFiles;

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen>
    with TaskScreenActions<EventEditScreen> {
  @override
  DateTime get actionTime => (widget.clock ?? DateTime.now)();

  @override
  TaskImportFiles get importFiles => widget.importFiles;

  final EditOverlay<TaskItem> _taskOverlay = EditOverlay(sameTaskEdit);
  final EditOverlay<Stage> _stageOverlay = EditOverlay(sameStageEdit);
  final Map<String, GlobalKey> _keys = {};

  List<TeamMember> _eventAssignees = const [];
  StreamSubscription<List<TeamMember>>? _assigneesSubscription;

  String _query = '';
  String? _assigneeFilter;
  String? _highlightId;
  Timer? _highlightTimer;

  /// The members as last delivered, to show a task's new assignees at once.
  Map<String, TeamMember> _members = const {};

  /// The board as last shown, so a drop acts on what the manager saw.
  EventTaskBoard? _shown;

  @override
  void initState() {
    super.initState();
    context.read<TaskBloc>().add(const LoadTasks());
    final auth = context.read<UserSelectionBloc>().state;
    if (auth is UserAuthenticated && canManageTasks(auth.user)) {
      _assigneesSubscription = context
          .read<TaskRepository>()
          .watchEventAssignees(widget.eventId)
          .listen((members) {
        if (mounted) setState(() => _eventAssignees = members);
      });
    }
  }

  @override
  void dispose() {
    _assigneesSubscription?.cancel();
    _highlightTimer?.cancel();
    _edgeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ---- scrolling while a task is dragged to an edge ----

  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  Timer? _edgeTimer;
  double _edgeSpeed = 0;
  final Stopwatch _edgeClock = Stopwatch();

  /// Where the dragged task's pointer is: near the list's top or bottom the
  /// list scrolls, until the pointer leaves the edge or the drag ends.
  void _onDragMoved(Offset global) {
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    _edgeSpeed = edgeScrollSpeed(
      pointerY: global.dy,
      top: top,
      bottom: top + box.size.height,
      edge: TaskStyle.editDragEdge,
      maxSpeed: TaskStyle.editDragMaxSpeed,
    );
    if (_edgeSpeed == 0) {
      _stopEdgeScroll();
    } else if (_edgeTimer == null) {
      _edgeClock
        ..reset()
        ..start();
      _edgeTimer =
          Timer.periodic(const Duration(milliseconds: 16), (_) => _edgeTick());
    }
  }

  void _edgeTick() {
    final seconds = _edgeClock.elapsedMicroseconds / 1e6;
    _edgeClock
      ..reset()
      ..start();
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final next = (position.pixels + _edgeSpeed * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) _scroll.jumpTo(next);
  }

  void _stopEdgeScroll() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeSpeed = 0;
    _edgeClock.stop();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void _backToEvent() => context.go(widget.place.eventRoute(widget.eventId));

  // ---- saving ----

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ));
  }

  /// Tints [id] for a moment and brings it into view: an edit may have moved
  /// it to a new place in the order.
  void _flash(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = id);
    _highlightTimer = Timer(TaskStyle.editHighlightFor, () {
      if (mounted) setState(() => _highlightId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[id]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  Future<void> _commitTask(TaskItem next) async {
    Logger.action('edit:task');
    _taskOverlay.sent(
      next.id,
      next.copyWith(
        assignees: [
          for (final id in next.assigneeIds)
            if (_members[id] != null) _members[id]!,
        ],
      ),
    );
    _flash(next.id);
    final result = await sendTaskEvent(
      (completion) => UpdateTask(next, completion: completion),
    );
    if (!mounted || result.isSuccess) return;
    setState(() => _taskOverlay.failed(next.id));
    _showError(result.message ?? 'השמירה נכשלה. נסו שוב.');
  }

  Future<void> _commitStage(Stage next) async {
    Logger.action('edit:stage');
    _stageOverlay.sent(next.id, next);
    _flash(next.id);
    final result = await sendTaskEvent(
      (completion) => UpdateStage(next, completion: completion),
    );
    if (!mounted || result.isSuccess) return;
    setState(() => _stageOverlay.failed(next.id));
    _showError(result.message ?? 'השמירה נכשלה. נסו שוב.');
  }

  void _moveTask(TaskItem task, Stage to) {
    if (task.stageId == to.id) return;
    Logger.action('edit:taskMove');
    _commitTask(task.copyWith(stageId: to.id, stage: to));
  }

  /// [moved] dropped on [target], due at the same moment in the same stage:
  /// the stage's tasks are numbered in their new order, shown at once.
  Future<void> _reorder(TaskItem moved, TaskItem target, bool after) async {
    final board = _shown;
    if (board == null) return;
    final shownMoved = board.taskById(moved.id) ?? moved;
    final shownTarget = board.taskById(target.id) ?? target;
    if (!canReorderOnto(shownMoved, shownTarget)) return;
    final before = board.tasksOf(shownTarget.stageId);
    final next =
        reorderedStageTasks(before, shownMoved, shownTarget, after: after);
    if (!orderChanged(before, next)) return;
    Logger.action('edit:taskReorder', {'tasks': next.length});
    for (final task in next) {
      _taskOverlay.sent(task.id, task);
    }
    _flash(moved.id);
    final result = await sendTaskEvent(
      (completion) => ReorderTasks(
        board.event.id,
        shownTarget.stageId,
        next,
        completion: completion,
      ),
    );
    if (!mounted || result.isSuccess) return;
    setState(() {
      for (final task in next) {
        _taskOverlay.failed(task.id);
      }
    });
    _showError(result.message ?? 'שינוי הסדר נכשל. נסו שוב.');
  }

  /// [from]'s [field] dragged onto [to]'s: copied in at once when [to] has
  /// none, after a yes when it has one. [from] stays as it is.
  Future<void> _copyField(TaskItem from, TaskItem to, TaskField field) async {
    final board = _shown;
    final source = board?.taskById(from.id) ?? from;
    final target = board?.taskById(to.id) ?? to;
    if (!canCopyField(source, target, field)) return;
    if (sameTaskField(source, target, field)) return;
    if (!isTaskFieldEmpty(target, field)) {
      final replace = await _confirmReplace(source, target, field);
      if (replace != true || !mounted) return;
    }
    Logger.action('edit:copyField', {'field': field.name});
    await _commitTask(
      copyTaskField(source, target, field, newId: const Uuid().v4),
    );
  }

  Future<bool?> _confirmReplace(
    TaskItem source,
    TaskItem target,
    TaskField field,
  ) =>
      showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            key: const Key('edit-copy-confirm'),
            title: Text('להחליף את ${field.definite}?'),
            content: Text(
              '"${target.title}" כבר מכילה ${field.label}. '
              'להעתיק לשם את ${field.definite} של "${source.title}" במקום?',
            ),
            actions: [
              TextButton(
                key: const Key('edit-copy-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                key: const Key('edit-copy-replace'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('החלפה'),
              ),
            ],
          ),
        ),
      );

  // ---- building ----

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

  /// The board with every value still on its way laid over the stream's.
  EventTaskBoard _board(Event event, TasksLoaded loaded) {
    _taskOverlay.reconcile({for (final task in loaded.tasks) task.id: task});
    _stageOverlay
        .reconcile({for (final stage in loaded.stages) stage.id: stage});
    _members = {for (final member in loaded.members) member.id: member};
    final stages = [
      for (final stage in loaded.stages) _stageOverlay.resolve(stage.id, stage),
    ];
    final stagesById = {for (final stage in stages) stage.id: stage};
    final tasks = [
      for (final task in loaded.tasks)
        () {
          final shown = _taskOverlay.resolve(task.id, task);
          // A moved task, or one whose stage moved, takes its day from the
          // stage shown.
          return shown.copyWith(stage: stagesById[shown.stageId]);
        }(),
    ];
    return eventTaskBoard(event, stages: stages, tasks: tasks);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, auth) {
          if (auth is! UserAuthenticated || !canManageTasks(auth.user)) {
            return _message(
              'אין הרשאה לעריכת המשימות',
              key: const Key('edit-no-access'),
            );
          }
          final user = auth.user;
          return BlocBuilder<TaskBloc, TaskState>(
            builder: (context, state) {
              if (state is TasksError) return _message(state.message);
              if (state is! TasksLoaded) {
                return _scaffold(
                  null,
                  const Center(child: CircularProgressIndicator()),
                );
              }
              final event = _findEvent(state);
              if (event == null) return _message('האירוע לא נמצא');
              return _buildLoaded(_board(event, state), user);
            },
          );
        },
      ),
    );
  }

  Widget _message(String text, {Key? key}) {
    return _scaffold(
      null,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, key: key, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(onPressed: _backToEvent, child: const Text('חזרה')),
          ],
        ),
      ),
    );
  }

  /// The bar: the event's name on its own line (two lines on a phone, so a
  /// long name is read whole), then "עריכה" and the event's days.
  Widget _scaffold(Event? event, Widget body) {
    final narrow = MediaQuery.sizeOf(context).width < TaskStyle.wideBreakpoint;
    return Scaffold(
      backgroundColor: TaskStyle.editPage,
      appBar: AppBar(
        toolbarHeight: event != null && narrow ? 84 : null,
        leading: IconButton(
          key: const Key('edit-back'),
          tooltip: 'חזרה לאירוע',
          icon: const Icon(Icons.arrow_forward),
          onPressed: _backToEvent,
        ),
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: event == null
            ? const Text('עריכה')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.name,
                    key: const Key('edit-title'),
                    maxLines: narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: narrow ? 17 : 20,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'עריכה · ${eventDaysLabel(event)}',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
      ),
      body: body,
    );
  }

  Widget _buildLoaded(EventTaskBoard board, TeamMember user) {
    _shown = board;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= TaskStyle.wideBreakpoint;
      final ctx = EditContext(
        wide: wide,
        event: board.event,
        days: eventDays(board.event),
        stages: board.stages,
        eventAssignees: _eventAssignees,
        onTaskCommit: _commitTask,
        onStageCommit: _commitStage,
        onMoveTask: _moveTask,
        onReorder: _reorder,
        onCopyField: _copyField,
        onDeleteTask: deleteTask,
        onDeleteStage: deleteStage,
        onAddTask: (stage) => createTask(board.event, stage, user),
        highlightId: _highlightId,
        keyFor: _keyFor,
        onDragMoved: _onDragMoved,
        onDragDone: _stopEdgeScroll,
      );
      final filtering = _query.trim().isNotEmpty || _assigneeFilter != null;
      final now = actionTime;
      final cards = <Widget>[];
      for (final stage in board.stages) {
        final visible = visibleStageTasks(
          board,
          stage,
          query: _query,
          assigneeId: _assigneeFilter,
          now: now,
        );
        if (filtering && visible.isEmpty) continue;
        cards.add(StageEditCard(
          key: ValueKey('stage-card-${stage.id}'),
          stage: stage,
          tasks: visible,
          allTaskCount: board.tasksOf(stage.id).length,
          ctx: ctx,
        ));
      }
      return EdgeSlideOver(
        wide: wide,
        handleTooltip: 'שיבוצים',
        panelBuilder: (context, close) => EventAssignmentsQuickView(
          event: board.event,
          onClose: close,
        ),
        child: _scaffold(
          board.event,
          KeyedSubtree(
            key: _listKey,
            child: _buildList(board, user, wide, cards),
          ),
        ),
      );
    });
  }

  Widget _buildList(
    EventTaskBoard board,
    TeamMember user,
    bool wide,
    List<Widget> cards,
  ) {
    return ListView(
      key: const Key('edit-list'),
      controller: _scroll,
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 24 : 10,
        vertical: wide ? 18 : 10,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: TaskStyle.editMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildToolbar(board, user, wide),
                SizedBox(height: wide ? 16 : 10),
                if (board.stages.isEmpty)
                  _emptyCard('אין עדיין שלבים באירוע. הוסיפו שלב ראשון.')
                else if (cards.isEmpty)
                  _emptyCard('לא נמצאו משימות')
                else
                  ...cards,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String text) => Container(
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: TaskStyle.editCard,
          borderRadius: BorderRadius.circular(TaskStyle.editCardRadius),
          boxShadow: TaskStyle.editCardShadow,
        ),
        child: Text(text, style: const TextStyle(color: TaskStyle.editMuted)),
      );

  Widget _buildToolbar(EventTaskBoard board, TeamMember user, bool wide) {
    final filterMembers = assigneeFilterMembers(board, _eventAssignees);
    final search = SizedBox(
      width: wide ? 240 : double.infinity,
      child: TextField(
        key: const Key('edit-search'),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          hintText: 'חיפוש משימה, שלב או אחראי',
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
    final assignee = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('edit-assignee-filter'),
          value: filterMembers.any((m) => m.id == _assigneeFilter)
              ? _assigneeFilter
              : null,
          isDense: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('אחראי: כולם'),
            ),
            for (final member in filterMembers)
              DropdownMenuItem<String?>(
                value: member.id,
                child: Text('אחראי: ${member.name}'),
              ),
          ],
          onChanged: (id) => setState(() => _assigneeFilter = id),
        ),
      ),
    );
    final excel = OutlinedButton.icon(
      key: const Key('edit-export'),
      onPressed: () => downloadExport(board),
      icon: const Icon(Icons.download, size: 18),
      label: const Text('אקסל'),
    );
    final addStage = FilledButton.icon(
      key: const Key('edit-stage-add'),
      onPressed: () => createStage(board.event, user),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('שלב חדש'),
    );
    final summary = Text(
      '${board.stages.length} שלבים · ${board.tasks.length} משימות',
      style: const TextStyle(color: TaskStyle.editMuted),
    );
    if (wide) {
      return Row(
        children: [
          summary,
          const Spacer(),
          search,
          const SizedBox(width: 8),
          assignee,
          const SizedBox(width: 8),
          excel,
          const SizedBox(width: 8),
          addStage,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        search,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [assignee, excel, addStage],
        ),
        const SizedBox(height: 6),
        summary,
      ],
    );
  }
}
