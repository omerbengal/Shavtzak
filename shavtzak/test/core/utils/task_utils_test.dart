import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_utils.dart';
import 'package:shavtzak/domain/entities/task_item.dart';

import '../../support/task_fixtures.dart';

void main() {
  // A Sunday afternoon. Every "today" below is 2026-10-11.
  final now = DateTime(2026, 10, 11, 14, 0);

  group('taskDueStatus', () {
    test('a task due one minute ago is overdue', () {
      final task = buildTask(dueAt: DateTime(2026, 10, 11, 13, 59));
      expect(taskDueStatus(task, now), TaskDueStatus.overdue);
    });

    test('a task due later today is due today', () {
      final task = buildTask(dueAt: DateTime(2026, 10, 11, 14, 1));
      expect(taskDueStatus(task, now), TaskDueStatus.dueToday);
    });

    test('a task due at the last minute of today is due today', () {
      final task = buildTask(dueAt: DateTime(2026, 10, 11, 23, 59));
      expect(taskDueStatus(task, now), TaskDueStatus.dueToday);
    });

    test('a task due exactly now is due today, not overdue', () {
      final task = buildTask(dueAt: now);
      expect(taskDueStatus(task, now), TaskDueStatus.dueToday);
    });

    test('a task due at midnight tonight belongs to tomorrow', () {
      final task = buildTask(dueAt: DateTime(2026, 10, 12));
      expect(taskDueStatus(task, now), TaskDueStatus.open);
    });

    test('a task due yesterday is overdue', () {
      final task = buildTask(dueAt: DateTime(2026, 10, 10, 23, 59));
      expect(taskDueStatus(task, now), TaskDueStatus.overdue);
    });

    test('a task with no due date is open', () {
      expect(taskDueStatus(buildTask(), now), TaskDueStatus.open);
    });

    test('completed wins over a passed due date', () {
      final task = buildTask(
        isComplete: true,
        dueAt: DateTime(2026, 10, 1, 8),
      );
      expect(taskDueStatus(task, now), TaskDueStatus.completed);
    });
  });

  group('permissions', () {
    final task = buildTask(assigneeIds: const ['m1']);

    test('an admin and a flagged member manage tasks', () {
      expect(canManageTasks(buildMember(isAdmin: true)), isTrue);
      expect(canManageTasks(buildMember(canManageTasks: true)), isTrue);
      expect(canManageTasks(buildMember()), isFalse);
    });

    test('an assignee can update progress on their own task', () {
      expect(canUpdateTaskProgress(task, buildMember(id: 'm1')), isTrue);
    });

    test('a manager can update progress on any task', () {
      final manager = buildMember(id: 'm7', canManageTasks: true);
      expect(canUpdateTaskProgress(task, manager), isTrue);
    });

    test('an unrelated member cannot update progress', () {
      expect(canUpdateTaskProgress(task, buildMember(id: 'm9')), isFalse);
    });
  });

  group('filterTasks', () {
    final bus = buildTask(
      id: 'bus',
      title: 'להזמין אוטובוס',
      description: 'שני רכבים',
      eventId: 'e1',
      event: buildEvent(id: 'e1', name: 'דו יומי צפון'),
      assigneeIds: const ['m1'],
      dueAt: DateTime(2026, 10, 10, 9), // overdue
    );
    final food = buildTask(
      id: 'food',
      title: "הזמנת קייטרינג ג'חנון",
      eventId: 'e2',
      event: buildEvent(id: 'e2', name: 'דו יומי דרום'),
      assigneeIds: const ['m2', 'm3'],
      dueAt: DateTime(2026, 10, 11, 20), // due today
    );
    final done = buildTask(
      id: 'done',
      title: 'אישור ביטחוני',
      eventId: 'e1',
      event: buildEvent(id: 'e1', name: 'דו יומי צפון'),
      assigneeIds: const ['m1', 'm2'],
      isComplete: true,
    );
    final orphan = buildTask(
      id: 'orphan',
      title: 'משימה יתומה',
      eventId: 'gone',
      assigneeIds: const ['m3'],
    );
    final all = [bus, food, done, orphan];

    List<String> ids(List<TaskItem> tasks) =>
        tasks.map((task) => task.id).toList();

    test('no restriction returns everything, including a task whose event is missing', () {
      expect(ids(filterTasks(all, now: now)), ['bus', 'food', 'done', 'orphan']);
    });

    test('onlyAssigneeId keeps only that member\'s tasks', () {
      expect(ids(filterTasks(all, now: now, onlyAssigneeId: 'm1')), ['bus', 'done']);
    });

    test('the query matches the title', () {
      expect(ids(filterTasks(all, now: now, query: 'אוטובוס')), ['bus']);
    });

    test('the query matches the description', () {
      expect(ids(filterTasks(all, now: now, query: 'רכבים')), ['bus']);
    });

    test('the query matches the event name', () {
      expect(ids(filterTasks(all, now: now, query: 'דרום')), ['food']);
    });

    test('the query ignores punctuation such as a geresh', () {
      expect(ids(filterTasks(all, now: now, query: 'גחנון')), ['food']);
    });

    test('a blank query is no restriction', () {
      expect(filterTasks(all, now: now, query: '   '), hasLength(4));
    });

    test('statuses keeps only tasks in one of the chosen statuses', () {
      expect(
        ids(filterTasks(all, now: now, statuses: {TaskDueStatus.overdue})),
        ['bus'],
      );
      expect(
        ids(filterTasks(
          all,
          now: now,
          statuses: {TaskDueStatus.dueToday, TaskDueStatus.completed},
        )),
        ['food', 'done'],
      );
      expect(
        ids(filterTasks(all, now: now, statuses: {TaskDueStatus.open})),
        ['orphan'],
      );
    });

    test('eventIds keeps only tasks of the chosen events', () {
      expect(ids(filterTasks(all, now: now, eventIds: {'e1'})), ['bus', 'done']);
    });

    test('a task whose event is missing drops out of a filter for another event', () {
      expect(ids(filterTasks(all, now: now, eventIds: {'e2'})), ['food']);
    });

    test('assigneeIds keeps tasks assigned to any chosen member', () {
      expect(
        ids(filterTasks(all, now: now, assigneeIds: {'m3'})),
        ['food', 'orphan'],
      );
    });

    test('restrictions combine with AND', () {
      expect(
        ids(filterTasks(
          all,
          now: now,
          onlyAssigneeId: 'm1',
          eventIds: {'e1'},
          statuses: {TaskDueStatus.completed},
        )),
        ['done'],
      );
    });
  });

  group('sortTasks', () {
    test('orders overdue, due today, open, then completed', () {
      final tasks = [
        buildTask(id: 'completed', isComplete: true),
        buildTask(id: 'open', dueAt: DateTime(2026, 10, 15, 9)),
        buildTask(id: 'today', dueAt: DateTime(2026, 10, 11, 18)),
        buildTask(id: 'overdue', dueAt: DateTime(2026, 10, 9, 9)),
      ];
      expect(
        sortTasks(tasks, now).map((task) => task.id).toList(),
        ['overdue', 'today', 'open', 'completed'],
      );
    });

    test('within a status the earliest due date comes first and undated last', () {
      final tasks = [
        buildTask(id: 'undated'),
        buildTask(id: 'later', dueAt: DateTime(2026, 10, 20, 9)),
        buildTask(id: 'sooner', dueAt: DateTime(2026, 10, 13, 9)),
      ];
      expect(
        sortTasks(tasks, now).map((task) => task.id).toList(),
        ['sooner', 'later', 'undated'],
      );
    });

    test('completed tasks are ordered by most recently completed', () {
      final tasks = [
        buildTask(
          id: 'old',
          isComplete: true,
          completedAt: DateTime(2026, 10, 1),
        ),
        buildTask(
          id: 'recent',
          isComplete: true,
          completedAt: DateTime(2026, 10, 10),
        ),
      ];
      expect(
        sortTasks(tasks, now).map((task) => task.id).toList(),
        ['recent', 'old'],
      );
    });

    test('ties fall back to the title so the order is stable', () {
      final tasks = [
        buildTask(id: 'b', title: 'בדיקה'),
        buildTask(id: 'a', title: 'אישור'),
      ];
      expect(
        sortTasks(tasks, now).map((task) => task.id).toList(),
        ['a', 'b'],
      );
    });

    test('does not mutate the list it was given', () {
      final tasks = [
        buildTask(id: 'completed', isComplete: true),
        buildTask(id: 'open'),
      ];
      sortTasks(tasks, now);
      expect(tasks.map((task) => task.id).toList(), ['completed', 'open']);
    });
  });
}
