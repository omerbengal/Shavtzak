import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../support/task_fixtures.dart';
import '../../support/team_task_fixtures.dart';

class _FakeBackend extends Fake implements BackendApiService {
  final List<({String operation, Map<String, dynamic>? payload})> calls = [];

  @override
  Future<Map<String, dynamic>> mutate(
    String operation, {
    Map<String, dynamic>? payload,
  }) async {
    calls.add((operation: operation, payload: payload));
    return {'ok': true};
  }
}

Map<String, dynamic> _stored(String title, List<String> ownerIds,
        {Map<String, dynamic>? link}) =>
    {
      'title': title,
      'assigneeIds': ownerIds,
      'ownerIds': ownerIds,
      'status': 'open',
      'link': link,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late _FakeBackend backend;
  late FirestoreDatabase database;
  late TeamTaskRepository repository;

  setUp(() async {
    EnvironmentService.instance.setTestMode(false);
    fake = FakeFirebaseFirestore();
    backend = _FakeBackend();
    database = FirestoreDatabase(firestore: fake, backendApiService: backend);
    repository = TeamTaskRepository(database);
    await fake.collection('teamTasks').doc('mine').set(_stored('שלי', ['m1']));
    await fake.collection('teamTasks').doc('theirs').set(_stored('של אחר', ['m2']));
  });

  tearDown(() async {
    EnvironmentService.instance.setTestMode(false);
    await database.close();
  });

  test('a non-manager watches only the ownerIds query', () async {
    final tasks = await database.watchOwnedTeamTasks('m1').first;
    expect(tasks.map((t) => t.id), ['mine']);

    final board = await repository.watchBoardFor(buildMember(id: 'm1')).first;
    expect(board.tasks.map((t) => t.id), ['mine']);
  });

  test('a manager watches every task', () async {
    final board =
        await repository.watchBoardFor(buildMember(id: 'm9', canManageTasks: true)).first;
    expect(board.tasks.map((t) => t.id).toSet(), {'mine', 'theirs'});
  });

  test('joins the event, the topic and the owners', () async {
    await fake.collection('teamMembers').doc('m1').set({
      'name': 'דנה',
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await fake.collection('utilities').doc('Lists').set({
      'TaskTopics': [buildTopic().toJson()],
    });
    await fake
        .collection('teamTasks')
        .doc('topic')
        .set(_stored('נושא', ['m1', 'gone'], link: {'type': 'topic', 'id': 'p1'}));

    final board =
        await repository.watchBoardFor(buildMember(id: 'm1')).firstWhere((b) => b.tasks.length == 2 && b.members.isNotEmpty && b.topics.isNotEmpty);
    final task = board.tasks.firstWhere((t) => t.id == 'topic');
    expect(task.topic, const TaskTopic(id: 'p1', name: 'נשות מגדים'));
    // A member who is gone is simply not joined; the id stays.
    expect(task.owners.map((m) => m.id), ['m1']);
    expect(task.ownerIds, ['m1', 'gone']);
    expect(board.topics.single.id, 'p1');
  });

  test('writes go through BackendApiService with the operation names of Task 2', () async {
    final task = buildTeamTask(id: 't9');
    await repository.insertTask(task);
    await repository.updateTask(task);
    await repository.deleteTask('t9');
    await repository.setStatus('t9', TeamTaskStatus.duplicate, duplicateOfId: 't1');
    await repository.setSubtaskDone('t9', 's1', true);
    await repository.addUpdate('t9', 'עדכון');
    await repository.insertTopic(buildTopic());
    await repository.updateTopic(buildTopic());
    await repository.archiveTopic('p1');
    await repository.restoreTopic('p1');

    expect(backend.calls.map((c) => c.operation), [
      'teamTask.insert',
      'teamTask.update',
      'teamTask.delete',
      'teamTask.setStatus',
      'teamTask.setSubtaskDone',
      'teamTask.addUpdate',
      'taskTopic.insert',
      'taskTopic.update',
      'taskTopic.delete',
      'taskTopic.restore',
    ]);
    expect(backend.calls[0].payload!['task']['id'], 't9');
    expect(backend.calls[2].payload, {'id': 't9'});
    expect(backend.calls[3].payload,
        {'id': 't9', 'status': 'duplicate', 'duplicateOfId': 't1'});
    expect(backend.calls[4].payload, {'id': 't9', 'subtaskId': 's1', 'isDone': true});
    expect(backend.calls[5].payload, {'id': 't9', 'text': 'עדכון'});
    expect(backend.calls[6].payload!['topic']['name'], 'נשות מגדים');
    expect(backend.calls[8].payload, {'topicId': 'p1'});
  });

  test('collection is test_teamTasks in test mode', () async {
    EnvironmentService.instance.setTestMode(true);
    await fake.collection('test_teamTasks').doc('t').set(_stored('בדיקה', ['m1']));
    final tasks = await database.watchAllTeamTasks().first;
    expect(tasks.map((t) => t.id), ['t']);
  });
}
