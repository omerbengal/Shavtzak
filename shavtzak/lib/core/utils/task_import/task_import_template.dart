import 'package:excel/excel.dart';

import '../../../domain/entities/event.dart';
import '../task_utils.dart';
import 'task_import_parser.dart';

const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';

/// The official import file for [event]: both sheets, right to left, the
/// headers with how to fill the list columns, and one made-up example row
/// each. Lists are written one "*" item per line.
List<int> buildTaskImportTemplate(Event event) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, stagesSheetName);
  final stages = excel[stagesSheetName];
  final tasks = excel[tasksSheetName];

  _writeSheet(
    stages,
    headers: StageColumns.templateHeaders,
    widths: const [12, 29, 12.5, 13.7, 10.5, 52, 16.5, 26.7, 64.5],
    example: [
      const IntCellValue(1),
      TextCellValue('קליטה והתכנסות'),
      DateCellValue.fromDateTime(eventDays(event).first),
      const TimeCellValue(hour: 9),
      const TimeCellValue(hour: 10, minute: 30),
      TextCellValue('* שולחן קליטה בלובי\n* עמדת כיבוד קל'),
      TextCellValue('לובי המלון'),
      TextCellValue('להגיע חצי שעה לפני'),
      TextCellValue(
        '* שם: ישראל ישראלי, טלפון: 050-0000000, תפקיד: מנהל המלון',
      ),
    ],
  );
  _writeSheet(
    tasks,
    headers: TaskColumns.templateHeaders,
    widths: const [12, 29, 25, 50, 15, 52.5],
    example: [
      const IntCellValue(1),
      TextCellValue('הקמת עמדת הקליטה'),
      TextCellValue('לוודא שיש מדפסת ותגים'),
      TextCellValue('* ישראל ישראלי'),
      const TimeCellValue(hour: 8, minute: 30),
      TextCellValue('* חיבור מדפסות\n* סידור תגים'),
    ],
  );

  excel.setDefaultSheet(stagesSheetName);
  return excel.encode()!;
}

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
  horizontalAlign: HorizontalAlign.Right,
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
);

void _writeSheet(
  Sheet sheet, {
  required List<String> headers,
  required List<double> widths,
  required List<CellValue> example,
}) {
  sheet.isRTL = true;
  sheet.appendRow([for (final header in headers) TextCellValue(header)]);
  sheet.appendRow(example);
  sheet.setRowHeight(0, 40);
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
    _cell(sheet, column, 0).cellStyle = _headerStyle;
    // Dates and times keep the format `excel` gives them; a style here would
    // replace it and show 0.375 instead of 09:00.
    if (example[column] is TextCellValue) {
      _cell(sheet, column, 1).cellStyle = _textStyle;
    }
  }
}

Data _cell(Sheet sheet, int column, int row) => sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );
