import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';

class MockUserSelectionBloc
    extends MockBloc<UserSelectionEvent, UserSelectionState>
    implements UserSelectionBloc {}

/// A repository for the tasks screens' widget tests: the test pushes the board
/// through [controller], and records every mutation in [calls]. A mutation
/// throws [failWith] when it is set, and waits for [gate] while that is set.
class FakeTaskRepository extends Fake implements TaskRepository {
  StreamController<TaskBoard> controller = StreamController<TaskBoard>();
  int watchCalls = 0;
  final calls = <String>[];
  Object? failWith;

  /// While set, a mutation does not answer until the test completes it.
  Completer<void>? gate;

  /// Who is assigned to each event, as the task form sees it.
  Map<String, List<TeamMember>> assigneesByEvent = {};

  @override
  Stream<List<TeamMember>> watchEventAssignees(String eventId) =>
      Stream.value(assigneesByEvent[eventId] ?? const []);

  @override
  Stream<TaskBoard> watchBoard() {
    watchCalls++;
    return controller.stream;
  }

  Future<void> _record(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> insertTask(TaskItem task) => _record('insert:${task.title}');

  @override
  Future<void> updateTask(TaskItem task) => _record('update:${task.id}');

  @override
  Future<void> deleteTask(String taskId) => _record('delete:$taskId');

  @override
  Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone) =>
      _record('subtask:$taskId:$subtaskId:$isDone');

  @override
  Future<void> setTaskComplete(String taskId, bool isComplete) =>
      _record('complete:$taskId:$isComplete');

  @override
  Future<void> setTaskAssigneeUpdate(String taskId, String text) =>
      _record('note:$taskId:$text');

  @override
  Future<void> insertStage(Stage stage) => _record('insertStage:${stage.title}');

  @override
  Future<void> updateStage(Stage stage) => _record('updateStage:${stage.id}');

  @override
  Future<void> deleteStage(String stageId) => _record('deleteStage:$stageId');
}
