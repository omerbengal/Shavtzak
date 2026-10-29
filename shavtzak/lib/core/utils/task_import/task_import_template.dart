import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../../../domain/entities/event.dart';
import '../../../domain/entities/stage.dart';
import '../task_progress.dart';
import '../task_utils.dart';
import 'task_import_parser.dart';

const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';

/// The official import file for [event]: both sheets right to left with the
/// header row frozen, every cell Rubik 12 with right-to-left text, centered
/// both ways except the "*" list columns, which sit on the right. The header
/// row is Rubik 14 bold with how to fill the list columns, and there is one
/// made-up example row on each sheet. Lists are
/// written one "*" item per line. A task's stage is picked from a drop-down
/// of the stage names.
List<int> buildTaskImportTemplate(Event event) {
  return _buildWorkbook(
    stageRows: [
      [
        TextCellValue(_exampleStage),
        DateCellValue.fromDateTime(eventDays(event).first),
        const TimeCellValue(hour: 9),
        const TimeCellValue(hour: 10, minute: 30),
        TextCellValue('* שולחן קליטה בלובי\n* עמדת כיבוד קל'),
        TextCellValue('לובי המלון'),
        TextCellValue('להגיע חצי שעה לפני'),
        // Two of each list, so the "*" on its own line shows in the example.
        TextCellValue(
          '* שם: ישראל ישראלי, טלפון: 050-0000000, תפקיד: מנהל המלון\n'
          '* שם: דנה כהן, טלפון: 052-0000000, תפקיד: קבלה',
        ),
      ],
    ],
    taskRows: [
      [
        TextCellValue(_exampleStage),
        TextCellValue('הקמת עמדת הקליטה'),
        TextCellValue('לוודא שיש מדפסת ותגים'),
        TextCellValue('* ישראל ישראלי\n* דנה כהן'),
        const TimeCellValue(hour: 8, minute: 30),
        TextCellValue('* חיבור מדפסות\n* סידור תגים'),
      ],
    ],
  );
}

/// The file name of [event]'s export, without characters a file name cannot
/// hold.
String taskExportFileName(Event event) {
  final name = event.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  return 'משימות דו יומי - $name.xlsx';
}

/// [board]'s stages and tasks in the official import file, with the same
/// look as [buildTaskImportTemplate]: one row per stage and per task, in
/// screen order.
///
/// Tasks find their stage by name and the import refuses a name twice, so a
/// repeated stage name is written with " (2)", " (3)" after it; the file then
/// imports back as it is. Ticks, completion and the assignees' notes are not
/// part of the format and are left out.
List<int> buildTaskExport(EventTaskBoard board) {
  final nameOf = <String, String>{};
  final used = <String>{};
  for (final stage in board.stages) {
    final base = stage.title.replaceAll(RegExp(r'\s+'), ' ').trim();
    var name = base;
    for (var copy = 2; !used.add(name); copy++) {
      name = '$base ($copy)';
    }
    nameOf[stage.id] = name;
  }

  return _buildWorkbook(
    stageRows: [
      for (final stage in board.stages)
        [
          TextCellValue(nameOf[stage.id]!),
          DateCellValue.fromDateTime(stage.date),
          _time(stage.startTime),
          _time(stage.endTime),
          _text(stage.requirements),
          _text(stage.hotelLocation),
          _text(stage.notes),
          _list([for (final contact in stage.contacts) _contactText(contact)]),
        ],
    ],
    taskRows: [
      for (final stage in board.stages)
        for (final task in board.tasksOf(stage.id))
          [
            TextCellValue(nameOf[stage.id]!),
            TextCellValue(task.title),
            _text(task.description),
            _list([for (final member in task.assignees) member.name]),
            _time(task.assemblyTime),
            _list([for (final subtask in task.subtasks) subtask.title]),
          ],
    ],
  );
}

CellValue? _text(String text) => text.isEmpty ? null : TextCellValue(text);

/// One "*" item per line, the way the import reads a list.
CellValue? _list(List<String> items) =>
    _text(items.map((item) => '* $item').join('\n'));

final RegExp _hourMinute = RegExp(r'^(\d{1,2}):(\d{2})$');

CellValue? _time(String? time) {
  final match = _hourMinute.firstMatch(time ?? '');
  if (match == null) return null;
  return TimeCellValue(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
  );
}

