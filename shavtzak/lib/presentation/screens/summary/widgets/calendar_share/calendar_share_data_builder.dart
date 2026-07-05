import '../../../../../core/utils/date_utils.dart' as app_date_utils;
import '../../../../../core/utils/event_sorting.dart';
import '../../../../../domain/entities/event.dart';
import '../../../../widgets/map_location_picker.dart';
import 'calendar_share_models.dart';

/// Builds the pure CalendarShareData snapshot from domain events.
///
/// Time semantics mirror calendar_sync_service.syncAppEventToCalendar:
///   separator = actualShowStartTime if non-empty, else startTime
///   allDay    = assemblyTime.isEmpty || endTime.isEmpty
class CalendarShareDataBuilder {
  static CalendarShareData build({
    required List<Event> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required CalendarShareMode mode,
    required DateTime today,
  }) {
    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);
    final active = events.where((e) => !e.isDeactivated).toList()
      ..sort(compareEventsChronologically);
    final rangeTitle = _formatRangeTitle(start, end);

    if (mode == CalendarShareMode.weeks) {
      return CalendarShareData(
        rangeTitle: rangeTitle,
        mode: mode,
        weeks: _buildWeeks(
          gridStart: _sundayOnOrBefore(start),
          gridEnd: _saturdayOnOrAfter(end),
          rangeStart: start,
          rangeEnd: end,
          monthBounds: null,
          events: active,
          today: today,
        ),
      );
    }
    // Months mode is implemented in the next task.
    throw UnimplementedError('months mode not implemented yet');
  }

  /// One week per row from [gridStart] (a Sunday) to [gridEnd] (a Saturday).
  /// When [monthBounds] is set (months mode), days outside it become null
  /// (blank cells); days outside [rangeStart..rangeEnd] carry inRange=false.
  static List<CalendarShareWeek> _buildWeeks({
    required DateTime gridStart,
    required DateTime gridEnd,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required ({DateTime first, DateTime last})? monthBounds,
    required List<Event> events,
    required DateTime today,
  }) {
    final weeks = <CalendarShareWeek>[];
    var cursor = gridStart;
    while (!cursor.isAfter(gridEnd)) {
      final days = <CalendarShareDay?>[];
      for (var i = 0; i < 7; i++) {
        final date = _addDays(cursor, i);
        final inMonth = monthBounds == null ||
            (!date.isBefore(monthBounds.first) &&
                !date.isAfter(monthBounds.last));
        if (!inMonth) {
          days.add(null);
          continue;
        }
        final inRange =
            !date.isBefore(rangeStart) && !date.isAfter(rangeEnd);
        days.add(CalendarShareDay(
          date: date,
          inRange: inRange,
          isPast: date.isBefore(today),
          events: inRange
              ? _eventsForDay(events, date, rangeStart, today)
              : const [],
        ));
      }
      weeks.add(CalendarShareWeek(days: days));
      cursor = _addDays(cursor, 7);
    }
    return weeks;
  }

  static List<CalendarShareEvent> _eventsForDay(
    List<Event> events,
    DateTime date,
    DateTime rangeStart,
    DateTime today,
  ) {
    final result = <CalendarShareEvent>[];
    for (final event in events) {
      if (!event.occursOn(date)) {
        continue;
      }
      final eventStart = _dateOnly(event.startDate);
      final firstVisibleDay =
          eventStart.isBefore(rangeStart) ? rangeStart : eventStart;
      result.add(buildShareEvent(
        event,
        today: today,
        isContinuation: date.isAfter(firstVisibleDay),
      ));
    }
    return result;
  }

  static String _formatRangeTitle(DateTime start, DateTime end) {
    final startMonth = app_date_utils.DateUtils.hebrewMonthName(start.month);
    final endMonth = app_date_utils.DateUtils.hebrewMonthName(end.month);
    if (start.year == end.year && start.month == end.month) {
      if (start.day == end.day) {
        return '${start.day} ב$startMonth ${start.year}';
      }
      return '${start.day}–${end.day} ב$startMonth ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ב$startMonth – ${end.day} ב$endMonth ${start.year}';
    }
    return '${start.day} ב$startMonth ${start.year} – '
        '${end.day} ב$endMonth ${end.year}';
  }

  /// Dart weekday: Mon=1..Sun=7, so weekday % 7 is days-since-Sunday.
  static DateTime _sundayOnOrBefore(DateTime date) =>
      _addDays(date, -(date.weekday % 7));

  static DateTime _saturdayOnOrAfter(DateTime date) =>
      _addDays(date, 6 - (date.weekday % 7));

  /// Constructor arithmetic (not Duration) so DST shifts can't move midnight.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static CalendarShareEvent buildShareEvent(
    Event event, {
    required DateTime today,
    required bool isContinuation,
  }) {
    final isPast = _dateOnly(event.endDate).isBefore(today);
    if (isContinuation) {
      return CalendarShareEvent(
        name: event.name,
        isPast: isPast,
        isContinuation: true,
      );
    }
    final location = event.location.trim().isEmpty
        ? ''
        : MapLocationResult.stripCoordinates(event.location).trim();
    return CalendarShareEvent(
      name: event.name,
      timeLines: _buildTimeLines(event),
      locationLine: location,
      isPast: isPast,
    );
  }

  static List<String> _buildTimeLines(Event event) {
    final assemblyTime = event.assemblyTime.trim();
    final endTime = event.endTime.trim();
    final actualShowStartTime = event.actualShowStartTime.trim();
    final startTime = event.startTime.trim();

    final separator =
        actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime;
    final allDay = assemblyTime.isEmpty || endTime.isEmpty;
    if (allDay) {
      return const ['כל היום'];
    }

    final lines = <String>[];
    if (assemblyTime.isNotEmpty && separator.isNotEmpty) {
      lines.add('התייצבות $assemblyTime–$separator');
    }
    if (endTime.isNotEmpty &&
        (separator.isNotEmpty || assemblyTime.isNotEmpty)) {
      lines.add(
        separator.isNotEmpty ? 'מופע $separator–$endTime' : 'מופע עד $endTime',
      );
    }
    return lines;
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
