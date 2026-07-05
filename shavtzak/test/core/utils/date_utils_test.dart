import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/date_utils.dart';

void main() {
  group('DateUtils.hebrewMonthName', () {
    test('returns correct name for boundary and middle months', () {
      expect(DateUtils.hebrewMonthName(1), 'ינואר');
      expect(DateUtils.hebrewMonthName(9), 'ספטמבר');
      expect(DateUtils.hebrewMonthName(12), 'דצמבר');
    });
  });

  group('DateUtils.formatDayMonth', () {
    test('formats September without the legacy typo', () {
      expect(DateUtils.formatDayMonth(DateTime(2026, 9, 3)), '3 בספטמבר');
    });

    test('formats other months unchanged', () {
      expect(DateUtils.formatDayMonth(DateTime(2026, 7, 15)), '15 ביולי');
    });
  });

  group('DateUtils.formatDateRange', () {
    test('same-month format is unchanged', () {
      expect(
        DateUtils.formatDateRange(DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        '3-5 בספטמבר',
      );
    });

    test('cross-month format is unchanged', () {
      expect(
        DateUtils.formatDateRange(DateTime(2026, 9, 3), DateTime(2026, 10, 2)),
        '3 בספטמבר - 2 באוקטובר',
      );
    });
  });

  group('DateUtils.shiftHmByMinutes', () {
    test('subtracts two hours (שעת התייצבות derive)', () {
      expect(DateUtils.shiftHmByMinutes('10:00', -120), '08:00');
      expect(DateUtils.shiftHmByMinutes('20:30', -120), '18:30');
    });

    test('adds one hour (שעת סיום הצוות derive)', () {
      expect(DateUtils.shiftHmByMinutes('12:00', 60), '13:00');
      expect(DateUtils.shiftHmByMinutes('22:15', 60), '23:15');
    });

    test('wraps around midnight in both directions', () {
      expect(DateUtils.shiftHmByMinutes('01:00', -120), '23:00');
      expect(DateUtils.shiftHmByMinutes('23:30', 60), '00:30');
    });

    test('returns null for empty or malformed input', () {
      expect(DateUtils.shiftHmByMinutes('', -120), isNull);
      expect(DateUtils.shiftHmByMinutes('abc', 60), isNull);
      expect(DateUtils.shiftHmByMinutes('25:00', -120), isNull);
      expect(DateUtils.shiftHmByMinutes('10:99', 60), isNull);
    });
  });
}
