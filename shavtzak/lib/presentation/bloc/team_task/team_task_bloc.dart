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

  /// Changes not sent yet, per task and field, laid over everything else.
  final Map<String, Map<String, TeamTask Function(TeamTask task)>> _drafts = {};

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
    on<CreateTeamTask>(
        (event, emit) => _send(event.completion, () => _repository.insertTask(event.task)));
    on<DeleteTeamTask>(
        (event, emit) => _send(event.completion, () => _repository.deleteTask(event.id)));
    on<AddTeamTaskUpdate>((event, emit) => _send(event.completion,
        () => _repository.addUpdate(event.id, event.text, mentionIds: event.mentionIds)));
    on<MarkTeamTaskMentionDone>((event, emit) =>
        _send(event.completion, () => _repository.setMentionDone(event.id, event.text)));
    on<EditTeamTaskUpdate>((event, emit) => _send(
        event.completion, () => _repository.editUpdate(event.id, event.updateId, event.text)));
    on<DeleteTeamTaskUpdate>((event, emit) =>
        _send(event.completion, () => _repository.deleteUpdate(event.id, event.updateId)));
    on<CreatePendingEvent>((event, emit) =>
        _send(event.completion, () => _repository.insertPendingEvent(event.pendingEvent)));
    on<LinkPendingEvent>((event, emit) =>
        _send(event.completion, () => _repository.linkPendingEvent(event.id, event.eventId)));
    on<CreateTaskTopic>(
        (event, emit) => _send(event.completion, () => _repository.insertTopic(event.topic)));
    on<UpdateTaskTopic>(
        (event, emit) => _send(event.completion, () => _repository.updateTopic(event.topic)));
    on<ArchiveTaskTopic>((event, emit) => _send(
          event.completion,
          () => event.archive
              ? _repository.archiveTopic(event.id)
              : _repository.restoreTopic(event.id),
        ));
    on<DeleteTaskTopic>(
        (event, emit) => _send(event.completion, () => _repository.deleteTopic(event.id)));
    on<UpdateTeamTask>(_onUpdate);
    on<TeamTaskDraftChanged>(_onDraft);
    on<SetTeamTaskStatus>(_onStatus);
    on<TeamTaskHoldPlace>(_onHold);
  }

  /// The task held in its place ([TeamTaskHoldPlace]) and how it was when
  /// held: the list places it by that copy and shows the live one.
  String? _heldId;
  TeamTask? _heldAs;

  void _onHold(TeamTaskHoldPlace event, Emitter<TeamTaskState> emit) {
    if (event.id == _heldId) return;
    _heldId = event.id;
    _heldAs = null;
    final state = this.state;
    if (event.id != null && state is TeamTasksLoaded) _heldAs = state.taskById(event.id!);
    // Letting go puts it where it belongs now.
    _emitLoaded(emit);
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
    _drafts.clear();
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
    _drafts.removeWhere((id, _) => !byId.containsKey(id));
    _board = event.board;
    _emitLoaded(emit);
  }

  void _emitLoaded(Emitter<TeamTaskState> emit) {
    final board = _board;
    final viewer = _viewer;
    if (board == null || viewer == null) return;
    final all = [
      for (final task in board.tasks)
        _withDrafts(
          (_pending[task.id] ?? const <_Pending>[])
              .fold<TeamTask>(task, (value, change) => change.apply(value)),
        ),
    ];
    final mine = myTeamTaskRows(all, viewer.id);
    final now = _clock();
    final eventCategoryById = {for (final e in board.events) e.id: e.categoryId};
    final categoryNameById = {for (final c in board.categories) c.id: c.name};
    // The held task is placed (grouped, ordered, filtered) as it was when
    // held, and drawn as it is now. A deleted one is simply gone.
    final heldAs = _heldAs;
    final live = heldAs == null ? null : _firstWithId(all, heldAs.id);
    var placedAll = all;
    var placedMine = mine;
    if (heldAs != null && live != null) {
      placedAll = [for (final t in all) t.id == heldAs.id ? heldAs : t];
      placedMine = myTeamTaskRows(placedAll, viewer.id);
    }
    List<TeamTaskGroup> drawn(List<TeamTaskGroup> groups) =>
        live == null ? groups : [for (final g in groups) g.withTask(live)];
    emit(TeamTasksLoaded(
      viewer: viewer,
      all: all,
      mine: mine,
      allGroups: drawn(groupTeamTasks(
        applyTeamTaskFilter(placedAll, _filter, eventCategoryById,
            now: now, categoryNameById: categoryNameById),
        now,
        categories: board.categories,
        // By urgency, then by owners (Omer, msg 4581): "כל המשימות" only.
        compare: compareTeamTasksByOwners,
      )),
      // "המשימות שלי" has no owner filter: they are all the viewer's.
      mineGroups: drawn(groupTeamTasks(
        // Nor the time chips: they are on "כל המשימות" only (19/11/2026).
        applyTeamTaskFilter(
            placedMine,
            _filter.copyWith(
                ownerIds: const {}, created: () => null, statusChanged: () => null),
            eventCategoryById,
            now: now, categoryNameById: categoryNameById),
        now,
        categories: board.categories,
      )),
      filter: _filter,
      canManage: canManageTeamTasks(viewer),
      events: board.events,
      categories: board.categories,
      topics: board.topics,
      members: board.members,
      pendingEvents: board.pendingEvents,
    ));
  }

  static TeamTask? _firstWithId(List<TeamTask> tasks, String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
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

  TeamTask _withDrafts(TeamTask task) {
    final drafts = _drafts[task.id];
    if (drafts == null || drafts.isEmpty) return task;
    var drafted = task;
    for (final apply in drafts.values) {
      drafted = apply(drafted);
    }
    return _joined(drafted.copyWith(ownerIds: _ownerIds(drafted)));
  }

  void _onDraft(TeamTaskDraftChanged event, Emitter<TeamTaskState> emit) {
    final apply = event.apply;
    if (apply == null) {
      final drafts = _drafts[event.id];
      if (drafts?.remove(event.field) == null) return;
      if (drafts!.isEmpty) _drafts.remove(event.id);
    } else {
      _drafts.putIfAbsent(event.id, () => {})[event.field] = apply;
    }
    _emitLoaded(emit);
  }

  Future<void> _onUpdate(UpdateTeamTask event, Emitter<TeamTaskState> emit) {
    final edited = event.task;
    final field = event.draftField;
    if (field != null) {
      final drafts = _drafts[edited.id];
      drafts?.remove(field);
      if (drafts?.isEmpty ?? false) _drafts.remove(edited.id);
    }
    return _optimistic(
      edited.id,
      (task) => _joined(task.copyWith(
        title: edited.title,
        description: edited.description,
        link: () => edited.link,
        eventIds: edited.linkedEventIds,
        urgency: edited.urgency,
        assigneeIds: edited.assigneeIds,
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
      (task) => task.copyWith(
        status: event.status,
        statusChangedAt: event.status == task.status ? null : () => _clock(),
        duplicateOfId: () =>
            event.status == TeamTaskStatus.duplicate ? event.duplicateOfId : null,
      ),
      () => _repository.setStatus(event.id, event.status, duplicateOfId: event.duplicateOfId),
      event.completion,
      emit,
    );
  }

  /// [task] with its owners and link targets looked up in the
  /// board's lists, so an edit shows names at once instead of "חבר צוות לא
  /// ידוע" until the stream brings the joined task back. Someone the task
  /// already had stays joined even when the board's member list lacks them.
  TeamTask _joined(TeamTask task) {
    final board = _board;
    if (board == null) return task;
    final members = {
      for (final member in task.owners) member.id: member,
      for (final member in board.members) member.id: member,
    };
    final link = task.link;
    final events = {
      for (final event in task.events) event.id: event,
      for (final event in board.events) event.id: event,
    };
    return task.copyWith(
      owners: task.ownerIds.map((id) => members[id]).whereType<TeamMember>().toList(),
      events: task.linkedEventIds.map((id) => events[id]).whereType<Event>().toList(),
      event: () => link?.type == TaskLinkType.event
          ? board.events.where((e) => e.id == link!.id).firstOrNull ?? task.event
          : null,
      category: () => link?.type == TaskLinkType.category
          ? board.categories.where((c) => c.id == link!.id).firstOrNull ?? task.category
          : null,
      topic: () => link?.type == TaskLinkType.topic
          ? board.topics.where((t) => t.id == link!.id).firstOrNull ?? task.topic
          : null,
      pendingEvent: () => link?.type == TaskLinkType.pendingEvent
          ? board.pendingEvents.where((p) => p.id == link!.id).firstOrNull ?? task.pendingEvent
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
