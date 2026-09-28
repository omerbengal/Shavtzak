/// Utility class for time range operations
/// All times are in "HH:mm" format (24-hour format)
class TimeRangeUtils {
  /// Parse a time string "HH:mm" to minutes since midnight
  /// Returns null if parsing fails
  static int? parseTimeToMinutes(String time) {
    if (time.isEmpty) return null;

    final parts = time.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return hour * 60 + minute;
  }

  /// Check if two time ranges overlap
  /// Both ranges are [start, end) (end is exclusive)
  /// Returns true if they overlap, false otherwise
  /// Null values mean the range extends to infinity (start = null means from beginning, end = null means to end)
  static bool timesOverlap(
    String? start1,
    String? end1,
    String? start2,
    String? end2,
  ) {
    // Convert times to minutes since midnight
    final s1 = parseTimeToMinutes(start1 ?? '');
    final e1 = parseTimeToMinutes(end1 ?? '');
    final s2 = parseTimeToMinutes(start2 ?? '');
    final e2 = parseTimeToMinutes(end2 ?? '');

    // If all times are null, ranges cover entire day - they overlap
    if (s1 == null && e1 == null && s2 == null && e2 == null) {
      return true;
    }

    // If constraint has no time specified, it covers entire day
    // It overlaps with any event time
    if (s1 == null && e1 == null) {
      return true; // Constraint is all-day
    }
    if (s2 == null && e2 == null) {
      return true; // Event covers entire day
    }

    // At this point, we have at least one non-null time for each range
    // Treat missing start as 00:00 and missing end as 23:59
    final start1Minutes = s1 ?? 0;
    final end1Minutes = e1 ?? (24 * 60 - 1);
    final start2Minutes = s2 ?? 0;
    final end2Minutes = e2 ?? (24 * 60 - 1);

    // Two ranges [a, b) and [c, d) overlap if a < d && c < b
    return start1Minutes < end2Minutes && start2Minutes < end1Minutes;
  }

  /// Validate a time range
  /// Returns true if start < end (both non-null and valid)
  static bool isValidTimeRange(String start, String end) {
    final startMinutes = parseTimeToMinutes(start);
    final endMinutes = parseTimeToMinutes(end);

    if (startMinutes == null || endMinutes == null) return false;
    return startMinutes < endMinutes;
  }

  /// Validate a one-time constraint's times.
  /// Within a single day the end must follow the start. A range over several
  /// days runs from [start] on its first day to [end] on its last, so any two
  /// valid times will do (e.g. 17:00 → 11:00 three days later).
  static bool isValidConstraintTimeRange(
    String start,
    String end, {
    required bool spansMultipleDays,
  }) {
    if (!spansMultipleDays) return isValidTimeRange(start, end);
    return isValidTimeString(start) && isValidTimeString(end);
  }

  /// Whether a constraint's date range covers more than one day
  /// (a null end date means a single day).
  static bool spansMultipleDays(DateTime? firstDay, DateTime? lastDay) =>
      firstDay != null && lastDay != null && !_isSameDay(firstDay, lastDay);

  /// The hours a one-time date-range constraint covers on [day], as
  /// (start, end). A null bound runs to that edge of the day, so (null, null)
  /// is the whole day.
  ///
  /// A range over several days with both times set is one continuous block,
  /// from [startTime] on [firstDay] to [endTime] on [lastDay]: the first day
  /// runs from [startTime] to midnight, the days in between are whole, and the
  /// last day runs from midnight to [endTime]. Anything else keeps
  /// [startTime]–[endTime] on every day.
  static (String?, String?) rangeWindowOn({
    required DateTime day,
    required DateTime firstDay,
    required DateTime lastDay,
    String? startTime,
    String? endTime,
  }) {
    final hasTimes = (startTime?.isNotEmpty ?? false) &&
        (endTime?.isNotEmpty ?? false);
    if (!hasTimes || _isSameDay(firstDay, lastDay)) {
      return (startTime, endTime);
    }
    return (
      _isSameDay(day, firstDay) ? startTime : null,
      _isSameDay(day, lastDay) ? endTime : null,
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Format minutes since midnight to "HH:mm" format
  static String formatMinutesToTime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  /// Check if a time string is valid (non-empty and in correct format)
  static bool isValidTimeString(String time) {
    return parseTimeToMinutes(time) != null;
  }
}
