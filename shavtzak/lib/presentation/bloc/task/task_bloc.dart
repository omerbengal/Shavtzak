import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/debug/logger.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/task_edit_overlay.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/imported_stage.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/stage_sync_plan.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';

part 'task_event.dart';
part 'task_state.dart';

const String _genericFailure = 'הפעולה נכשלה. נסו שוב.';

final RegExp _backendMutationFailure =
    RegExp(r'Failed backend mutation [\w.]+: (.*)$', dotAll: true);
final RegExp _hebrewLetter = RegExp(r'[א-ת]');

/// The message to show a member when a task action fails.
///
/// The backend answers permission and validation failures in Hebrew; that text
/// reaches the client wrapped in a `DatabaseException`. Anything else (a
/// network error, an English internal message) is replaced by a generic line.
String taskErrorMessage(Object error) {
  final message =
      _backendMutationFailure.firstMatch(error.toString())?.group(1)?.trim();
  if (message != null && _hebrewLetter.hasMatch(message)) return message;
  return _genericFailure;
}

/// A tick the member made that the backend has not confirmed yet: one subtask
/// done or not, or a whole task completed or reopened.
class _PendingProgress {
  _PendingProgress({
    required this.taskId,
    this.subtaskId,
    required this.value,
    required this.at,
  });

  final String taskId;

  /// The subtask ticked. Null when the task itself was completed or reopened.
  final String? subtaskId;
  final bool value;

  /// When the member ticked; shown as the completion time until the backend's
  /// own arrives.
  final DateTime at;

  /// The backend accepted the write. The tick stays laid over the list only
  /// until the stream next delivers.
  bool isSettled = false;

  String get key => subtaskId == null ? taskId : '$taskId/$subtaskId';

  /// Whether [task], as the stream delivered it, already holds this tick.
  bool isReflectedIn(TaskItem task) {
    if (subtaskId == null) return task.isComplete == value;
    return task.subtasks
        .where((subtask) => subtask.id == subtaskId)
        .every((subtask) => subtask.isDone == value);
  }

  /// [task] as it will look once the backend applies this tick. Follows the
  /// backend's rule: a task with subtasks is complete exactly when all of them
  /// are done, and only a task without subtasks is completed directly.
  TaskItem applyTo(TaskItem task) {
    if (subtaskId == null) {
      return task.hasSubtasks ? task : _withCompletion(task, value);
    }
    if (!task.subtasks.any((subtask) => subtask.id == subtaskId)) return task;
    final subtasks = <Subtask>[
      for (final subtask in task.subtasks)
        subtask.id == subtaskId ? subtask.copyWith(isDone: value) : subtask,
    ];
    return _withCompletion(
      task.copyWith(subtasks: subtasks),
      subtasks.every((subtask) => subtask.isDone),
    );
  }

  TaskItem _withCompletion(TaskItem task, bool isComplete) {
    if (task.isComplete == isComplete) return task;
    // A reopened task keeps its old completion time: copyWith cannot clear it,
    // and nothing reads it while the task is open.
    return task.copyWith(
      isComplete: isComplete,
      completedAt: isComplete ? at : null,
    );
  }
}

