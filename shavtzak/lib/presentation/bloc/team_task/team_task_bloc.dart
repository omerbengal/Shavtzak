import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/team_task_rules.dart';
import '../../../data/repositories/team_task_repository.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/task_topic.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/team_task.dart';
import '../task/task_bloc.dart' show taskErrorMessage;

part 'team_task_event.dart';
part 'team_task_state.dart';

/// A change the viewer made that the stream has not brought back yet, laid
/// over the task as the stream delivers it.
class _Pending {
  _Pending(this.apply, this.baseUpdatedAt);

  /// The task as it will look once the backend applies the change.
  final TeamTask Function(TeamTask task) apply;

  /// The task's `updatedAt` when the change was made. A delivery with a newer
  /// one after the backend accepted carries the change (or something newer).
  final DateTime baseUpdatedAt;
  bool isSettled = false;
}

/// BLoC of the team tasks screen ("משימות").
///
/// One live subscription to the tasks the viewer may see (all for a manager,
/// owned otherwise). Ticks, status changes and a manager's edits show at once
/// and are sent in the background; a refused one is taken back. Every
/// mutation reports through the event's completer, never through the state.
class TeamTaskBloc extends Bloc<TeamTaskEvent, TeamTaskState> {
  final TeamTaskRepository _repository;
  final DateTime Function() _clock;

  StreamSubscription<TeamTaskBoard>? _subscription;
  TeamMember? _viewer;
  TeamTaskBoard? _board;
  TeamTaskFilter _filter = TeamTaskFilter.initial;
  final Map<String, List<_Pending>> _pending = {};

