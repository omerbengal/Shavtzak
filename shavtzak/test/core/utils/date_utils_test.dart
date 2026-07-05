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
}
