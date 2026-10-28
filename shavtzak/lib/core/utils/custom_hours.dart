// Small helpers around an assignment's custom hours: how they read as text,
// whole-day arithmetic, whether an event save moves the event in time, and the
// warning lines for constraints that fall inside a member's hours.
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import 'constraint_labels.dart';
import 'event_stretch.dart';

const String _dash = '–';

String _two(int value) => value.toString().padLeft(2, '0');

/// A day as d.M, '27.10'. Reads the fields as they are, so it serves a wall
/// moment and a local date alike.
String formatWallDay(DateTime moment) => '${moment.day}.${moment.month}';

/// A time of day as HH:mm, '09:05'.
String formatWallTime(DateTime moment) =>
    '${_two(moment.hour)}:${_two(moment.minute)}';

/// A window as the admin reads it:
/// - '27.10 14:00–23:00' when the start and the end fall on the same day;
/// - '27.10 14:00 – 28.10 02:00' otherwise.
///
/// Days are d.M, times HH:mm. An end at exactly 00:00 belongs to the next day,
/// so '27.10 18:00' to midnight reads '27.10 18:00 – 28.10 00:00'.
String formatCustomHours(WallInterval window) {
  final start = window.start;
  final end = window.end;
  final sameDay =
      start.year == end.year && start.month == end.month && start.day == end.day;
  if (sameDay) {
    return '${formatWallDay(start)} ${formatWallTime(start)}$_dash'
        '${formatWallTime(end)}';
  }
  return '${formatWallDay(start)} ${formatWallTime(start)} $_dash '
      '${formatWallDay(end)} ${formatWallTime(end)}';
}

/// The first usable custom window among [assignments], in the order given;
/// null when none has one.
///
/// One member holds one set of hours across their roles in an event (the
/// backend enforces it, except for members flagged `allowMultipleAssignments`,
/// who may differ); the screens that show a member's hours once take the first.
/// Hours that cannot be read count as no hours.
WallInterval? firstCustomWindow(Iterable<Assignment> assignments) {
  for (final assignment in assignments) {
    final window = assignment.customWindow;
    if (window != null) return window;
  }
  return null;
}

/// Whole calendar days from [from] to [to], negative when [to] is earlier.
/// Times of day are ignored. Counted on `DateTime.utc` dates, which have no
/// DST, so a 23- or 25-hour day never skews the count.
int calendarDaysBetween(DateTime from, DateTime to) {
  final fromDay = DateTime.utc(from.year, from.month, from.day);
  final toDay = DateTime.utc(to.year, to.month, to.day);
  return toDay.difference(fromDay).inDays;
}

/// Whether a save moves the event in time: the calendar day of its first or
/// last date differs, or any of its five times differs. Times compare
/// trimmed, an empty one being equal to a blank one. The name, location and
/// every other field never count.
///
/// The twin of `eventTimesChanged` in functions/src/assignment_hours.ts. The
/// server decides whether an `event.update` must carry hours resolutions, so
/// this must never report fewer changes than the server sees: it judges the
/// same fields the same way. Days are read from the date's own year, month
/// and day, as [eventStretch] reads them.
bool eventTimesChanged(Event before, Event after) {
  if (!_sameCalendarDay(before.startDate, after.startDate)) return true;
  if (!_sameCalendarDay(before.endDate, after.endDate)) return true;
  return _differsTrimmed(before.assemblyTime, after.assemblyTime) ||
      _differsTrimmed(before.startTime, after.startTime) ||
      _differsTrimmed(before.actualShowStartTime, after.actualShowStartTime) ||
      _differsTrimmed(before.endTime, after.endTime) ||
      _differsTrimmed(before.teamEndTime, after.teamEndTime);
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _differsTrimmed(String a, String b) => a.trim() != b.trim();

/// What the custom-hours dialogs call a member whose name is blank or not
/// loaded, in place of the name ('שעות מותאמות לחבר/ת הצוות').
const String unnamedMemberName = 'חבר/ת הצוות';

/// The first whitespace-separated word of [name]; empty for a blank name.
String memberFirstName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).first;
}

/// One warning line for each of [member]'s constraints that overlaps [window]
/// ([TeamMember.constraintsBlockingWindow]), approved or pending:
/// - '⚠️ מתנגש עם אילוץ מאושר של דנה: 28.10 (כל היום)';
/// - '⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 28.10 (כל היום)'.
List<String> customHoursWarningLines(TeamMember member, WallInterval window) {
  final first = memberFirstName(member.name);
  return [
    for (final constraint in member.constraintsBlockingWindow(window))
      '⚠️ מתנגש עם אילוץ '
          '${constraint.isPending() ? 'ממתין לאישור' : 'מאושר'} '
          'של $first: ${constraintShortLabel(constraint)}',
  ];
}