  TeamTaskBloc({
    required TeamTaskRepository repository,
    DateTime Function()? clock,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now,
        super(const TeamTasksInitial()) {
    on<TeamTasksSubscribe>(_onSubscribe);
    on<_BoardArrived>(_onBoard);
    on<_BoardFailed>((event, emit) => emit(TeamTasksError(event.message)));
    on<TeamTaskFilterChanged>((event, emit) {
      _filter = event.filter;
      _emitLoaded(emit);
    });
    on<CreateTeamTask>((event, emit) =>
        _send(event.completion, () => _repository.insertTask(event.task)));
    on<DeleteTeamTask>((event, emit) =>
        _send(event.completion, () => _repository.deleteTask(event.id)));
    on<AddTeamTaskUpdate>((event, emit) =>
        _send(event.completion,
            () => _repository.addUpdate(event.id, event.text, subtaskId: event.subtaskId)));
    on<CreateTaskTopic>((event, emit) =>
        _send(event.completion, () => _repository.insertTopic(event.topic)));
    on<UpdateTaskTopic>((event, emit) =>
        _send(event.completion, () => _repository.updateTopic(event.topic)));
    on<ArchiveTaskTopic>((event, emit) => _send(
          event.completion,
          () => event.archive
              ? _repository.archiveTopic(event.id)
              : _repository.restoreTopic(event.id),
        ));
    on<DeleteTaskTopic>((event, emit) =>
        _send(event.completion, () => _repository.deleteTopic(event.id)));
    on<UpdateTeamTask>(_onUpdate);
    on<SetTeamTaskStatus>(_onStatus);
    on<ToggleTeamSubtask>(_onToggle);
  }

  Future<void> _onSubscribe(TeamTasksSubscribe event, Emitter<TeamTaskState> emit) async {
    final viewer = event.viewer;
    final current = _viewer;
    // The query depends only on who the viewer is and whether they manage
    // tasks; any other change to their document (a constraint, a rename) keeps
    // the live subscription and its unconfirmed ticks.
    if (_subscription != null &&
        current != null &&
        current.id == viewer.id &&
        canManageTeamTasks(current) == canManageTeamTasks(viewer)) {
      _viewer = viewer;
      _emitLoaded(emit);
      return;
    }
    await _subscription?.cancel();
    _viewer = viewer;
    _board = null;
    _pending.clear();
    _subscription = _repository.watchBoardFor(viewer).listen(
      (board) => add(_BoardArrived(board)),
      onError: (Object error) {
        // A dead stream (sign-out, a refused query) must not block the next
        // subscribe: drop it so the next TeamTasksSubscribe opens a new one.
        final dead = _subscription;
        _subscription = null;
        unawaited(dead?.cancel());
        add(const _BoardFailed('טעינת המשימות נכשלה'));
      },
    );
  }

  void _onBoard(_BoardArrived event, Emitter<TeamTaskState> emit) {
    final byId = {for (final task in event.board.tasks) task.id: task};
    // A settled change is dropped once the stream delivers a newer version of
    // its task; a task that disappeared takes its changes with it.
    _pending.removeWhere((id, changes) {
      final delivered = byId[id];
      if (delivered == null) return true;
      changes.removeWhere(
          (change) => change.isSettled && delivered.updatedAt.isAfter(change.baseUpdatedAt));
      return changes.isEmpty;
    });
    _board = event.board;
    _emitLoaded(emit);
  }

  void _emitLoaded(Emitter<TeamTaskState> emit) {
    final board = _board;
    final viewer = _viewer;
    if (board == null || viewer == null) return;
    final all = [
      for (final task in board.tasks)
        (_pending[task.id] ?? const <_Pending>[])
            .fold<TeamTask>(task, (value, change) => change.apply(value)),
    ];
    final mine = myTeamTaskRows(all, viewer.id);
    final now = _clock();
    final eventCategoryById = {for (final e in board.events) e.id: e.categoryId};
    emit(TeamTasksLoaded(
      viewer: viewer,
      all: all,
      mine: mine,
      allGroups: groupTeamTasks(applyTeamTaskFilter(all, _filter, eventCategoryById), now),
      // "המשימות שלי" has no owner filter: they are all the viewer's.
      mineGroups: groupTeamTasks(
        applyTeamTaskFilter(mine, _filter.copyWith(ownerId: () => null), eventCategoryById),
        now,
      ),
      filter: _filter,
      canManage: canManageTeamTasks(viewer),
      events: board.events,
      categories: board.categories,
      topics: board.topics,
      members: board.members,
    ));
  }

  Future<void> _send(CrudActionCompleter? completion, Future<void> Function() action) async {
    try {
      await action();
      completeCrudAction(completion, const CrudActionResult.success());
    } catch (error) {
      completeCrudAction(completion, CrudActionResult.failure(taskErrorMessage(error)));
    }
  }

  /// Lays [apply] over task [id] at once, sends [action], and takes the
  /// change back if the backend refuses it.
  Future<void> _optimistic(
    String id,
    TeamTask Function(TeamTask task) apply,
    Future<void> Function() action,
    CrudActionCompleter? completion,
    Emitter<TeamTaskState> emit,
  ) async {
    final base = _board?.tasks.where((task) => task.id == id).firstOrNull;
    if (base == null) {
      await _send(completion, action);
      return;
    }
    final change = _Pending(apply, base.updatedAt);
    _pending.putIfAbsent(id, () => []).add(change);
    _emitLoaded(emit);
    try {
      await action();
      change.isSettled = true;
      completeCrudAction(completion, const CrudActionResult.success());
    } catch (error) {
      _pending[id]?.remove(change);
      if (_pending[id]?.isEmpty ?? false) _pending.remove(id);
      _emitLoaded(emit);
      completeCrudAction(completion, CrudActionResult.failure(taskErrorMessage(error)));
    }
  }

  Future<void> _onUpdate(UpdateTeamTask event, Emitter<TeamTaskState> emit) {
    final edited = event.task;
    return _optimistic(
      edited.id,
      (task) => _joined(task.copyWith(
        title: edited.title,
        description: edited.description,
        link: () => edited.link,
        assigneeIds: edited.subtasks.isEmpty ? edited.assigneeIds : const [],
        // A subtask keeps its live status and log; an edit only brings what
        // a manager edits (as the backend does).
        subtasks: [
          for (final subtask in edited.subtasks)
            if (task.subtasks.where((old) => old.id == subtask.id).firstOrNull
                case final old?)
              old.copyWith(
                title: subtask.title,
                description: subtask.description,
                assigneeIds: subtask.assigneeIds,
                contacts: subtask.contacts,
                deadline: () => subtask.deadline,
              )
            else
              subtask.copyWith(
                status: TeamTaskStatus.open,
                duplicateOfId: () => null,
                updates: const [],
                completedAt: () => null,
              ),
        ],
        contacts: edited.contacts,
        deadline: () => edited.deadline,
        ownerIds: _ownerIds(edited),
      )),
      () => _repository.updateTask(edited),
      event.completion,
      emit,
    );
  }

  Future<void> _onStatus(SetTeamTaskStatus event, Emitter<TeamTaskState> emit) {
    return _optimistic(
      event.id,
      (task) => event.subtaskId != null
          ? withSubtaskStatus(task, event.subtaskId!, event.status,
              duplicateOfId: event.duplicateOfId)
          : task.copyWith(
              status: event.status,
              duplicateOfId: () =>
                  event.status == TeamTaskStatus.duplicate ? event.duplicateOfId : null,
            ),
      () => _repository.setStatus(event.id, event.status,
          duplicateOfId: event.duplicateOfId, subtaskId: event.subtaskId),
      event.completion,
      emit,
    );
  }

  Future<void> _onToggle(ToggleTeamSubtask event, Emitter<TeamTaskState> emit) {
    return _optimistic(
      event.taskId,
      (task) => withSubtaskTicked(task, event.subtaskId, event.isDone),
      () => _repository.setSubtaskDone(event.taskId, event.subtaskId, event.isDone),
      event.completion,
      emit,
    );
  }

  /// [task] with its owners, subtask owners and link target looked up in the
  /// board's lists, so an edit shows names at once instead of "חבר צוות לא
  /// ידוע" until the stream brings the joined task back. Someone the task
  /// already had stays joined even when the board's member list lacks them.
  TeamTask _joined(TeamTask task) {
    final board = _board;
    if (board == null) return task;
    final members = {
      for (final member in task.owners) member.id: member,
      for (final subtask in task.subtasks)
        for (final member in subtask.assignees) member.id: member,
      for (final member in board.members) member.id: member,
    };
    final link = task.link;
    return task.copyWith(
      owners: task.ownerIds.map((id) => members[id]).whereType<TeamMember>().toList(),
      subtasks: [
        for (final subtask in task.subtasks)
          subtask.copyWith(
            assignees:
                subtask.assigneeIds.map((id) => members[id]).whereType<TeamMember>().toList(),
          ),
      ],
      event: () => link?.type == TaskLinkType.event
          ? board.events.where((e) => e.id == link!.id).firstOrNull ?? task.event
          : null,
      category: () => link?.type == TaskLinkType.category
          ? board.categories.where((c) => c.id == link!.id).firstOrNull ?? task.category
          : null,
      topic: () => link?.type == TaskLinkType.topic
          ? board.topics.where((t) => t.id == link!.id).firstOrNull ?? task.topic
          : null,
    );
  }

  static List<String> _ownerIds(TeamTask task) => teamTaskOwnerIds(task);

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
