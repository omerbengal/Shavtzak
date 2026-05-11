/// Project a DateTime onto the Asia/Jerusalem calendar.
///
/// Event date Timestamps in Firestore are stored as Israel midnight
/// (21:00Z previous day in summer IDT, 22:00Z in winter IST). When read
/// via `Timestamp.toDate()`, `DateTime.year/.month/.day` reflect the
/// *browser's* local TZ, not Israel. For users abroad that produces
/// off-by-one days on event dates.
///
/// Israeli DST rules (stable since 2013):
///   - Start: Friday before the last Sunday of March, at 02:00 IST → 03:00 IDT
///   - End:   last Sunday of October,                 at 02:00 IDT → 01:00 IST
class IsraelCalendar {
  static const int _istOffsetMinutes = 120; // UTC+2 winter
  static const int _idtOffsetMinutes = 180; // UTC+3 summer

  /// Returns the (year, month, day) of [instant] interpreted in Asia/Jerusalem.
  static ({int year, int month, int day}) calendarParts(DateTime instant) {
    final shifted = instant.toUtc().add(Duration(minutes: _offsetMinutes(instant)));
    return (year: shifted.year, month: shifted.month, day: shifted.day);
  }

  /// Returns a local-TZ-independent DateTime at midnight whose y/m/d match
  /// the Israel calendar day of [instant]. Use for entity "calendar day"
  /// fields stripped of any time component.
  static DateTime calendarDay(DateTime instant) {
    final parts = calendarParts(instant);
    return DateTime(parts.year, parts.month, parts.day);
  }

  /// Israel UTC offset (minutes) at the given UTC instant.
  static int _offsetMinutes(DateTime instant) {
    final utc = instant.toUtc();
    final dstStart = _dstStartUtc(utc.year);
    final dstEnd = _dstEndUtc(utc.year);
    final inDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
    return inDst ? _idtOffsetMinutes : _istOffsetMinutes;
  }

  /// 02:00 IST → 00:00 UTC on the Friday before the last Sunday of March.
  static DateTime _dstStartUtc(int year) {
    final lastSunday = _lastWeekdayOfMonth(year, 3, DateTime.sunday);
    final fridayBefore = lastSunday.subtract(const Duration(days: 2));
    return DateTime.utc(year, 3, fridayBefore.day, 0, 0, 0);
  }

  /// 02:00 IDT → 23:00 UTC the day before the last Sunday of October.
  static DateTime _dstEndUtc(int year) {
    final lastSunday = _lastWeekdayOfMonth(year, 10, DateTime.sunday);
    return DateTime.utc(year, 10, lastSunday.day - 1, 23, 0, 0);
  }

  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final daysInMonth = DateTime.utc(year, month + 1, 0).day;
    var d = DateTime.utc(year, month, daysInMonth);
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }
}
