import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_utils.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_item.dart';

import '../../support/sample_event.dart';
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

    test('the query matches an assignee\'s name', () {
      final named = buildTask(
        id: 'named',
        title: 'סידור כיסאות',
        assigneeIds: const ['m2'],
        assignees: [buildMember(id: 'm2', name: 'יואב כהן')],
      );
      expect(ids(filterTasks([bus, named], now: now, query: 'יואב')), ['named']);
    });

    test('the query no longer matches the event name', () {
      expect(filterTasks(all, now: now, query: 'דרום'), isEmpty);
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
    });

    group('the open status', () {
      List<String> open(List<TaskItem> tasks) => ids(filterTasks(
            tasks,
            now: now,
            statuses: {TaskDueStatus.open},
          ));

      test('keeps an unfinished task with no due date', () {
        expect(open([buildTask(id: 'undated')]), ['undated']);
      });

      test('keeps an unfinished task due on a later day', () {
        expect(
          open([buildTask(id: 'next', dueAt: DateTime(2026, 10, 12, 9))]),
          ['next'],
        );
      });

      test('keeps an unfinished task due later today', () {
        expect(
          open([buildTask(id: 'tonight', dueAt: DateTime(2026, 10, 11, 20))]),
          ['tonight'],
        );
      });

      test('keeps an unfinished task due exactly now', () {
        expect(
          open([buildTask(id: 'now', dueAt: DateTime(2026, 10, 11, 14, 0))]),
          ['now'],
        );
      });

      test('drops a task whose due time passed a minute ago', () {
        expect(
          open([buildTask(id: 'late', dueAt: DateTime(2026, 10, 11, 13, 59))]),
          isEmpty,
        );
      });

      test('drops a completed task, even one that was not due yet', () {
        expect(
          open([
            buildTask(id: 'done', isComplete: true),
            buildTask(
              id: 'done-early',
              isComplete: true,
              dueAt: DateTime(2026, 10, 12, 9),
            ),
          ]),
          isEmpty,
        );
      });

      test('the due-today status alone still leaves out tasks due later', () {
        expect(
          ids(filterTasks(
            [
              buildTask(id: 'tonight', dueAt: DateTime(2026, 10, 11, 20)),
              buildTask(id: 'next', dueAt: DateTime(2026, 10, 12, 9)),
              buildTask(id: 'undated'),
            ],
            now: now,
            statuses: {TaskDueStatus.dueToday},
          )),
          ['tonight'],
        );
      });
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
          statuses: {TaskDueStatus.completed},
        )),
        ['done'],
      );
    });

    group('dueWithin', () {
      TaskItem dueAt(String id, DateTime? due, {bool isComplete = false}) =>
          buildTask(id: id, dueAt: due, isComplete: isComplete);

      List<String> soon(List<TaskItem> tasks) => ids(filterTasks(
            tasks,
            now: now,
            dueWithin: const Duration(minutes: 30),
          ));

      test('keeps a task due inside the window', () {
        expect(soon([dueAt('in10', DateTime(2026, 10, 11, 14, 10))]), ['in10']);
      });

      test('keeps a task due exactly now and one due exactly at the end', () {
        expect(
          soon([
            dueAt('now', DateTime(2026, 10, 11, 14, 0)),
            dueAt('edge', DateTime(2026, 10, 11, 14, 30)),
          ]),
          ['now', 'edge'],
        );
      });

      test('drops a task due a minute after the window', () {
        expect(soon([dueAt('in31', DateTime(2026, 10, 11, 14, 31))]), isEmpty);
      });

      test('drops a task that is already overdue', () {
        expect(soon([dueAt('late', DateTime(2026, 10, 11, 13, 59))]), isEmpty);
      });

      test('drops a task with no due date', () {
        expect(soon([dueAt('undated', null)]), isEmpty);
      });

      test('drops a completed task even when it was due inside the window',
          () {
        expect(
          soon([
            dueAt('done', DateTime(2026, 10, 11, 14, 10), isComplete: true),
          ]),
          isEmpty,
        );
      });

      test('drops a task with no assembly time, even when its day ends inside '
          'the window', () {
        final lateEvening = DateTime(2026, 10, 11, 23, 45);
        final untimed = buildTask(
          id: 'untimed',
          stage: buildStage(date: DateTime(2026, 10, 11)),
        );
        // Due at 23:59 for the colours, but with no time it is never "soon".
        expect(untimed.dueAt, DateTime(2026, 10, 11, 23, 59));
        expect(
          ids(filterTasks(
            [untimed],
            now: lateEvening,
            dueWithin: const Duration(minutes: 30),
          )),
          isEmpty,
        );
      });

      test('no window is no restriction', () {
        expect(
          ids(filterTasks(
            [dueAt('in31', DateTime(2026, 10, 11, 14, 31))],
            now: now,
          )),
          ['in31'],
        );
      });
    });
  });

  group('assignableTaskMembers', () {
    final dana = buildMember(id: 'm1', name: 'דנה');
    final avi = buildMember(id: 'm2', name: 'אבי');
    final inactive = buildMember(id: 'm3', name: 'גיל', isActive: false);
    final archived = buildMember(id: 'm4', name: 'הדס', isArchived: true);

    List<String> ids(Iterable<dynamic> members) =>
        members.map((member) => member.id as String).toList();

    test('offers active, non-archived members by name', () {
      final offered = assignableTaskMembers([dana, inactive, archived, avi]);
      expect(ids(offered), ['m2', 'm1']);
    });
  });

  group('isValidDueTime', () {
    test('accepts a complete 24-hour time', () {
      expect(isValidDueTime('00:00'), isTrue);
      expect(isValidDueTime('09:30'), isTrue);
      expect(isValidDueTime('23:59'), isTrue);
    });

    test('rejects an impossible or unfinished time', () {
      for (final time in ['93:00', '24:00', '12:60', '9', '18', '9:30', 'ab:cd', '']) {
        expect(isValidDueTime(time), isFalse, reason: time);
      }
    });
  });

  group('isDueSoon', () {
    // sampleNow is Tuesday 14:40; stWorkshops is on that Tuesday.
    TaskItem at(String time, {bool isComplete = false}) => buildTask(
          stage: stWorkshops,
          assemblyTime: time,
          isComplete: isComplete,
        );

    test('covers now through half an hour from now', () {
      expect(isDueSoon(at('14:40'), sampleNow), isTrue);
      expect(isDueSoon(at('15:10'), sampleNow), isTrue);
      expect(isDueSoon(at('15:11'), sampleNow), isFalse);
    });

    test('never a task without a report time, or a done one', () {
      expect(isDueSoon(buildTask(stage: stWorkshops), sampleNow), isFalse);
      expect(isDueSoon(at('14:50', isComplete: true), sampleNow), isFalse);
    });
  });

  group('minutesOfDay', () {
    test('counts the minutes since midnight', () {
      expect(minutesOfDay('09:30'), 570);
      expect(minutesOfDay('00:00'), 0);
    });

    test('is null for anything but a complete 24-hour time', () {
      for (final time in ['9:30', '24:00', '']) {
        expect(minutesOfDay(time), isNull, reason: time);
      }
      expect(minutesOfDay(null), isNull);
    });
  });

  group('sortTasks', () {
    test('orders by due date, earliest first and undated last', () {
      final tasks = [
        buildTask(id: 'undated'),
        buildTask(id: 'later', dueAt: DateTime(2026, 10, 20, 9)),
        buildTask(id: 'overdue', dueAt: DateTime(2026, 10, 9, 9)),
        buildTask(id: 'sooner', dueAt: DateTime(2026, 10, 13, 9)),
      ];
      expect(
        sortTasks(tasks).map((task) => task.id).toList(),
        ['overdue', 'sooner', 'later', 'undated'],
      );
    });

    test('a completed task keeps its place by due date', () {
      final tasks = [
        buildTask(id: 'third', dueAt: DateTime(2026, 10, 13, 12)),
        buildTask(
          id: 'second',
          dueAt: DateTime(2026, 10, 13, 10),
          isComplete: true,
          completedAt: DateTime(2026, 10, 11, 9),
        ),
        buildTask(id: 'first', dueAt: DateTime(2026, 10, 13, 8)),
      ];
      expect(
        sortTasks(tasks).map((task) => task.id).toList(),
        ['first', 'second', 'third'],
      );
    });

    test('ties fall back to the title so the order is stable', () {
      final tasks = [
        buildTask(id: 'b', title: 'בדיקה'),
        buildTask(id: 'a', title: 'אישור'),
      ];
      expect(
        sortTasks(tasks).map((task) => task.id).toList(),
        ['a', 'b'],
      );
    });

    test('does not mutate the list it was given', () {
      final tasks = [
        buildTask(id: 'completed', isComplete: true),
        buildTask(id: 'open'),
      ];
      sortTasks(tasks);
      expect(tasks.map((task) => task.id).toList(), ['completed', 'open']);
    });
  });

  group('sortStages', () {
    test('orders by day, then start time with untimed first, then title', () {
      final stages = [
        buildStage(id: 'dinner', title: 'ערב', date: DateTime(2026, 10, 21), startTime: '19:00'),
        buildStage(id: 'day2', title: 'בוקר', date: DateTime(2026, 10, 22), startTime: '07:00'),
        buildStage(id: 'arrive', title: 'קליטה', date: DateTime(2026, 10, 21), startTime: '08:00'),
        buildStage(id: 'note-b', title: 'ב', date: DateTime(2026, 10, 21)),
        buildStage(id: 'note-a', title: 'א', date: DateTime(2026, 10, 21)),
      ];

      expect(
        sortStages(stages).map((stage) => stage.id),
        ['note-a', 'note-b', 'arrive', 'dinner', 'day2'],
      );
    });

    test('does not change the list it was given', () {
      final stages = [
        buildStage(id: 'b', date: DateTime(2026, 10, 22)),
        buildStage(id: 'a', date: DateTime(2026, 10, 21)),
      ];
      sortStages(stages);
      expect(stages.map((stage) => stage.id), ['b', 'a']);
    });
  });

  group('stagesToShow', () {
    final arrival = buildStage(id: 'arrive', title: 'קליטה', date: DateTime(2026, 10, 21));
    final dinner = buildStage(id: 'dinner', title: 'ערב', date: DateTime(2026, 10, 21), startTime: '19:00');
    final empty = buildStage(id: 'empty', title: 'ריק', date: DateTime(2026, 10, 22));

    final mine = buildTask(id: 'mine', stage: arrival, assigneeIds: const ['m1']);
    final theirs = buildTask(id: 'theirs', stage: dinner, assigneeIds: const ['m2']);

    List<String> shown(List<StageTasks> groups) =>
        [for (final group in groups) '${group.stage.id}:${group.tasks.map((t) => t.id).join(',')}'];

    test('all tasks with nothing narrowing shows every stage, empty ones too', () {
      final groups = stagesToShow(
        stages: [empty, dinner, arrival],
        visibleTasks: [mine, theirs],
        showEveryStage: true,
      );
      expect(shown(groups), ['arrive:mine', 'dinner:theirs', 'empty:']);
    });

    test('otherwise only stages with a visible task show', () {
      final groups = stagesToShow(
        stages: [empty, dinner, arrival],
        visibleTasks: [mine],
        showEveryStage: false,
      );
      expect(shown(groups), ['arrive:mine']);
    });

    test('a visible task whose stage is not among the stages is left out', () {
      final stray = buildTask(id: 'stray', stage: buildStage(id: 'gone'));
      final groups = stagesToShow(
        stages: [arrival],
        visibleTasks: [stray],
        showEveryStage: false,
      );
      expect(groups, isEmpty);
    });
  });

  group('eventDays', () {
    test('lists every day of a multi-day event', () {
      final event = buildEvent(
        startDate: DateTime(2026, 10, 30),
        endDate: DateTime(2026, 11, 1),
      );
      expect(eventDays(event), [
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
      ]);
    });

    test('a one-day event has one day', () {
      final event = buildEvent(startDate: DateTime(2026, 10, 30));
      expect(eventDays(event), [DateTime(2026, 10, 30)]);
    });

    test('ignores the time of day on the stored dates', () {
      final event = buildEvent(
        startDate: DateTime(2026, 10, 30, 21),
        endDate: DateTime(2026, 10, 31, 3),
      );
      expect(eventDays(event), [DateTime(2026, 10, 30), DateTime(2026, 10, 31)]);
    });

    test('an end before the start is a one-day event', () {
      final event = buildEvent(
        startDate: DateTime(2026, 10, 30),
        endDate: DateTime(2026, 10, 20),
      );
      expect(eventDays(event), [DateTime(2026, 10, 30)]);
    });
  });

  group('taskEvents', () {
    final upcoming = buildEvent(id: 'up', startDate: DateTime(2026, 10, 20));
    final later = buildEvent(id: 'later', startDate: DateTime(2026, 11, 3));
    final running = buildEvent(
      id: 'running',
      startDate: DateTime(2026, 10, 10),
      endDate: DateTime(2026, 10, 12),
    );
    final past = buildEvent(id: 'past', startDate: DateTime(2026, 9, 1));
    final older = buildEvent(id: 'older', startDate: DateTime(2026, 8, 1));
    final onHold = buildEvent(id: 'hold', startDate: DateTime(2026, 10, 25), isDeactivated: true);
    final otherCategory = buildEvent(
      id: 'other',
      startDate: DateTime(2026, 10, 26),
      categoryId: '6de41bf3-1a22-476d-b922-ec35ede6bc9f',
    );

    test('splits active דו יומי events into upcoming, nearest first, and past, '
        'latest first', () {
      final split = taskEvents(
        [past, later, onHold, upcoming, older, otherCategory, running],
        now: now,
      );
      expect(split.upcoming.map((event) => event.id), ['running', 'up', 'later']);
      expect(split.past.map((event) => event.id), ['past', 'older']);
    });
  });

  group('summarizeTaskEvent', () {
    test('counts the stages, the open tasks and the member\'s open tasks', () {
      final board = [
        buildTask(id: 'a', eventId: 'e1', stageId: 's1', assigneeIds: const ['m1']),
        buildTask(id: 'b', eventId: 'e1', stageId: 's1', assigneeIds: const ['m2']),
        buildTask(id: 'c', eventId: 'e1', stageId: 's1', assigneeIds: const ['m1'], isComplete: true),
        buildTask(id: 'd', eventId: 'e2', assigneeIds: const ['m1']),
      ];
      final stages = [
        buildStage(id: 's1', eventId: 'e1'),
        buildStage(id: 's2', eventId: 'e1'),
        buildStage(id: 's3', eventId: 'e2'),
      ];

      final summary = summarizeTaskEvent(
        'e1',
        tasks: board,
        stages: stages,
        memberId: 'm1',
      );

      expect(summary.stageCount, 2);
      expect(summary.openTaskCount, 2);
      expect(summary.myOpenTaskCount, 1);
    });

    test('leaves out tasks whose stage is gone, as the event screen does', () {
      final summary = summarizeTaskEvent(
        'e1',
        tasks: [
          buildTask(id: 'a', eventId: 'e1', stageId: 's1'),
          // Saved before stages existed, or left behind by a deleted stage.
          buildTask(id: 'old', eventId: 'e1', stageId: ''),
          buildTask(id: 'orphan', eventId: 'e1', stageId: 'gone'),
        ],
        stages: [buildStage(id: 's1', eventId: 'e1')],
        memberId: 'm1',
      );

      expect(summary.openTaskCount, 1);
      expect(summary.myOpenTaskCount, 1);
    });
  });

  group('StageContact', () {
    test('two contacts with the same fields are equal', () {
      expect(
        const StageContact(id: 'c1', name: 'אבי'),
        const StageContact(id: 'c1', name: 'אבי'),
      );
    });
  });
}
