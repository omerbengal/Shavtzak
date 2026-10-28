import 'package:equatable/equatable.dart';

import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import 'event_stretch.dart';

/// A run of calendar days, first to last inclusive, as local date-only
/// `DateTime(y, m, d)` values.
class DayRange extends Equatable {
  const DayRange(this.first, this.last);

  final DateTime first;
  final DateTime last;

  @override
  List<Object?> get props => [first, last];

  @override
  String toString() => 'DayRange($first → $last)';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// The calendar days [e] spans, first date to last date. Times are ignored.
DayRange eventDays(Event e) =>
    DayRange(_dateOnly(e.startDate), _dateOnly(e.endDate));

/// The calendar days [a] holds its member in [event].
///
/// With custom hours: from the day of the start to the day of the last minute
/// the member is there (the end minus one minute, so hours ending exactly at
/// midnight stay on the day before). The hours may reach outside the event's
/// own dates. Without usable hours: [eventDays].
DayRange assignmentDays(Assignment a, Event event) {
  final window = a.customWindow;
  return window == null ? eventDays(event) : windowDays(window);
}

/// The calendar days [window] covers: the day of its start to the day of its
/// last minute (its end minus one minute, so a window ending exactly at
/// midnight stays on the day before).
DayRange windowDays(WallInterval window) {
  final lastMinute = window.end.subtract(const Duration(minutes: 1));
  return DayRange(
    DateTime(window.start.year, window.start.month, window.start.day),
    DateTime(lastMinute.year, lastMinute.month, lastMinute.day),
  );
}

/// True when [a] and [b] have at least one calendar day in common.
///
/// Deliberately does NOT add a `Duration` to a local `DateTime`:
/// `DateTime(y, m, d).add(const Duration(days: 1))` shifts by an hour across
/// an Israel DST boundary and can report a spurious overlap. `!isAfter` has
/// no such hazard.
bool dayRangesOverlap(DayRange a, DayRange b) =>
    !a.first.isAfter(b.last) && !b.first.isAfter(a.last);

/// True when [a] and [b] occupy at least one calendar day in common.
///
/// Day precision — times are ignored.
bool eventsShareDay(Event a, Event b) =>
    dayRangesOverlap(eventDays(a), eventDays(b));

/// True when [assignment], held in [assignmentEvent], keeps its member on at
/// least one day [event] spans.
///
/// The "other booking" side of a same-day check: the existing assignment is
/// judged by its own days ([assignmentDays]: its custom hours, else its whole
/// event), the event being filled by all of its days ([eventDays]). Hours on
/// day 1 of a two-day event do not collide with another event on day 2.
bool assignmentOverlapsEventDays(
  Assignment assignment,
  Event assignmentEvent,
  Event event,
) =>
    dayRangesOverlap(
      eventDays(event),
      assignmentDays(assignment, assignmentEvent),
    );

/// Other events sharing a calendar day with [event] that a member is ALSO
/// assigned to, keyed by member id. Members with no such event are absent.
///
/// "Sharing a day" is judged on the member's own days, not the events': the
/// days they hold in [event] (the union over their assignments there) against
/// the days they hold in each other event ([assignmentDays]). A member with
/// custom hours on day 1 of a two-day event is not double-booked by another
/// event on day 2.
///
/// Each list is sorted by start date, then name, so every surface renders the
/// same order and a re-export of unchanged data is byte-identical.
///
/// Deactivated events never count as the other event.
///
/// This deliberately does NOT filter by role capability, availability, or the
/// `allowMultipleAssignments` flag — unlike the candidate-filtering logic in
/// `AssignmentBloc` that it sits beside. That logic answers "who should I hide
/// from the assign dropdown". This answers a different question: is this
/// person, who is ALREADY assigned, booked somewhere else the same day? A
/// member who cannot perform this slot's role, or who carries the
/// `שיבוץ מרובה` flag, is absent from that logic yet must still be marked here.
Map<String, List<Event>> sameDayOtherEventsByMember({
  required Event event,
  required List<Event> allEvents,
  required List<Assignment> allAssignments,
}) {
  // A member only qualifies if they are assigned to [event] itself — the
  // function answers "who here is ALSO booked elsewhere", not "who is booked
  // to any same-day event". Their days here are the union over their roles.
  final daysInEvent = <String, List<DayRange>>{};
  for (final assignment in allAssignments) {
    if (assignment.eventId != event.id) continue;
    daysInEvent
        .putIfAbsent(assignment.teamMemberId, () => <DayRange>[])
        .add(assignmentDays(assignment, event));
  }
  if (daysInEvent.isEmpty) return const {};

  final candidatesById = <String, Event>{};
  for (final candidate in allEvents) {
    if (candidate.id == event.id) continue;
    if (candidate.isDeactivated) continue;
    candidatesById[candidate.id] = candidate;
  }
  if (candidatesById.isEmpty) return const {};

  // Inner map keyed by event id: a member holding two roles in the same other
  // event must see that event listed once.
  final byMember = <String, Map<String, Event>>{};
  for (final assignment in allAssignments) {
    final memberDays = daysInEvent[assignment.teamMemberId];
    if (memberDays == null) continue;
    final other = candidatesById[assignment.eventId];
    if (other == null) continue;
    final daysInOther = assignmentDays(assignment, other);
    if (!memberDays.any((days) => dayRangesOverlap(days, daysInOther))) {
      continue;
    }
    byMember.putIfAbsent(
      assignment.teamMemberId,
      () => <String, Event>{},
    )[other.id] = other;
  }

  return {
    for (final entry in byMember.entries)
      entry.key: entry.value.values.toList()..sort(_byStartDateThenName),
  };
}

/// eventId -> memberId -> other same-day events, for every event in [events].
/// Events with no double-booked member are absent from the outer map.
///
/// The relation is symmetric: if member M is in E and O on a shared day, then
/// `index[E.id][M]` names O *and* `index[O.id][M]` names E. Every surface must
/// look up the event it is currently rendering — do not collapse this into a
/// one-directional check.
Map<String, Map<String, List<Event>>> buildSameDayOtherEventsIndex({
  required List<Event> events,
  required List<Assignment> assignments,
}) {
  final index = <String, Map<String, List<Event>>>{};
  for (final event in events) {
    if (event.isDeactivated) continue;
    final byMember = sameDayOtherEventsByMember(
      event: event,
      allEvents: events,
      allAssignments: assignments,
    );
    if (byMember.isNotEmpty) {
      index[event.id] = byMember;
    }
  }
  return index;
}

int _byStartDateThenName(Event a, Event b) {
  final byDate = a.startDate.compareTo(b.startDate);
  if (byDate != 0) return byDate;
  return a.name.compareTo(b.name);
}
