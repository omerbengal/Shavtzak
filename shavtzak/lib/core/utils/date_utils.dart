import 'package:intl/intl.dart';

/// Utility functions for date formatting and manipulation
/// Supports Hebrew formatting for the Israeli market
class DateUtils {
  /// Format date as Hebrew date string (e.g., "03/09/2025")
  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Format time as Hebrew time string (e.g., "19:00")
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Format date and time together (e.g., "03/09/2025 19:00")
  static String formatDateTime(DateTime date) {
    return '${formatDate(date)} ${formatTime(date)}';
  }

  /// Hebrew month names. Index 0 = ינואר. Prefer [hebrewMonthName].
  static const List<String> hebrewMonths = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];

  /// Hebrew name for a 1-indexed month (1 = ינואר).
  static String hebrewMonthName(int month) => hebrewMonths[month - 1];

  /// Format date as day and month (e.g., "3 בספטמבר")
  static String formatDayMonth(DateTime date) {
    return '${date.day} ב${hebrewMonthName(date.month)}';
  }

  /// Format date as weekday and date (e.g., "יום שלישי, 3 בספטמבר")
  static String formatWeekdayDate(DateTime date) {
    final hebrewWeekdays = [
      'יום שני',
      'יום שלישי',
      'יום רביעי',
      'יום חמישי',
      'יום שישי',
      'שבת',
      'יום ראשון',
    ];

    final weekday = hebrewWeekdays[date.weekday - 1];
    return '$weekday, ${formatDayMonth(date)}';
  }

  /// Check if two dates are on the same day
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    return isSameDay(date, DateTime.now());
  }

  /// Check if date is in the past
  static bool isPast(DateTime date) {
    return date.isBefore(DateTime.now());
  }

  /// Check if date is in the future
  static bool isFuture(DateTime date) {
    return date.isAfter(DateTime.now());
  }

  /// Get date range as string (e.g., "3-5 בספטמבר" or "3 בספטמבר - 2 באוקטובר")
  static String formatDateRange(DateTime start, DateTime end) {
    if (isSameDay(start, end)) {
      return formatDayMonth(start);
    }

    if (start.month == end.month && start.year == end.year) {
      // Same month: "3-5 בספטמבר"
      return '${start.day}-${end.day} ב${hebrewMonthName(start.month)}';
    }

    // Different months: "3 בספטמבר - 2 באוקטובר"
    return '${formatDayMonth(start)} - ${formatDayMonth(end)}';
  }

  /// Parse date from string (DD/MM/YYYY)
  static DateTime? parseDate(String dateString) {
    try {
      return DateFormat('dd/MM/yyyy').parse(dateString);
    } catch (e) {
      return null;
    }
  }

  /// Parse time from string (HH:mm)
  static DateTime? parseTime(String timeString) {
    try {
      return DateFormat('HH:mm').parse(timeString);
    } catch (e) {
      return null;
    }
  }

  /// Get start of day (00:00:00)
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day (23:59:59)
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// Get relative date string (e.g., "היום", "מחר", "אתמול", or formatted date)
  static String getRelativeDateString(DateTime date) {
    final now = DateTime.now();
    final today = startOfDay(now);
    final targetDay = startOfDay(date);

    final difference = targetDay.difference(today).inDays;

    if (difference == 0) {
      return 'היום';
    } else if (difference == 1) {
      return 'מחר';
    } else if (difference == -1) {
      return 'אתמול';
    } else if (difference > 0 && difference <= 7) {
      return 'בעוד $difference ימים';
    } else if (difference < 0 && difference >= -7) {
      return 'לפני ${-difference} ימים';
    } else {
      return formatDate(date);
    }
  }

  /// Check if a date falls within a range (inclusive)
  static bool isDateInRange(DateTime date, DateTime start, DateTime end) {
    final dateOnly = startOfDay(date);
    final startOnly = startOfDay(start);
    final endOnly = startOfDay(end);

    return (dateOnly.isAtSameMomentAs(startOnly) ||
            dateOnly.isAfter(startOnly)) &&
        (dateOnly.isAtSameMomentAs(endOnly) || dateOnly.isBefore(endOnly));
  }

  /// Get days between two dates
  static int daysBetween(DateTime start, DateTime end) {
    final startOnly = startOfDay(start);
    final endOnly = startOfDay(end);
    return endOnly.difference(startOnly).inDays;
  }

  /// Shift an "HH:mm" time string by [minutes] (can be negative), wrapping
  /// around midnight so the result is always a valid time-of-day.
  ///
  /// Used to derive dependent event times, e.g. שעת התייצבות = 2h before
  /// שעת התכנסות קהל (-120), or שעת סיום הצוות = 1h after שעת סיום המופע (+60).
  /// Returns null when [time] is empty or not a valid "HH:mm" value.
  static String? shiftHmByMinutes(String time, int minutes) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
    if (match == null) return null;

    final hours = int.parse(match.group(1)!);
    final mins = int.parse(match.group(2)!);
    if (hours > 23 || mins > 59) return null;

    // Wrap into [0, 1440) so crossing midnight stays a valid time-of-day.
    final total = (((hours * 60 + mins + minutes) % 1440) + 1440) % 1440;
    final outHours = total ~/ 60;
    final outMins = total % 60;
    return '${outHours.toString().padLeft(2, '0')}:${outMins.toString().padLeft(2, '0')}';
  }
}
