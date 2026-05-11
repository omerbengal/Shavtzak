import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/israel_calendar.dart';

void main() {
  group('IsraelCalendar.calendarParts', () {
    test('summer (IDT, UTC+3) Israel midnight stored as 21:00Z → June 8', () {
      // Production event "אירוע הוקרה בית הנשיא" is stored as
      // 2026-06-07T21:00:00Z, representing midnight on June 8 in IDT.
      final instant = DateTime.utc(2026, 6, 7, 21, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.year, 2026);
      expect(parts.month, 6);
      expect(parts.day, 8);
    });

    test('winter (IST, UTC+2) Israel midnight stored as 22:00Z → Jan 15', () {
      final instant = DateTime.utc(2026, 1, 14, 22, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.year, 2026);
      expect(parts.month, 1);
      expect(parts.day, 15);
    });

    test('moment right before DST starts: still IST', () {
      // 2026 DST begins Friday 2026-03-27 at 02:00 IST = 00:00 UTC.
      // 23:00Z on 2026-03-26 is still IST. Israel local = 01:00 on Mar 27.
      final instant = DateTime.utc(2026, 3, 26, 23, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.year, 2026);
      expect(parts.month, 3);
      expect(parts.day, 27);
    });

    test('moment right after DST starts: IDT', () {
      // 00:00Z on 2026-03-27 → DST takes effect → Israel local = 03:00 Mar 27.
      final instant = DateTime.utc(2026, 3, 27, 0, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.day, 27);
    });

    test('moment right before DST ends: IDT', () {
      // 2026 DST ends Sunday 2026-10-25 at 02:00 IDT = 23:00 UTC Oct 24.
      // 22:59:59Z on Oct 24 is still IDT. Israel local = 01:59:59 Oct 25.
      final instant = DateTime.utc(2026, 10, 24, 22, 59, 59);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.day, 25);
    });

    test('moment right after DST ends: IST', () {
      // 23:00Z on Oct 24 → Israel local = 01:00 Oct 25 (rolled back from 02:00).
      final instant = DateTime.utc(2026, 10, 24, 23, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.day, 25);
    });

    test('UTC midnight constraint string parsed in UTC TZ still maps to same Israel day', () {
      // Naive constraint string "2026-06-07T00:00:00.000Z" parses to UTC midnight.
      // In Israel (UTC+3 IDT), that is 03:00 on June 7 → calendar day June 7.
      final instant = DateTime.utc(2026, 6, 7, 0, 0, 0);
      final parts = IsraelCalendar.calendarParts(instant);
      expect(parts.day, 7);
    });
  });

  group('IsraelCalendar.calendarDay', () {
    test('returns a local DateTime at midnight on the Israel calendar day', () {
      final instant = DateTime.utc(2026, 6, 7, 21, 0, 0); // June 8 IDT
      final day = IsraelCalendar.calendarDay(instant);
      expect(day.year, 2026);
      expect(day.month, 6);
      expect(day.day, 8);
      expect(day.hour, 0);
      expect(day.minute, 0);
      expect(day.second, 0);
    });

    test('DST start year boundary: 2024 (last Sunday Mar = 31, Friday before = 29)', () {
      // 2024 DST: starts Fri 2024-03-29 at 02:00 IST → 00:00 UTC.
      // 23:00Z on 2024-03-28 → IST → Israel local 01:00 Mar 29.
      final before = IsraelCalendar.calendarDay(DateTime.utc(2024, 3, 28, 23, 0, 0));
      expect(before.day, 29);
      // 23:00Z on 2024-03-29 → IDT (already past 00:00Z transition) → Israel 02:00 Mar 30.
      final after = IsraelCalendar.calendarDay(DateTime.utc(2024, 3, 29, 23, 0, 0));
      expect(after.day, 30);
    });

    test('DST end year boundary: 2025 (last Sunday Oct = 26)', () {
      // 2025 DST ends Sun 2025-10-26 at 02:00 IDT → 23:00 UTC Oct 25.
      // 22:00Z on 2025-10-25 → IDT → Israel 01:00 Oct 26.
      final before = IsraelCalendar.calendarDay(DateTime.utc(2025, 10, 25, 22, 0, 0));
      expect(before.day, 26);
      // 23:00Z on 2025-10-25 → IST → Israel 01:00 Oct 26.
      final after = IsraelCalendar.calendarDay(DateTime.utc(2025, 10, 25, 23, 0, 0));
      expect(after.day, 26);
    });
  });
}
