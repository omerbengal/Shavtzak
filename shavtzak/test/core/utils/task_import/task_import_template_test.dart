import 'dart:convert';

import 'package:archive/archive.dart';
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
      [
        'משימות, שורה 2: "ישראל ישראלי" אינו משובץ לאירוע',
        'משימות, שורה 2: "דנה כהן" אינו משובץ לאירוע',
      ],
    );
    final stage = result.stages.single;
    expect(stage.stage.date, DateTime(2026, 6, 15));
    expect(stage.stage.startTime, '09:00');
    expect(stage.stage.endTime, '10:30');
    // Two of each, so the "*" on its own line shows in the example.
    expect(
      stage.stage.contacts.map((c) => [c.name, c.phone, c.role]),
      [
        ['ישראל ישראלי', '050-0000000', 'מנהל המלון'],
        ['דנה כהן', '052-0000000', 'קבלה'],
      ],
    );
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

  test('time cells are formatted hh:mm, like the official file', () {
    // Read the file itself: the `excel` reader reports a custom "hh:mm" back
    // as its own "h:mm".
    final zip = ZipDecoder().decodeBytes(buildTaskImportTemplate(event));
    String part(String name) =>
        utf8.decode(zip.findFile(name)!.content as List<int>);
    final styles = part('xl/styles.xml');
    final timeFormat = RegExp(r'<numFmt numFmtId="(\d+)" formatCode="hh:mm"/>')
        .firstMatch(styles);
    expect(timeFormat, isNotNull);
    final xfs = RegExp(r'<xf [^>]*numFmtId="(\d+)"')
        .allMatches(styles.substring(styles.indexOf('<cellXfs')))
        .map((m) => m.group(1))
        .toList();

    String formatIdOf(String sheetPart, String cell) {
      final style = RegExp('<c r="$cell" s="(\\d+)"')
          .firstMatch(part(sheetPart))!
          .group(1)!;
      return xfs[int.parse(style)]!;
    }

    final hhmm = timeFormat!.group(1);
    expect(formatIdOf('xl/worksheets/sheet1.xml', 'C2'), hhmm);
    expect(formatIdOf('xl/worksheets/sheet1.xml', 'D2'), hhmm);
    expect(formatIdOf('xl/worksheets/sheet2.xml', 'E2'), hhmm);
  });

  test('the task\'s stage is a drop-down of the first 100 stage names', () {
    final zip = ZipDecoder().decodeBytes(buildTaskImportTemplate(event));
    final tasks =
        utf8.decode(zip.findFile('xl/worksheets/sheet2.xml')!.content as List<int>);
    final validation =
        RegExp(r'<dataValidation [^>]*>.*?</dataValidation>', dotAll: true)
            .firstMatch(tasks)
            ?.group(0);
    expect(validation, isNotNull, reason: tasks);
    expect(validation, contains('type="list"'));
    expect(validation, contains('sqref="A2:A401"'));
    expect(
      validation,
      contains('<formula1>$stagesSheetName!\$A\$2:\$A\$101</formula1>'),
    );
    // Valid XML order: before the page margins, after the sheet data.
    expect(tasks.indexOf('<dataValidations'),
        greaterThan(tasks.indexOf('</sheetData>')));
    final margins = tasks.indexOf('<pageMargins');
    if (margins != -1) {
      expect(tasks.indexOf('<dataValidations'), lessThan(margins));
    }
    final stages =
        utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(stages, isNot(contains('<dataValidations')));
  });

  group('the look of the official file', () {
    late Archive zip;
    String part(String name) =>
        utf8.decode(zip.findFile(name)!.content as List<int>);
    const sheets = ['xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml'];

    setUp(() => zip = ZipDecoder().decodeBytes(buildTaskImportTemplate(event)));

    List<String> fonts() => RegExp(r'<font>.*?</font>|<font/>')
        .allMatches(part('xl/styles.xml'))
        .map((m) => m.group(0)!)
        .toList();

    List<String> cellXfs() {
      final styles = part('xl/styles.xml');
      final block = styles.substring(
        styles.indexOf('<cellXfs'),
        styles.indexOf('</cellXfs>'),
      );
      return RegExp(r'<xf [^>]*/>|<xf [^>]*>.*?</xf>')
          .allMatches(block)
          .map((m) => m.group(0)!)
          .toList();
    }

    String fontOfCell(String sheet, String cell) {
      final style = RegExp('<c r="$cell" s="(\\d+)"').firstMatch(part(sheet));
      final xf = cellXfs()[int.parse(style!.group(1)!)];
      final fontId = int.parse(RegExp(r'fontId="(\d+)"').firstMatch(xf)!.group(1)!);
      return fonts()[fontId];
    }

    bool isRubik(String font, int size, {required bool bold}) =>
        font.contains('<name val="Rubik"/>') &&
        RegExp('<sz val="$size(\\.0)?"/>').hasMatch(font) &&
        font.contains('<b/>') == bold;

    test('both sheets run right to left', () {
      for (final sheet in sheets) {
        expect(part(sheet), contains('rightToLeft="1"'), reason: sheet);
      }
    });

    test('every cell style reads right to left', () {
      for (final xf in cellXfs()) {
        expect(xf, contains('readingOrder="2"'), reason: xf);
      }
    });

    test('the default font is Rubik 12, so typed-in cells get it too', () {
      expect(isRubik(fonts().first, 12, bold: false), isTrue,
          reason: fonts().first);
    });

    test('headers are Rubik 14 bold; every other cell Rubik 12', () {
      for (final sheet in sheets) {
        final cells = RegExp(r'<c r="([A-Z]+)(\d+)"')
            .allMatches(part(sheet))
            .map((m) => (m.group(1)! + m.group(2)!, m.group(2)!));
        expect(cells, isNotEmpty);
        for (final (cell, row) in cells) {
          final font = fontOfCell(sheet, cell);
          expect(
            row == '1'
                ? isRubik(font, 14, bold: true)
                : isRubik(font, 12, bold: false),
            isTrue,
            reason: '$sheet $cell: $font',
          );
        }
      }
    });
  });

  test('with the example assignee assigned, the template imports cleanly', () {
    final israel = buildMember(id: 'i1', name: 'ישראל ישראלי');
    final result = parseTaskImport(
      buildTaskImportTemplate(event),
      event: event,
      candidates: [israel, buildMember(id: 'd1', name: 'דנה כהן')],
      currentUserId: 'boss',
      now: DateTime(2026, 6, 1),
    );
    expect(result.isValid, isTrue);
    expect(result.stages.single.tasks.single.assigneeIds, ['i1', 'd1']);
  });
}