/// BLoC for the tasks screen.
///
/// Holds one live subscription to every task. Creating, editing, deleting and
/// the assignee note do not touch the state: the backend write comes back
/// through the stream. Ticking a subtask or a task is shown at once and sent
/// in the background; a refused tick is undone. Every mutation reports its
/// outcome through the event's completer so the screen can show a snackbar
/// without the list being replaced by an error.
class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository _repository;
  final DateTime Function() _clock;
  bool _isWatching = false;

  // The board as the stream last delivered it, without unconfirmed ticks.
  TaskBoard? _board;

  // Ticks sent but not yet seen back from the stream, by what they tick. Laid
  // over [_board] on every emission, so a tick shows without waiting for the
  // backend and an unrelated stream update cannot undo it meanwhile.
  final Map<String, _PendingProgress> _pending = <String, _PendingProgress>{};

  // Stage and task edits the backend accepted that the stream has not brought
  // back yet. Laid over [_board], so whoever saved sees their edit at once
  // even when the stream is slow, or stuck until a reconnect.
  final EditOverlay<Stage> _stageOverlay = EditOverlay(sameStageEdit);
  final EditOverlay<TaskItem> _taskOverlay = EditOverlay(sameTaskEdit);

  // Saves the backend accepted, each waiting to show up in the stream.
  final List<_AwaitedWrite> _awaited = <_AwaitedWrite>[];

  final void Function(String reason)? _onStaleStream;
  final Duration _staleAfter;

  /// [clock] is the current time, injected by tests.
  ///
  /// [onStaleStream] is called when a save the backend accepted has not come
  /// back through the stream within [staleAfter]: the live connection is
  /// probably stuck, and the caller reconnects it.
  TaskBloc({
    required TaskRepository repository,
    DateTime Function()? clock,
    void Function(String reason)? onStaleStream,
    Duration staleAfter = const Duration(seconds: 5),
  })  : _repository = repository,
        _clock = clock ?? DateTime.now,
        _onStaleStream = onStaleStream,
        _staleAfter = staleAfter,
        super(const TasksInitial()) {
    on<LoadTasks>(_onLoadTasks);
    on<_ShowBoard>((event, emit) => _emitBoard(emit));
    on<CreateStage>(
      (event, emit) => _run(
        event.completion,
        () => _repository.insertStage(event.stage),
        awaited: _AwaitedWrite(
          'stageCreate',
          (board) => board.stages.any((stage) => stage.id == event.stage.id),
        ),
      ),
    );
    on<UpdateStage>((event, emit) {
      final stage = event.stage;
      return _run(
        event.completion,
        () => _repository.updateStage(stage),
        awaited: _AwaitedWrite(
          'stageUpdate',
          (board) => board.stages.any(
            (live) => live.id == stage.id && sameStageEdit(live, stage),
          ),
          onTimeout: () => _stageOverlay.failed(stage.id),
        ),
        onSuccess: () {
          _stageOverlay.sent(stage.id, stage);
          _emitBoard(emit);
        },
      );
    });
    on<ImportStages>(
      (event, emit) => _run(
        event.completion,
        () => _repository.importStages(event.eventId, event.stages),
      ),
    );
    on<SyncStages>(
      (event, emit) => _run(
        event.completion,
        () => _repository.syncStages(event.eventId, event.plan),
      ),
    );
    on<DeleteStage>(
      (event, emit) => _run(
        event.completion,
        () => _repository.deleteStage(event.stageId),
        awaited: _AwaitedWrite(
          'stageDelete',
          (board) => board.stages.every((stage) => stage.id != event.stageId),
        ),
      ),
    );
    on<DeleteAllStages>(
      (event, emit) => _run(
        event.completion,
        () => _repository.deleteAllStages(event.eventId),
        awaited: _AwaitedWrite(
          'stagesDeleteAll',
          (board) =>
              board.stages.every((stage) => stage.eventId != event.eventId),
        ),
      ),
    );
    on<CreateTask>(
      (event, emit) => _run(
        event.completion,
        () => _repository.insertTask(event.task),
        awaited: _AwaitedWrite(
          'taskCreate',
          (board) => board.tasks.any((task) => task.id == event.task.id),
        ),
      ),
    );
    on<UpdateTask>((event, emit) {
      final task = event.task;
      return _run(
        event.completion,
        () => _repository.updateTask(task),
        awaited: _AwaitedWrite(
          'taskUpdate',
          (board) => board.tasks.any(
            (live) => live.id == task.id && sameTaskEdit(live, task),
          ),
          onTimeout: () => _taskOverlay.failed(task.id),
        ),
        onSuccess: () {
          _taskOverlay.sent(task.id, task);
          _emitBoard(emit);
        },
      );
    });
    on<DeleteTask>(
      (event, emit) => _run(
        event.completion,
        () => _repository.deleteTask(event.taskId),
        awaited: _AwaitedWrite(
          'taskDelete',
          (board) => board.tasks.every((task) => task.id != event.taskId),
        ),
      ),
    );
    on<ToggleSubtask>(
      (event, emit) => _runProgress(
        emit,
        _PendingProgress(
          taskId: event.taskId,
          subtaskId: event.subtaskId,
          value: event.isDone,
          at: _clock(),
        ),
        event.completion,
        () => _repository.setSubtaskDone(
          event.taskId,
          event.subtaskId,
          event.isDone,
        ),
      ),
    );
    on<SetTaskComplete>(
      (event, emit) => _runProgress(
        emit,
        _PendingProgress(
          taskId: event.taskId,
          value: event.isComplete,
          at: _clock(),
        ),
        event.completion,
        () => _repository.setTaskComplete(event.taskId, event.isComplete),
      ),
    );
    on<SaveAssigneeUpdate>(
      (event, emit) => _run(
        event.completion,
        () => _repository.setTaskAssigneeUpdate(event.taskId, event.text),
      ),
    );
  }

  Future<void> _onLoadTasks(LoadTasks event, Emitter<TaskState> emit) async {
    // The screen dispatches this every time it opens; one subscription is
    // enough, and a second would double every emission.
    if (_isWatching) return;
    _isWatching = true;
    try {
      // Keep a list that is already on screen instead of flashing a spinner
      // while a replacement subscription warms up.
      if (state is! TasksLoaded) emit(const TasksLoading());
      // No onError here, on purpose. With one, bloc keeps the subscription
      // open after an error, and a dead Firestore listener (sign-out kills
      // every one of them) reports its error and then never closes: the bloc
      // would stay "watching" a corpse and swallow every retry. Letting the
      // error throw cancels the subscription and reaches the catch below.
      await emit.forEach<TaskBoard>(
        _repository.watchBoard(),
        onData: (board) {
          _board = board;
          _dropConfirmedProgress(board);
          _stageOverlay
              .reconcile({for (final stage in board.stages) stage.id: stage});
          _taskOverlay
              .reconcile({for (final task in board.tasks) task.id: task});
          _settleAwaited(board);
          return _loaded(board);
        },
      );
    } catch (error, stackTrace) {
      developer.log(
        'TaskBloc: error watching tasks: $error',
        name: 'Tasks',
        error: error,
        stackTrace: stackTrace,
      );
      // Nothing to lay a tick over once the list is gone.
      _board = null;
      emit(const TasksError('טעינת המשימות נכשלה'));
    } finally {
      // Whether the stream ended or failed, the next LoadTasks must be
      // allowed to subscribe again.
      _isWatching = false;
    }
  }

  /// [board] as the screen should show it: with every unconfirmed tick applied.
  TasksLoaded _loaded(TaskBoard board) {
    final stages = _stageOverlay.isEmpty
        ? board.stages
        : [
            for (final stage in board.stages)
              _stageOverlay.resolve(stage.id, stage),
          ];
    final stagesById = {for (final stage in stages) stage.id: stage};
    final membersById = {for (final member in board.members) member.id: member};
    return TasksLoaded(
      [
        for (final task in board.tasks)
          _pending.values
              .where((change) => change.taskId == task.id)
              .fold(
                _withEdits(task, stagesById, membersById),
                (shown, change) => change.applyTo(shown),
              ),
      ],
      events: board.events,
      stages: stages,
      members: board.members,
    );
  }

  /// [task] with its accepted-but-unseen edit, and its stage as shown.
  TaskItem _withEdits(
    TaskItem task,
    Map<String, Stage> stagesById,
    Map<String, TeamMember> membersById,
  ) {
    if (_taskOverlay.isEmpty && _stageOverlay.isEmpty) return task;
    final edit = _taskOverlay.resolve(task.id, task);
    final shown = identical(edit, task)
        ? task
        : withTaskEdit(
            task,
            edit,
            assignees: [
              for (final id in edit.assigneeIds)
                if (membersById[id] != null) membersById[id]!,
            ],
          );
    final stage = stagesById[shown.stageId];
    return stage == null || identical(stage, shown.stage)
        ? shown
        : shown.copyWith(stage: stage);
  }

  /// Wait for [write] to show up in the stream. When it has not within
  /// [_staleAfter], the stream is probably stuck: report it once, and give
  /// the reconnect as long again before dropping what is laid over the board.
  void _await(_AwaitedWrite write) {
    final board = _board;
    if (board != null && write.isIn(board)) {
      write.onTimeout?.call();
      return;
    }
    // Nobody to tell: what is laid over the board goes once the stream
    // carries it.
    if (_onStaleStream == null) return;
    _awaited.add(write);
    write.timer = Timer(_staleAfter, () {
      if (!_awaited.contains(write)) return;
      Logger.warning('tasks:staleStream', {'write': write.label});
      _onStaleStream('tasks:${write.label}');
      write.timer = Timer(_staleAfter, () {
        if (!_awaited.remove(write)) return;
        write.onTimeout?.call();
        if (!isClosed) add(const _ShowBoard());
      });
    });
  }

  /// Forget every awaited write [board] carries.
  void _settleAwaited(TaskBoard board) {
    _awaited.removeWhere((write) {
      if (!write.isIn(board)) return false;
      write.timer?.cancel();
      return true;
    });
  }

  @override
  Future<void> close() {
    for (final write in _awaited) {
      write.timer?.cancel();
    }
    _awaited.clear();
    return super.close();
  }

  /// Forget the ticks [board] has caught up with. A tick the backend already
  /// accepted goes too, even when the board disagrees: by then the stream, not
  /// the member's tick, is the truth.
  void _dropConfirmedProgress(TaskBoard board) {
    final tasksById = {for (final task in board.tasks) task.id: task};
    _pending.removeWhere((_, change) {
      final task = tasksById[change.taskId];
      return change.isSettled || task == null || change.isReflectedIn(task);
    });
  }

  void _emitBoard(Emitter<TaskState> emit) {
    final board = _board;
    if (board != null) emit(_loaded(board));
  }

  /// Show [change] at once, then send it. A refusal takes it back off the
  /// screen; a later tick on the same thing replaces it and is not disturbed
  /// by this one's answer.
  Future<void> _runProgress(
    Emitter<TaskState> emit,
    _PendingProgress change,
    CrudActionCompleter? completion,
    Future<void> Function() action,
  ) async {
    _pending[change.key] = change;
    _emitBoard(emit);
    try {
      await action();
      change.isSettled = true;
      _await(_AwaitedWrite(
        'progress',
        (board) => board.tasks.any(
          (task) => task.id == change.taskId && change.isReflectedIn(task),
        ),
      ));
      completeCrudAction(completion, const CrudActionResult.success());
    } catch (error, stackTrace) {
      developer.log(
        'TaskBloc: task progress update failed: $error',
        name: 'Tasks',
        error: error,
        stackTrace: stackTrace,
      );
      if (identical(_pending[change.key], change)) {
        _pending.remove(change.key);
        _emitBoard(emit);
      }
      completeCrudAction(
        completion,
        CrudActionResult.failure(taskErrorMessage(error)),
      );
    }
  }

  Future<void> _run(
    CrudActionCompleter? completion,
    Future<void> Function() action, {
    _AwaitedWrite? awaited,
    void Function()? onSuccess,
  }) async {
    try {
      await action();
      onSuccess?.call();
      if (awaited != null) _await(awaited);
      completeCrudAction(completion, const CrudActionResult.success());
    } catch (error, stackTrace) {
      developer.log(
        'TaskBloc: task action failed: $error',
        name: 'Tasks',
        error: error,
        stackTrace: stackTrace,
      );
      completeCrudAction(
        completion,
        CrudActionResult.failure(taskErrorMessage(error)),
      );
    }
  }
}

/// A save the backend accepted, waiting to show up in the stream.
class _AwaitedWrite {
  _AwaitedWrite(this.label, this.isIn, {this.onTimeout});

  /// What was saved, for the log.
  final String label;

  /// Whether the board, as the stream delivered it, carries the save.
  final bool Function(TaskBoard board) isIn;

  /// Drops what this save laid over the board. Called once the stream has
  /// had its chance: right away when it is already in, else after a
  /// reconnect did not bring it.
  final void Function()? onTimeout;

  Timer? timer;
}

/// Re-emit the board, after something laid over it was dropped.
class _ShowBoard extends TaskEvent {
  const _ShowBoard();
}
