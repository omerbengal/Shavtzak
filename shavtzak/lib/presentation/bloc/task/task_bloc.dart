import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/crud_action_result.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
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

  /// [clock] is the current time, injected by tests.
  TaskBloc({
    required TaskRepository repository,
    DateTime Function()? clock,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now,
        super(const TasksInitial()) {
    on<LoadTasks>(_onLoadTasks);
    on<CreateTask>(
      (event, emit) =>
          _run(event.completion, () => _repository.insertTask(event.task)),
    );
    on<UpdateTask>(
      (event, emit) =>
          _run(event.completion, () => _repository.updateTask(event.task)),
    );
    on<DeleteTask>(
      (event, emit) =>
          _run(event.completion, () => _repository.deleteTask(event.taskId)),
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
    return TasksLoaded(
      [
        for (final task in board.tasks)
          _pending.values
              .where((change) => change.taskId == task.id)
              .fold(task, (shown, change) => change.applyTo(shown)),
      ],
      events: board.events,
      members: board.members,
    );
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
    Future<void> Function() action,
  ) async {
    try {
      await action();
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
