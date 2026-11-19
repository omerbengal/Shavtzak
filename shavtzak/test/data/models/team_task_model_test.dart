import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/team_task_model.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

void main() {
  final createdAt = DateTime(2026, 11, 1, 9);
  final updatedAt = DateTime(2026, 11, 5, 12, 30);

  Map<String, dynamic> fullMap() => {
        'title': 'להזמין אולם',
        'description': 'לחנוכה',
        'link': {'type': 'topic', 'id': 'p1'},
        'assigneeIds': <String>[],
        'subtasks': [
          {
            'id': 's1',
            'title': 'מחיר',
            'isDone': true,
            'assigneeId': 'a',
            'contacts': [
              {'id': 'c2', 'name': 'משה', 'role': 'מנהל אולם', 'phone': '050-1'},
            ],
          },
          {'id': 's2', 'title': 'חוזה', 'isDone': false, 'assigneeId': null},
        ],
        'contacts': [
          {'id': 'c1', 'name': 'רונית', 'role': 'אולם', 'phone': '050-2'},
        ],
        'deadline': '2026-12-01',
        'status': 'duplicate',
        'duplicateOfId': 't0',
        'updates': [
          {
            'id': 'u1',
            'text': 'הבוט מוכן',
            'at': Timestamp.fromDate(updatedAt),
            'byId': 'a',
            'byName': 'דנה',
          },
        ],
        'ownerIds': ['a'],
        'completedAt': null,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdById': 'mgr',
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  test('round-trips every field', () {
    final task = TeamTaskModel.fromMap('t1', fullMap());
    expect(task.id, 't1');
    expect(task.title, 'להזמין אולם');
    expect(task.description, 'לחנוכה');
    expect(task.link, const TaskLink(TaskLinkType.topic, 'p1'));
    // An old document's subtasks are no longer read (16/11/2026).
    expect(task.urgency, TeamTaskUrgency.normal);
    expect(task.eventIds, isEmpty);
    expect(task.contacts.single,
        const StageContact(id: 'c1', name: 'רונית', role: 'אולם', phone: '050-2'));
    expect(task.status, TeamTaskStatus.duplicate);
    expect(task.duplicateOfId, 't0');
    expect(task.updates.single.text, 'הבוט מוכן');
    expect(task.updates.single.at, updatedAt);
    expect(task.updates.single.byName, 'דנה');
    expect(task.ownerIds, ['a']);
    expect(task.createdAt, createdAt);
    expect(task.createdById, 'mgr');

    final payload = TeamTaskModel.toMutationPayload(task);
    expect(payload['id'], 't1');
    expect(payload['link'], {'type': 'topic', 'id': 'p1'});
    expect(payload['deadline'], '2026-12-01');
    expect(payload['assigneeIds'], <String>[]);
    // No subtasks key: the backend keeps an old document's subtasks.
    expect(payload.containsKey('subtasks'), isFalse);
    expect(payload['urgency'], 'normal');
    expect(payload['eventIds'], <String>[]);
    expect(payload['contacts'], [
      {'id': 'c1', 'name': 'רונית', 'phone': '050-2', 'role': 'אולם'},
    ]);
    // Progress and status are not part of an edit.
    expect(payload.containsKey('status'), isFalse);
    expect(payload.containsKey('updates'), isFalse);
  });

  test('unknown status key reads as open', () {
    expect(TeamTaskStatus.fromKey('weird'), TeamTaskStatus.open);
    expect(TeamTaskModel.fromMap('t', {'status': 'weird'}).status, TeamTaskStatus.open);
    expect(TeamTaskStatus.inProgress.key, 'inProgress');
    expect(TeamTaskStatus.cancelled.hebrewLabel, 'לא רלוונטי/בוטל');
  });

  test('missing contacts read as empty', () {
    final task = TeamTaskModel.fromMap('t', {
      'title': 'x',
      'subtasks': [
        {'id': 's1', 'title': 'y'},
      ],
    });
    expect(task.contacts, isEmpty);
    expect(task.link, isNull);
    expect(task.updates, isEmpty);
  });

  test('deadline stays a plain date string', () {
    final task = TeamTaskModel.fromMap('t', {'deadline': '2026-12-01'});
    expect(task.deadline, '2026-12-01');
    expect(task.deadlineDate, DateTime(2026, 12, 1));
    expect(TeamTaskModel.fromMap('t', {'deadline': '15.11'}).deadline, isNull);
  });

  test('topics list parses like the other managed lists', () {
    final topics = TaskTopic.listFromJson([
      {'id': 'b', 'name': 'כללי', 'sortOrder': 2},
      {'id': 'a', 'name': 'נשות מגדים', 'sortOrder': 1, 'isArchived': true},
      {'id': '', 'name': 'x'},
    ]);
    expect(topics.map((t) => t.id), ['a', 'b']);
    expect(topics.first.isArchived, isTrue);
    expect(topics.last.toJson()['name'], 'כללי');
  });

  test('several events and the urgency: read, and sent with the first event as the link', () {
    final task = TeamTaskModel.fromMap('t1', {
      'title': 'x',
      'link': {'type': 'event', 'id': 'e1'},
      'eventIds': ['e1', 'e2'],
      'urgency': 'high',
    });
    expect(task.eventIds, ['e1', 'e2']);
    expect(task.linkedEventIds, ['e1', 'e2']);
    expect(task.hasSeveralEvents, isTrue);
    expect(task.urgency, TeamTaskUrgency.high);
    final payload = TeamTaskModel.toMutationPayload(task);
    expect(payload['link'], {'type': 'event', 'id': 'e1'});
    expect(payload['eventIds'], ['e1', 'e2']);
    expect(payload['urgency'], 'high');
    // A document from before: its one event.
    final old = TeamTaskModel.fromMap('t2', {
      'title': 'y',
      'link': {'type': 'event', 'id': 'e9'},
      'urgency': 'weird',
    });
    expect(old.linkedEventIds, ['e9']);
    expect(old.hasSeveralEvents, isFalse);
    expect(old.urgency, TeamTaskUrgency.normal);
  });

  test('tags: the mentions and the tagged ids of an update (19/11/2026)', () {
    final task = TeamTaskModel.fromMap('t1', {
      'title': 'x',
      'status': 'open',
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'updates': [
        {
          'id': 'u1',
          'text': '@יוסי',
          'at': Timestamp.fromDate(updatedAt),
          'byId': 'a',
          'mentionIds': ['b'],
        },
      ],
      'mentions': [
        {'memberId': 'b', 'byId': 'a', 'at': Timestamp.fromDate(updatedAt), 'doneAt': null},
        {'memberId': 'b', 'byId': 'a', 'at': Timestamp.fromDate(updatedAt)},
        {'memberId': 'c', 'at': Timestamp.fromDate(updatedAt), 'doneAt': Timestamp.fromDate(updatedAt),
          'doneText': 'בוצע'},
        {'byId': 'a'},
      ],
    });
    expect(task.updates.single.mentionIds, ['b']);
    expect(task.mentions.map((m) => m.memberId), ['b', 'c']);
    expect(task.mentionOf('b')!.isDone, isFalse);
    expect(task.mentionOf('c')!.doneText, 'בוצע');
    expect(TeamTaskModel.fromMap('t2', {'title': 'y'}).mentions, isEmpty);
  });
}
