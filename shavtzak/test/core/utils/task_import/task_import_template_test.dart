import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/core/utils/task_import/task_import_template.dart';

import '../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );

  test('the template parses to one stage and one task on the event\'s first day',
      () {
    final result = parseTaskImport(
      buildTaskImportTemplate(event),
      event: event,
      candidates: const [],
      currentUserId: 'boss',
      now: DateTime(2026, 6, 1),
    );

    // The only problem is the made-up assignee, by design.
    expect(
      result.problems.map((p) => p.text),
      ['משימות, שורה 2: "ישראל ישראלי" אינו משובץ לאירוע'],
    );
    final stage = result.stages.single;
    expect(stage.stage.date, DateTime(2026, 6, 15));
    expect(stage.stage.startTime, '09:00');
    expect(stage.stage.endTime, '10:30');
    expect(stage.stage.contacts.single.phone, '050-0000000');
    expect(stage.tasks.single.subtasks, hasLength(2));
    expect(stage.tasks.single.assemblyTime, '08:30');
  });

  test('the template carries the official headers and "*" lists', () {
    final workbook = Excel.decodeBytes(buildTaskImportTemplate(event));
    List<String> header(String sheet) => [
          for (final cell in workbook.tables[sheet]!.rows.first)
            if (cell?.value != null) cell!.value.toString(),
        ];
    List<String> example(String sheet) => [
          for (final cell in workbook.tables[sheet]!.rows[1])
            if (cell?.value != null) cell!.value.toString(),
        ];

    expect(header(stagesSheetName), StageColumns.templateHeaders);
    expect(header(tasksSheetName), TaskColumns.templateHeaders);
    expect(
      StageColumns.templateHeaders,
      contains('אנשי קשר (כל אחד בכוכבית נפרדת בשורה נפרדת)'),
    );
    expect(example(tasksSheetName), contains('* חיבור מדפסות\n* סידור תגים'));
  });

  test('with the example assignee assigned, the template imports cleanly', () {
    final israel = buildMember(id: 'i1', name: 'ישראל ישראלי');
    final result = parseTaskImport(
      buildTaskImportTemplate(event),
      event: event,
      candidates: [israel],
      currentUserId: 'boss',
      now: DateTime(2026, 6, 1),
    );
    expect(result.isValid, isTrue);
  });
}
