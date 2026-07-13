import '../../../../core/utils/same_day_assignments.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import 'assignment_slot.dart';

/// Pure passes that annotate already-built slots. Both `AssignmentBloc`
/// slot-building paths run them, so the grid cannot disagree with itself.

/// Flag every filled quota slot whose member also holds a DIFFERENT role in the
/// SAME event, and list those other roles.
///
/// Off-quota slots are skipped — they are already flagged "מחוץ למכסה" and are
/// display+delete only. Members flagged `allowMultipleAssignments`
/// (`שיבוץ מרובה`) are skipped too: several roles in one event is exactly what
/// that flag permits, so it is not worth warning about.
List<AssignmentSlot> annotateDoubleAssignments(List<AssignmentSlot> slots) {
  return slots.map((slot) {
    if (slot.isOffQuota || !slot.isFilled) return slot;

    final member = slot.currentAssignment!.teamMember;
    if (member?.allowMultipleAssignments ?? false) return slot;

    final otherRoles = slots
        .where((other) =>
            other.event.id == slot.event.id &&
            other.isFilled &&
            other.currentAssignment!.teamMemberId ==
                slot.currentAssignment!.teamMemberId &&
            other.role.key != slot.role.key)
        .map((other) => other.role.hebrewName)
        .toList();

    if (otherRoles.isEmpty) return slot;

    // copyWith, never the raw constructor: hand-rebuilding the slot drops every
    // field the call forgets, which is how sameDayAssignedMembers /
    // sameDayEventInfo used to vanish from exactly the rows that had a double
    // assignment.
    return slot.copyWith(hasDoubleAssignment: true, otherRoles: otherRoles);
  }).toList();
}

/// Flag every filled slot — including off-quota rows, which are real
/// assignments — whose member is also assigned to another event sharing a
/// calendar day, and list those events.
///
/// [allEvents] and [allAssignments] must be the FULL loaded window, before any
/// event filter is applied. Narrowing the grid to a single event must not erase
/// that event's own marks.
List<AssignmentSlot> annotateSameDayOtherEvents(
  List<AssignmentSlot> slots, {
  required List<Event> allEvents,
  required List<Assignment> allAssignments,
}) {
  final index = buildSameDayOtherEventsIndex(
    events: allEvents,
    assignments: allAssignments,
  );
  if (index.isEmpty) return slots;

  return slots.map((slot) {
    if (!slot.isFilled) return slot;

    final otherEvents =
        index[slot.event.id]?[slot.currentAssignment!.teamMemberId];
    if (otherEvents == null || otherEvents.isEmpty) return slot;

    return slot.copyWith(sameDayOtherEvents: otherEvents);
  }).toList();
}