String _contactText(StageContact contact) => [
      'שם: ${contact.name}',
      if (contact.phone.isNotEmpty) 'טלפון: ${contact.phone}',
      if (contact.role.isNotEmpty) 'תפקיד: ${contact.role}',
    ].join(', ');

List<int> _buildWorkbook({
  required List<List<CellValue?>> stageRows,
  required List<List<CellValue?>> taskRows,
}) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, stagesSheetName);
  _writeSheet(
    excel[stagesSheetName],
    headers: StageColumns.templateHeaders,
    widths: const [34.25, 12.5, 13.7, 10.5, 52, 16.5, 26.7, 64.5],
    kinds: const [
      _Kind.text,
      _Kind.date,
      _Kind.time,
      _Kind.time,
      _Kind.list, // requirements
      _Kind.text,
      _Kind.text,
      _Kind.list, // contacts
    ],
    rows: stageRows,
  );
  _writeSheet(
    excel[tasksSheetName],
    headers: TaskColumns.templateHeaders,
    widths: const [34.25, 49.6, 25, 50, 15, 52.5],
    kinds: const [
      _Kind.text,
      _Kind.text,
      _Kind.text,
      _Kind.list, // assignees
      _Kind.time,
      _Kind.list, // subtasks
    ],
    rows: taskRows,
  );

  excel.setDefaultSheet(stagesSheetName);
  return _finishLook(excel.encode()!);
}

enum _Kind { text, list, date, time }

const String _exampleStage = 'קליטה והתכנסות';

final CellStyle _headerStyle = CellStyle(
  bold: true,
  fontSize: 14,
  fontFamily: 'Rubik',
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
);

final CellStyle _textStyle = CellStyle(
  fontSize: 12,
  fontFamily: 'Rubik',
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
);

// A "*" list reads from the right, one item under the other.
final CellStyle _listStyle = CellStyle(
  fontSize: 12,
  fontFamily: 'Rubik',
  horizontalAlign: HorizontalAlign.Right,
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
);

final CellStyle _dateStyle = CellStyle(
  fontSize: 12,
  fontFamily: 'Rubik',
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
  numberFormat: NumFormat.defaultDate,
);

// Two-digit hours, as in the official file: 09:00, not 9:00.
final CellStyle _timeStyle = CellStyle(
  fontSize: 12,
  fontFamily: 'Rubik',
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
  numberFormat: const CustomTimeNumFormat(formatCode: 'hh:mm'),
);

void _writeSheet(
  Sheet sheet, {
  required List<String> headers,
  required List<double> widths,
  required List<_Kind> kinds,
  required List<List<CellValue?>> rows,
}) {
  sheet.isRTL = true;
  sheet.appendRow([for (final header in headers) TextCellValue(header)]);
  sheet.setRowHeight(0, 40);
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
    _cell(sheet, column, 0).cellStyle = _headerStyle;
  }
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < headers.length; column++) {
      final cell = _cell(sheet, column, row + 1);
      cell.value = rows[row][column];
      // The whole column later takes its first row's style (see
      // [_finishLook]), so empty cells are styled too.
      cell.cellStyle = switch (kinds[column]) {
        _Kind.date => _dateStyle,
        _Kind.time => _timeStyle,
        _Kind.list => _listStyle,
        _Kind.text => _textStyle,
      };
    }
  }
}

Data _cell(Sheet sheet, int column, int row) => sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );

// ---- what `excel` cannot set ----
//
// `excel` 4.0.6 drops a sheet's right-to-left view on save, has no text
// direction setting, keeps Arial 10 as the workbook's default font, cannot
// style a whole column, freeze a row or write a drop-down. These are set in
// the saved file's XML instead.

const String _rubik12 =
    '<font><sz val="12"/><color rgb="FF000000"/><name val="Rubik"/></font>';

List<int> _finishLook(List<int> bytes) {
  final source = ZipDecoder().decodeBytes(bytes);
  final finished = Archive();
  for (final file in source.files) {
    final name = file.name;
    String Function(String)? change;
    if (name == 'xl/styles.xml') {
      change = _rubikAndRightToLeftText;
    } else if (name == _tasksSheetPart) {
      change = (xml) => _withStageDropDown(_finishSheet(xml));
    } else if (name.startsWith('xl/worksheets/sheet') && name.endsWith('.xml')) {
      change = _finishSheet;
    }
    if (change == null || !file.isFile) {
      finished.addFile(file);
      continue;
    }
    final data = utf8.encode(change(utf8.decode(file.content as List<int>)));
    finished.addFile(ArchiveFile(name, data.length, data));
  }
  return ZipEncoder().encode(finished)!;
}

