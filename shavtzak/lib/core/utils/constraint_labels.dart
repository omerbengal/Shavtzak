// One-line Hebrew wording of a constraint, as shown in the "בעלי מגבלות / לא
// זמינים" lists. Dates are d.M, ranges use an en-dash.
import '../../domain/entities/team_member.dart';
import 'event_stretch.dart' show wallTimeMinutes;

const String _approvedPrefix = 'אילוץ מאושר: ';
const String _pendingPrefix = 'אילוץ ממתין לאישור: ';
const String _rejectedPrefix = 'אילוץ שנדחה: ';
const String _dash = '–';

/// What a constraint covers, without its status:
/// - one day: '28.10 (כל היום)' or '27.10 17:00–20:00';
/// - several days: '27–28.10', '30.10–2.11' or '27.10 17:00 – 28.10 11:00';
/// - recurring: 'כל יום שלישי 18:00–20:00', 'כל יום', 'כל 15 לחודש'.
///
/// A time that is not a valid `HH:mm` counts as missing. A constraint with
/// only one of its two times (the old form could save that) says 'מ-17:00' or
/// 'עד 20:00'.
String constraintShortLabel(DateConstraint c) {
  final startTime = _validTime(c.startTime);
  final endTime = _validTime(c.endTime);

  if (c.repeatType != null) {
    final pattern = c.repeatPatternDescription();
    final hours = _hours(startTime, endTime);
    return hours == null ? pattern : '$pattern $hours';
  }

  final first = _day(c.startDate);
  final lastDate = c.endDate;

  // No end date, or one that is not after the start (bad data): one day.
  if (lastDate == null ||
      !_dateOnly(lastDate).isAfter(_dateOnly(c.startDate))) {
    final hours = _hours(startTime, endTime);
    return hours == null ? '$first (כל היום)' : '$first $hours';
  }

  final last = _day(lastDate);
  if (startTime == null && endTime == null) {
    final sameMonth = c.startDate.year == lastDate.year &&
        c.startDate.month == lastDate.month;
    return sameMonth
        ? '${c.startDate.day}$_dash${lastDate.day}.${lastDate.month}'
        : '$first$_dash$last';
  }
  final from = startTime == null ? first : '$first $startTime';
  final until = endTime == null ? last : '$last $endTime';
  return '$from $_dash $until';
}

/// The constraint with its status in front: 'אילוץ מאושר: …',
/// 'אילוץ ממתין לאישור: …' or 'אילוץ שנדחה: …'. Meant for the constraints
/// that block an assignment, which are approved or pending; a rejected one
/// is for a listing that shows constraints that do not block.
String constraintStatusLabel(DateConstraint c) {
  final prefix = c.isPending()
      ? _pendingPrefix
      : c.isRejected()
          ? _rejectedPrefix
          : _approvedPrefix;
  return '$prefix${constraintShortLabel(c)}';
}

String? _validTime(String? value) =>
    wallTimeMinutes(value) == null ? null : value;

/// '17:00–20:00', 'מ-17:00', 'עד 20:00', or null with no valid time.
String? _hours(String? startTime, String? endTime) {
  if (startTime != null && endTime != null) return '$startTime$_dash$endTime';
  if (startTime != null) return 'מ-$startTime';
  if (endTime != null) return 'עד $endTime';
  return null;
}

String _day(DateTime date) => '${date.day}.${date.month}';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
