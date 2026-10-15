import 'package:excel/excel.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';

/// Builds an import workbook in memory. Values: null or '' leave the cell
/// empty, a String is text, an int or double a number, a CellValue itself.
List<int> buildImportWorkbook({
  List<String>? stageHeaders,
  List<List<Object?>> stageRows = const [],
  List<String>? taskHeaders,
  List<List<Object?>> taskRows = const [],
  bool withStagesSheet = true,
  bool withTasksSheet = true,
}) {
  final excel = Excel.createExcel();
  final first = excel.getDefaultSheet()!;
  if (withStagesSheet) {
    excel.rename(first, stagesSheetName);
    final sheet = excel[stagesSheetName];
    sheet.appendRow(
      [for (final h in stageHeaders ?? StageColumns.all) TextCellValue(h)],
    );
    for (final row in stageRows) {
      sheet.appendRow(row.map(_cell).toList());
    }
  }
  if (withTasksSheet) {
    final sheet = excel[tasksSheetName];
    sheet.appendRow(
      [for (final h in taskHeaders ?? TaskColumns.all) TextCellValue(h)],
    );
    for (final row in taskRows) {
      sheet.appendRow(row.map(_cell).toList());
    }
  }
  return excel.encode()!;
}

/// A stage row in [StageColumns.all] order.
List<Object?> stageRow({
  Object? number = 1,
  Object? title = 'קליטה',
  Object? date = const DateCellValue(year: 2026, month: 6, day: 15),
  Object? start,
  Object? end,
  Object? requirements,
  Object? location,
  Object? notes,
  Object? contacts,
}) =>
    [number, title, date, start, end, requirements, location, notes, contacts];

/// A task row in [TaskColumns.all] order. The default assignee is 'עומר',
/// which the parser tests' candidates hold.
List<Object?> taskRow({
  Object? number = 1,
  Object? title = 'הקמת עמדה',
  Object? description,
  Object? assignees = 'עומר',
  Object? assembly,
  Object? subtasks,
}) =>
    [number, title, description, assignees, assembly, subtasks];

CellValue? _cell(Object? value) => switch (value) {
      null => null,
      '' => null,
      String() => TextCellValue(value),
      int() => IntCellValue(value),
      double() => DoubleCellValue(value),
      CellValue() => value,
      _ => throw ArgumentError('Unsupported cell $value'),
    };
