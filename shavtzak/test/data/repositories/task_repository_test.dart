import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

import '../../support/task_fixtures.dart';

/// Stands in for the three source streams and records every mutation call.
class _FakeDatabase extends Fake implements DatabaseInterface {
  final tasks = StreamController<List<TaskItem>>.broadcast();
  final events = StreamController<List<Event>>.broadcast();
  final members = StreamController<List<TeamMember>>.broadcast();
  final calls = <String>[];

  @override
  Stream<List<TaskItem>> watchTasks() => tasks.stream;

  @override
  Stream<List<Event>> watchEvents() => events.stream;

  @override
  Stream<List<TeamMember>> watchTeamMembers() => members.stream;

  @override
  Future<void> insertTask(TaskItem task) async => calls.add('insert:${task.id}');

  @override
  Future<void> updateTask(TaskItem task) async => calls.add('update:${task.id}');

  @override
  Future<void> deleteTask(String taskId) async => calls.add('delete:$taskId');

  @override
  Future<void> setSubtaskDone(
    String taskId,
    String subtaskId,
    bool isDone,
  ) async =>
      calls.add('subtask:$taskId:$subtaskId:$isDone');

  @override
  Future<void> setTaskComplete(String taskId, bool isComplete) async =>
      calls.add('complete:$taskId:$isComplete');

  @override
  Future<void> setTaskAssigneeUpdate(String taskId, String text) async =>
      calls.add('note:$taskId:$text');

  Future<void> close() async {
    await tasks.close();
    await events.close();
    await members.close();
  }
}

void main() {
  group('TaskRepository.watchTasks', () {
    late _FakeDatabase database;
    late TaskRepository repository;
    late List<List<TaskItem>> emissions;
    late StreamSubscription<List<TaskItem>> subscription;

    setUp(() {
      database = _FakeDatabase();
      repository = TaskRepository(database);
      emissions = [];
      subscription = repository.watchTasks().listen(emissions.add);
    });

    tearDown(() async {
      await subscription.cancel();
      await database.close();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('populates each task with its event and its assignees', () async {
      final event = buildEvent(id: 'e1');
      final dana = buildMember(id: 'm1', name: 'דנה');
      final yoav = buildMember(id: 'm2', name: 'יואב');

      database.tasks.add([
        buildTask(eventId: 'e1', assigneeIds: const ['m2', 'm1']),
      ]);
      database.events.add([event]);
      database.members.add([dana, yoav]);
      await settle();

      expect(emissions, hasLength(1));
      final task = emissions.single.single;
      expect(task.event, event);
      // Assignees follow assigneeIds order, not the members list order.
      expect(task.assignees, [yoav, dana]);
    });

    test('does not emit until all three sources have delivered', () async {
      database.tasks.add([buildTask()]);
      database.events.add([buildEvent()]);
      await settle();
      expect(emissions, isEmpty);

      database.members.add([buildMember()]);
      await settle();
      expect(emissions, hasLength(1));
    });

    test('re-emits with the new name when an event is renamed', () async {
      database.tasks.add([buildTask(eventId: 'e1')]);
      database.events.add([buildEvent(id: 'e1', name: 'שם ישן')]);
      database.members.add([buildMember()]);
      await settle();

      database.events.add([buildEvent(id: 'e1', name: 'שם חדש')]);
      await settle();

      expect(emissions, hasLength(2));
      expect(emissions.last.single.event?.name, 'שם חדש');
      expect(emissions.last, isNot(emissions.first));
    });

    test('re-emits when an assignee is renamed', () async {
      database.tasks.add([buildTask(assigneeIds: const ['m1'])]);
      database.events.add([buildEvent()]);
      database.members.add([buildMember(id: 'm1', name: 'דנה')]);
      await settle();

      database.members.add([buildMember(id: 'm1', name: 'דנה כהן')]);
      await settle();

      expect(emissions.last.single.assignees.single.name, 'דנה כהן');
    });

    test('leaves the event null when it does not resolve', () async {
      database.tasks.add([buildTask(eventId: 'gone')]);
      database.events.add([buildEvent(id: 'e1')]);
      database.members.add([buildMember()]);
      await settle();

      expect(emissions.single.single.event, isNull);
      expect(emissions.single.single.eventId, 'gone');
    });

    test('drops an assignee id that no longer resolves but keeps the id', () async {
      database.tasks.add([
        buildTask(assigneeIds: const ['m1', 'deleted']),
      ]);
      database.events.add([buildEvent()]);
      database.members.add([buildMember(id: 'm1')]);
      await settle();

      final task = emissions.single.single;
      expect(task.assignees.map((member) => member.id), ['m1']);
      expect(task.assigneeIds, ['m1', 'deleted']);
    });
  });

  group('TaskRepository mutations', () {
    test('forward to the database with their arguments', () async {
      final database = _FakeDatabase();
      final repository = TaskRepository(database);
      final task = buildTask(id: 't1');

      await repository.insertTask(task);
      await repository.updateTask(task);
      await repository.deleteTask('t1');
      await repository.setSubtaskDone('t1', 'a', true);
      await repository.setTaskComplete('t1', false);
      await repository.setTaskAssigneeUpdate('t1', 'בטיפול');

      expect(database.calls, [
        'insert:t1',
        'update:t1',
        'delete:t1',
        'subtask:t1:a:true',
        'complete:t1:false',
        'note:t1:בטיפול',
      ]);
      await database.close();
    });
  });

  group('FirestoreDatabase.watchTasks', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late FakeFirebaseFirestore fake;
    late FirestoreDatabase database;

    setUp(() {
      fake = FakeFirebaseFirestore();
      database = FirestoreDatabase(firestore: fake);
    });

    tearDown(() async {
      await database.close();
    });

    test('reads the tasks collection into unpopulated entities', () async {
      await fake.collection('tasks').doc('t1').set({
        'eventId': 'e1',
        'title': 'להזמין אוטובוס',
        'assigneeIds': ['m1'],
        'subtasks': [
          {'id': 'a', 'title': 'הצעת מחיר', 'isDone': true},
        ],
        'isComplete': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
      });

      final tasks = await database.watchTasks().first;

      expect(tasks, hasLength(1));
      expect(tasks.single.id, 't1');
      expect(tasks.single.title, 'להזמין אוטובוס');
      expect(tasks.single.isComplete, isTrue);
      expect(tasks.single.subtasks.single.isDone, isTrue);
      expect(tasks.single.event, isNull);
      expect(tasks.single.assignees, isEmpty);
    });

    test('one unreadable document does not blank the whole list', () async {
      await fake.collection('tasks').doc('good').set({
        'eventId': 'e1',
        'title': 'תקין',
        'assigneeIds': ['m1'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
      });
      await fake.collection('tasks').doc('odd').set({
        'title': 42,
        'subtasks': 'not a list',
        'assigneeIds': 'm1',
      });

      final tasks = await database.watchTasks().first;

      expect(tasks.map((task) => task.id).toSet(), {'good', 'odd'});
    });

    test('emits again when a task changes', () async {
      final ref = fake.collection('tasks').doc('t1');
      await ref.set({
        'eventId': 'e1',
        'title': 'להזמין אוטובוס',
        'assigneeIds': ['m1'],
        'isComplete': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
      });

      final seen = <bool>[];
      final subscription = database
          .watchTasks()
          .listen((tasks) => seen.add(tasks.single.isComplete));
      await Future<void>.delayed(Duration.zero);
      await ref.update({'isComplete': true});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(seen, [false, true]);
    });
  });
}
