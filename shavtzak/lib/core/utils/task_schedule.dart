import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';
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

  /// 2 when it shares the width with a stage it overlaps, 1 when it has the
  /// whole width.
  final int columnCount;

  @override
  List<Object?> get props => [stage, startMinute, endMinute, column, columnCount];
}

/// One day of stages, ready to draw.
class DayLayout extends Equatable {
  const DayLayout({
    required this.allDay,
    required this.blocks,
    this.bands = const [],
  });

  /// Stages with no usable time, in screen order, for the all-day row.
  final List<Stage> allDay;
  final List<CalendarBlock> blocks;

  /// Stages that found both columns taken at their start: each gets a
  /// full-width row of its own at its start minute.
  final List<CalendarBlock> bands;

  @override
  List<Object?> get props => [allDay, blocks, bands];
}

int _drawnEnd(Stage stage, int start, int minBlockMinutes) {
  final end = _realEnd(stage, start) ?? start;
  return math.min(math.max(end, start + minBlockMinutes), _minutesPerDay);
}

/// Lays out one day's stages. Each timed stage takes the lowest column free
/// at its start; stages that overlap, directly or through each other, share
/// the width between the columns their group needed, and a stage that
/// overlaps none has it all. With [maxColumns], a stage that finds every
/// column taken becomes a full-width band instead.
DayLayout layoutDay(
  List<Stage> dayStages, {
  required int minBlockMinutes,
  int? maxColumns,
}) {
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

  final placed = <({Stage stage, int start, int end, int column})>[];
  final bands = <CalendarBlock>[];
  final columnEnds = <int>[];
  for (final block in timed) {
    var column = columnEnds.indexWhere((end) => end <= block.start);
    if (column == -1 &&
        (maxColumns == null || columnEnds.length < maxColumns)) {
      column = columnEnds.length;
      columnEnds.add(block.end);
    }
    if (column == -1) {
      bands.add(CalendarBlock(
        stage: block.stage,
        startMinute: block.start,
        endMinute: block.end,
        column: 0,
        columnCount: 1,
      ));
      continue;
    }
    columnEnds[column] = block.end;
    placed.add((
      stage: block.stage,
      start: block.start,
      end: block.end,
      column: column,
    ));
  }

  // Groups of stages that overlap, directly or through each other: each
  // group shares out the columns it needed.
  final columnsOf = <int, int>{};
  final groupOf = <int>[];
  var group = -1;
  var groupEnd = -1;
  for (final one in placed) {
    if (one.start >= groupEnd) group++;
    groupEnd = math.max(groupEnd, one.end);
    groupOf.add(group);
    columnsOf[group] = math.max(columnsOf[group] ?? 0, one.column + 1);
  }

  return DayLayout(
    allDay: allDay,
    blocks: [
      for (var i = 0; i < placed.length; i++)
        CalendarBlock(
          stage: placed[i].stage,
          startMinute: placed[i].start,
          endMinute: placed[i].end,
          column: placed[i].column,
          columnCount: columnsOf[groupOf[i]]!,
        ),
    ],
    bands: bands,
  );
}

/// Where each minute of a calendar's grid is drawn, once the hours have
/// stretched so every stage's name fits and long empty stretches have
/// squashed. Shared by every day drawn side by side, so their hours line up.
class TimeAxis {
  TimeAxis._(this._marks, this._bandSpace, this._segments, this._squashed);

  /// Every minute where something starts or ends, every whole hour, first to
  /// last.
  final List<int> _marks;

  /// The room the bands take at each mark.
  final List<double> _bandSpace;

  /// The height from each mark to the next.
  final List<double> _segments;

  /// The squashed stretches, as (from, to) minutes.
  final List<(int, int)> _squashed;

  double get height =>
      _bandSpace.fold(0.0, (sum, space) => sum + space) +
      _segments.fold(0.0, (sum, segment) => sum + segment);

  int _indexAtOrBefore(int minute) {
    var index = 0;
    while (index + 1 < _marks.length && _marks[index + 1] <= minute) {
      index++;
    }
    return index;
  }

  /// Where [minute] is drawn: above any band that sits there.
  double before(int minute) {
    final index = _indexAtOrBefore(minute);
    var y = 0.0;
    for (var i = 0; i < index; i++) {
      y += _bandSpace[i] + _segments[i];
    }
    if (minute <= _marks[index]) return y;
    y += _bandSpace[index];
    if (index >= _segments.length) return y;
    final span = _marks[index + 1] - _marks[index];
    return y + _segments[index] * (minute - _marks[index]) / span;
  }

  /// Where a stage starting at [minute] begins: below the bands there.
  double after(int minute) {
    final index = _indexAtOrBefore(minute);
    final y = before(minute);
    return _marks[index] == minute ? y + _bandSpace[index] : y;
  }

  /// The top of [band], below the bands of its day that came before it at
  /// the same minute.
  double bandTop(DayLayout day, CalendarBlock band) {
    var y = before(band.startMinute);
    for (final other in day.bands) {
      if (identical(other, band)) break;
      if (other.startMinute == band.startMinute) y += _bandHeights[other] ?? 0;
    }
    return y;
  }

  final Map<CalendarBlock, double> _bandHeights = {};

  /// Whether [minute] lies inside a squashed stretch, where no hour line is
  /// drawn.
  bool isSquashed(int minute) =>
      _squashed.any((run) => run.$1 < minute && minute < run.$2);

  /// The squashed stretches, as (from, to) minutes.
  List<(int, int)> get squashed => List.unmodifiable(_squashed);
}

