import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_cycle_copy.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';

import '../../support/task_fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 8, 10);
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yoav = buildMember(id: 'm2', name: 'יואב');
  final boss = buildMember(id: 'boss', name: 'מנהלת', isAdmin: true);

  // Old מחזור: 2 days, 5-6/10. New one: 2 days, 12-13/11.
  final oldEvent = buildEvent(
    id: 'old',
    startDate: DateTime(2026, 10, 5),
    endDate: DateTime(2026, 10, 6),
  );
  final newEvent = buildEvent(
    id: 'new',
    startDate: DateTime(2026, 11, 12),
    endDate: DateTime(2026, 11, 13),
  );
  final day1 = buildStage(
    id: 's1',
    eventId: 'old',
    title: 'קליטה',
    date: DateTime(2026, 10, 5),
    startTime: '08:00',
    endTime: '09:00',
    hotelLocation: 'לובי',
    notes: 'להגיע מוקדם',
    requirements: 'שולחן',
    contacts: const [
      StageContact(id: 'c1', name: 'הלל', phone: '0522010344', role: 'מנהל'),
    ],
  );
  final day2 = buildStage(
    id: 's2',
    eventId: 'old',
    title: 'סיכום',
    date: DateTime(2026, 10, 6),
  );
  final kept = buildTask(
    id: 't1',
    eventId: 'old',
    stageId: 's1',
    title: 'חלוקת ערכות',
    description: 'בכניסה',
    assemblyTime: '07:45',
    assigneeIds: const ['m1', 'gone'],
    isComplete: true,
    subtasks: const [Subtask(id: 'x', title: 'תגים', isDone: true)],
  );
  final orphan = buildTask(
    id: 't2',
    eventId: 'old',
    stageId: 's2',
    title: 'פירוק',
    assigneeIds: const ['gone'],
  );
  final source = EventTaskBoard(
    event: oldEvent,
    stages: [day1, day2],
    tasks: [kept, orphan],
  );

  var counter = 0;
  String newId() => 'id${counter++}';

  CycleCopy copy({List<DateTime>? days}) {
    counter = 0;
    return copyCycle(
      source,
      target: days == null
          ? newEvent
          : buildEvent(id: 'new', startDate: days.first, endDate: days.last),
      members: [dana, yoav],
      currentUser: boss,
      now: now,
      newId: newId,
    );
  }

  test('stages keep their day in the event, with every detail', () {
    final result = copy();
    expect(result.stages, hasLength(2));
    final first = result.stages[0].stage;
    expect(first.eventId, 'new');
    expect(first.date, DateTime(2026, 11, 12));
    expect(first.title, 'קליטה');
    expect(first.startTime, '08:00');
    expect(first.endTime, '09:00');
    expect(first.hotelLocation, 'לובי');
    expect(first.notes, 'להגיע מוקדם');
    expect(first.requirements, 'שולחן');
    expect(first.contacts.single.name, 'הלל');
    expect(first.contacts.single.phone, '0522010344');
    expect(first.contacts.single.id, isNot('c1'));
    expect(first.id, isNot('s1'));
    expect(result.stages[1].stage.date, DateTime(2026, 11, 13));
    expect(result.movedToLastDay, 0);
  });

  test('tasks are copied fresh: new ids, nothing done, same content', () {
    final task = copy().stages[0].tasks.single;
    expect(task.id, isNot('t1'));
    expect(task.eventId, 'new');
    expect(task.stageId, copy().stages[0].stage.id);
    expect(task.title, 'חלוקת ערכות');
    expect(task.description, 'בכניסה');
    expect(task.assemblyTime, '07:45');
    expect(task.isComplete, isFalse);
    expect(task.subtasks.single.title, 'תגים');
    expect(task.subtasks.single.isDone, isFalse);
    expect(task.subtasks.single.id, isNot('x'));
  });

  test('a task keeps the people assigned to the new event', () {
    final task = copy().stages[0].tasks.single;
    expect(task.assigneeIds, ['m1']);
    expect(task.assignees.single.name, 'דנה');
  });

  test('a task left with nobody goes to the person copying, and is listed',
      () {
    final result = copy();
    final task = result.stages[1].tasks.single;
    expect(task.assigneeIds, ['boss']);
    expect(result.givenToYou.map((t) => t.title), ['פירוק']);
  });

  test('a shorter new event puts the extra days on its last day', () {
    final result = copy(days: [DateTime(2026, 11, 12)]);
    expect(result.stages[1].stage.date, DateTime(2026, 11, 12));
    expect(result.movedToLastDay, 1);
  });

  test('sources: other active דו יומי events with stages, latest first', () {
    final older = buildEvent(id: 'older', startDate: DateTime(2026, 9, 1));
    final empty = buildEvent(id: 'empty', startDate: DateTime(2026, 10, 20));
    final other = buildEvent(
        id: 'other', startDate: DateTime(2026, 10, 25), categoryId: 'x');
    final off = buildEvent(
        id: 'off', startDate: DateTime(2026, 10, 26), isDeactivated: true);
    final sources = cycleSources(
      events: [older, oldEvent, newEvent, empty, other, off],
      stages: [
        day1,
        buildStage(id: 'so', eventId: 'older', date: DateTime(2026, 9, 1)),
        buildStage(id: 'sn', eventId: 'new', date: DateTime(2026, 11, 12)),
        buildStage(id: 'sx', eventId: 'other', date: DateTime(2026, 10, 25)),
        buildStage(id: 'sf', eventId: 'off', date: DateTime(2026, 10, 26)),
      ],
      tasks: const [],
      targetEventId: 'new',
    );
    expect(sources.map((b) => b.event.id), ['old', 'older']);
  });
}
