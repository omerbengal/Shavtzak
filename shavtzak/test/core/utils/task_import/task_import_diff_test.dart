import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/task_import_diff.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/core/utils/task_import/task_import_template.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/imported_stage.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';

import '../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 21),
  );
  final dana = buildMember(id: 'm1', name: 'דנה');
  final omer = buildMember(id: 'm2', name: 'עומר');

  EventTaskBoard board(List<Stage> stages, List<TaskItem> tasks) =>
      eventTaskBoard(event, stages: stages, tasks: tasks);

  // The file side: fresh ids, as the parser hands them out.
  var counter = 0;
  String fresh() => 'new-${counter++}';
  Stage fileStage(String title, {String? startTime, String notes = ''}) =>
      buildStage(id: fresh(), title: title, startTime: startTime, notes: notes);
  TaskItem fileTask(
    Stage stage,
    String title, {
    List<String> subtasks = const [],
    List<String> assigneeIds = const ['m1'],
    String description = '',
  }) =>
      buildTask(
        id: fresh(),
        stage: stage,
        title: title,
        description: description,
        assigneeIds: assigneeIds,
        assignees: [
          for (final id in assigneeIds) id == 'm1' ? dana : omer,
        ],
        subtasks: [
          for (final title in subtasks) Subtask(id: fresh(), title: title),
        ],
      );

  test('the same content is no change', () {
    final stage = buildStage(id: 's1', title: 'קליטה', startTime: '09:00');
    final task = buildTask(
      id: 't1',
      stage: stage,
      title: 'הקמת עמדה',
      assignees: [dana],
      subtasks: const [Subtask(id: 'a', title: 'מדפסת', isDone: true)],
    );
    final s = fileStage('קליטה', startTime: '09:00');
    final diff = diffTaskImport(board([stage], [task]), [
      ImportedStage(stage: s, tasks: [
        fileTask(s, ' הקמת  עמדה ', subtasks: ['מדפסת'])
      ]),
    ]);
    expect(diff.hasChanges, isFalse);
    expect(diff.stages.single.kind, ChangeKind.unchanged);
  });

  test('an exported board read back is no change', () {
    final s1 = buildStage(id: 's1', title: 'קליטה', startTime: '09:00');
    final s2 = buildStage(id: 's2', title: 'קליטה', startTime: '12:00');
    final current = board([s1, s2], [
      buildTask(
        id: 't1',
        stage: s1,
        title: 'הקמת עמדה',
        assigneeIds: const ['m1', 'm2'],
        assignees: [dana, omer],
        assemblyTime: '08:30',
        subtasks: const [
          Subtask(id: 'a', title: 'מדפסת', isDone: true),
          Subtask(id: 'b', title: 'תגים'),
        ],
      ),
      buildTask(id: 't2', stage: s2, title: 'סגירה', assignees: [dana]),
    ]);
    final parsed = parseTaskImport(
      buildTaskExport(current),
      event: event,
      candidates: [dana, omer],
      currentUserId: 'boss',
      now: DateTime(2026, 10, 1),
    );
    expect(parsed.problems, isEmpty);
    final diff = diffTaskImport(current, parsed.stages);
    expect(diff.hasChanges, isFalse, reason: '${diff.plan}');
  });

  test('adds, removes and changes, keeping ids and progress', () {
    final s1 = buildStage(id: 's1', title: 'קליטה');
    final s2 = buildStage(id: 's2', title: 'ארוחת ערב');
    final kept = buildTask(
      id: 't1',
      stage: s1,
      title: 'הקמת עמדה',
      assignees: [dana],
      assigneeUpdate: 'בדרך',
      subtasks: const [
        Subtask(id: 'a', title: 'מדפסת', isDone: true),
        Subtask(id: 'b', title: 'תגים', isDone: true),
      ],
    );
    final dropped = buildTask(
      id: 't2',
      stage: s1,
      title: 'ישנה',
      isComplete: true,
      assignees: [dana],
    );
    final dinnerTask = buildTask(id: 't3', stage: s2, title: 'הזמנה');

    final f1 = fileStage('קליטה', notes: 'חדש');
    final f3 = fileStage('לילה');
    final diff = diffTaskImport(board([s1, s2], [kept, dropped, dinnerTask]), [
      ImportedStage(stage: f1, tasks: [
        fileTask(f1, 'הקמת עמדה',
            subtasks: ['מדפסת', 'שלטים'], assigneeIds: ['m1', 'm2']),
        fileTask(f1, 'חדשה'),
      ]),
      ImportedStage(stage: f3, tasks: [fileTask(f3, 'סיור')]),
    ]);

    final plan = diff.plan;
    expect(plan.stagesToUpdate.single.id, 's1');
    expect(plan.stagesToUpdate.single.notes, 'חדש');
    expect(plan.stagesToCreate.single.title, 'לילה');
    expect(plan.stageIdsToDelete, ['s2']);
    expect(plan.taskIdsToDelete, unorderedEquals(['t2', 't3']));
    expect(plan.tasksToCreate.map((t) => t.title), ['חדשה', 'סיור']);
    expect(plan.tasksToCreate.last.stageId, f3.id);
    expect(plan.tasksToCreate.first.stageId, 's1');

    final updated = plan.tasksToUpdate.single;
    expect(updated.id, 't1');
    expect(updated.assigneeIds, ['m1', 'm2']);
    expect(updated.assigneeUpdate, 'בדרך');
    // The kept subtask keeps its id and tick; the new one is fresh.
    expect(updated.subtasks.first, const Subtask(id: 'a', title: 'מדפסת', isDone: true));
    expect(updated.subtasks.last.title, 'שלטים');
    expect(updated.subtasks.last.isDone, isFalse);

    final change = diff.stages
        .expand((s) => s.tasks)
        .firstWhere((t) => t.before?.id == 't1');
    expect(change.addedSubtasks, ['שלטים']);
    expect(change.removedSubtasks.single.title, 'תגים');
    expect(change.lostProgress, ['תת המשימה "תגים" סומנה']);

    final removed = diff.stages
        .expand((s) => s.tasks)
        .firstWhere((t) => t.before?.id == 't2');
    expect(removed.kind, ChangeKind.removed);
    expect(removed.lostProgress, ['המשימה סומנה כבוצעה']);

    expect(diff.stageCount(ChangeKind.added), 1);
    expect(diff.stageCount(ChangeKind.removed), 1);
    expect(diff.stageCount(ChangeKind.changed), 1);
    expect(diff.taskCount(ChangeKind.added), 2);
    expect(diff.taskCount(ChangeKind.removed), 2);
    expect(diff.taskCount(ChangeKind.changed), 1);
    expect(diff.lostProgressCount, 2);
    // The removed stage comes last, with its task under it.
    expect(diff.stages.last.kind, ChangeKind.removed);
    expect(diff.stages.last.tasks.single.before?.id, 't3');
  });

  test('a task under another stage in the file moves, keeping its state', () {
    final s1 = buildStage(id: 's1', title: 'קליטה');
    final s2 = buildStage(id: 's2', title: 'ארוחה');
    final task = buildTask(
      id: 't1',
      stage: s1,
      title: 'שלטים',
      isComplete: true,
      assignees: [dana],
    );
    final f1 = fileStage('קליטה');
    final f2 = fileStage('ארוחה');
    final diff = diffTaskImport(board([s1, s2], [task]), [
      ImportedStage(stage: f1, tasks: const []),
      ImportedStage(stage: f2, tasks: [fileTask(f2, 'שלטים')]),
    ]);
    final moved = diff.plan.tasksToUpdate.single;
    expect(moved.id, 't1');
    expect(moved.stageId, 's2');
    expect(moved.isComplete, isTrue);
    expect(diff.plan.taskIdsToDelete, isEmpty);
    expect(diff.movedTaskCount, 1);
    final change = diff.stages.expand((s) => s.tasks).single;
    expect(change.movedFrom, 'קליטה');
    expect(change.lostProgress, isEmpty);
  });

  test('a renamed stage is a new stage, and its tasks move into it', () {
    final s1 = buildStage(id: 's1', title: 'קליטה');
    final task = buildTask(id: 't1', stage: s1, title: 'שלטים', assignees: [dana]);
    final f = fileStage('קבלת פנים');
    final diff = diffTaskImport(board([s1], [task]), [
      ImportedStage(stage: f, tasks: [fileTask(f, 'שלטים')]),
    ]);
    expect(diff.plan.stagesToCreate.single.id, f.id);
    expect(diff.plan.stageIdsToDelete, ['s1']);
    expect(diff.plan.tasksToUpdate.single.stageId, f.id);
    expect(diff.plan.taskIdsToDelete, isEmpty);
  });

  test('a repeated stage title matches by the export\'s " (2)" name', () {
    final a = buildStage(id: 'sa', title: 'ארוחה', startTime: '08:00');
    final b = buildStage(id: 'sb', title: 'ארוחה', startTime: '19:00');
    final fa = fileStage('ארוחה', startTime: '08:00');
    final fb = fileStage('ארוחה (2)', startTime: '20:00');
    final diff = diffTaskImport(board([a, b], const []), [
      ImportedStage(stage: fa, tasks: const []),
      ImportedStage(stage: fb, tasks: const []),
    ]);
    final updated = diff.plan.stagesToUpdate.single;
    expect(updated.id, 'sb');
    expect(updated.title, 'ארוחה', reason: 'the " (2)" is not saved');
    expect(updated.startTime, '20:00');
    expect(diff.plan.stagesToCreate, isEmpty);
  });

  test('repeated task titles pair up in order', () {
    final s = buildStage(id: 's1', title: 'קליטה');
    final first = buildTask(id: 't1', stage: s, title: 'בדיקה', assignees: [dana]);
    final second = buildTask(
      id: 't2',
      stage: s,
      title: 'בדיקה',
      description: 'שנייה',
      assignees: [dana],
    );
    final f = fileStage('קליטה');
    final diff = diffTaskImport(board([s], [first, second]), [
      ImportedStage(stage: f, tasks: [fileTask(f, 'בדיקה')]),
    ]);
    expect(diff.plan.taskIdsToDelete.length, 1);
    expect(diff.plan.tasksToCreate, isEmpty);
  });

  test('a stage field change lists before and after', () {
    final s = buildStage(id: 's1', title: 'קליטה', startTime: '09:00');
    final f = fileStage('קליטה', startTime: '10:00');
    final diff = diffTaskImport(board([s], const []), [
      ImportedStage(stage: f, tasks: const []),
    ]);
    expect(
      diff.stages.single.fields,
      [const FieldChange(StageColumns.start, '09:00', '10:00')],
    );
  });

  test('contacts keep their ids by name, so the same list is no change', () {
    final s = buildStage(
      id: 's1',
      contacts: const [StageContact(id: 'c1', name: 'יוסי', phone: '050')],
    );
    final f = buildStage(
      id: 'new-s',
      contacts: const [StageContact(id: 'c9', name: 'יוסי', phone: '050')],
    );
    final diff = diffTaskImport(board([s], const []), [
      ImportedStage(stage: f, tasks: const []),
    ]);
    expect(diff.hasChanges, isFalse);
  });
}
