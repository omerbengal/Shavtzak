import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

/// A repository for the team tasks bloc and screen tests: the test pushes
/// boards through [controller] and reads every mutation in [calls]. A
/// mutation throws [failWith] when set, and waits for [gate] while set.
class FakeTeamTaskRepository extends Fake implements TeamTaskRepository {
  StreamController<TeamTaskBoard> controller = StreamController<TeamTaskBoard>.broadcast();
  final viewers = <TeamMember>[];
  final calls = <String>[];
  final inserted = <TeamTask>[];
  final updated = <TeamTask>[];
  Object? failWith;
  Completer<void>? gate;

  @override
  Stream<TeamTaskBoard> watchBoardFor(TeamMember viewer) {
    viewers.add(viewer);
    return controller.stream;
  }

  Future<void> _record(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> insertTask(TeamTask task) {
    inserted.add(task);
    return _record('insert:${task.title}');
  }

  @override
  Future<void> updateTask(TeamTask task) {
    updated.add(task);
    return _record('update:${task.id}');
  }

  @override
  Future<void> deleteTask(String id) => _record('delete:$id');

  @override
  Future<void> setStatus(
    String id,
    TeamTaskStatus status, {
    String? duplicateOfId,
    String? subtaskId,
  }) =>
      _record('status:$id${subtaskId == null ? '' : '/$subtaskId'}:${status.key}'
          '${duplicateOfId == null ? '' : ':$duplicateOfId'}');

  @override
  Future<void> setSubtaskDone(String id, String subtaskId, bool isDone) =>
      _record('subtask:$id:$subtaskId:$isDone');

  @override
  Future<void> addUpdate(String id, String text, {String? subtaskId}) =>
      _record('log:$id${subtaskId == null ? '' : '/$subtaskId'}:$text');

  @override
  Future<void> insertTopic(TaskTopic topic) => _record('insertTopic:${topic.name}');

  @override
  Future<void> updateTopic(TaskTopic topic) => _record('updateTopic:${topic.id}:${topic.name}');

  @override
  Future<void> archiveTopic(String id) => _record('archiveTopic:$id');

  @override
  Future<void> restoreTopic(String id) => _record('restoreTopic:$id');

  @override
  Future<void> deleteTopic(String id) => _record('deleteTopic:$id');
}
