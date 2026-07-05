import '../../../../../core/utils/date_utils.dart' as app_date_utils;
import '../../../../../core/utils/event_sorting.dart';
import '../../../../../domain/entities/category.dart';
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
    required List<Category> categories,
  }) {
    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);
    final active = events.where((e) => !e.isDeactivated).toList()
      ..sort(compareEventsChronologically);
    final rangeTitle = _formatRangeTitle(start, end);
    final colorByCategoryId = {
      for (final c in categories)
        if (c.colorValue != null) c.id: c.colorValue!,
    };

    // Categories (with colors) that appear on at least one in-range event —
    // archived categories are deliberately included here when referenced.
    final usedCategoryIds = <String>{
      for (final event in active)
        if (event.categoryId != null &&
            !_dateOnly(event.endDate).isBefore(start) &&
            !_dateOnly(event.startDate).isAfter(end))
          event.categoryId!,
    };
    final legendCategories = categories
        .where((c) => c.colorValue != null && usedCategoryIds.contains(c.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final legend = [
      for (final c in legendCategories)
        CalendarShareLegendItem(name: c.name, colorValue: c.colorValue!),
    ];

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
          colorByCategoryId: colorByCategoryId,
        ),
        legend: legend,
      );
    }
    return CalendarShareData(
      rangeTitle: rangeTitle,
      mode: mode,
      months: _buildMonths(
        rangeStart: start,
        rangeEnd: end,
        events: active,
        today: today,
        colorByCategoryId: colorByCategoryId,
      ),
      legend: legend,
    );
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
    required Map<String, int> colorByCategoryId,
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
        final inRange = !date.isBefore(rangeStart) && !date.isAfter(rangeEnd);
        days.add(CalendarShareDay(
          date: date,
          inRange: inRange,
          isPast: date.isBefore(today),
          events: inRange
              ? _eventsForDay(
                  events, date, rangeStart, today, colorByCategoryId)
              : const [],
        ));
      }
      weeks.add(CalendarShareWeek(days: days));
      cursor = _addDays(cursor, 7);
    }
    return weeks;
  }

  static List<CalendarShareMonth> _buildMonths({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required List<Event> events,
    required DateTime today,
    required Map<String, int> colorByCategoryId,
  }) {
    final months = <CalendarShareMonth>[];
    var year = rangeStart.year;
    var month = rangeStart.month;
    while (year < rangeEnd.year ||
        (year == rangeEnd.year && month <= rangeEnd.month)) {
      final firstOfMonth = DateTime(year, month, 1);
      final lastOfMonth = DateTime(year, month + 1, 0);
      months.add(CalendarShareMonth(
        title: '${app_date_utils.DateUtils.hebrewMonthName(month)} $year',
        weeks: _buildWeeks(
          gridStart: _sundayOnOrBefore(firstOfMonth),
          gridEnd: _saturdayOnOrAfter(lastOfMonth),
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          monthBounds: (first: firstOfMonth, last: lastOfMonth),
          events: events,
          today: today,
          colorByCategoryId: colorByCategoryId,
        ),
      ));
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    }
    return months;
  }

  /// All-day events ('כל היום') sort first in a day cell, ahead of timed
  /// events; within each group the existing chronological order is kept
  /// (stable partition). Applies to continuation days too, since the
  /// partition key is the underlying event's all-day-ness, not its rendered
  /// timeLines.
  static List<CalendarShareEvent> _eventsForDay(
    List<Event> events,
    DateTime date,
    DateTime rangeStart,
    DateTime today,
    Map<String, int> colorByCategoryId,
  ) {
    final allDayResults = <CalendarShareEvent>[];
    final timedResults = <CalendarShareEvent>[];
    for (final event in events) {
      if (!event.occursOn(date)) {
        continue;
      }
      final eventStart = _dateOnly(event.startDate);
      final firstVisibleDay =
          eventStart.isBefore(rangeStart) ? rangeStart : eventStart;
      final shareEvent = buildShareEvent(
        event,
        today: today,
        isContinuation: date.isAfter(firstVisibleDay),
        categoryColorValue: event.categoryId == null
            ? null
            : colorByCategoryId[event.categoryId],
      );
      (_isAllDayEvent(event) ? allDayResults : timedResults).add(shareEvent);
    }
    return [...allDayResults, ...timedResults];
  }

  /// Mirrors the all-day predicate in _buildTimeLines: an event with no
  /// assembly time or no end time renders as 'כל היום'.
  static bool _isAllDayEvent(Event event) =>
      event.assemblyTime.trim().isEmpty || event.endTime.trim().isEmpty;

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
    int? categoryColorValue,
  }) {
    final isPast = _dateOnly(event.endDate).isBefore(today);
    if (isContinuation) {
      return CalendarShareEvent(
        name: event.name,
        isPast: isPast,
        isContinuation: true,
        categoryColorValue: categoryColorValue,
      );
    }
    final location = event.location.trim().isEmpty
        ? ''
        : MapLocationResult.stripCoordinates(event.location).trim();
    return CalendarShareEvent(
      name: event.name,
      timeLines: _buildTimeLines(event),
      participantsLine: _buildParticipantsLine(event),
      locationLine: location,
      isPast: isPast,
      categoryColorValue: categoryColorValue,
    );
  }

  static List<String> _buildTimeLines(Event event) {
    final assemblyTime = event.assemblyTime.trim();
    final endTime = event.endTime.trim();
    final teamEndTime = event.teamEndTime.trim();
    final actualShowStartTime = event.actualShowStartTime.trim();
    final startTime = event.startTime.trim();

    final separator =
        actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime;
    if (_isAllDayEvent(event)) {
      return const ['כל היום'];
    }

    final lines = <String>[];
    // Assembly end time is omitted: it always equals the מופע start shown on
    // the next line (separator), so a single time keeps the cell line short.
    if (assemblyTime.isNotEmpty && separator.isNotEmpty) {
      lines.add('התייצבות $assemblyTime');
    }
    if (endTime.isNotEmpty &&
        (separator.isNotEmpty || assemblyTime.isNotEmpty)) {
      // Mirror of the backend fallback (calendar_integration.ts, main event
      // start): separator when present, else assembly time — so the card
      // matches the block the boss sees in Google Calendar.
      final effectiveStart = separator.isNotEmpty ? separator : assemblyTime;
      lines.add('מופע $effectiveStart–$endTime');
    }
    if (teamEndTime.isNotEmpty) {
      lines.add('סיום צוות $teamEndTime');
    }
    return lines;
  }

  static String _buildParticipantsLine(Event event) {
    if (event.participantCount == null) {
      return '';
    }
    return '${event.participantCount}';
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
