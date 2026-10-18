import 'package:excel/excel.dart';

/// Reading single cells of an import workbook. Every reader takes the cell as
/// `excel` decoded it, so a date typed as a date, as a serial number or as
/// text all arrive at the same value.

/// Marks Excel and copy-paste leave in Hebrew text that nobody can see:
/// direction marks, embeddings and isolates, and the byte-order mark.
final RegExp _invisible =
    RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

/// [text] without invisible marks, with non-breaking spaces as spaces.
String cleanText(String text) =>
    text.replaceAll(_invisible, '').replaceAll('\u00A0', ' ');

/// The cell as text, cleaned and trimmed; '' for an empty cell. Line breaks
/// inside the text are kept.
String cellText(CellValue? value) {
  return switch (value) {
    null => '',
    TextCellValue(value: final span) => cleanText(span.toString()).trim(),
    IntCellValue(value: final number) => '$number',
    DoubleCellValue(value: final number) =>
      number == number.roundToDouble() ? '${number.toInt()}' : '$number',
    DateCellValue(:final year, :final month, :final day) =>
      formatImportDay(DateTime(year, month, day)),
    DateTimeCellValue(
      :final year,
      :final month,
      :final day,
      :final hour,
      :final minute,
    ) =>
      '${formatImportDay(DateTime(year, month, day))} '
          '${_hourMinute(hour, minute)}',
    TimeCellValue(:final hour, :final minute) => _hourMinute(hour, minute),
    BoolCellValue(value: final flag) => flag ? 'TRUE' : 'FALSE',
    FormulaCellValue(:final formula) => cleanText(formula).trim(),
  };
}

/// Whether the cell holds nothing a person typed.
bool isBlankCell(CellValue? value) => cellText(value).isEmpty;

final RegExp _dayText = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$');

/// A calendar day at local midnight.
DateTime? cellDate(CellValue? value) {
  switch (value) {
    case DateCellValue(:final year, :final month, :final day):
      return DateTime(year, month, day);
    case DateTimeCellValue(:final year, :final month, :final day):
      return DateTime(year, month, day);
    case IntCellValue(value: final serial):
      return _fromSerial(serial);
    case DoubleCellValue(value: final serial):
      return _fromSerial(serial.floor());
    case TextCellValue():
      final match = _dayText.firstMatch(cellText(value));
      if (match == null) return null;
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final date = DateTime(year, month, day);
      // DateTime rolls 31/02 over into March; refuse instead.
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    default:
      return null;
  }
}

/// Excel's day count, where 1 is 1/1/1900 and 30/12/1899 is day zero.
DateTime? _fromSerial(int serial) =>
    serial < 1 ? null : DateTime(1899, 12, 30 + serial);

final RegExp _timeText = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$');

/// A time of day as `HH:mm`.
String? cellTime(CellValue? value) {
  switch (value) {
    case TimeCellValue(:final hour, :final minute, :final second):
      return _fromMinutes(hour * 60 + minute + (second >= 30 ? 1 : 0));
    case DateTimeCellValue(:final hour, :final minute):
      return _fromMinutes(hour * 60 + minute);
    case DoubleCellValue(value: final fraction):
      if (fraction < 0 || fraction >= 1) return null;
      return _fromMinutes((fraction * 24 * 60).round());
    case TextCellValue():
      final match = _timeText.firstMatch(cellText(value));
      if (match == null) return null;
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return _hourMinute(hour, minute);
    default:
      return null;
  }
}

String? _fromMinutes(int minutes) => minutes < 0 || minutes >= 24 * 60
    ? null
    : _hourMinute(minutes ~/ 60, minutes % 60);

String _hourMinute(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// `dd/MM/yyyy`, the way the app and the problem messages write a day.
String formatImportDay(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')}/'
    '${day.month.toString().padLeft(2, '0')}/${day.year}';

final RegExp _listSeparator = RegExp(r'[|\n\r]');
final RegExp _bullet = RegExp(r'^[*•·]\s*');

/// The items of a list cell: split on line breaks or `|`, each without a
/// leading "*" bullet, empty items dropped.
List<String> splitImportList(String text) => text
    .split(_listSeparator)
    .map((item) => item.trim().replaceFirst(_bullet, '').trim())
    .where((item) => item.isNotEmpty)
    .toList();
