import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import 'event_stretch.dart';

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

/// Whether [event] gives too few hours for the stretch to be exact, so that
/// [eventStretch] had to fall back to a day edge: no assembly and no show
/// start (the stretch begins at 00:00), or no team end and no show end (it
/// ends at 24:00). "Missing" is decided with the stretch's own strict parser,
/// so a time it cannot read ('24:00', a stray space) counts as missing.
bool _eventStretchFellBack(Event event) {
  final hasStart = wallTimeMinutes(event.assemblyTime) != null ||
      wallTimeMinutes(event.startTime) != null;
  final hasEnd = wallTimeMinutes(event.teamEndTime) != null ||
      wallTimeMinutes(event.endTime) != null;
  return !hasStart || !hasEnd;
}

/// Whether [constraint] touches any minute of [event], judged exactly as the
/// assignment check judges it ([eventStretch], [constraintOverlapsStretch]):
/// the event is one continuous stretch, nights included, and every occurrence
/// of a recurring constraint counts.
bool constraintOverlapsEvent({
  required DateConstraint constraint,
  required Event event,
}) {
  return constraintOverlapsStretch(constraint, eventStretch(event));
}

List<EventOverlapInfo> getConstraintEventOverlaps({
  required DateConstraint constraint,
  required List<Event> events,
}) {
  final overlaps = <EventOverlapInfo>[];

  // The event's own hours only matter when the constraint has hours too.
  final hasConstraintTime = (constraint.startTime?.isNotEmpty ?? false) &&
      (constraint.endTime?.isNotEmpty ?? false);

  for (final event in events) {
    if (!constraintOverlapsEvent(constraint: constraint, event: event)) {
      continue;
    }

    final eventHasMissingTime =
        hasConstraintTime && _eventStretchFellBack(event);

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
