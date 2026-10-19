import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/stage.dart';
import 'task_utils.dart';

/// Time on the stage axis of a דו יומי event: when each stage runs, which one
/// is happening now, how a day of stages sits on a calendar, and the labels
/// for its days. `now` is always injected so the rules can be tested at their
/// boundaries.

final DateFormat _dayMonth = DateFormat('dd/MM');
final DateFormat _dayOnly = DateFormat('dd');

const int _minutesPerDay = 24 * 60;

/// [text] inside a left-to-right isolate, so a time, a range or an "x/y"
/// count keeps its order inside a Hebrew line ("20–21/10", not "21/10–20").
String ltr(String text) => '\u2066$text\u2069';

/// When a stage runs: from [start], up to but not including [end].
class StageSpan extends Equatable {
  const StageSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  @override
  List<Object?> get props => [start, end];
}

DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _at(DateTime day, int minutes) =>
    DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

/// The end minute a stage really has: its end time when that comes after its
/// start, otherwise none.
int? _realEnd(Stage stage, int start) {
  final end = minutesOfDay(stage.endTime);
  return end != null && end > start ? end : null;
}

/// When [stage] runs, judged against the other stages of its event.
///
/// A stage with an end runs until it. One with a start only (or an end that
/// is not after its start) runs until the next stage of the event starts,
/// the next day too, and to the end of its day when none follows. A stage
/// with no usable start time has no span.
StageSpan? stageSpan(Stage stage, List<Stage> eventStages) {
  final startMinute = minutesOfDay(stage.startTime);
  if (startMinute == null) return null;
  final start = _at(stage.date, startMinute);
  final endMinute = _realEnd(stage, startMinute);
  if (endMinute != null) return StageSpan(start, _at(stage.date, endMinute));

  DateTime? nextStart;
  for (final other in eventStages) {
    final otherMinute = minutesOfDay(other.startTime);
    if (otherMinute == null) continue;
    final otherStart = _at(other.date, otherMinute);
    if (!otherStart.isAfter(start)) continue;
    if (nextStart == null || otherStart.isBefore(nextStart)) {
      nextStart = otherStart;
    }
  }
  final day = _dayOf(stage.date);
  return StageSpan(
    start,
    nextStart ?? DateTime(day.year, day.month, day.day + 1),
  );
}

/// The stages running at [now], in screen order. Usually one; overlapping
/// stages can make it more.
List<Stage> currentStages(List<Stage> eventStages, DateTime now) => [
      for (final stage in sortStages(eventStages))
        if (stageSpan(stage, eventStages)?.contains(now) ?? false) stage,
    ];

/// Whether [stage] is behind us at [now]: a timed stage once its span has
/// ended, one with no time once its day has.
bool isStageOver(Stage stage, List<Stage> eventStages, DateTime now) {
  final span = stageSpan(stage, eventStages);
  if (span != null) return !span.end.isAfter(now);
  return _dayOf(stage.date).isBefore(_dayOf(now));
}

/// The stage "המשימות שלי" opens on: the one running now; between stages the
/// next timed one; before the event the first; after it the last. A stage
/// with no time is never current, but with nothing timed left the first
/// stage not over stands in.
Stage? timelineAnchor(List<Stage> eventStages, DateTime now) {
  if (eventStages.isEmpty) return null;
  final current = currentStages(eventStages, now);
  if (current.isNotEmpty) return current.first;
  final ordered = sortStages(eventStages);
  for (final stage in ordered) {
    if (stageSpan(stage, eventStages) != null &&
        !isStageOver(stage, eventStages, now)) {
      return stage;
    }
  }
  for (final stage in ordered) {
    if (!isStageOver(stage, eventStages, now)) return stage;
  }
  return ordered.last;
}

/// The stages "המשימות שלי" folds above [anchor]: every stage before it in
/// screen order, except the untimed stages of its own day, which belong to
/// that day rather than to the past.
Set<String> foldedStageIds(List<Stage> eventStages, Stage anchor) {
  final anchorDay = _dayOf(anchor.date);
  final folded = <String>{};
  for (final stage in sortStages(eventStages)) {
    if (stage.id == anchor.id) break;
    final isUntimedOnAnchorDay = minutesOfDay(stage.startTime) == null &&
        _dayOf(stage.date) == anchorDay;
    if (!isUntimedOnAnchorDay) folded.add(stage.id);
  }
  return folded;
}

/// A timed stage placed on a day's hour grid.
class CalendarBlock extends Equatable {
  const CalendarBlock({
    required this.stage,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columnCount,
  });

  final Stage stage;

  /// Minutes since midnight.
  final int startMinute;

  /// Where the block is drawn to: its end, at least [startMinute] plus the
  /// smallest readable block, never past midnight.
  final int endMinute;

  /// Its column among the stages it overlaps; 0 is the start side, the right
  /// under RTL.
  final int column;
  final int columnCount;

  @override
  List<Object?> get props => [stage, startMinute, endMinute, column, columnCount];
}

/// One day of stages, ready to draw.
class DayLayout extends Equatable {
  const DayLayout({required this.allDay, required this.blocks});

  /// Stages with no usable time, in screen order, for the all-day row.
  final List<Stage> allDay;
  final List<CalendarBlock> blocks;

  @override
  List<Object?> get props => [allDay, blocks];
}

int _drawnEnd(Stage stage, int start, int minBlockMinutes) {
  final end = _realEnd(stage, start) ?? start;
  return math.min(math.max(end, start + minBlockMinutes), _minutesPerDay);
}

