import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/task_item.dart';

import '../../support/sample_event.dart';
import '../../support/task_fixtures.dart';

void main() {
  List<String> ids(Iterable<TaskItem> tasks) =>
      tasks.map((task) => task.id).toList();

  // sampleNow is Tuesday 14:40.
  final done = buildTask(
      id: 'done', stage: stWorkshops, assemblyTime: '14:00', isComplete: true);
  final late = buildTask(id: 'late', stage: stLunch, assemblyTime: '13:00');
  final soon = buildTask(id: 'soon', stage: stWorkshops, assemblyTime: '15:00');
  final later =
      buildTask(id: 'later', stage: stWorkshops, assemblyTime: '15:45');
  final untimed = buildTask(id: 'untimed', stage: stWorkshops);

  test('taskProgress counts done, late, due in the half hour and the rest', () {
    final progress =
        taskProgress([done, late, soon, later, untimed], sampleNow);
    expect(progress, const TaskProgress(total: 5, done: 1, late: 1, dueSoon: 1));
    expect((progress.missing, progress.rest), (4, 2));
  });

  test('countTone takes the worst case', () {
    expect(countTone(const TaskProgress()), CountTone.none);
    expect(countTone(const TaskProgress(total: 2, done: 2)), CountTone.done);
    expect(
      countTone(const TaskProgress(total: 3, late: 1, dueSoon: 1)),
      CountTone.late,
    );
    expect(countTone(const TaskProgress(total: 3, dueSoon: 1)), CountTone.soon);
    expect(countTone(const TaskProgress(total: 3, done: 1)), CountTone.open);
  });

  test('labels', () {
    expect(missingLabel(1), '1 חסרה');
    expect(missingLabel(3), '3 חסרות');
    expect(hebrewCount(1, one: 'משימה אחת', many: 'משימות'), 'משימה אחת');
    expect(hebrewCount(4, one: 'משימה אחת', many: 'משימות'), '4 משימות');
  });

  test('lateTasks: unfinished and past due, longest overdue first', () {
    final early = buildTask(id: 'early', stage: stSetup, assemblyTime: '08:30');
    expect(ids(lateTasks([late, done, early, soon], sampleNow)), ['early', 'late']);
  });

  test('dueSoonTasks: unfinished, timed, due in the next half hour, soonest first',
      () {
    final sooner =
        buildTask(id: 'sooner', stage: stWorkshops, assemblyTime: '14:50');
    expect(
      ids(dueSoonTasks([soon, later, untimed, sooner, late], sampleNow)),
      ['sooner', 'soon'],
    );
  });

  test('removedAssigneeIds lists assignees no longer on the event, deleted members too',
      () {
    expect(
      removedAssigneeIds(
        buildTask(assigneeIds: const ['m1', 'm2', 'gone']),
        {'m1'},
      ),
      ['m2', 'gone'],
    );
  });

  test('tasksWithRemovedAssignees keeps the tasks that have any', () {
    final ok = buildTask(id: 'ok', assigneeIds: const ['m1']);
    final off = buildTask(id: 'off', assigneeIds: const ['m1', 'm2']);
    expect(ids(tasksWithRemovedAssignees([ok, off], {'m1'})), ['off']);
  });

  test('heldRows keeps the rows already shown, live and in order, and drops deleted ones',
      () {
    final a = buildTask(id: 'a', stage: stWorkshops, assemblyTime: '15:00');
    final b = buildTask(
        id: 'b', stage: stWorkshops, assemblyTime: '14:45', isComplete: true);
    final c = buildTask(id: 'c', stage: stWorkshops, assemblyTime: '16:00');
    expect(
      heldRows(matching: [a], heldIds: {'a', 'b', 'gone'}, all: [a, b, c]),
      [b, a],
    );
  });

  test('eventTaskBoard keeps this event\'s stages and the tasks whose stage exists',
      () {
    final other = buildStage(id: 'other', eventId: 'e2');
    final board = eventTaskBoard(
      sampleEvent,
      stages: [stWorkshops, other, stSetup],
      tasks: [
        buildTask(id: 'in', stage: stWorkshops, assemblyTime: '15:00'),
        buildTask(id: 'orphan', stageId: 'gone'),
        buildTask(id: 'elsewhere', eventId: 'e2', stage: other),
      ],
    );
    expect(board.stages.map((stage) => stage.id), ['setup', 'ws']);
    expect(ids(board.tasks), ['in']);
    expect(ids(board.tasksOf('ws')), ['in']);
    expect(board.stageById('other'), isNull);
    expect(board.taskById('in')!.id, 'in');
  });
}
