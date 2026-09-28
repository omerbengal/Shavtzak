import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import 'time_range_utils.dart';

class EventOverlapInfo {
  final Event event;
  final bool eventHasMissingTime;
  final String overlapReason;

  const EventOverlapInfo({
    required this.event,
    required this.eventHasMissingTime,
    required this.overlapReason,
  });
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool datesOverlap(
    DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final startA = _dateOnly(aStart);
  final endA = _dateOnly(aEnd);
  final startB = _dateOnly(bStart);
  final endB = _dateOnly(bEnd);

  return !startA.isAfter(endB) && !startB.isAfter(endA);
}

bool _eventOccursOnDate(Event event, DateTime date) {
  final day = _dateOnly(date);
  final eventStart = _dateOnly(event.startDate);
  final eventEnd = _dateOnly(event.endDate);
  return !day.isBefore(eventStart) && !day.isAfter(eventEnd);
}

bool _eventHasValidTime(Event event) {
  return TimeRangeUtils.parseTimeToMinutes(event.startTime) != null &&
      TimeRangeUtils.parseTimeToMinutes(event.endTime) != null;
}

bool constraintOverlapsEvent({
  required DateConstraint constraint,
  required Event event,
}) {
  final constraintEnd = constraint.endDate ?? constraint.startDate;
  if (!datesOverlap(
      constraint.startDate, constraintEnd, event.startDate, event.endDate)) {
    return false;
  }

  final hasConstraintTime = (constraint.startTime?.isNotEmpty ?? false) &&
      (constraint.endTime?.isNotEmpty ?? false);

  if (!hasConstraintTime) {
    return true;
  }

  if (!_eventHasValidTime(event)) {
    // Conservative warning when event time is missing.
    return true;
  }

  // A multi-day constraint covers different hours on its first, middle and
  // last days, so check each day the two date ranges share.
  final constraintFirst = _dateOnly(constraint.startDate);
  final eventFirst = _dateOnly(event.startDate);
  final constraintLast = _dateOnly(constraintEnd);
  final eventLast = _dateOnly(event.endDate);
  final lastShared =
      constraintLast.isBefore(eventLast) ? constraintLast : eventLast;
  for (DateTime day =
          constraintFirst.isAfter(eventFirst) ? constraintFirst : eventFirst;
      !day.isAfter(lastShared);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final (windowStart, windowEnd) = constraint.timeWindowOn(day);
    if (TimeRangeUtils.timesOverlap(
      windowStart,
      windowEnd,
      event.startTime,
      event.endTime,
    )) {
      return true;
    }
  }
  return false;
}

List<EventOverlapInfo> getConstraintEventOverlaps({
  required DateConstraint constraint,
  required List<Event> events,
}) {
  final overlaps = <EventOverlapInfo>[];

  for (final event in events) {
    if (!constraintOverlapsEvent(constraint: constraint, event: event)) {
      continue;
    }

    final hasConstraintTime = (constraint.startTime?.isNotEmpty ?? false) &&
        (constraint.endTime?.isNotEmpty ?? false);
    final eventHasMissingTime = hasConstraintTime && !_eventHasValidTime(event);

    overlaps.add(
      EventOverlapInfo(
        event: event,
        eventHasMissingTime: eventHasMissingTime,
        overlapReason:
            eventHasMissingTime ? 'missing_event_time' : 'date_time_overlap',
      ),
    );
  }

  overlaps.sort((a, b) => a.event.startDate.compareTo(b.event.startDate));
  return overlaps;
}

Set<DateTime> getHighlightedDatesForConstraintRange({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required List<Event> events,
  String? constraintStartTime,
  String? constraintEndTime,
}) {
  final highlighted = <DateTime>{};
  final start = _dateOnly(rangeStart);
  final end = _dateOnly(rangeEnd);

  for (DateTime day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))) {
    for (final event in events) {
      if (!_eventOccursOnDate(event, day)) {
        continue;
      }

      final hasConstraintTime = (constraintStartTime?.isNotEmpty ?? false) &&
          (constraintEndTime?.isNotEmpty ?? false);

      if (!hasConstraintTime) {
        highlighted.add(day);
        break;
      }

      final (windowStart, windowEnd) = TimeRangeUtils.rangeWindowOn(
        day: day,
        firstDay: start,
        lastDay: end,
        startTime: constraintStartTime,
        endTime: constraintEndTime,
      );
      if (!_eventHasValidTime(event) ||
          TimeRangeUtils.timesOverlap(
            windowStart,
            windowEnd,
            event.startTime,
            event.endTime,
          )) {
        highlighted.add(day);
        break;
      }
    }
  }

  return highlighted;
}

Set<DateTime> getAllEventDates(List<Event> events) {
  final dates = <DateTime>{};

  for (final event in events) {
    final start = _dateOnly(event.startDate);
    final end = _dateOnly(event.endDate);

    for (DateTime day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))) {
      dates.add(day);
    }
  }

  return dates;
}
