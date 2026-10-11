import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/task_item_model.dart';
import 'package:shavtzak/domain/entities/subtask.dart';

import '../../support/task_fixtures.dart';

void main() {
  final createdAt = DateTime(2026, 10, 1, 9);
  final updatedAt = DateTime(2026, 10, 5, 12, 30);
  final dueAt = DateTime(2026, 10, 20, 7, 30);

  Map<String, dynamic> fullMap() => {
        'id': 't1',
        'eventId': 'e1',
        'title': 'להזמין אוטובוס',
        'description': 'שני רכבים',
        'subtasks': [
          {'id': 'a', 'title': 'הצעת מחיר', 'isDone': true},
          {'id': 'b', 'title': 'אישור', 'isDone': false},
        ],
        'dueAt': Timestamp.fromDate(dueAt),
        'assigneeIds': ['m1', 'm2'],
        'assigneeUpdate': 'ממתין לאישור',
        'assigneeUpdateAt': Timestamp.fromDate(updatedAt),
        'assigneeUpdateById': 'm1',
        'assigneeUpdateByName': 'דנה',
        'isComplete': false,
        'completedAt': null,
        'completedById': null,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  group('TaskItemModel.fromMap', () {
    test('reads every stored field', () {
      final task = TaskItemModel.fromMap('t1', fullMap());

      expect(task.id, 't1');
      expect(task.eventId, 'e1');
      expect(task.title, 'להזמין אוטובוס');
      expect(task.description, 'שני רכבים');
      expect(task.subtasks, const [
        Subtask(id: 'a', title: 'הצעת מחיר', isDone: true),
        Subtask(id: 'b', title: 'אישור'),
      ]);
      expect(task.dueAt, dueAt);
      expect(task.assigneeIds, ['m1', 'm2']);
      expect(task.assigneeUpdate, 'ממתין לאישור');
      expect(task.assigneeUpdateAt, updatedAt);
      expect(task.assigneeUpdateById, 'm1');
      expect(task.assigneeUpdateByName, 'דנה');
      expect(task.isComplete, isFalse);
      expect(task.completedAt, isNull);
      expect(task.completedById, isNull);
      expect(task.createdAt, createdAt);
      expect(task.createdById, 'm-admin');
      expect(task.updatedAt, updatedAt);
    });

    test('uses the document id, not an id stored inside the document', () {
      final task = TaskItemModel.fromMap('doc-id', fullMap());
      expect(task.id, 'doc-id');
    });

    test('attaches the populated event and assignees', () {
      final event = buildEvent();
      final assignees = [buildMember(id: 'm1'), buildMember(id: 'm2')];
      final task = TaskItemModel.fromMap(
        't1',
        fullMap(),
        event: event,
        assignees: assignees,
      );
      expect(task.event, event);
      expect(task.assignees, assignees);
    });

    test('a document with only its required fields parses with defaults', () {
      final task = TaskItemModel.fromMap('t1', {
        'eventId': 'e1',
        'title': 'ישן',
        'assigneeIds': ['m1'],
        'createdAt': Timestamp.fromDate(createdAt),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(updatedAt),
      });

      expect(task.description, '');
      expect(task.subtasks, isEmpty);
      expect(task.dueAt, isNull);
      expect(task.assigneeUpdate, isNull);
      expect(task.assigneeUpdateAt, isNull);
      expect(task.assigneeUpdateById, isNull);
      expect(task.assigneeUpdateByName, isNull);
      expect(task.isComplete, isFalse);
      expect(task.completedAt, isNull);
      expect(task.completedById, isNull);
    });

    test('an empty document still parses instead of throwing', () {
      final task = TaskItemModel.fromMap('t1', const {});

      expect(task.id, 't1');
      expect(task.eventId, '');
      expect(task.title, '');
      expect(task.assigneeIds, isEmpty);
      expect(task.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(task.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('malformed subtask entries are skipped', () {
      final task = TaskItemModel.fromMap('t1', {
        ...fullMap(),
        'subtasks': [
          {'id': 'a', 'title': 'טוב', 'isDone': true},
          'זבל',
          {'title': 'בלי מזהה'},
          null,
        ],
      });
      expect(task.subtasks, const [Subtask(id: 'a', title: 'טוב', isDone: true)]);
    });

    test('non-string assignee ids are skipped', () {
      final task = TaskItemModel.fromMap('t1', {
        ...fullMap(),
        'assigneeIds': ['m1', 7, null, 'm2'],
      });
      expect(task.assigneeIds, ['m1', 'm2']);
    });
  });

  group('TaskItemModel.toMutationPayload', () {
    test('sends the editable fields only', () {
      final payload = TaskItemModel.toMutationPayload(buildTask(
        id: 't1',
        eventId: 'e1',
        title: 'להזמין אוטובוס',
        description: 'שני רכבים',
        assigneeIds: const ['m1', 'm2'],
        subtasks: const [
          Subtask(id: 'a', title: 'הצעת מחיר', isDone: true),
          Subtask(id: 'b', title: 'אישור'),
        ],
        isComplete: true,
        assigneeUpdate: 'בטיפול',
      ));

      expect(payload.keys.toSet(), {
        'id',
        'eventId',
        'title',
        'description',
        'dueAt',
        'assigneeIds',
        'subtasks',
      });
      expect(payload['id'], 't1');
      expect(payload['eventId'], 'e1');
      expect(payload['title'], 'להזמין אוטובוס');
      expect(payload['description'], 'שני רכבים');
      expect(payload['assigneeIds'], ['m1', 'm2']);
    });

    test('subtasks carry id and title but never isDone', () {
      final payload = TaskItemModel.toMutationPayload(buildTask(
        subtasks: const [Subtask(id: 'a', title: 'הצעת מחיר', isDone: true)],
      ));
      expect(payload['subtasks'], [
        {'id': 'a', 'title': 'הצעת מחיר'},
      ]);
    });

    test('a due date is sent as a UTC instant so the server reads it correctly', () {
      final payload = TaskItemModel.toMutationPayload(buildTask(dueAt: dueAt));

      final sent = payload['dueAt'] as String;
      expect(sent, endsWith('Z'));
      expect(DateTime.parse(sent).isAtSameMomentAs(dueAt), isTrue);
    });

    test('no due date is sent as null', () {
      final payload = TaskItemModel.toMutationPayload(buildTask());
      expect(payload.containsKey('dueAt'), isTrue);
      expect(payload['dueAt'], isNull);
    });
  });
}
