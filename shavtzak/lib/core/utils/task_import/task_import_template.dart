import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../../../domain/entities/event.dart';
import '../task_utils.dart';
import 'task_import_parser.dart';

const String taskImportTemplateFileName = 'תבנית משימות דו יומי.xlsx';

/// The official import file for [event]: both sheets right to left, every
/// cell Rubik 12 with right-to-left text, the header row Rubik 14 bold with
/// how to fill the list columns, and one made-up example row each. Lists are
/// written one "*" item per line.
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
      // Two of each list, so the "*" on its own line shows in the example.
      TextCellValue(
        '* שם: ישראל ישראלי, טלפון: 050-0000000, תפקיד: מנהל המלון\n'
        '* שם: דנה כהן, טלפון: 052-0000000, תפקיד: קבלה',
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
      TextCellValue('* ישראל ישראלי\n* דנה כהן'),
      const TimeCellValue(hour: 8, minute: 30),
      TextCellValue('* חיבור מדפסות\n* סידור תגים'),
    ],
  );

  excel.setDefaultSheet(stagesSheetName);
  return _finishLook(excel.encode()!);
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
  required List<CellValue> example,
}) {
  sheet.isRTL = true;
  sheet.appendRow([for (final header in headers) TextCellValue(header)]);
  sheet.appendRow(example);
  sheet.setRowHeight(0, 40);
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
    _cell(sheet, column, 0).cellStyle = _headerStyle;
    // A date keeps the format `excel` gives it: any style here would also
    // have to carry a date format, or Excel would show a plain number.
    switch (example[column]) {
      case TextCellValue():
        _cell(sheet, column, 1).cellStyle = _textStyle;
      case TimeCellValue():
        _cell(sheet, column, 1).cellStyle = _timeStyle;
      default:
        break;
    }
  }
}

Data _cell(Sheet sheet, int column, int row) => sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );

// ---- what `excel` cannot set ----
//
// `excel` 4.0.6 drops a sheet's right-to-left view on save, has no text
// direction setting, and keeps Arial 10 as the workbook's default font. These
// are set in the saved file's XML instead.

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
    } else if (name.startsWith('xl/worksheets/sheet') && name.endsWith('.xml')) {
      change = _rightToLeftSheet;
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

// `<sheetView ` with its space: `<sheetViews>` is the element around it.
final RegExp _sheetView = RegExp(r'<sheetView\s(?![^>]*rightToLeft)');

String _rightToLeftSheet(String xml) =>
    xml.replaceAll(_sheetView, '<sheetView rightToLeft="1" ');

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
