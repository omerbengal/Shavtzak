import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

import '../../../support/import_workbook.dart';
import '../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    name: 'דו יומי',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');
  final matan = buildMember(id: 'm2', name: 'מתן סלפטי');
  final now = DateTime(2026, 6, 1, 12);

  TaskImportResult parse(List<int> bytes, {List<TeamMember>? candidates}) {
    var counter = 0;
    return parseTaskImport(
      bytes,
      event: event,
      candidates: candidates ?? [omer, matan],
      currentUserId: 'boss',
      now: now,
      newId: () => 'id${++counter}',
    );
  }

  List<String> texts(TaskImportResult result) =>
      result.problems.map((problem) => problem.text).toList();

  test('reads stages and tasks, linking tasks by stage number', () {
    final result = parse(buildImportWorkbook(
      stageRows: [
        stageRow(
          number: 1,
          title: 'מוכנות עמדות',
          start: const TimeCellValue(hour: 8, minute: 30),
          end: const TimeCellValue(hour: 10),
          requirements: '• שולחנות\n• מפות',
          location: 'אולם ימים',
          notes: 'ב-09:30 מוכנים',
          contacts: 'שם: הלל, טלפון: 0522010344, תפקיד: צייר',
        ),
        stageRow(
          number: 2,
          title: 'קליטה',
          date: const DateCellValue(year: 2026, month: 6, day: 16),
        ),
      ],
      taskRows: [
        taskRow(
          number: 1,
          title: 'וידוא עמדת הקליטה',
          description: 'כולל מדפסות',
          assignees: 'עומר אליהו | סלפטי',
          assembly: const TimeCellValue(hour: 8, minute: 30),
          subtasks: 'חיבור מדפסות | סידור תגים',
        ),
        taskRow(number: 2, title: 'איוש'),
      ],
    ));

    expect(texts(result), isEmpty);
    expect(result.isValid, isTrue);
    expect(result.stages, hasLength(2));
    final first = result.stages.first;
    expect(first.stage.eventId, 'e1');
    expect(first.stage.title, 'מוכנות עמדות');
    expect(first.stage.date, DateTime(2026, 6, 15));
    expect(first.stage.startTime, '08:30');
    expect(first.stage.endTime, '10:00');
    expect(first.stage.requirements, '• שולחנות\n• מפות');
    expect(first.stage.hotelLocation, 'אולם ימים');
    expect(first.stage.notes, 'ב-09:30 מוכנים');
    expect(first.stage.contacts.single.phone, '052-2010344');
    expect(first.stage.createdById, 'boss');
    final task = first.tasks.single;
    expect(task.stageId, first.stage.id);
    expect(task.eventId, 'e1');
    expect(task.description, 'כולל מדפסות');
    expect(task.assigneeIds, ['m1', 'm2']);
    expect(task.assemblyTime, '08:30');
    expect(task.subtasks.map((s) => s.title), ['חיבור מדפסות', 'סידור תגים']);
    expect(result.stages.last.tasks.single.title, 'איוש');
    expect(result.taskCount, 2);
    expect(result.contactCount, 1);
  });

  test('headers are found by text: any order, trailing colon, invisible marks',
      () {
    final result = parse(buildImportWorkbook(
      stageHeaders: ['תאריך', 'שם\u2069', 'מספר שלב'],
      stageRows: [
        [const DateCellValue(year: 2026, month: 6, day: 15), 'קליטה', 1],
      ],
      taskHeaders: ['משימה', 'תתי משימות:', ' מספר שלב ', 'אחראי/ים'],
      taskRows: [
        ['הקמה', 'א | ב', 1, 'עומר'],
      ],
    ));
    expect(texts(result), isEmpty);
    expect(result.stages.single.tasks.single.subtasks, hasLength(2));
  });

  test('reads the official format: hints in headers, one "*" item per line',
      () {
    final result = parse(buildImportWorkbook(
      stageHeaders: StageColumns.templateHeaders,
      stageRows: [
        stageRow(
          requirements: '* שולחנות\n* מפות',
          contacts: '* שם: הלל, טלפון: 0522010344, תפקיד: צייר\n'
              '* שם:יוכי, טלפון: 050-628-5016',
        ),
      ],
      taskHeaders: TaskColumns.templateHeaders,
      taskRows: [
        taskRow(
          assignees: '* עומר אליהו\n* מתן סלפטי',
          subtasks: '* חיבור מדפסות\n* סידור תגים',
        ),
      ],
    ));

    expect(texts(result), isEmpty);
    final stage = result.stages.single;
    expect(stage.stage.requirements, '* שולחנות\n* מפות');
    expect(stage.stage.contacts.map((c) => c.name), ['הלל', 'יוכי']);
    final task = stage.tasks.single;
    expect(task.assigneeIds, ['m1', 'm2']);
    expect(task.subtasks.map((s) => s.title), ['חיבור מדפסות', 'סידור תגים']);
  });

  test('rows that are empty, spaces only, or only a stage number are skipped',
      () {
    final result = parse(buildImportWorkbook(
      stageRows: [
        stageRow(),
        stageRow(number: 3, title: null, date: null),
        stageRow(number: null, title: '   ', date: null),
      ],
    ));
    expect(texts(result), isEmpty);
    expect(result.stages, hasLength(1));
  });

  test('missing sheets and required headers are problems', () {
    expect(
      texts(parse(
          buildImportWorkbook(withTasksSheet: false, stageRows: [stageRow()]))),
      ['חסר גיליון "משימות"'],
    );
    expect(
      texts(parse(buildImportWorkbook(
          stageHeaders: ['מספר שלב', 'שם'], stageRows: [stageRow()]))),
      ['שלבים, שורה 1: חסרה עמודה "תאריך"'],
    );
  });

  test('a file that is not a workbook is one problem', () {
    expect(texts(parse([1, 2, 3])), ['הקובץ אינו קובץ אקסל תקין']);
  });

  test('stage problems name the sheet and the Excel row', () {
    final result = parse(buildImportWorkbook(stageRows: [
      stageRow(number: 1, title: null),
      stageRow(number: 1, title: 'כפול'),
      stageRow(number: 'שלב', title: 'מילה'),
      stageRow(
        number: 4,
        title: 'מחוץ',
        date: const DateCellValue(year: 2026, month: 6, day: 20),
      ),
      stageRow(number: 5, title: 'שעות', start: '10:00', end: '09:00'),
      stageRow(number: 6, title: 'סיום בלבד', end: '09:00'),
      stageRow(number: 7, title: 'שעה שבורה', start: '25:00'),
      stageRow(number: 8, title: 'ללא תאריך', date: null),
    ]));

    expect(texts(result), [
      'שלבים, שורה 2: חסר שם לשלב',
      'שלבים, שורה 3: מספר שלב 1 מופיע פעמיים (גם בשורה 2)',
      'שלבים, שורה 4: מספר השלב "שלב" אינו מספר שלם',
      'שלבים, שורה 5: התאריך 20/06/2026 אינו מתאריכי האירוע (15/06/2026 – 16/06/2026)',
      'שלבים, שורה 6: שעת הסיום חייבת להיות אחרי שעת ההתחלה',
      'שלבים, שורה 7: שעת סיום דורשת שעת התחלה',
      'שלבים, שורה 8: "שעת התחלה" אינה שעה תקינה: "25:00"',
      'שלבים, שורה 9: חסר תאריך',
    ]);
    expect(result.isValid, isFalse);
  });

  test('contact problems are prefixed with the stage row', () {
    final result = parse(buildImportWorkbook(stageRows: [
      stageRow(contacts: 'טלפון: 0501234567'),
    ]));
    expect(texts(result), ['שלבים, שורה 2: איש קשר 1: חסר שם']);
  });

  test('task problems: unknown stage, missing title, names, long text', () {
    final result = parse(buildImportWorkbook(
      stageRows: [stageRow()],
      taskRows: [
        taskRow(number: 9),
        taskRow(title: null, description: 'רק תיאור'),
        taskRow(assignees: 'יצחק דני'),
        taskRow(title: 'א' * 201),
      ],
    ));
    expect(texts(result), [
      'משימות, שורה 2: מספר שלב 9 לא קיים בגיליון "שלבים"',
      'משימות, שורה 3: חסרה כותרת למשימה',
      'משימות, שורה 4: "יצחק דני" אינו משובץ לאירוע',
      'משימות, שורה 5: הטקסט בעמודה "משימה" ארוך מ-200 תווים',
    ]);
  });

  test('a task needs at least one assignee', () {
    final result = parse(buildImportWorkbook(
      stageRows: [stageRow()],
      taskRows: [taskRow(assignees: null)],
    ));
    expect(texts(result), ['משימות, שורה 2: חסר אחראי למשימה']);
  });

  test('an ambiguous name lists the members it could be', () {
    final boazA = buildMember(id: 'b1', name: 'בועז כהן');
    final boazB = buildMember(id: 'b2', name: 'בועז לוי');
    final result = parse(
      buildImportWorkbook(
        stageRows: [stageRow()],
        taskRows: [taskRow(assignees: 'בועז')],
      ),
      candidates: [boazA, boazB],
    );
    expect(texts(result), [
      'משימות, שורה 2: "בועז" תואם כמה משובצים: בועז כהן, בועז לוי',
    ]);
  });

  test('the same member named twice is assigned once', () {
    final result = parse(buildImportWorkbook(
      stageRows: [stageRow()],
      taskRows: [taskRow(assignees: 'עומר אליהו | עומר')],
    ));
    expect(result.stages.single.tasks.single.assigneeIds, ['m1']);
  });

  test('a file with no stage rows is a problem', () {
    expect(texts(parse(buildImportWorkbook())), ['שלבים: אין שלבים בקובץ']);
  });

  test('the stage and task caps are problems', () {
    final stages = [
      for (var i = 1; i <= maxImportStages + 1; i++)
        stageRow(number: i, title: 'שלב $i'),
    ];
    expect(
      texts(parse(buildImportWorkbook(stageRows: stages))),
      [
        'שלבים: בקובץ ${maxImportStages + 1} שלבים; אפשר לייבא עד $maxImportStages',
      ],
    );
    final tasks = [
      for (var i = 0; i <= maxImportTasks; i++) taskRow(title: 'משימה $i'),
    ];
    expect(
      texts(parse(buildImportWorkbook(stageRows: [stageRow()], taskRows: tasks))),
      [
        'משימות: בקובץ ${maxImportTasks + 1} משימות; אפשר לייבא עד $maxImportTasks',
      ],
    );
  });
}
