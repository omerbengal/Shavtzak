import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/calendar_share/calendar_share_flow_dialog.dart';

void main() {
  group('calendarShareRangeExceedsMax', () {
    test('exactly 6 months is rejected (strict boundary)', () {
      expect(
        calendarShareRangeExceedsMax(DateTime(2026, 1, 15), DateTime(2026, 7, 15)),
        isTrue,
      );
    });

    test('one day under 6 months is allowed', () {
      expect(
        calendarShareRangeExceedsMax(DateTime(2026, 1, 15), DateTime(2026, 7, 14)),
        isFalse,
      );
    });

    test('cross-year cap works (Oct → Apr)', () {
      expect(
        calendarShareRangeExceedsMax(DateTime(2026, 10, 1), DateTime(2027, 3, 31)),
        isFalse,
      );
      expect(
        calendarShareRangeExceedsMax(DateTime(2026, 10, 1), DateTime(2027, 4, 1)),
        isTrue,
      );
    });

    test('single day range is allowed', () {
      expect(
        calendarShareRangeExceedsMax(DateTime(2026, 7, 8), DateTime(2026, 7, 8)),
        isFalse,
      );
    });
  });
}