// The sheets are written in the order they were created: stages, then tasks.
const String _tasksSheetPart = 'xl/worksheets/sheet2.xml';

/// The task's stage column offers the names on the first 100 stage rows,
/// for as many rows as an import may hold tasks, and refuses anything else.
const String _stageDropDown = '<dataValidations count="1">'
    '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
    'showErrorMessage="1" sqref="A2:A${maxImportTasks + 1}">'
    '<formula1>$stagesSheetName!\$A\$2:\$A\$101</formula1>'
    '</dataValidation></dataValidations>';

// Where the schema puts <dataValidations>: before the first of these.
final RegExp _afterDataValidations = RegExp(
  '<(hyperlinks|printOptions|pageMargins|pageSetup|headerFooter|'
  r'rowBreaks|colBreaks|drawing|legacyDrawing|tableParts|extLst)[\s/>]'
  '|</worksheet>',
);

String _withStageDropDown(String xml) {
  final at = _afterDataValidations.firstMatch(xml)!.start;
  return xml.replaceRange(at, at, _stageDropDown);
}

String _finishSheet(String xml) =>
    _columnsStyledLikeExample(_frozenHeader(_rightToLeftSheet(xml)));

// `<sheetView ` with its space: `<sheetViews>` is the element around it.
final RegExp _sheetView = RegExp(r'<sheetView\s(?![^>]*rightToLeft)');

String _rightToLeftSheet(String xml) =>
    xml.replaceAll(_sheetView, '<sheetView rightToLeft="1" ');

final RegExp _emptySheetView = RegExp(r'<sheetView\s([^>]*?)/>');

const String _frozenPane =
    '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
    'state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>';

String _frozenHeader(String xml) => xml.replaceFirstMapped(
      _emptySheetView,
      (view) => '<sheetView ${view.group(1)!.trim()}>$_frozenPane</sheetView>',
    );

final RegExp _column = RegExp(r'<col min="(\d+)" max="\1"(?![^>]*style=)');

/// Each column takes the style of its first row's cell, so rows typed later
/// are laid out the same.
String _columnsStyledLikeExample(String xml) =>
    xml.replaceAllMapped(_column, (col) {
      final letter = String.fromCharCode(64 + int.parse(col.group(1)!));
      final style = RegExp('<c r="${letter}2" s="(\\d+)"').firstMatch(xml);
      if (style == null) return col.group(0)!;
      return '${col.group(0)!} style="${style.group(1)}"';
    });

final RegExp _fontsBlock = RegExp(r'<fonts[^>]*>.*?</fonts>', dotAll: true);
final RegExp _font = RegExp(r'<font>.*?</font>|<font/>', dotAll: true);
final RegExp _cellXfsBlock =
    RegExp(r'<cellXfs[^>]*>.*?</cellXfs>', dotAll: true);
final RegExp _xf = RegExp(r'<xf ([^>]*?)(/>|>(.*?)</xf>)', dotAll: true);
final RegExp _alignment = RegExp(r'<alignment([^>]*?)/>');
final RegExp _readingOrder = RegExp(r'\s*readingOrder="\d+"');

/// Rubik 12 as the default font (the first one, which every unstyled and
/// newly typed cell uses) and for any font left empty; right-to-left text
/// in every cell style.
String _rubikAndRightToLeftText(String xml) {
  xml = xml.replaceFirstMapped(_fontsBlock, (block) {
    var index = 0;
    return block.group(0)!.replaceAllMapped(_font, (font) {
      final isDefault = index++ == 0;
      return isDefault || font.group(0) == '<font/>' ? _rubik12 : font.group(0)!;
    });
  });
  return xml.replaceFirstMapped(_cellXfsBlock, (block) {
    return block.group(0)!.replaceAllMapped(_xf, (xf) {
      var attributes = xf.group(1)!;
      if (!attributes.contains('applyAlignment')) {
        attributes = '$attributes applyAlignment="1"';
      }
      var inner = xf.group(3) ?? '';
      if (_alignment.hasMatch(inner)) {
        inner = inner.replaceFirstMapped(_alignment, (alignment) {
          final rest = alignment.group(1)!.replaceAll(_readingOrder, '');
          return '<alignment$rest readingOrder="2"/>';
        });
      } else {
        inner = '<alignment readingOrder="2"/>$inner';
      }
      return '<xf $attributes>$inner</xf>';
    });
  });
}
