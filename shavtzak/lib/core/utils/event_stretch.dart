// Whether a constraint touches an event, judged on the Israel wall clock.
//
// An event is one continuous stretch, from its start on the first day to its
// end on the last day, nights included. A constraint blocks when any of its
// intervals overlaps that stretch. The backend implements the same rule in
// functions/src/event_stretch.ts, and both run
// shared/test-fixtures/event_conflict_cases.json.
//
// A moment is a `DateTime.utc` holding the Israel wall-clock fields (the
// calendar day of the entity's date, plus hours and minutes). UTC has no DST,
// so a DST change never shifts a comparison or a duration.
import 'package:equatable/equatable.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';

const int _minutesPerDay = 24 * 60;

/// A stretch of the Israel wall clock, half-open: [start, end). Both ends are
/// `DateTime.utc` values holding wall-clock fields.
class WallInterval extends Equatable {
  const WallInterval(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Half-open overlap: touching at either end is not an overlap.
  bool overlaps(WallInterval other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  @override
  List<Object?> get props => [start, end];

  @override
  String toString() =>
      'WallInterval(${formatWallMoment(start)} → ${formatWallMoment(end)})';
}

final RegExp _wallTimePattern = RegExp(r'^([0-9]{2}):([0-9]{2})$');

/// Minutes since midnight of an `HH:mm` time, hours 0–23 and minutes 0–59.
/// Anything else ('', '24:00', '9:00', '16:00 ', null) is missing: null,
/// never a throw. Stricter than `TimeRangeUtils.parseTimeToMinutes` on
/// purpose, to match the backend's `wallTimeMinutes` exactly.
int? wallTimeMinutes(String? value) {
  if (value == null) return null;
  final match = _wallTimePattern.firstMatch(value);
  if (match == null) return null;
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  if (hours > 23 || minutes > 59) return null;
  return hours * 60 + minutes;
}

/// The wall-clock midnight of [date]'s calendar day.
DateTime _wallDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

DateTime _at(DateTime wallDay, int minutes) =>
    wallDay.add(Duration(minutes: minutes));

/// The event's stretch:
/// - start: the first day at `assemblyTime`, else `startTime`, else 00:00;
/// - end: the last day at `teamEndTime`, else `endTime`, else 24:00;
/// - a one-day event whose end is not after its start ends the next day;
/// - a multi-day event is read literally;
/// - a last day before the first day (bad data) is taken as the first day.
WallInterval eventStretch(Event event) {
  final firstDay = _wallDay(event.startDate);
  var lastDay = _wallDay(event.endDate);
  if (lastDay.isBefore(firstDay)) lastDay = firstDay;

  final start = _at(
    firstDay,
    wallTimeMinutes(event.assemblyTime) ??
        wallTimeMinutes(event.startTime) ??
        0,
  );
  var end = _at(
    lastDay,
    wallTimeMinutes(event.teamEndTime) ??
        wallTimeMinutes(event.endTime) ??
        _minutesPerDay,
  );
  if (lastDay == firstDay && !end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  return WallInterval(start, end);
}

/// Whether [event] gives too few hours for [eventStretch] to be exact, so that
/// it had to fall back to a day edge: no assembly and no show start (the
/// stretch begins at 00:00), or no team end and no show end (it ends at
/// 24:00). Read with [wallTimeMinutes], so a time it cannot read ('24:00', a
/// stray space) counts as missing.
///
/// The one test behind both the 'missing_event_time' warning
/// (`getConstraintEventOverlaps`) and the "שעת האירוע לא מוגדרת" label of
/// the constraint warning dialog.
bool eventStretchFellBack(Event event) {
  final hasStart = wallTimeMinutes(event.assemblyTime) != null ||
      wallTimeMinutes(event.startTime) != null;
  final hasEnd = wallTimeMinutes(event.teamEndTime) != null ||
      wallTimeMinutes(event.endTime) != null;
  return !hasStart || !hasEnd;
}

/// From [startTime] on [firstDay] to [endTime] on [lastDay]; a missing start
/// is 00:00 and a missing end is 24:00. An end not after its start rolls to
/// the next day.
WallInterval _timeWindow(
  DateTime firstDay,
  DateTime lastDay,
  String? startTime,
  String? endTime,
) {
  final start = _at(firstDay, wallTimeMinutes(startTime) ?? 0);
  var end = _at(lastDay, wallTimeMinutes(endTime) ?? _minutesPerDay);
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  return WallInterval(start, end);
}

/// The constraint's intervals that can reach [stretch]:
/// - one-time: one interval, from `startTime` on its first day to `endTime`
///   on its last day (the whole days without hours). A last day before the
///   first day (bad data) is taken as the first day, as on the event side;
/// - recurring: one interval on each matching day
///   ([DateConstraint.conflictsWith]) from the day before the stretch's first
///   day to its last day, the whole day or `startTime`→`endTime`. The day
///   before covers an occurrence that rolls past midnight into the stretch.
///   A null `repeatEndDate` matches nothing.
List<WallInterval> constraintIntervalsNear(
  DateConstraint constraint,
  WallInterval stretch,
) {
  if (constraint.repeatType == null) {
    final firstDay = _wallDay(constraint.startDate);
    var lastDay =
        constraint.endDate == null ? firstDay : _wallDay(constraint.endDate!);
    if (lastDay.isBefore(firstDay)) lastDay = firstDay;
    return [
      _timeWindow(firstDay, lastDay, constraint.startTime, constraint.endTime),
    ];
  }

  final intervals = <WallInterval>[];
  final lastCandidate = _wallDay(stretch.end);
  for (var day = _wallDay(stretch.start).subtract(const Duration(days: 1));
      !day.isAfter(lastCandidate);
      day = day.add(const Duration(days: 1))) {
    if (constraint.conflictsWith(day)) {
      intervals
          .add(_timeWindow(day, day, constraint.startTime, constraint.endTime));
    }
  }
  return intervals;
}

/// Whether any of [constraint]'s intervals overlaps [stretch] (half-open:
/// touching is not a conflict). Status and type are the caller's business.
bool constraintOverlapsStretch(
        DateConstraint constraint, WallInterval stretch) =>
    constraintIntervalsNear(constraint, stretch)
        .any((interval) => interval.overlaps(stretch));

/// A wall-clock moment as `yyyy-MM-ddTHH:mm`.
String formatWallMoment(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${moment.year.toString().padLeft(4, '0')}-${two(moment.month)}-'
      '${two(moment.day)}T${two(moment.hour)}:${two(moment.minute)}';
}
