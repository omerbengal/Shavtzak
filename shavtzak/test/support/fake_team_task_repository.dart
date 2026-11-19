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
  Future<void> setStatus(String id, TeamTaskStatus status, {String? duplicateOfId}) =>
      _record('status:$id:${status.key}${duplicateOfId == null ? '' : ':$duplicateOfId'}');

  @override
  Future<void> addUpdate(String id, String text, {List<String> mentionIds = const []}) =>
      _record('log:$id:$text${mentionIds.isEmpty ? '' : ':@${mentionIds.join(',')}'}');

  @override
  Future<void> setMentionDone(String id, String text) => _record('mentionDone:$id:$text');

  @override
  Future<void> editUpdate(String id, String updateId, String text) =>
      _record('editLog:$id:$updateId:$text');

  @override
  Future<void> deleteUpdate(String id, String updateId) => _record('deleteLog:$id:$updateId');

  @override
  Future<void> insertPendingEvent(TaskTopic pendingEvent) =>
      _record('insertPending:${pendingEvent.name}');

  @override
  Future<void> linkPendingEvent(String id, String eventId) =>
      _record('linkPending:$id:$eventId');

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
