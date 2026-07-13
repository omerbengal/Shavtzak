import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';

/// True when [a] and [b] occupy at least one calendar day in common.
///
/// Day precision — times are ignored. The comparison deliberately does NOT add
/// a `Duration` to a local `DateTime`: `DateTime(y, m, d).add(const
/// Duration(days: 1))` shifts by an hour across an Israel DST boundary and can
/// report a spurious overlap. `!isAfter` has no such hazard.
bool eventsShareDay(Event a, Event b) {
  final aStart = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
  final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
  final bStart = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
  final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

  return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
}

/// Other events sharing a calendar day with [event] that a member is ALSO
/// assigned to, keyed by member id. Members with no such event are absent.
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
  final otherEventsById = <String, Event>{};
  for (final candidate in allEvents) {
    if (candidate.id == event.id) continue;
    if (candidate.isDeactivated) continue;
    if (!eventsShareDay(event, candidate)) continue;
    otherEventsById[candidate.id] = candidate;
  }
  if (otherEventsById.isEmpty) return const {};

  // A member only qualifies if they are assigned to [event] itself — the
  // function answers "who here is ALSO booked elsewhere", not "who is booked
  // to any same-day event".
  final eventMemberIds = <String>{};
  for (final assignment in allAssignments) {
    if (assignment.eventId != event.id) continue;
    eventMemberIds.add(assignment.teamMemberId);
  }

  // Inner map keyed by event id: a member holding two roles in the same other
  // event must see that event listed once.
  final byMember = <String, Map<String, Event>>{};
  for (final assignment in allAssignments) {
    if (!eventMemberIds.contains(assignment.teamMemberId)) continue;
    final other = otherEventsById[assignment.eventId];
    if (other == null) continue;
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