/// Lays out one day's stages. Stages that overlap, directly or through each
/// other, share the width: each takes the lowest column free at its start,
/// and all of them count the columns their group needed.
DayLayout layoutDay(List<Stage> dayStages, {required int minBlockMinutes}) {
  final allDay = <Stage>[];
  final timed = <({Stage stage, int start, int end})>[];
  for (final stage in sortStages(dayStages)) {
    final start = minutesOfDay(stage.startTime);
    if (start == null) {
      allDay.add(stage);
      continue;
    }
    timed.add((
      stage: stage,
      start: start,
      end: _drawnEnd(stage, start, minBlockMinutes),
    ));
  }
  // By start, the longer one first, so it keeps the first column.
  timed.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    final byEnd = b.end.compareTo(a.end);
    if (byEnd != 0) return byEnd;
    return a.stage.title.compareTo(b.stage.title);
  });

  final blocks = <CalendarBlock>[];
  var group = <({Stage stage, int start, int end, int column})>[];
  var columnEnds = <int>[];
  var groupEnd = 0;
  void closeGroup() {
    for (final placed in group) {
      blocks.add(CalendarBlock(
        stage: placed.stage,
        startMinute: placed.start,
        endMinute: placed.end,
        column: placed.column,
        columnCount: columnEnds.length,
      ));
    }
    group = [];
    columnEnds = [];
  }

  for (final block in timed) {
    if (group.isNotEmpty && block.start >= groupEnd) closeGroup();
    groupEnd = group.isEmpty ? block.end : math.max(groupEnd, block.end);
    var column = columnEnds.indexWhere((end) => end <= block.start);
    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(block.end);
    } else {
      columnEnds[column] = block.end;
    }
    group.add((
      stage: block.stage,
      start: block.start,
      end: block.end,
      column: column,
    ));
  }
  closeGroup();
  return DayLayout(allDay: allDay, blocks: blocks);
}

/// The whole hours a calendar of [stages] shows: from the hour of the
/// earliest start to the hour after the latest drawn end, at most midnight.
/// Null when none of them has a time.
({int first, int last})? calendarHours(
  Iterable<Stage> stages, {
  required int minBlockMinutes,
}) {
  int? earliest;
  int? latest;
  for (final stage in stages) {
    final start = minutesOfDay(stage.startTime);
    if (start == null) continue;
    final end = _drawnEnd(stage, start, minBlockMinutes);
    earliest = earliest == null ? start : math.min(earliest, start);
    latest = latest == null ? end : math.max(latest, end);
  }
  if (earliest == null || latest == null) return null;
  return (first: earliest ~/ 60, last: math.min(24, (latest + 59) ~/ 60));
}

/// The days the calendar offers: every day of [event], plus the day of any
/// stage that fell outside it (the event moved after its stages were made),
/// first to last.
List<DateTime> calendarDays(Event event, List<Stage> eventStages) {
  final days = <DateTime>{
    ...eventDays(event),
    for (final stage in eventStages) _dayOf(stage.date),
  }.toList()
    ..sort();
  return days;
}

/// The day the calendar opens on: today while it is one of [days], otherwise
/// the first of them.
DateTime initialCalendarDay(List<DateTime> days, DateTime now) {
  final today = _dayOf(now);
  if (days.isEmpty || days.contains(today)) return today;
  return days.first;
}

// DateTime.weekday runs from Monday (1) to Sunday (7).
const List<String> _weekdays = [
  'שני',
  'שלישי',
  'רביעי',
  'חמישי',
  'שישי',
  'שבת',
  'ראשון',
];

/// "ראשון" … "שבת".
String hebrewWeekday(DateTime date) => _weekdays[date.weekday - 1];

/// "שלישי 20/10", with " · היום" on today.
String dayLabel(DateTime day, DateTime now) {
  final label = '${hebrewWeekday(day)} ${_dayMonth.format(day)}';
  return _dayOf(day) == _dayOf(now) ? '$label · היום' : label;
}

/// "שלישי–רביעי, 20–21/10" for the events list; "שלישי, 20/10" for a one-day
/// event. The dates sit in a left-to-right isolate.
String eventDaysLabel(Event event) {
  final days = eventDays(event);
  final first = days.first;
  final last = days.last;
  if (days.length == 1) {
    return '${hebrewWeekday(first)}, ${_dayMonth.format(first)}';
  }
  final sameMonth = first.year == last.year && first.month == last.month;
  final dates = sameMonth
      ? '${_dayOnly.format(first)}–${_dayMonth.format(last)}'
      : '${_dayMonth.format(first)}–${_dayMonth.format(last)}';
  return '${hebrewWeekday(first)}–${hebrewWeekday(last)}, ${ltr(dates)}';
}

/// Whether today is one of [event]'s days.
bool isEventUnderWay(Event event, DateTime now) =>
    eventDays(event).contains(_dayOf(now));

/// A stage's time for display: its range, its start alone, or nothing.
String stageTimeLabel(Stage stage) {
  final start = minutesOfDay(stage.startTime);
  if (start == null) return '';
  if (_realEnd(stage, start) != null) {
    return ltr('${stage.startTime}–${stage.endTime}');
  }
  return ltr(stage.startTime!);
}

/// "21/10 · 08:00–10:45 · לובי": the stage's day, time and place, skipping
/// whatever is missing.
///
/// A range is wrapped in a left-to-right isolate, so the start time stays on
/// the left inside the Hebrew line.
String stageSummaryLine(Stage stage) {
  final start = stage.startTime;
  final end = stage.endTime;
  final time =
      start == null ? null : (end == null ? start : '\u2066$start–$end\u2069');
  return [
    _dayMonth.format(stage.date),
    if (time != null) time,
    if (stage.hotelLocation.isNotEmpty) stage.hotelLocation,
  ].join(' · ');
}