/// Builds the [TimeAxis] of [days] from [firstHour] to [lastHour].
///
/// An hour is [hourHeight] tall unless a stage in it needs more: [needOf]
/// gives the height a block or band needs for its whole name, and the hours
/// a block runs through stretch evenly until it fits, so every hour keeps
/// its minutes evenly spread. A band takes its height at its start minute,
/// before the blocks that start there. Runs of whole hours, together at
/// least [squashFromMinutes] long, with no stage running shrink to
/// [squashedHeight].
TimeAxis buildTimeAxis(
  List<DayLayout> days, {
  required int firstHour,
  required int lastHour,
  required double hourHeight,
  required double Function(CalendarBlock block) needOf,
  int squashFromMinutes = 120,
  double squashedHeight = 24,
}) {
  final first = firstHour * 60;
  final last = lastHour * 60;
  final markSet = <int>{
    for (var hour = firstHour; hour <= lastHour; hour++) hour * 60,
    for (final day in days) ...[
      for (final block in day.blocks) ...[block.startMinute, block.endMinute],
      for (final band in day.bands) band.startMinute,
    ],
  }..removeWhere((minute) => minute < first || minute > last);
  final marks = markSet.toList()..sort();
  final indexOf = {for (var i = 0; i < marks.length; i++) marks[i]: i};

  // Each hour has one height and its minutes spread evenly over it, so
  // half past always sits halfway between two hour lines.
  final hourHeights = {
    for (var hour = firstHour; hour < lastHour; hour++) hour: hourHeight,
  };
  final segments = List<double>.filled(math.max(0, marks.length - 1), 0);
  void spreadHours() {
    for (var i = 0; i + 1 < marks.length; i++) {
      final hour = marks[i] ~/ 60;
      segments[i] =
          (hourHeights[hour] ?? hourHeight) * (marks[i + 1] - marks[i]) / 60;
    }
  }

  // Runs of whole empty hours shrink.
  bool isEmptyHour(int hour) => !days.any((day) => day.blocks.any((block) =>
      block.startMinute < (hour + 1) * 60 && block.endMinute > hour * 60));
  final squashed = <(int, int)>[];
  var runStart = -1;
  void closeRun(int endHour) {
    if (runStart < 0) return;
    final hours = endHour - runStart;
    if (hours * 60 >= squashFromMinutes) {
      for (var hour = runStart; hour < endHour; hour++) {
        hourHeights[hour] = squashedHeight / hours;
      }
      squashed.add((runStart * 60, endHour * 60));
    }
    runStart = -1;
  }

  for (var hour = firstHour; hour < lastHour; hour++) {
    if (!isEmptyHour(hour)) {
      closeRun(hour);
    } else if (runStart < 0) {
      runStart = hour;
    }
  }
  closeRun(lastHour);
  spreadHours();

  // Bands take their room at their minute; the busiest day sets it.
  final bandSpace = List<double>.filled(marks.length, 0);
  final bandHeights = <CalendarBlock, double>{};
  for (final day in days) {
    final perMark = <int, double>{};
    for (final band in day.bands) {
      final need = needOf(band);
      bandHeights[band] = need;
      final index = indexOf[band.startMinute];
      if (index == null) continue;
      perMark[index] = (perMark[index] ?? 0) + need;
    }
    perMark.forEach((index, space) {
      bandSpace[index] = math.max(bandSpace[index], space);
    });
  }

  final axis = TimeAxis._(marks, bandSpace, segments, squashed);
  axis._bandHeights.addAll(bandHeights);

  // Blocks in order of start, so stretching one never takes room another
  // already counted on.
  final blocks = [
    for (final day in days)
      for (final block in day.blocks) (day: day, block: block),
  ]..sort((a, b) => a.block.startMinute.compareTo(b.block.startMinute));
  for (final (:day, :block) in blocks) {
    final start = block.startMinute;
    if (start < first || start >= last) continue;
    // A band inside the block covers it from there down: the name must fit
    // above it.
    var limit = math.min(block.endMinute, last);
    for (final band in day.bands) {
      if (band.startMinute > start && band.startMinute < limit) {
        limit = band.startMinute;
      }
    }
    final room = axis.before(limit) - axis.after(start);
    final need = needOf(block);
    if (need <= room) continue;
    // Stretch every hour the block runs through by the same factor.
    var hourRoom = 0.0;
    final touched = <int>[];
    for (var hour = start ~/ 60; hour * 60 < limit; hour++) {
      final from = math.max(start, hour * 60);
      final to = math.min(limit, (hour + 1) * 60);
      if (to <= from) continue;
      touched.add(hour);
      hourRoom += (hourHeights[hour] ?? hourHeight) * (to - from) / 60;
    }
    if (hourRoom <= 0) continue;
    final factor = (need - (room - hourRoom)) / hourRoom;
    for (final hour in touched) {
      hourHeights[hour] = (hourHeights[hour] ?? hourHeight) * factor;
    }
    spreadHours();
  }
  return axis;
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

final DateFormat _updateTime = DateFormat('HH:mm');
final DateFormat _updateDayTime = DateFormat('dd/MM HH:mm');

/// A task's assignee update with its author and time ("מחכים למקרן · נועה
/// לוי, 14:22"): the time alone on [now]'s day, with the date on any other
/// day. Null when the task has no update.
String? assigneeUpdateLine(TaskItem task, DateTime now) {
  final note = task.assigneeUpdate;
  if (note == null || note.isEmpty) return null;
  final at = task.assigneeUpdateAt;
  final isToday = at != null &&
      at.year == now.year &&
      at.month == now.month &&
      at.day == now.day;
  final byline = [
    if (task.assigneeUpdateByName != null) task.assigneeUpdateByName!,
    if (at != null) ltr((isToday ? _updateTime : _updateDayTime).format(at)),
  ].join(', ');
  return byline.isEmpty ? note : '$note · $byline';
}
