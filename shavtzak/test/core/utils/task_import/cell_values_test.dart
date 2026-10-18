import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/cell_values.dart';

void main() {
  group('text', () {
    test('drops invisible marks and turns non-breaking spaces into spaces', () {
      expect(cleanText('050-628-5016\u2069'), '050-628-5016');
      expect(cleanText('\u200Fשם\u00A0מלא\uFEFF'), 'שם מלא');
    });

    test('reads every kind of cell as trimmed text', () {
      expect(cellText(null), '');
      expect(cellText(TextCellValue('  שלום \u2069 ')), 'שלום');
      expect(cellText(const IntCellValue(3)), '3');
      expect(cellText(const DoubleCellValue(2.0)), '2');
      expect(cellText(const DoubleCellValue(2.5)), '2.5');
      expect(
        cellText(const DateCellValue(year: 2026, month: 6, day: 15)),
        '15/06/2026',
      );
      expect(cellText(const TimeCellValue(hour: 8, minute: 5)), '08:05');
    });

    test('keeps line breaks inside the text', () {
      expect(cellText(TextCellValue('• א\n• ב')), '• א\n• ב');
    });

    test('a cell of spaces is blank', () {
      expect(isBlankCell(TextCellValue('   ')), isTrue);
      expect(isBlankCell(null), isTrue);
      expect(isBlankCell(const IntCellValue(0)), isFalse);
    });
  });

  group('dates', () {
    test('reads date cells, date-time cells and serial numbers', () {
      expect(
        cellDate(const DateCellValue(year: 2026, month: 6, day: 15)),
        DateTime(2026, 6, 15),
      );
      expect(
        cellDate(const DateTimeCellValue(
            year: 2026, month: 6, day: 15, hour: 9, minute: 0)),
        DateTime(2026, 6, 15),
      );
      expect(cellDate(const IntCellValue(46188)), DateTime(2026, 6, 15));
      expect(cellDate(const DoubleCellValue(46188.75)), DateTime(2026, 6, 15));
    });

    test('reads day/month/year text with slashes or dots', () {
      expect(cellDate(TextCellValue('15/06/2026')), DateTime(2026, 6, 15));
      expect(cellDate(TextCellValue('15/6/2026')), DateTime(2026, 6, 15));
      expect(cellDate(TextCellValue('15.06.2026')), DateTime(2026, 6, 15));
    });

    test('refuses impossible or unreadable dates', () {
      expect(cellDate(TextCellValue('31/02/2026')), isNull);
      expect(cellDate(TextCellValue('מחר')), isNull);
      expect(cellDate(const IntCellValue(0)), isNull);
    });
  });

  group('times', () {
    test('reads time cells, rounding seconds to the minute', () {
      expect(cellTime(const TimeCellValue(hour: 8, minute: 30)), '08:30');
      expect(
        cellTime(const TimeCellValue(hour: 8, minute: 29, second: 59)),
        '08:30',
      );
    });

    test('reads date-time cells and fractions of a day', () {
      expect(
        cellTime(const DateTimeCellValue(
            year: 2026, month: 6, day: 15, hour: 14, minute: 5)),
        '14:05',
      );
      expect(cellTime(const DoubleCellValue(0.3541666666666667)), '08:30');
    });

    test('reads H:mm and HH:mm text, with or without seconds', () {
      expect(cellTime(TextCellValue('8:30')), '08:30');
      expect(cellTime(TextCellValue('08:30:00')), '08:30');
    });

    test('refuses impossible or unreadable times', () {
      expect(cellTime(TextCellValue('24:00')), isNull);
      expect(cellTime(TextCellValue('8:75')), isNull);
      expect(cellTime(TextCellValue('בבוקר')), isNull);
      expect(cellTime(const DoubleCellValue(1.5)), isNull);
    });
  });
}
