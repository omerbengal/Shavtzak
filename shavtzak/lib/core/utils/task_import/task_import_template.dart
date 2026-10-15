import 'package:excel/excel.dart';

import '../../../domain/entities/event.dart';
import '../task_utils.dart';
import 'task_import_parser.dart';

const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';

/// An empty import file for [event]: both sheets, right to left, with every
/// header and one made-up example row each.
List<int> buildTaskImportTemplate(Event event) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, stagesSheetName);
  final stages = excel[stagesSheetName];
  final tasks = excel[tasksSheetName];
  stages.isRTL = true;
  tasks.isRTL = true;

  stages.appendRow(
    [for (final header in StageColumns.all) TextCellValue(header)],
  );
  stages.appendRow([
    const IntCellValue(1),
    TextCellValue('קליטה והתכנסות'),
    DateCellValue.fromDateTime(eventDays(event).first),
    const TimeCellValue(hour: 9),
    const TimeCellValue(hour: 10, minute: 30),
    TextCellValue('• שולחן קליטה בלובי\n• עמדת כיבוד קל'),
    TextCellValue('לובי המלון'),
    TextCellValue('להגיע חצי שעה לפני'),
    TextCellValue('שם: ישראל ישראלי, טלפון: 050-0000000, תפקיד: מנהל המלון'),
  ]);

  tasks.appendRow(
    [for (final header in TaskColumns.all) TextCellValue(header)],
  );
  tasks.appendRow([
    const IntCellValue(1),
    TextCellValue('הקמת עמדת הקליטה'),
    TextCellValue('לוודא שיש מדפסת ותגים'),
    TextCellValue('ישראל ישראלי'),
    const TimeCellValue(hour: 8, minute: 30),
    TextCellValue('חיבור מדפסות | סידור תגים'),
  ]);

  excel.setDefaultSheet(stagesSheetName);
  return excel.encode()!;
}
