import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/crud_action_result.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
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

/// BLoC for the tasks screen.
///
/// Holds one live subscription to every task. Mutations do not touch the
/// state: the backend write comes back through the stream. Their outcome is
/// reported through the event's completer so the screen can show a snackbar
/// without the list being replaced by an error.
class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository _repository;
  bool _isWatching = false;

  TaskBloc({required TaskRepository repository})
      : _repository = repository,
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
      (event, emit) => _run(
        event.completion,
        () => _repository.setSubtaskDone(
          event.taskId,
          event.subtaskId,
          event.isDone,
        ),
      ),
    );
    on<SetTaskComplete>(
      (event, emit) => _run(
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
        onData: (board) => TasksLoaded(
          board.tasks,
          events: board.events,
          members: board.members,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'TaskBloc: error watching tasks: $error',
        name: 'Tasks',
        error: error,
        stackTrace: stackTrace,
      );
      emit(const TasksError('טעינת המשימות נכשלה'));
    } finally {
      // Whether the stream ended or failed, the next LoadTasks must be
      // allowed to subscribe again.
      _isWatching = false;
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
